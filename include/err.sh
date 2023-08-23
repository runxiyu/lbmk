# Copyright (c) 2022, 2023 Leah Rowe <info@minifree.org>
# SPDX-License-Identifier: MIT

err()
{
	printf "ERROR %s: %s\n" "${0}" "${1}" 1>&2
	exit 1
}
