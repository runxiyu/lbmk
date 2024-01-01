# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2020,2021,2023,2024 Leah Rowe <leah@libreboot.org>
# SPDX-FileCopyrightText: 2022 Caleb La Grange <thonkpeasant@protonmail.com>

# This file is only used by update/project/trees

eval "$(setvars "" _target rev _xm loc url bkup_url depend)"

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
	[ -f "$cfgsdir/$1/target.cfg" ] || err "$1: target.cfg missing"
	[ -f "${cfgsdir}/${1}/seen" ] && \
		err "${_xm} check: infinite loop in tree definitions"

	. "$cfgsdir/$1/target.cfg" || err "load_target_config !$cfgsdir/$1"
	touch "$cfgsdir/$1/seen" || err "load_config $cfgsdir/$1: !mk seen"
}

prepare_new_tree()
{
	printf "Creating %s tree %s (%s)\n" "$project" "$tree" "$_target"

	cp -R "src/${project}/${project}" "${tmpgit}" || \
	    err "prepare_new_tree ${project}/${tree}: can't make tmpclone"
	git_prep "$PWD/$cfgsdir/$tree/patches" "src/$project/$tree" "update"
}

fetch_project_repo()
{
	scan_config "${project}" "config/git" "err"
	verify_config

	clone_project
	[ -z "${depend}" ] || for d in ${depend} ; do
		x_ ./update trees -f ${d}
	done
	rm -Rf "${tmpgit}" || err "fetch_repo: !rm -Rf ${tmpgit}"
}

verify_config()
{
	[ -z "${rev+x}" ] && err 'verify_config: rev not set'
	[ -z "${loc+x}" ] && err 'verify_config: loc not set'
	[ -z "${url+x}" ] && err 'verify_config: url not set'; return 0
}

clone_project()
{
	loc="${loc#src/}"
	loc="src/${loc}"
	if [ -d "${loc}" ]; then
		printf "%s already exists, so skipping download\n" "$loc" 1>&2
		return 0
	fi

	git clone $url "$tmpgit" || git clone $bkup_url "$tmpgit" \
	    || err "clone_project: could not download ${project}"
	git_prep "$PWD/config/$project/patches" "$loc"
}

git_prep()
{
	_patchdir="$1"
	_loc="$2"

	git -C "$tmpgit" reset --hard $rev || err "git -C $_loc: !reset $rev"
	git_am_patches "$tmpgit" "$_patchdir" || err "!am $_loc $_patchdir"

	if [ "$project" != "coreboot" ] || [ $# -gt 2 ]; then
		[ ! -f "$tmpgit/.gitmodules" ] || git -C "$tmpgit" submodule \
		    update --init --checkout || err "git_prep $_loc: !submod"
	fi

	[ "$_loc" = "${_loc%/*}" ] || x_ mkdir -p "${_loc%/*}"
	mv "$tmpgit" "$_loc" || err "git_prep: !mv $tmpgit $_loc"
}

git_am_patches()
{
	for _patch in "$2/"*; do
		[ -L "$_patch" ] || [ ! -f "$_patch" ] || git -C "$1" am \
		    "$_patch" || err "git_am $1 $2: !git am $_patch"; continue
	done
	for _patches in "$2/"*; do
		[ ! -L "$_patches" ] && [ -d "$_patches" ] && \
			git_am_patches "$1" "$_patches"; continue
	done
}
