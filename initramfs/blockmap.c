/* Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1> */
/*
 * blockmap: print a device-mapper "linear" table that maps a file's data
 * blocks on its filesystem device, so the file can be used as a block device
 * after the filesystem itself is unmounted.
 *
 *   blockmap FILE DEVICE
 *
 * Used for the <name>-ps4.img files on the PS4's internal drive: the UFS2
 * partition is mounted read-only only long enough to run this, so Linux
 * never writes the PS4's own filesystem metadata. Every block of FILE must be
 * allocated (no holes); the program fails otherwise. A partial last block is
 * mapped whole, so readers must stop at the file size themselves.
 *
 * Output: one "start length linear DEVICE offset" line per extent, in
 * 512-byte sectors. Needs CAP_SYS_RAWIO (FIBMAP).
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/fs.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	struct stat st;
	int fd, bsz;
	unsigned long nblocks, i, run_start = 0, run_len = 0;
	unsigned long long run_phys = 0;
	unsigned long sect_per_blk;

	if (argc != 3) {
		fprintf(stderr, "usage: %s FILE DEVICE\n", argv[0]);
		return 2;
	}
	fd = open(argv[1], O_RDONLY);
	if (fd < 0 || fstat(fd, &st) < 0) {
		perror(argv[1]);
		return 1;
	}
	if (ioctl(fd, FIGETBSZ, &bsz) < 0 || bsz < 512 || bsz % 512) {
		fprintf(stderr, "FIGETBSZ failed or odd block size\n");
		return 1;
	}
	/* A partial last block is mapped whole; readers use the file size
	 * (e.g. head -c SIZE) to stop at the real end. */
	sect_per_blk = bsz / 512;
	nblocks = (st.st_size + bsz - 1) / bsz;

	for (i = 0; i < nblocks; i++) {
		int blk = (int)i;

		if (ioctl(fd, FIBMAP, &blk) < 0) {
			fprintf(stderr, "FIBMAP block %lu: %s\n", i, strerror(errno));
			return 1;
		}
		if (blk == 0) {
			fprintf(stderr, "block %lu is a hole; file must be fully allocated\n", i);
			return 1;
		}
		if (run_len && (unsigned long long)blk == run_phys + run_len) {
			run_len++;
			continue;
		}
		if (run_len)
			printf("%lu %lu linear %s %llu\n", run_start * sect_per_blk,
			       run_len * sect_per_blk, argv[2], run_phys * sect_per_blk);
		run_start = i;
		run_phys = (unsigned long long)blk;
		run_len = 1;
	}
	if (run_len)
		printf("%lu %lu linear %s %llu\n", run_start * sect_per_blk,
		       run_len * sect_per_blk, argv[2], run_phys * sect_per_blk);
	close(fd);
	return 0;
}
