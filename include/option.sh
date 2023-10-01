# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: 2022 Caleb La Grange <thonkpeasant@protonmail.com>
# SPDX-FileCopyrightText: 2022 Ferass El Hafidi <vitali64pmemail@protonmail.com>
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

scan_config()
{
	awkstr=" /\{.*${1}.*}{/ {flag=1;next} /\}/{flag=0} flag { print }"
	confdir="${2}"
	_fail="${3}"
	revfile="$(mktemp -t sources.XXXXXXXXXX)" || \
	    "${_fail}" "scan_config: Cannot initialise tmpfile"
	cat "${confdir}/"* > "${revfile}" || \
	    "${_fail}" "scan_config: Cannot concatenate files"
	while read -r line ; do
		set ${line} 1>/dev/null 2>/dev/null || :
		if [ "${1%:}" = "depend" ]; then
			depend="${depend} ${2}"
		else
			eval "${1%:}=\"${2}\""
		fi
	done << EOF
	$(eval "awk '${awkstr}' \"${revfile}\"")
EOF
	rm -f "${revfile}" || "${_fail}" "scan_config: Cannot remove tmpfile"
}
