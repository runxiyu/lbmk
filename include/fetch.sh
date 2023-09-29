# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: 2023 Leah Rowe <leah@libreboot.org>

agent="Mozilla/5.0 (Windows NT 10.0; rv:91.0) Gecko/20100101 Firefox/91.0"
dl_path=""

fetch()
{
	dl_type="${1}"
	dl="${2}"
	dl_bkup="${3}"
	dlsum="${4}"
	dl_path="${5}"
	_fail="${6}"

	mkdir -p "${dl_path%/*}" || "${_fail}" "fetch: !mkdir ${dl_path%/*}"

	dl_fail="y"
	vendor_checksum "${dlsum}" "${dl_path}" && dl_fail="n"
	for url in "${dl}" "${dl_bkup}"; do
		[ "${dl_fail}" = "n" ] && break
		[ -z "${url}" ] && continue
		rm -f "${dl_path}" || "${_fail}" "fetch: !rm -f ${dl_path}"
		wget --tries 3 -U "${agent}" "${url}" -O "${dl_path}" || \
		    continue
		vendor_checksum "${dlsum}" "${dl_path}" && dl_fail="n"
	done
	[ "${dl_fail}" = "y" ] && \
		"${_fail}" "fetch ${dlsum}: matched file unavailable"

	eval "extract_${dl_type}"
}

vendor_checksum()
{
	if [ "$(sha512sum ${2} | awk '{print $1}')" != "${1}" ]; then
		printf "Bad checksum for file: %s\n" "${2}" 1>&2
		rm -f "${2}" || :
		return 1
	fi
}
