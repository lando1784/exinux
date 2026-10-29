/*
 * exinux-fb-refresher: keep the Galaxy S20 FE panel showing /dev/fb0.
 *
 * The Exynos DECON driver drives a command-mode DSI panel: writing to the
 * framebuffer memory is not enough, a frame only reaches the panel when
 * someone triggers an update. Android's hwcomposer does that through ioctls;
 * for plain fbdev clients (Xorg fbdev, fbterm, ...) the driver triggers it
 * in decon_pan_display(). This daemon unblanks the display and pans to the
 * current offset at a fixed rate.
 *
 * Usage: exinux-fb-refresher [-d /dev/fb0] [-r fps]
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

static void on_signal(int sig)
{
	(void)sig;
	running = 0;
}

static void sleep_until(struct timespec *next, long period_ns)
{
	next->tv_nsec += period_ns;
	while (next->tv_nsec >= 1000000000L) {
		next->tv_nsec -= 1000000000L;
		next->tv_sec++;
	}
	while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, next, NULL) == EINTR && running)
		;
}

int main(int argc, char **argv)
{
	const char *dev = "/dev/fb0";
	int fps = 30;
	int opt, fd;
	struct fb_var_screeninfo var;
	struct timespec next;
	unsigned long errors = 0;

	while ((opt = getopt(argc, argv, "d:r:")) != -1) {
		switch (opt) {
		case 'd': dev = optarg; break;
		case 'r': fps = atoi(optarg); break;
		default:
			fprintf(stderr, "usage: %s [-d fbdev] [-r fps]\n", argv[0]);
			return 2;
		}
	}
	if (fps < 1 || fps > 120)
		fps = 30;

	fd = open(dev, O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "open %s: %s\n", dev, strerror(errno));
		return 1;
	}

	if (ioctl(fd, FBIOBLANK, FB_BLANK_UNBLANK) < 0)
		fprintf(stderr, "unblank: %s\n", strerror(errno));

	if (ioctl(fd, FBIOGET_VSCREENINFO, &var) < 0) {
		fprintf(stderr, "FBIOGET_VSCREENINFO: %s\n", strerror(errno));
		return 1;
	}
	fprintf(stderr, "%s: %ux%u %ubpp, refreshing at %d fps\n",
		dev, var.xres, var.yres, var.bits_per_pixel, fps);

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);
	clock_gettime(CLOCK_MONOTONIC, &next);

	while (running) {
		/* Re-read so we follow mode or offset changes made by clients. */
		if (ioctl(fd, FBIOGET_VSCREENINFO, &var) == 0 &&
		    ioctl(fd, FBIOPAN_DISPLAY, &var) < 0) {
			if (errors++ % 300 == 0)
				fprintf(stderr, "FBIOPAN_DISPLAY: %s\n", strerror(errno));
		}
		sleep_until(&next, 1000000000L / fps);
	}

	close(fd);
	return 0;
}
