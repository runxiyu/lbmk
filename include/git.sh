# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2020,2021,2023 Leah Rowe <leah@libreboot.org>
# SPDX-FileCopyrightText: 2022 Caleb La Grange <thonkpeasant@protonmail.com>

# This file is only used by update/project/trees

eval "$(setvars "" _target rev _xm loc url bkup_url depend)"
tmp_git_dir="${PWD}/tmp/gitclone"

fetch_project_trees()
{
	_target="${target}"
	[ -d "src/${project}/${project}" ] || fetch_from_upstream
	fetch_config
	[ -z "${rev}" ] && err "fetch_project_trees $target: undefined rev"
	[ -d "src/${project}/${tree}" ] && \
		printf "download/%s %s (%s): exists\n" \
		    "${project}" "${tree}" "${_target}" 1>&2 && \
		return 1
	prepare_new_tree
}

fetch_from_upstream()
{
	[ -d "src/${project}/${project}" ] && return 0

	x_ mkdir -p "src/${project}"
	x_ fetch_project_repo "${project}"
}

fetch_config()
{
	x_ rm -f "${cfgsdir}/"*/seen
	while true; do
		eval "$(setvars "" rev tree)"
		_xm="fetch_config ${project}/${_target}"
		load_target_config "${_target}"
		[ "${_target}" != "${tree}" ] && _target="${tree}" && continue
		break
	done
}

load_target_config()
{
	[ -f "${cfgsdir}/${1}/target.cfg" ] || \
		err "${_xm} check: target.cfg does not exist"
	[ -f "${cfgsdir}/${1}/seen" ] && \
		err "${_xm} check: infinite loop in tree definitions"

	. "${cfgsdir}/${1}/target.cfg" || \
	    err "load_target_config ${cfgsdir}/${1}: cannot load config"

	x_ touch "${cfgsdir}/${1}/seen"
}

prepare_new_tree()
{
	printf "Creating %s tree %s (%s)\n" "${project}" "${tree}" "${_target}"

	x_ cp -R "src/${project}/${project}" "src/${project}/${tree}"
	x_ git_reset_rev "src/${project}/${tree}" "${rev}"
	(
	x_ cd "src/${project}/${tree}"
	git submodule update --init --checkout || \
	    err "prepare_new_tree ${project}/${tree}: can't update git modules"
	)
	git_am_patches "${PWD}/src/${project}/${tree}" \
	    "${PWD}/${cfgsdir}/${tree}/patches"
}

fetch_project_repo()
{
	scan_config "${project}" "config/git" "err"
	verify_config

	clone_project
	[ "${depend}" = "" ] || for d in ${depend} ; do
		x_ ./update trees -f ${d}
	done
	x_ rm -Rf "${tmp_git_dir}"
}

verify_config()
{
	[ -z "${rev+x}" ] && err 'verify_config: rev not set'
	[ -z "${loc+x}" ] && err 'verify_config: loc not set'
	[ -z "${url+x}" ] && err 'verify_config: url not set'
	return 0
}

clone_project()
{
	x_ rm -Rf "${tmp_git_dir}"
	x_ mkdir -p "${tmp_git_dir%/*}"

	loc="${loc#src/}"
	loc="src/${loc}"

	git clone ${url} "${tmp_git_dir}" || \
	    git clone ${bkup_url} "${tmp_git_dir}" || \
	    err "clone_project: could not download ${project}"
	git_reset_rev "${tmp_git_dir}" "${rev}" || \
	    err "clone_project ${loc}/: cannot reset <- ${rev}"
	git_am_patches "${tmp_git_dir}" "${PWD}/config/${project}/patches" || \
	    err "clone_project ${loc}/: cannot apply patches"

	x_ rm -Rf "${loc}"
	[ "${loc}" = "${loc%/*}" ] || x_ mkdir -p ${loc%/*}
	x_ mv "${tmp_git_dir}" "${loc}"
}

git_reset_rev()
{
	sdir="${1}"
	_rev="${2}"
	(
	x_ cd "${sdir}"
	git reset --hard ${_rev} || \
	    err  "cannot git reset ${sdir} <- ${rev}"
	)
}

git_am_patches()
{
	sdir="${1}" # assumed to be absolute path
	patchdir="${2}" # ditto
	(
	x_ cd "${sdir}"
	for patch in "${patchdir}/"*; do
		[ -L "${patch}" ] && continue
		[ -f "${patch}" ] || continue
		if ! git am "${patch}"; then
			git am --abort || err  "${sdir}: !git am --abort"
			err  "!git am ${patch} -> ${sdir}"
		fi
	done
	)
	for patches in "${patchdir}/"*; do
		[ -L "${patches}" ] && continue
		[ ! -d "${patches}" ] || \
			git_am_patches "${sdir}" "${patches}" err  || \
			    err  "apply_patches: !${sdir}/ ${patches}/"
	done
}
