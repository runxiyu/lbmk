# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2023 Leah Rowe <leah@libreboot.org>

main()
{
	while getopts b:m:u:c:x: option
	do
		_flag="${1}"
		case "${1}" in
		-b) mode="all" ;;
		-u) mode="oldconfig" ;;
		-m) mode="menuconfig" ;;
		-c) mode="distclean" ;;
		-x) mode="crossgcc-clean" ;;
		*) fail "Invalid option" ;;
		esac
		shift; project="${OPTARG}"; shift
	done
	[ -z "${mode}" ] && fail "mode not given (-m, -u, -b, -c or -x)"
	[ -z "${project}" ] && fail "project name not specified"

	handle_dependencies $@
	handle_targets
}

fail()
{
	[ -z "${codedir}" ] || ./handle make file -c "${codedir}" || :
	err "${1}"
}
