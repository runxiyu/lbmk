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

signed short frame[2 * SAMPLES_PER_FRAME];
signed short pulse[2 * SAMPLES_PER_FRAME];
int f1, f2, lp, ascii_bit = 7;
char ascii = 0;

void handle_audio(void);
void print_char(void);
void fetch_sample(void);

int
main(int argc, char *argv[])
{
	int c;

#ifdef __OpenBSD__
	if (pledge("stdio", NULL) == -1)
		err(errno, "pledge");
#endif

	while ((c = getopt(argc, argv, "u")) != -1) {
		switch (c) {
		case 'u':
			setvbuf(stdout, NULL, _IONBF, 0);
			break;
		default:
			err(errno = EINVAL, NULL);
		}
	}

	while (!feof(stdin))
		handle_audio();

	return errno;
}

void
handle_audio(void)
{
	static int llp = 0;

	if (lp > (3 * SAMPLES_PER_FRAME)) {
		ascii_bit = 7;
		ascii = 0;
		lp = 0;
		llp++;
	}
	if (llp == FLUSH_TIMEOUT)
		if (fflush(stdout) == EOF)
			err(errno, NULL);

	if ((f2 <= FREQ_SEP_MIN) || (f2 >= FREQ_SEP_MAX)
			|| (f1 <= FREQ_DATA_MIN) || (f1 >= FREQ_DATA_MAX)) {
		fetch_sample();
		return;
	}

	print_char();

	lp = 0;
	llp = 0;
	for (int i = 0; i < SAMPLES_PER_FRAME; i++)
		fetch_sample();
}

void
fetch_sample(void)
{
	static int ringpos = 0;

	f1 -= pulse[ringpos];
	f1 += pulse[(ringpos + SAMPLES_PER_FRAME) % (2 * SAMPLES_PER_FRAME)];
	f2 -= pulse[(ringpos + SAMPLES_PER_FRAME) % (2 * SAMPLES_PER_FRAME)];
	if (fread(frame + ringpos, 1, sizeof(frame[0]), stdin)
			!= sizeof(frame[0]))
		err(errno = ECANCELED, "Could not read frame.");

	if (abs(frame[ringpos]) > THRESHOLD) { /* rising/falling edge(pulse) */
		pulse[ringpos] = 1;
		f2++;
	} else {
		pulse[ringpos] = 0;
	}

	ringpos++;
	ringpos %= 2 * SAMPLES_PER_FRAME;
	lp++;
}

void
print_char(void)
{
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
}
