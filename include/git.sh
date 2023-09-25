# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2023 Leah Rowe <leah@libreboot.org>

git_reset_rev()
{
	sdir="${1}"
	_rev="${2}"
	_fail="${3}"
	(
	cd "${sdir}" || "${_fail}" "cannot cd to ${sdir}"
	git reset --hard ${_rev} || \
	    "${_fail}" "cannot git reset ${sdir} <- ${rev}"
	)
}

git_am_patches()
{
	sdir="${1}" # assumed to be absolute path
	patchdir="${2}" # ditto
	_fail="${3}"
	(
	cd "${sdir}" || \
	    "${_fail}" "apply_patches: !cd \"${sdir}\""
	for patch in "${patchdir}/"*; do
		[ -L "${patch}" ] && continue
		[ -f "${patch}" ] || continue
		if ! git am "${patch}"; then
			git am --abort || "${_fail}" "${sdir}: !git am --abort"
			"${_fail}" "!git am ${patch} -> ${sdir}"
		fi
	done
	)
	for patches in "${patchdir}/"*; do
		[ -L "${patches}" ] && continue
		[ ! -d "${patches}" ] || \
			git_am_patches "${sdir}" "${patches}" "${_fail}" || \
			    "${_fail}" "apply_patches: !${sdir}/ ${patches}/"
	done
}
