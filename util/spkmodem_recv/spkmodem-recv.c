/* spkmodem-recv.c - decode spkmodem signals */
/* SPDX-License-Identifier: GPL-2.0-or-later */

#include <err.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

signed short frame[2 * SAMPLES_PER_FRAME];
signed short pulse[2 * SAMPLES_PER_FRAME];
int ringpos = 0;
int pos, f1, f2;
int amplitude = 0;
int lp = 0;

void read_sample(void);
void print_chars(void);

int
main(int argc, char *argv[])
{
	(void)argc; (void)argv;

	while (!feof(stdin))
		print_chars();

	return 0;
}

void
print_chars(void)
{
	static int ascii_bit = 7;
	static char ascii = 0;
	static int llp = 0;

	if (lp > 3 * SAMPLES_PER_FRAME) {
		ascii_bit = 7;
		ascii = 0;
		lp = 0;
		llp++;
	}
	if (llp == FLUSH_TIMEOUT)
		if (fflush(stdout) == EOF)
			err(errno, NULL);

	if (f2 <= FREQ_SEP_MIN || f2 >= FREQ_SEP_MAX
			|| f1 <= FREQ_DATA_MIN || f1 >= FREQ_DATA_MAX) {
		read_sample();
		return;
	}
#if DEBUG
	long stdin_pos = 0;
	if ((stdin_pos = ftell(stdin)) == -1)
		err(errno, NULL);
	printf ("%d %d %d @%ld\n", f1, f2, FREQ_DATA_THRESHOLD,
			stdin_pos - sizeof(frame));
#endif
	if (f1 < FREQ_DATA_THRESHOLD)
		ascii |= (1 << ascii_bit);
	ascii_bit--;
	if (ascii_bit < 0) {
#if DEBUG
		printf("<%c, %x>", ascii, ascii);
#else
		printf("%c", ascii);
#endif
		ascii_bit = 7;
		ascii = 0;
	}
	lp = 0;
	llp = 0;
	for (int i = 0; i < SAMPLES_PER_FRAME; i++)
		read_sample();
}

void
read_sample(void)
{
	amplitude -= abs(frame[ringpos]);
	f1 -= pulse[ringpos];
	f1 += pulse[(ringpos + SAMPLES_PER_FRAME) % (2 * SAMPLES_PER_FRAME)];
	f2 -= pulse[(ringpos + SAMPLES_PER_FRAME) % (2 * SAMPLES_PER_FRAME)];
	if (fread(frame + ringpos, 1, sizeof(frame[0]), stdin)
			!= sizeof(frame[0]))
		err(errno = ECANCELED, "Could not read frame.");
	amplitude += abs(frame[ringpos]);

	if (abs(frame[ringpos]) > THRESHOLD) { /* rising/falling edge(pulse) */
		pulse[ringpos] = 1;
		pos = !pos;
		f2++;
	} else {
		pulse[ringpos] = 0;
	}

	ringpos++;
	ringpos %= 2 * SAMPLES_PER_FRAME;
	lp++;
}
