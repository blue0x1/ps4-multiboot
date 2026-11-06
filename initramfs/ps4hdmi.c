/* Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1> */
/*
 * ps4hdmi: keep the PS4 Slim/Pro HDMI bridge (MN864729) output on while the
 * initramfs runs, so the boot screen and first-boot progress are visible.
 * Same job as ps4-hdmi-keepalive in the installed distro; C so it fits in the initramfs.
 *
 *   ps4hdmi           check every 2 s forever (run in the background)
 *   ps4hdmi once      check once
 *
 * The bridge turns its HDMI output enables (0x1e00 bit 0, 0x1e02 bits 4-6)
 * off and sets the video mute (0x705f bit 7) shortly after boot. Talks to it
 * through the PS4 ICC device (/dev/icc, major 73) with the I2C command-queue
 * format of drivers/gpu/drm/amd/amdgpu/ps4_bridge.c.
 */
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

struct icc_cmd {
	uint8_t major;
	uint16_t minor;
	void *data;
	uint16_t length;
	void *reply;
	uint16_t reply_length;
};
#define ICC_IOCTL_CMD _IOWR('I', 1, struct icc_cmd)

static int fd = -1;

static void klog(const char *fmt, ...)
{
	char buf[160];
	va_list ap;
	int k = open("/dev/kmsg", O_WRONLY), n;

	va_start(ap, fmt);
	n = snprintf(buf, sizeof(buf), "ps4hdmi: ");
	vsnprintf(buf + n, sizeof(buf) - n, fmt, ap);
	va_end(ap);
	if (k >= 0) {
		write(k, buf, strlen(buf));
		close(k);
	}
}
static uint8_t reply[0x7f0];

/* One command group: hdr(major, length, minor, count) + payload. */
static int run(uint8_t code, uint8_t major, uint8_t minor, const uint8_t *ops,
	       uint8_t count, uint8_t op_len)
{
	uint8_t req[64];
	uint16_t body = 4 + count * op_len;
	uint16_t total = 4 + body;
	struct icc_cmd c;
	int n;

	req[0] = code;
	req[1] = total & 0xff;
	req[2] = total >> 8;
	req[3] = 1;
	req[4] = major;
	req[5] = (uint8_t)body;
	req[6] = minor;
	req[7] = count;
	memcpy(req + 8, ops, (size_t)count * op_len);

	memset(&c, 0, sizeof(c));
	c.major = 0x10;
	c.minor = 0;
	c.data = req;
	c.length = total;
	c.reply = reply;
	c.reply_length = sizeof(reply);
	n = ioctl(fd, ICC_IOCTL_CMD, &c);
	if (n < 5 || reply[0] || reply[1])
		return -1;
	return n;
}

static int read_reg(uint16_t addr)
{
	uint8_t op[4] = { 1, addr >> 8, addr & 0xff, 0 };

	if (run(1, 1, 1, op, 1, 4) < 9)
		return -1;
	return reply[8];
}

static void output_on(void)
{
	uint8_t masks[10] = { 1, 0x1e, 0x02, 0x70, 0x70,   /* 0x1e02 |= 0x70 */
			      1, 0x1e, 0x00, 0x01, 0x01 }; /* 0x1e00 |= 0x01 */
	uint8_t unmute[4] = { 1, 0x70, 0x5f, 0x10 };       /* VMUTECNT = 0x10 */

	run(4, 2, 3, masks, 2, 5);
	run(4, 2, 2, unmute, 1, 4);
}

static void check(void)
{
	int en = read_reg(0x1e00), mute = read_reg(0x705f);

	static int fails;

	if (en < 0 || mute < 0) {
		if (fails++ % 15 == 0)
			klog("bridge read failed (%d)", fails);
		return;
	}
	if (!(en & 0x01) || (mute & 0x80)) {
		klog("output was off (0x1e00=0x%02x 0x705f=0x%02x), turning it on", en, mute);
		output_on();
	}
}

int main(int argc, char **argv)
{
	char id[16] = "";
	int g = open("/sys/bus/pci/devices/0000:00:01.0/device", O_RDONLY);

	if (g >= 0) {
		read(g, id, sizeof(id) - 1);
		close(g);
	}
	if (!strncmp(id, "0x9920", 6))
		return 0; /* fat CUH-10xx/11xx: MN86471A, not affected */

	/* The ICC driver can come up after this starts: keep trying. */
	for (int i = 0; fd < 0; i++) {
		if (access("/dev/icc", F_OK))
			mknod("/dev/icc", S_IFCHR | 0600, makedev(73, 0));
		fd = open("/dev/icc", O_RDWR);
		if (fd < 0) {
			if (i % 30 == 0)
				klog("waiting for /dev/icc");
			sleep(1);
		}
	}
	klog("running, bridge 0x1e00=0x%02x", read_reg(0x1e00));
	if (argc > 1 && !strcmp(argv[1], "once")) {
		check();
		return 0;
	}
	for (;;) {
		check();
		sleep(2);
	}
}
