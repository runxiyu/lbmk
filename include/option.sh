# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Leah Rowe <leah@libreboot.org>

listitems()
{
	rval=1
	[ ! -d "${1}" ] && \
		printf "listitems: directory '%s' doesn't exist" "${1}" && \
		    return 1
	for x in "${1}/"*; do
		# -e used because this is for files *or* directories
		[ -e "${x}" ] || continue
		[ "${x##*/}" = "build.list" ] && continue
		printf "%s\n" "${x##*/}" 2>/dev/null
		rval=0
	done
	return ${rval}
}
