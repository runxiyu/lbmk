# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 Leah Rowe <leah@libreboot.org>

check_defconfig()
{
	no_config="printf \"No target defconfig in %s\\n\" ${1} 1>&2; return 1"
	for x in "${1}"/config/*; do
		[ -f "${x}" ] && no_config=""
	done
	eval "${no_config}"
}
