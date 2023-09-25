# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Nicholas Chin

CC=cc
CFLAGS=-Wall -Wextra -Werror -O2 -pedantic

all: e6400_flash_unlock.c
	$(CC) $(CFLAGS) e6400_flash_unlock.c -o e6400_flash_unlock

clean:
	rm -f e6400_flash_unlock
