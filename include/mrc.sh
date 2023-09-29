# SPDX-License-Identifier: GPL-2.0-only

# Logic based on util/chromeos/crosfirmware.sh in coreboot cfc26ce278.
# Modifications in this version are Copyright 2021 and 2023 Leah Rowe.
# Original copyright detailed in repo: https://review.coreboot.org/coreboot/

extract_mrc()
{
	[ -z "${MRC_board}" ] && err "extract_mrc $MRC_hash: MRC_board not set"
	[ -z "${CONFIG_MRC_FILE}" ] && \
		err "extract_mrc $MRC_hash: CONFIG_MRC_FILE not set"

	_file="${MRC_url##*/}"
	_file="${_file%.zip}"
	_mrc_destination="${CONFIG_MRC_FILE#../../}"
	mkdirs "${_mrc_destination}" "extract_mrc" || return 0

	(
	cd "${appdir}" || err "extract_mrc: !cd ${appdir}"
	extract_partition ROOT-A "${_file}" root-a.ext2
	extract_shellball root-a.ext2 chromeos-firmwareupdate-${MRC_board}
	extract_coreboot chromeos-firmwareupdate-${MRC_board}
	)

	"${cbfstool}" "${appdir}/"coreboot-*.bin extract -n mrc.bin \
	    -f "${_mrc_destination}" -r RO_SECTION || \
	    err "extract_mrc: could not fetch mrc.bin"
}

extract_partition()
{
	NAME=${1}
	FILE=${2}
	ROOTFS=${3}
	_bs=1024

	printf "Extracting ROOT-A partition\n"
	ROOTP=$( printf "unit\nB\nprint\nquit\n" | \
	    parted "${FILE}" 2>/dev/null | grep "${NAME}" )

	START=$(( $( echo ${ROOTP} | cut -f2 -d\ | tr -d "B" ) ))
	SIZE=$(( $( echo ${ROOTP} | cut -f4 -d\ | tr -d "B" ) ))

	dd if="${FILE}" of="${ROOTFS}" bs=${_bs} skip=$(( ${START} / ${_bs} )) \
	    count=$(( ${SIZE} / ${_bs} )) || \
	    err "extract_partition: can't extract root file system"
}

extract_shellball()
{
	ROOTFS=${1}
	SHELLBALL=${2}

	printf "Extracting chromeos-firmwareupdate\n"
	printf "cd /usr/sbin\ndump chromeos-firmwareupdate ${SHELLBALL}\nquit" \
	    | debugfs "${ROOTFS}" || err "extract_shellball: debugfs"
}

extract_coreboot()
{
	_shellball=${1}
	_unpacked=$( mktemp -d )

	printf "Extracting coreboot image\n"
	[ -f "${_shellball}" ] || \
	    err "extract_coreboot: shellball missing in google cros image"
	sh "${_shellball}" --unpack "${_unpacked}" || \
	    err "extract_coreboot: shellball exits with non-zero status"

	# TODO: audit the f* out of that shellball, for each mrc version.
	# it has to be updated for each mrc update. we should ideally
	# implement the functionality ourselves.

	[ -f "${_unpacked}/VERSION" ] || \
	    err "extract_coreboot: VERSION file missing on google coreboot rom"

	_version=$( cat "${_unpacked}/VERSION" | grep BIOS\ version: | \
	    cut -f2 -d: | tr -d \  )

	cp "${_unpacked}/bios.bin" "coreboot-${_version}.bin" || \
	    err "extract_coreboot: cannot copy google cros rom"
}
