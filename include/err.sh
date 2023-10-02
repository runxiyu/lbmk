# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2022, 2023 Leah Rowe <leah@libreboot.org>

x_() {
	[ $# -lt 1 ] || ${@} || err "non-zero exit status: ${@}"
}
xx_() {
	[ $# -lt 1 ] || ${@} || fail "non-zero exit status: ${@}"
}

setvars()
{
	_setvars=""
	[ $# -lt 2 ] && err "setvars: too few arguments"
	val="${1}"
	shift 1
	for var in $@; do
		_setvars="${var}=\"${val}\"; ${_setvars}"
	done
	printf "%s\n" "${_setvars% }"
}

err()
{
	printf "ERROR %s: %s\n" "${0}" "${1}" 1>&2
	exit 1
}
