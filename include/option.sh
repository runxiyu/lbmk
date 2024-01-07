# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: 2022 Caleb La Grange <thonkpeasant@protonmail.com>
# SPDX-FileCopyrightText: 2022 Ferass El Hafidi <vitali64pmemail@protonmail.com>
# SPDX-FileCopyrightText: 2020-2024 Leah Rowe <leah@libreboot.org>

vendir="vendorfiles"
appdir="${vendir}/app"
cbdir="src/coreboot/default"
cbcfgsdir="config/coreboot"
ifdtool="cbutils/default/ifdtool"
cbfstool="cbutils/default/cbfstool"
grubcfgsdir="config/grub"
layoutdir="/boot/grub/layouts"
. "${grubcfgsdir}/modules.list"
tmpgit="${PWD}/tmp/gitclone"

eval "$(setvars "" CONFIG_BOARD_DELL_E6400 CONFIG_HAVE_MRC CONFIG_HAVE_ME_BIN \
    CONFIG_ME_BIN_PATH CONFIG_KBC1126_FIRMWARE CONFIG_KBC1126_FW1 \
    CONFIG_KBC1126_FW1_OFFSET CONFIG_KBC1126_FW2 CONFIG_KBC1126_FW2_OFFSET \
    CONFIG_VGA_BIOS_FILE CONFIG_VGA_BIOS_ID CONFIG_GBE_BIN_PATH \
    CONFIG_INCLUDE_SMSC_SCH5545_EC_FW CONFIG_SMSC_SCH5545_EC_FW_FILE \
    CONFIG_IFD_BIN_PATH CONFIG_MRC_FILE _dest board boarddir \
    CONFIG_HAVE_REFCODE_BLOB CONFIG_REFCODE_BLOB_FILE)"

items()
{
	rval=1
	if [ ! -d "${1}" ]; then
		printf "items: directory '%s' doesn't exist" "${1}" 1>&2
		return 1
	fi
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
		if [ "${1%:}" = "depend" ]; then
			depend="${depend} ${2}"
		else
			eval "${1%:}=\"${2}\""
		fi
	done << EOF
	$(eval "awk '${awkstr}' \"${revfile}\"")
EOF
	rm -f "$revfile" || "$_fail" "scan_config: Cannot remove tmpfile"
}

check_defconfig()
{
	for x in "${1}"/config/*; do
		[ -f "${x}" ] && return 1
	done
}

handle_coreboot_utils()
{
	for util in cbfstool ifdtool; do
		x_ ./update trees ${_f} "src/coreboot/${1}/util/${util}"
		[ -z "${mode}" ] && [ ! -f "cbutils/${1}/${util}" ] && \
			x_ mkdir -p "cbutils/${1}" && \
			x_ cp "src/coreboot/${1}/util/${util}/${util}" \
			    "cbutils/${1}"
		[ -z "${mode}" ] || x_ rm -Rf "cbutils/${1}"
	done
}

remkdir()
{
	rm -Rf "${1}" || err "remkdir: !rm -Rf \"${1}\""
	mkdir -p "${1}" || err "remkdir: !mkdir -p \"${1}\""
}
