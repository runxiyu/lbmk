/* spkmodem-recv.c - decode spkmodem signals */
/*
 *  Copyright (C) 2013  Free Software Foundation, Inc.
 *
 *  spkmodem-recv is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  spkmodem-recv is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with spkmodem-recv.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <err.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Compilation:	cc -o spkmodem-recv spkmodem-recv.c */
/* Usage: parec --channels=1 --rate=48000 --format=s16le | ./spkmodem-recv */

#define SAMPLES_PER_FRAME 240
#define MAX_SAMPLES (2 * SAMPLES_PER_FRAME)
#define FREQ_SEP_MIN 5
#define FREQ_SEP_MAX 15
#define FREQ_DATA_MIN 15
#define FREQ_DATA_THRESHOLD 25
#define FREQ_DATA_MAX 60
#define THRESHOLD 500

#define ERR() (errno = errno ? errno : ECANCELED)
#define reset_char() ascii = 0, ascii_bit = 7

signed short frame[MAX_SAMPLES], pulse[MAX_SAMPLES];
int ringpos, debug, freq_data, freq_separator, sample_count, ascii_bit = 7;
char ascii = 0;

void handle_audio(void);
void decode_pulse(void);
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
	while ((c = getopt(argc, argv, "d")) != -1)
		if (!(debug = (c == 'd')))
			err(errno = EINVAL, NULL);
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
		decode_pulse();
		return;
	}

	if (set_ascii_bit() < 0)
		print_char();
	sample_count = 0;
	for (int sample = 0; sample < SAMPLES_PER_FRAME; sample++)
		decode_pulse();
}

void
decode_pulse(void)
{
	int next_ringpos = (ringpos + SAMPLES_PER_FRAME) % MAX_SAMPLES;
	freq_data -= pulse[ringpos];
	freq_data += pulse[next_ringpos];
	freq_separator -= pulse[next_ringpos];

	fread(frame + ringpos, 1, sizeof(frame[0]), stdin);
	if (ferror(stdin) != 0)
		err(ERR(), "Could not read from frame.");

	if ((pulse[ringpos] = (abs(frame[ringpos]) > THRESHOLD) ? 1 : 0))
		++freq_separator;
	++ringpos;
	ringpos %= MAX_SAMPLES;
	++sample_count;
}

int
set_ascii_bit(void)
{
	if (debug)
		print_stats();
	if (freq_data < FREQ_DATA_THRESHOLD)
		ascii |= (1 << ascii_bit);
	--ascii_bit;
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
	long stdin_pos;
	if ((stdin_pos = ftell(stdin)) == -1)
		err(ERR(), NULL);
	printf ("%d %d %d @%ld\n", freq_data, freq_separator,
	    FREQ_DATA_THRESHOLD, stdin_pos - sizeof(frame));
}
