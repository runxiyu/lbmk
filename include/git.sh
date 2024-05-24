# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2020,2021,2023,2024 Leah Rowe <leah@libreboot.org>
# SPDX-FileCopyrightText: 2022 Caleb La Grange <thonkpeasant@protonmail.com>

eval "$(setvars "" _target rev _xm loc url bkup_url depend tree_depend xtree \
    mdir subrev subrepo subrepo_bkup)"

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

	[ "$project" = "coreboot" ] && [ -n "$xtree" ] && [ $# -gt 2 ] && \
	    [ "$xtree" != "$tree" ] && link_crossgcc "$_loc"

	[ "$xbmk_release" = "y" ] && [ "$_loc" != "src/$project/$project" ] \
	    && rmgit "$tmpgit"

	move_repo "$_loc"
}

prep_submodules()
{
	[ -f "$tmpgit/.gitmodules" ] || return 0

	mdir="${PWD}/config/submodule/$project"
	[ -n "$tree" ] && mdir="$mdir/$tree"

	if [ -f "$mdir/module.list" ]; then
		cat "$mdir/module.list" > "$tmpdir/modules" || \
		    $err "!cp $mdir/module.list $tmpdir/modules"
	else
		git -C "$tmpgit" submodule status | awk '{print $2}' > \
		    "$tmpdir/modules" || $err "$mdir: cannot list submodules"
	fi

	while read -r msrcdir; do
		fetch_submodule "$msrcdir"
		patch_submodule "$msrcdir"
	done < "$tmpdir/modules"

	# some build systems may download more (we want to control it)
	rm -f "$tmpgit/.gitmodules" || $err "!rm .gitmodules as per: $mdir"
}

fetch_submodule()
{
	mcfgdir="$mdir/${1##*/}"
	eval "$(setvars "" subrev subrepo subrepo_bkup)"

	[ ! -f "$mcfgdir/module.cfg" ] || . "$mcfgdir/module.cfg" || \
	    $err "! . $mcfgdir/module.cfg"

	if [ -n "$subrepo" ] || [ -n "$subrepo_bkup" ]; then
		[ -n "$subrev" ] || \
		    $err "$1 as per $mdir: subrev not defined"

		rm -Rf "$tmpgit/$1" || $err "!rm '$mdir' '$1'"
		for mod in "$subrepo" "$subrepo_bkup"; do
			[ -z "$mod" ] && continue
			git clone "$mod" "$tmpgit/$1" || rm -Rf "$tmpgit/$1" \
			    || $err "!rm $mod $project $cfgdir $1"
		done
		[ -d "$tmpgit/$1" ] || $err "!clone $mod $project $mcfgdir $1"
	else
		git -C "$tmpgit" submodule update --init --checkout -- "$1" || \
		    $err "$mdir: !update $1"
	fi
}

patch_submodule()
{
	[ -z "$subrev" ] || \
		git -C "$tmpgit/$1" reset --hard "$subrev" || \
		    $err "$mdir $1: cannot reset git revision"

	git_am_patches "$tmpgit/$1" "$mdir/${1##*/}/patches"
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

link_crossgcc()
{
	(
	cd "$tmpgit/util" || $err "prep $1: !cd $tmpgit/util"
	rm -Rf crossgcc || $err "prep $1: !rm xgcc"
	ln -s "../../$xtree/util/crossgcc" crossgcc || $err "$1: !xgcc link"
	) || $err "$1: !xgcc link"
}

move_repo()
{
	[ "$1" = "${1%/*}" ] || x_ mkdir -p "${1%/*}"
	mv "$tmpgit" "$1" || $err "git_prep: !mv $tmpgit $1"
	[ -n "$xtree" ] && [ ! -d "src/coreboot/$xtree" ] && \
		x_ ./update trees -f coreboot "$xtree"; return 0
}
