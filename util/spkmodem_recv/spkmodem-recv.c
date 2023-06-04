/* spkmodem-recv.c - decode spkmodem signals */
/* SPDX-License-Identifier: GPL-2.0-or-later */

#include <err.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Compilation:	gcc -o spkmodem-recv spkmodem-recv  */
/* Usage: parec --channels=1 --rate=48000 --format=s16le | ./spkmodem-recv */

#define SAMPLES_PER_FRAME 240
#define FREQ_SEP_MIN 5
#define FREQ_SEP_MAX 15
#define FREQ_DATA_MIN 15
#define FREQ_DATA_THRESHOLD 25
#define FREQ_DATA_MAX 60
#define THRESHOLD 500

#define DEBUG 0
#define FLUSH_TIMEOUT 1
#define ERR() (errno = errno ? errno : ECANCELED)

signed short frame[2 * SAMPLES_PER_FRAME], pulse[2 * SAMPLES_PER_FRAME];
int f1, f2, lp, ascii_bit = 7;
char ascii = 0;

void handle_audio(void);
void fetch_sample(void);
void read_frame(int ringpos);
int set_ascii_bit(void);
void print_char(void);

int
main(int argc, char *argv[])
{
	int c;
#ifdef __OpenBSD__
	if (pledge("stdio", NULL) == -1)
		err(ERR(), "pledge");
#endif
	while ((c = getopt(argc, argv, "u")) != -1) {
		if (c != 'u')
			err(errno = EINVAL, NULL);
		setvbuf(stdout, NULL, _IONBF, 0);
	}
	while (!feof(stdin))
		handle_audio();
	if (errno)
		err(errno, "Unhandled error upon exit. Exit status is errno.");
	return 0;
}

void
handle_audio(void)
{
	static int llp = 0;
	if (lp > (3 * SAMPLES_PER_FRAME)) {
		ascii_bit = 7;
		ascii = lp = 0;
		++llp;
	}
	if (llp == FLUSH_TIMEOUT)
		if (fflush(stdout) == EOF)
			err(ERR(), NULL);
	if ((f2 <= FREQ_SEP_MIN) || (f2 >= FREQ_SEP_MAX)
	    || (f1 <= FREQ_DATA_MIN) || (f1 >= FREQ_DATA_MAX)) {
		fetch_sample();
		return;
	}
	if (!set_ascii_bit())
		print_char();

	lp = llp = 0;
	for (int sample = 0; sample < SAMPLES_PER_FRAME; sample++)
		fetch_sample();
}

void
fetch_sample(void)
{
	static int ringpos = 0;
	f1 -= pulse[ringpos];
	f1 += pulse[(ringpos + SAMPLES_PER_FRAME) % (2 * SAMPLES_PER_FRAME)];
	f2 -= pulse[(ringpos + SAMPLES_PER_FRAME) % (2 * SAMPLES_PER_FRAME)];

	read_frame(ringpos);
	if ((pulse[ringpos] = (abs(frame[ringpos]) > THRESHOLD) ? 1 : 0))
		++f2;
	++ringpos;
	ringpos %= 2 * SAMPLES_PER_FRAME;
	++lp;
}

void
read_frame(int ringpos)
{
	if ((fread(frame + ringpos, 1, sizeof(frame[0]), stdin)
	    != sizeof(frame[0])) || (ferror(stdin) != 0))
		err(ERR(), "Could not read from frame.");
}

int
set_ascii_bit(void)
{
#if DEBUG
	long stdin_pos = 0;
	if ((stdin_pos = ftell(stdin)) == -1)
		err(ERR(), NULL);
	printf ("%d %d %d @%ld\n", f1, f2, FREQ_DATA_THRESHOLD,
	    stdin_pos - sizeof(frame));
#endif
	if (f1 < FREQ_DATA_THRESHOLD)
		ascii |= (1 << ascii_bit);
	return ascii_bit;
}

void
print_char(void)
{
#if DEBUG
	printf("<%c, %x>", ascii, ascii);
#else
	printf("%c", ascii);
#endif
	ascii_bit = 7;
	ascii = 0;
}
