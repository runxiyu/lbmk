# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2020-2021,2023-2024 Leah Rowe <leah@libreboot.org>
# Copyright (c) 2022 Caleb La Grange <thonkpeasant@protonmail.com>

eval "$(setvars "" _target rev _xm loc url bkup_url depend tree_depend xtree \
    mdir subrev subrepo subrepo_bkup)"

fetch_project_trees()
{
	_target="$target"
	[ ! -d "src/$project/$project" ] && x_ mkdir -p "src/$project" \
	    && fetch_project_repo "$project"
	fetch_config
	e "src/$project/$tree" d && return 0
	prepare_new_tree
}

fetch_config()
{
	rm -f "$cfgsdir/"*/seen || $err "fetch_config $cfgsdir: !rm seen"
	eval "$(setvars "" xtree tree_depend)"
	while true; do
		eval "$(setvars "" rev tree)"
		_xm="fetch_config $project/$_target"
		load_target_config "$_target"
		[ "$_target" = "$tree" ] && break
		_target="$tree"
	done
	[ -n "$tree_depend" ] && [ "$tree_depend" != "$tree" ] && \
		x_ ./update trees -f "$project" "$tree_depend"; return 0
}

load_target_config()
{
	[ -f "$cfgsdir/$1/target.cfg" ] || $err "$1: target.cfg missing"
	[ -f "$cfgsdir/$1/seen" ] && $err "$_xm cfg: infinite loop in trees"

	. "$cfgsdir/$1/target.cfg" || $err "load_target_config !$cfgsdir/$1"
	touch "$cfgsdir/$1/seen" || $err "load_config $cfgsdir/$1: !mk seen"
}

prepare_new_tree()
{
	printf "Creating %s tree %s (%s)\n" "$project" "$tree" "$_target"

	git_prep "src/$project/$project" "src/$project/$project" \
	    "$PWD/$cfgsdir/$tree/patches" "src/$project/$tree" "update"
	nuke "$project/$tree" "$project/$tree"
}

fetch_project_repo()
{
	eval "$(setvars "" xtree tree_depend)"

	scan_config "$project" "config/git"
	[ -z "${loc+x}" ] && $err "fetch_project_repo $project: loc not set"
	[ -z "${url+x}" ] && $err "fetch_project_repo $project: url not set"

	[ -z "$depend" ] || for d in $depend ; do
		printf "'%s' needs dependency '%s'; grabbing '%s' now\n" \
		    "$project" "$d" "$d"
		x_ ./update trees -f $d
	done
	clone_project

	for x in config/git/*; do
		[ -f "$x" ] && nuke "${x##*/}" "src/${x##*/}"; continue
	done
}

clone_project()
{
	loc="${loc#src/}"
	loc="src/$loc"

	printf "Downloading project '%s' to '%s'\n" "$project" "$loc"
	e "$loc" d && return 0

	remkdir "${tmpgit%/*}"
	git_prep "$url" "$bkup_url" "$PWD/config/$project/patches" "$loc"
}

git_prep()
{
	_patchdir="$3" # $1 and $2 are gitrepo and gitrepo_backup
	_loc="$4"

	[ -z "${rev+x}" ] && $err "git_prep $_loc: rev not set"

	tmpclone "$1" "$2" "$tmpgit" "$rev" "$_patchdir"
	if singletree "$project" || [ $# -gt 4 ]; then
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
	mdir="$PWD/config/submodule/$project"
	[ -n "$tree" ] && mdir="$mdir/$tree"

	[ -f "$mdir/module.list" ] && while read -r msrcdir; do
		fetch_submodule "$msrcdir"
	done < "$mdir/module.list"; return 0
}

fetch_submodule()
{
	mcfgdir="$mdir/${1##*/}"
	eval "$(setvars "" subrev subrepo subrepo_bkup)"
	[ ! -f "$mcfgdir/module.cfg" ] || . "$mcfgdir/module.cfg" || \
	    $err "! . $mcfgdir/module.cfg"

	[ -z "$subrepo" ] && [ -z "$subrepo_bkup" ] && return 0
	for mvar in subrepo subrepo_bkup subrev; do
		eval "[ -n \"\$$mvar\" ] || $err \"$1, $mdir: $mvar unset\""
	done

	rm -Rf "$tmpgit/$1" || $err "!rm '$mdir' '$1'"
	tmpclone "$subrepo" "$subrepo_bkup" "$tmpgit/$1" "$subrev" \
	    "$mdir/${1##*/}/patches"
}

tmpclone()
{
	git clone $1 "$3" || git clone $2 "$3" || $err "!clone $1 $2 $3 $4 $5"
	git -C "$3" reset --hard "$4" || $err "!reset $1 $2 $3 $4 $5"
	git_am_patches "$3" "$5"
}

git_am_patches()
{
	for _patch in "$2/"*; do
		[ -L "$_patch" ] || [ ! -f "$_patch" ] || git -C "$1" am \
		    "$_patch" || $err "$1 $2: !git am $_patch"; continue
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

# can delete from multi- and single-tree projects.
# called from script/trees when downloading sources.
nuke()
{
	del="n"
	pjcfgdir="${1%/}"
	pjsrcdir="${2%/}"
	pjsrcdir="${pjsrcdir#src/}"
	[ ! -f "config/$pjcfgdir/nuke.list" ] && return 0

	while read -r nukefile; do
		rmf="$(realpath "src/$pjsrcdir/$nukefile" 2>/dev/null)" || \
		    continue
		[ -L "$rmf" ] && continue # we will delete the actual file
		[ "${rmf#"$PWD/src/$pjsrcdir"}" = "$rmf" ] && continue
		[ "${rmf#"$PWD/src/"}" = "$pjsrcdir" ] && continue
		rmf="${rmf#"$PWD/"}"
		[ -e "$rmf" ] || continue
		del="y"
		rm -Rf "$rmf" || $err "$nuke pjcfgdir: can't rm \"$nukefile\""
		printf "nuke %s: deleted \"%s\"\n" "$pjcfgdir" "$rmf"
	done < "config/$pjcfgdir/nuke.list"

	[ "${del}" = "y" ] && return 0
	printf "nuke %s: no defined files exist in dir, src/%s\n" 1>&2 \
	    "$pjcfgdir" "$pjsrcdir"
	printf "(this is not an error)\n" 1>&2
}
