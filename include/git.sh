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

	cp -R "src/$project/$project" "$tmpgit" || \
	    $err "prepare_new_tree $project/$tree: can't make tmpclone"
	git_prep "$PWD/$cfgsdir/$tree/patches" "src/$project/$tree" "update"
	nuke "$project/$tree" "$project/$tree"
}

fetch_project_repo()
{
	eval "$(setvars "" xtree tree_depend)"

	scan_config "$project" "config/git"
	[ -z "${loc+x}" ] && $err "fetch_project_repo $project: loc not set"
	[ -z "${url+x}" ] && $err "fetch_project_repo $project: url not set"

	clone_project
	[ -z "$depend" ] || for d in $depend ; do
		x_ ./update trees -f $d
	done
	rm -Rf "$tmpgit" || $err "fetch_repo: !rm -Rf $tmpgit"

	for x in config/git/*; do
		[ -f "$x" ] && nuke "${x##*/}" "src/${x##*/}"; continue
	done
}

clone_project()
{
	loc="${loc#src/}"
	loc="src/$loc"
	e "$loc" d && return 0

	git clone $url "$tmpgit" || git clone $bkup_url "$tmpgit" \
	    || $err "clone_project: could not download $project"
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

	mdir="$PWD/config/submodule/$project"
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
		[ -n "$subrev" ] || $err "$1, $mdir: subrev not defined"

		rm -Rf "$tmpgit/$1" || $err "!rm '$mdir' '$1'"
		for mod in "$subrepo" "$subrepo_bkup"; do
			[ -z "$mod" ] && continue
			git clone "$mod" "$tmpgit/$1" || rm -Rf "$tmpgit/$1" \
			    || $err "!rm $mod $project $cfgdir $1"
			[ -d "$tmpgit/$1" ] && break
		done
		[ -d "$tmpgit/$1" ] || $err "!clone $mod $project $mcfgdir $1"
	else
		git -C "$tmpgit" submodule update --init --checkout -- "$1" \
		    || $err "$mdir: !update $1"
	fi
}

patch_submodule()
{
	[ -z "$subrev" ] || git -C "$tmpgit/$1" reset --hard "$subrev" || \
	    $err "$mdir $1: cannot reset git revision"

	git_am_patches "$tmpgit/$1" "$mdir/${1##*/}/patches"
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
