/* Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1> */
/*
 * splash: draw a raw RGB image on the Linux framebuffer, centred
 * horizontally, near the top of the screen.
 *
 *   splash IMAGE.rgb [TOP_PERCENT]
 *
 * IMAGE.rgb: u32 width, u32 height (little endian), then width*height RGB
 * bytes. Supports 32 and 16 bpp framebuffers (what amdgpu's fbdev gives).
 */
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	struct fb_var_screeninfo var;
	struct fb_fix_screeninfo fix;
	uint32_t w, h, x, y;
	unsigned int top_pct = argc > 2 ? (unsigned int)atoi(argv[2]) : 8;
	unsigned char *img, *fb;
	FILE *f;
	int fd;

	if (argc < 2) {
		fprintf(stderr, "usage: %s IMAGE.rgb [TOP_PERCENT]\n", argv[0]);
		return 2;
	}
	f = fopen(argv[1], "rb");
	if (!f || fread(&w, 4, 1, f) != 1 || fread(&h, 4, 1, f) != 1 || !w || !h ||
	    w > 4096 || h > 4096) {
		fprintf(stderr, "bad image %s\n", argv[1]);
		return 1;
	}
	img = malloc((size_t)w * h * 3);
	if (!img || fread(img, 3, (size_t)w * h, f) != (size_t)w * h) {
		fprintf(stderr, "short image %s\n", argv[1]);
		return 1;
	}
	fclose(f);

	fd = open("/dev/fb0", O_RDWR);
	if (fd < 0 || ioctl(fd, FBIOGET_VSCREENINFO, &var) < 0 ||
	    ioctl(fd, FBIOGET_FSCREENINFO, &fix) < 0) {
		perror("/dev/fb0");
		return 1;
	}
	if (var.bits_per_pixel != 32 && var.bits_per_pixel != 16) {
		fprintf(stderr, "unsupported %u bpp\n", var.bits_per_pixel);
		return 1;
	}
	fb = mmap(NULL, fix.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (fb == MAP_FAILED) {
		perror("mmap");
		return 1;
	}

	uint32_t ox = var.xres > w ? (var.xres - w) / 2 : 0;
	uint32_t oy = var.yres * top_pct / 100;

	for (y = 0; y < h && oy + y < var.yres; y++) {
		for (x = 0; x < w && ox + x < var.xres; x++) {
			const unsigned char *p = img + ((size_t)y * w + x) * 3;
			size_t off = (size_t)(oy + y + var.yoffset) * fix.line_length;

			if (var.bits_per_pixel == 32) {
				uint32_t px = ((uint32_t)p[0] >> (8 - var.red.length)) << var.red.offset |
					      ((uint32_t)p[1] >> (8 - var.green.length)) << var.green.offset |
					      ((uint32_t)p[2] >> (8 - var.blue.length)) << var.blue.offset;
				*(uint32_t *)(fb + off + (size_t)(ox + x) * 4) = px;
			} else {
				uint16_t px = (uint16_t)(((p[0] >> 3) << 11) | ((p[1] >> 2) << 5) | (p[2] >> 3));
				*(uint16_t *)(fb + off + (size_t)(ox + x) * 2) = px;
			}
		}
	}
	munmap(fb, fix.smem_len);
	close(fd);
	return 0;
}
