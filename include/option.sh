# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: 2022 Caleb La Grange <thonkpeasant@protonmail.com>
# SPDX-FileCopyrightText: 2022 Ferass El Hafidi <vitali64pmemail@protonmail.com>
# SPDX-FileCopyrightText: 2023 Leah Rowe <leah@libreboot.org>

vendir="vendorfiles"
appdir="${vendir}/app"
cbdir="src/coreboot/default"
cbcfgsdir="config/coreboot"
ifdtool="cbutils/default/ifdtool"
cbfstool="cbutils/default/cbfstool"

eval "$(setvars "" CONFIG_BOARD_DELL_E6400 CONFIG_HAVE_MRC CONFIG_HAVE_ME_BIN \
    CONFIG_ME_BIN_PATH CONFIG_KBC1126_FIRMWARE CONFIG_KBC1126_FW1 \
    CONFIG_KBC1126_FW1_OFFSET CONFIG_KBC1126_FW2 CONFIG_KBC1126_FW2_OFFSET \
    CONFIG_VGA_BIOS_FILE CONFIG_VGA_BIOS_ID CONFIG_GBE_BIN_PATH \
    CONFIG_INCLUDE_SMSC_SCH5545_EC_FW CONFIG_SMSC_SCH5545_EC_FW_FILE \
    CONFIG_IFD_BIN_PATH CONFIG_MRC_FILE _dest board boarddir)"

items()
{
	rval=1
	[ ! -d "${1}" ] && \
		printf "items: directory '%s' doesn't exist" "${1}" && \
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
	revfile="$(mktemp -t sources.XXXXXXXXXX)"
	cat "${confdir}/"* > "${revfile}" || \
	    "${_fail}" "scan_config ${confdir}: Cannot concatenate files"
	while read -r line ; do
		set ${line} 1>/dev/null 2>/dev/null || :
		[ "${1%:}" = "depend" ] && depend="${depend} ${2}" && continue
		eval "${1%:}=\"${2}\""
	done << EOF
	$(eval "awk '${awkstr}' \"${revfile}\"")
EOF
	rm -f "${revfile}" || "${_fail}" "scan_config: Cannot remove tmpfile"
}

check_defconfig()
{
	for x in "${1}"/config/*; do
		[ -f "${x}" ] && return 0
	done
	return 1
}

handle_coreboot_utils()
{
	for util in cbfstool ifdtool; do
		x_ ./update trees ${_f} "src/coreboot/${1}/util/${util}"
		[ -z "${mode}" ] && [ ! -f "cbutils/${1}/${util}" ] && \
			x_ mkdir -p "cbutils/${1}" && \
			x_ cp "src/coreboot/${1}/util/${util}/${util}" \
			    "cbutils/${1}"
		[ -z "${mode}" ] || \
			x_ rm -Rf "cbutils/${1}"
	done
}

modify_coreboot_rom()
{
	rompath="${codedir}/build/coreboot.rom"
	[ -f "${rompath}" ] || \
	    err "modify_coreboot_rom: does not exist: ${rompath}"
	tmprom="$(mktemp -t rom.XXXXXXXXXX)"
	x_ rm -f "${tmprom}"

	if [ "${romtype}" = "d8d16sas" ]; then
		# pike2008 roms hang seabios. an empty rom will override
		# the built-in one, thus disabling all execution of it
		x_ touch "${tmprom}"
		for deviceID in "0072" "3050"; do
			x_ "${cbfstool}" "${rompath}" add -f "${tmprom}" \
			    -n "pci1000,${deviceID}.rom" -t raw
		done
	elif [ "${romtype}" = "i945 laptop" ]; then
		# for bucts-based installation method from factory bios
		x_ dd if="${rompath}" of="${tmprom}" bs=1 \
		    skip=$(($(stat -c %s "${rompath}") - 0x10000)) \
		    count=64k
		x_ dd if="${tmprom}" of="${rompath}" bs=1 \
		    seek=$(($(stat -c %s "${rompath}") - 0x20000)) \
		    count=64k conv=notrunc
	fi
	x_ rm -f "${tmprom}"
}
