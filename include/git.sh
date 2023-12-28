# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2020,2021,2023 Leah Rowe <leah@libreboot.org>
# SPDX-FileCopyrightText: 2022 Caleb La Grange <thonkpeasant@protonmail.com>

# This file is only used by update/project/trees

eval "$(setvars "" _target rev _xm loc url bkup_url depend patchfail)"
tmp_git_dir="${PWD}/tmp/gitclone"

fetch_project_trees()
{
	_target="${target}"
	[ -d "src/${project}/${project}" ] || fetch_from_upstream
	fetch_config
	[ -z "${rev}" ] && err "fetch_project_trees $target: undefined rev"
	if [ -d "src/${project}/${tree}" ]; then
		printf "download/%s %s (%s): exists\n" \
		    "${project}" "${tree}" "${_target}" 1>&2
		return 0
	fi
	prepare_new_tree
}

fetch_from_upstream()
{
	[ -d "src/${project}/${project}" ] && return 0

	x_ mkdir -p "src/${project}"
	fetch_project_repo "${project}"
}

fetch_config()
{
	rm -f "${cfgsdir}/"*/seen || err "fetch_config ${cfgsdir}: !rm seen"
	while true; do
		eval "$(setvars "" rev tree)"
		_xm="fetch_config ${project}/${_target}"
		load_target_config "${_target}"
		[ "${_target}" = "${tree}" ] && break
		_target="${tree}"
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

	touch "${cfgsdir}/${1}/seen" || \
	    err "load_config $cfgsdir/$1: !mk seen"
}

prepare_new_tree()
{
	printf "Creating %s tree %s (%s)\n" "$project" "$tree" "$_target"

	remkdir "${tmp_git_dir%/*}"
	cp -R "src/${project}/${project}" "${tmp_git_dir}" || \
	    err "prepare_new_tree ${project}/${tree}: can't make tmpclone"
	git_reset_rev "${tmp_git_dir}" "${rev}"
	[ ! -f "${tmp_git_dir}/.gitmodules" ] || \
		git -C "${tmp_git_dir}" submodule update --init --checkout \
		    || err "prepare_new_tree ${project}/${tree}: !submodules"
	git_am_patches "${tmp_git_dir}" "$PWD/$cfgsdir/$tree/patches" || \
	    err "prepare_new_tree ${project}/${tree}: patch fail"
	[ "${patchfail}" = "y" ] && err "PATCH FAIL"

	mv "${tmp_git_dir}" "src/${project}/${tree}" || \
	    err "prepare_new_tree ${project}/${tree}: can't copy tmpclone"
}

fetch_project_repo()
{
	scan_config "${project}" "config/git" "err"
	verify_config

	clone_project
	[ -z "${depend}" ] || for d in ${depend} ; do
		x_ ./update trees -f ${d}
	done
	rm -Rf "${tmp_git_dir}" || err "fetch_repo: !rm -Rf ${tmp_git_dir}"
}

verify_config()
{
	[ -z "${rev+x}" ] && err 'verify_config: rev not set'
	[ -z "${loc+x}" ] && err 'verify_config: loc not set'
	[ -z "${url+x}" ] && err 'verify_config: url not set'; return 0
}

clone_project()
{
	remkdir "${tmp_git_dir%/}"

	loc="${loc#src/}"
	loc="src/${loc}"
	if [ -d "${loc}" ]; then
		printf "%s already exists, so skipping download\n" "$loc" 1>&2
		return 0
	fi

	git clone ${url} "${tmp_git_dir}" || \
	    git clone ${bkup_url} "${tmp_git_dir}" || \
	    err "clone_project: could not download ${project}"
	git_reset_rev "${tmp_git_dir}" "${rev}"
	git_am_patches "${tmp_git_dir}" "${PWD}/config/${project}/patches" \
	    || err "clone_project ${project} ${loc}: patch fail"
	[ "${patchfail}" = "y" ] && err "PATCH FAIL"

	x_ rm -Rf "${loc}"
	[ "${loc}" = "${loc%/*}" ] || x_ mkdir -p "${loc%/*}"
	mv "${tmp_git_dir}" "${loc}" || \
	    err "clone_project: !mv ${tmp_git_dir} ${loc}"
}

git_reset_rev()
{
	git -C "${1}" reset --hard ${2} || err "!git reset ${1} <- ${2}"
	if [ "$project" != "coreboot" ] && [ "$project" != "u-boot" ] && \
	    [ -f "${1}/.gitmodules" ]; then
		git -C "${1}" submodule update --init --checkout || \
		    err "git_reset_rev ${1}: can't download submodules"
	fi
}

git_am_patches()
{
	sdir="${1}" # assumed to be absolute path
	patchdir="${2}" # ditto
	for patch in "${patchdir}/"*; do
		[ -L "${patch}" ] && continue
		[ -f "${patch}" ] || continue
		git -C "${sdir}" am "${patch}" || patchfail="y"
		[ "${patchfail}" != "y" ] && continue
		git -C "$sdir" am --abort || err  "$sdir: !git am --abort"
		err  "!git am ${patch} -> ${sdir}"
	done
	for patches in "${patchdir}/"*; do
		[ -L "${patches}" ] && continue
		[ ! -d "${patches}" ] && continue
		git_am_patches "${sdir}" "${patches}"
	done
	[ "${patchfail}" = "y" ] && return 1; return 0
}
