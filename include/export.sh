# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Leah Rowe <leah@libreboot.org>

tmpdir=""
tmpdir_was_set="y"
set | grep TMPDIR 1>/dev/null 2>/dev/null || tmpdir_was_set="n"
if [ "${tmpdir_was_set}" = "y" ]; then
	tmpdir="${TMPDIR##*/}"
	tmpdir="${TMPDIR%_*}"
	if [ "${tmpdir}" = "lbmk" ]; then
		tmpdir=""
		tmpdir_was_set="n"
	fi
fi
if [ "${tmpdir_was_set}" = "n" ]; then
	export TMPDIR="/tmp"
	tmpdir="$(mktemp -d -t lbmk_XXXXXXXX)"
	export TMPDIR="${tmpdir}"
else
	export TMPDIR="${TMPDIR}"
fi
tmpdir="${TMPDIR}"
