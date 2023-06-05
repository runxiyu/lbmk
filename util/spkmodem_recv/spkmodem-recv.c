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

#define ERR() (errno = errno ? errno : ECANCELED)
#define reset_char() ascii = 0, ascii_bit = 7

signed short frame[2 * SAMPLES_PER_FRAME], pulse[2 * SAMPLES_PER_FRAME];
int debug, freq_data, freq_separator, sample_count, ascii_bit = 7;
char ascii = 0;

void handle_audio(void);
void fetch_sample(void);
void read_frame(int ringpos);
int set_ascii_bit(void);
void print_char(void);
void print_stats(void);

int
main(int argc, char *argv[])
{
	int c;
#ifdef __OpenBSD__
	if (pledge("stdio", NULL) == -1)
		err(ERR(), "pledge");
#endif
	while ((c = getopt(argc, argv, "d")) != -1) {
		if (c != 'd')
			err(errno = EINVAL, NULL);
		debug = 1;
	}
	setvbuf(stdout, NULL, _IONBF, 0);
	while (!feof(stdin))
		handle_audio();
	if (errno && debug)
		err(errno, "Unhandled error, errno %d", errno);
	return errno;
}

void
handle_audio(void)
{
	if (sample_count > (3 * SAMPLES_PER_FRAME))
		sample_count = reset_char();
	if ((freq_separator <= FREQ_SEP_MIN) || (freq_separator >= FREQ_SEP_MAX)
	    || (freq_data <= FREQ_DATA_MIN) || (freq_data >= FREQ_DATA_MAX)) {
		fetch_sample();
		return;
	}

	if (!set_ascii_bit())
		print_char();
	sample_count = 0;
	for (int sample = 0; sample < SAMPLES_PER_FRAME; sample++)
		fetch_sample();
}

void
fetch_sample(void)
{
	static int ringpos = 0;
	freq_data -= pulse[ringpos];
	freq_data += pulse[(ringpos + SAMPLES_PER_FRAME)
	    % (2 * SAMPLES_PER_FRAME)];
	freq_separator -= pulse[(ringpos + SAMPLES_PER_FRAME)
	    % (2 * SAMPLES_PER_FRAME)];

	read_frame(ringpos);
	if ((pulse[ringpos] = (abs(frame[ringpos]) > THRESHOLD) ? 1 : 0))
		++freq_separator;
	++ringpos;
	ringpos %= 2 * SAMPLES_PER_FRAME;
	++sample_count;
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
	if (debug)
		print_stats();
	if (freq_data < FREQ_DATA_THRESHOLD)
		ascii |= (1 << ascii_bit);
	return ascii_bit;
}

void
print_char(void)
{
	if (debug)
		printf("<%c, %x>", ascii, ascii);
	else
		printf("%c", ascii);
	reset_char();
}

void
print_stats(void)
{
	long stdin_pos = 0;
	if ((stdin_pos = ftell(stdin)) == -1)
		err(ERR(), NULL);
	printf ("%d %d %d @%ld\n", freq_data, freq_separator,
	    FREQ_DATA_THRESHOLD, stdin_pos - sizeof(frame));
}
