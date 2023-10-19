# SPDX-License-Identifier: GPL-2.0-only

# Logic based on util/chromeos/crosfirmware.sh in coreboot cfc26ce278.
# Modifications in this version are Copyright 2021 and 2023 Leah Rowe.
# Original copyright detailed in repo: https://review.coreboot.org/coreboot/

eval "$(setvars "" MRC_url MRC_url_bkup MRC_hash MRC_board ROOTFS SHELLBALL)"

extract_mrc()
{
	[ -z "${MRC_board}" ] && err "extract_mrc $MRC_hash: MRC_board not set"
	[ -z "${CONFIG_MRC_FILE}" ] && \
		err "extract_mrc $MRC_hash: CONFIG_MRC_FILE not set"

	ROOTFS="root-a.ext2"
	SHELLBALL="chromeos-firmwareupdate-${MRC_board}"

	(
	x_ cd "${appdir}"
	extract_partition
	extract_shellball
	extract_coreboot
	)

	x_ "${cbfstool}" "${appdir}/"coreboot-*.bin extract -n mrc.bin \
	    -f "${_dest}" -r RO_SECTION
}

extract_partition()
{
	NAME="ROOT-A"
	FILE="${MRC_url##*/}"
	FILE="${FILE%.zip}"
	_bs=1024

	printf "Extracting ROOT-A partition\n"
	ROOTP=$( printf "unit\nB\nprint\nquit\n" | \
	    parted "${FILE}" 2>/dev/null | grep "${NAME}" )

	START=$(( $( echo ${ROOTP} | cut -f2 -d\ | tr -d "B" ) ))
	SIZE=$(( $( echo ${ROOTP} | cut -f4 -d\ | tr -d "B" ) ))

	x_ dd if="${FILE}" of="${ROOTFS}" bs=${_bs} \
	    skip=$(( ${START} / ${_bs} )) count=$(( ${SIZE} / ${_bs} ))
}

extract_shellball()
{
	printf "Extracting chromeos-firmwareupdate\n"
	printf "cd /usr/sbin\ndump chromeos-firmwareupdate ${SHELLBALL}\nquit" \
	    | debugfs "${ROOTFS}" || err "extract_shellball: debugfs"
}

extract_coreboot()
{
	_unpacked=$( mktemp -d )

	printf "Extracting coreboot image\n"
	[ -f "${SHELLBALL}" ] || \
	    err "extract_coreboot: shellball missing in google cros image"
	x_ sh "${SHELLBALL}" --unpack "${_unpacked}"

	# TODO: audit the f* out of that shellball, for each mrc version.
	# it has to be updated for each mrc update. we should ideally
	# implement the functionality ourselves.

	[ -f "${_unpacked}/VERSION" ] || \
	    err "extract_coreboot: VERSION file missing on google coreboot rom"

	_version=$( cat "${_unpacked}/VERSION" | grep BIOS\ version: | \
	    cut -f2 -d: | tr -d \  )

	x_ cp "${_unpacked}/bios.bin" "coreboot-${_version}.bin"
}
