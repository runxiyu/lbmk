/* spkmodem-recv.c - decode spkmodem signals */
/* SPDX-License-Identifier: GPL-2.0-or-later */

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

int
main(int argc, char *argv[])
{
	int bitn = 7;
	char ascii = 0;
	int i;
	int llp = 0;

	(void)argc; (void)argv;

	while (!feof(stdin)) {
		if (lp > 3 * SAMPLES_PER_FRAME) {
			bitn = 7;
			ascii = 0;
			lp = 0;
			llp++;
		}
		if (llp == FLUSH_TIMEOUT)
			fflush(stdout);

		if (f2 <= FREQ_SEP_MIN || f2 >= FREQ_SEP_MAX
				|| f1 <= FREQ_DATA_MIN || f1 >= FREQ_DATA_MAX) {
			read_sample();
			continue;
		}
#if DEBUG
		printf ("%d %d %d @%d\n", f1, f2, FREQ_DATA_THRESHOLD,
				ftell(stdin) - sizeof(frame));
#endif
		if (f1 < FREQ_DATA_THRESHOLD)
			ascii |= (1 << bitn);
		bitn--;
		if (bitn < 0) {
#if DEBUG
			printf("<%c, %x>", ascii, ascii);
#else
			printf("%c", ascii);
#endif
			bitn = 7;
			ascii = 0;
		}
		lp = 0;
		llp = 0;
		for (i = 0; i < SAMPLES_PER_FRAME; i++)
			read_sample();
	}
	return 0;
}

void
read_sample(void)
{
	amplitude -= abs(frame[ringpos]);
	f1 -= pulse[ringpos];
	f1 += pulse[(ringpos + SAMPLES_PER_FRAME) % (2 * SAMPLES_PER_FRAME)];
	f2 -= pulse[(ringpos + SAMPLES_PER_FRAME) % (2 * SAMPLES_PER_FRAME)];
	fread(frame + ringpos, 1, sizeof(frame[0]), stdin);
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
