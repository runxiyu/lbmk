# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2020,2021,2023,2024 Leah Rowe <leah@libreboot.org>
# SPDX-FileCopyrightText: 2022 Caleb La Grange <thonkpeasant@protonmail.com>

eval "$(setvars "" _target rev _xm loc url bkup_url depend tree_depend xtree)"

fetch_project_trees()
{
	_target="${target}"
	[ ! -d "src/${project}/${project}" ] && x_ mkdir -p "src/${project}" \
	    && fetch_project_repo "${project}"
	fetch_config
	if [ -d "src/${project}/${tree}" ]; then
		printf "download/%s %s (%s): exists\n" \
		    "${project}" "${tree}" "${_target}" 1>&2
		return 0
	fi
	prepare_new_tree
}

fetch_config()
{
	rm -f "${cfgsdir}/"*/seen || $err "fetch_config ${cfgsdir}: !rm seen"
	eval "$(setvars "" xtree tree_depend)"
	while true; do
		eval "$(setvars "" rev tree)"
		_xm="fetch_config ${project}/${_target}"
		load_target_config "${_target}"
		[ "${_target}" = "${tree}" ] && break
		_target="${tree}"
	done
	[ -n "$tree_depend" ] && [ "$tree_depend" != "$tree" ] && \
		x_ ./update trees -f "$project" "$tree_depend"; return 0
}

load_target_config()
{
	[ -f "$cfgsdir/$1/target.cfg" ] || $err "$1: target.cfg missing"
	[ -f "${cfgsdir}/${1}/seen" ] && \
		$err "${_xm} check: infinite loop in tree definitions"

	. "$cfgsdir/$1/target.cfg" || $err "load_target_config !$cfgsdir/$1"
	touch "$cfgsdir/$1/seen" || $err "load_config $cfgsdir/$1: !mk seen"
}

prepare_new_tree()
{
	printf "Creating %s tree %s (%s)\n" "$project" "$tree" "$_target"

	cp -R "src/${project}/${project}" "${tmpgit}" || \
	    $err "prepare_new_tree ${project}/${tree}: can't make tmpclone"
	git_prep "$PWD/$cfgsdir/$tree/patches" "src/$project/$tree" "update"
}

fetch_project_repo()
{
	eval "$(setvars "" xtree tree_depend)"

	scan_config "${project}" "config/git"
	[ -z "${loc+x}" ] && $err "fetch_project_repo $project: loc not set"
	[ -z "${url+x}" ] && $err "fetch_project_repo $project: url not set"

	clone_project
	[ -z "${depend}" ] || for d in ${depend} ; do
		x_ ./update trees -f ${d}
	done
	rm -Rf "${tmpgit}" || $err "fetch_repo: !rm -Rf ${tmpgit}"
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
	    || $err "clone_project: could not download ${project}"
	git_prep "$PWD/config/$project/patches" "$loc"
}

git_prep()
{
	_patchdir="$1"
	_loc="$2"

	[ -z "${rev+x}" ] && $err "git_prep $_loc: rev not set"
	git -C "$tmpgit" reset --hard $rev || $err "git -C $_loc: !reset $rev"
	git_am_patches "$tmpgit" "$_patchdir" || $err "!am $_loc $_patchdir"

	if [ "$project" != "coreboot" ] || [ $# -gt 2 ]; then
		prep_submodules "$_loc"
	fi

	if [ "$project" = "coreboot" ] && [ -n "$xtree" ] && \
	    [ "$xtree" != "$tree" ] && [ $# -gt 2 ]; then
		(
		cd "$tmpgit/util" || $err "prep $1: !cd $tmpgit/util"
		rm -Rf crossgcc || $err "prep $1: !rm xgcc"
		ln -s "../../$xtree/util/crossgcc" crossgcc || \
		    $err "prep $1: can't create xgcc symlink"
		) || $err "prep $1: can't create xgcc symlink"
	fi

	[ "$xbmk_release" = "y" ] && [ "$_loc" != "src/$project/$project" ] \
	    && rmgit "$tmpgit"

	[ "$_loc" = "${_loc%/*}" ] || x_ mkdir -p "${_loc%/*}"
	mv "$tmpgit" "$_loc" || $err "git_prep: !mv $tmpgit $_loc"
	[ -n "$xtree" ] && [ ! -d "src/coreboot/$xtree" ] && \
		x_ ./update trees -f coreboot "$xtree"; return 0
}

prep_submodules()
{
	[ -f "$tmpgit/.gitmodules" ] || return 0
	git -C "$tmpgit" submodule update --init --checkout || $err "$1: !mod"

	mdir="${PWD}/config/submodule/$project"
	[ -n "$tree" ] && mdir="$mdir/$tree"

	git -C "$tmpgit" submodule status | awk '{print $2}' > \
	    "$tmpdir/modules" || $err "$mdir: cannot list submodules"

	while read -r msrcdir; do
		git_am_patches "$tmpgit/$msrcdir" "$mdir/${msrcdir##*/}/patches"
	done < "$tmpdir/modules"
}

git_am_patches()
{
	for _patch in "$2/"*; do
		[ -L "$_patch" ] || [ ! -f "$_patch" ] || git -C "$1" am \
		    "$_patch" || $err "git_am $1 $2: !git am $_patch"; continue
	done
	for _patches in "$2/"*; do
		[ ! -L "$_patches" ] && [ -d "$_patches" ] && \
			git_am_patches "$1" "$_patches"; continue
	done
}
