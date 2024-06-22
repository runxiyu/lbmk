# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2020-2021,2023-2024 Leah Rowe <leah@libreboot.org>
# Copyright (c) 2022 Caleb La Grange <thonkpeasant@protonmail.com>

eval "$(setvars "" _target rev _xm loc url bkup_url depend tree_depend xtree \
    mdir subhash subrepo subrepo_bkup subfile subfile_bkup)"

fetch_project_trees()
{
	_target="$target"
	[ ! -d "src/$project/$project" ] && x_ mkdir -p "src/$project" \
	    && fetch_project_repo "$project"
	fetch_config
	e "src/$project/$tree" d || prepare_new_tree; return 0
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
	[ -f "$cfgsdir/$1/seen" ] && $err "$_xm cfg: infinite loop in trees"
	eval `setcfg "$cfgsdir/$1/target.cfg"`
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
	eval `setcfg "config/git/$project/pkg.cfg"`

	chkvars url

	[ -n "$xtree" ] && [ ! -d "src/coreboot/$xtree" ] && \
		x_ ./update trees -f coreboot "$xtree"
	[ -z "$depend" ] || for d in $depend ; do
		printf "'%s' needs '%s'; grabbing '%s'\n" "$project" "$d" "$d"
		x_ ./update trees -f $d
	done
	clone_project

	for x in config/git/*; do
		[ -d "$x" ] && nuke "${x##*/}" "src/${x##*/}" 2>/dev/null
	done; return 0
}

clone_project()
{
	loc="src/$project"
	singletree "$project" || loc="src/$project/$project"

	printf "Downloading project '%s' to '%s'\n" "$project" "$loc"
	e "$loc" d && return 0

	remkdir "${tmpgit%/*}"
	git_prep "$url" "$bkup_url" "$PWD/config/$project/patches" "$loc"
}

git_prep()
{
	_patchdir="$3" # $1 and $2 are gitrepo and gitrepo_backup
	_loc="$4"

	chkvars rev

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
	eval $(setvars "" subhash subrepo subrepo_bkup subfile subfile_bkup st)
	[ ! -f "$mcfgdir/module.cfg" ] || . "$mcfgdir/module.cfg" || \
	    $err "! . $mcfgdir/module.cfg"

	for xt in repo file; do
		_seval="if [ -n \"\$sub$xt\" ] || [ -n \"\$sub${xt}_bkup\" ]"
		eval "$_seval; then st=\"\$st \$xt\"; fi"
	done

	st="${st# }" && [ "$st" = "repo file" ] && $err "$mdir: repo+file"

	[ -z "$st" ] && return 0 # subrepo/subfile not defined
	chkvars "sub${st}" "sub${st}_bkup" "subhash"

	[ "$st" = "file" ] && download "$subfile" "$subfile_bkup" \
	    "$tmpgit/$1" "$subhash" && return 0
	rm -Rf "$tmpgit/$1" || $err "!rm '$mdir' '$1'"
	tmpclone "$subrepo" "$subrepo_bkup" "$tmpgit/$1" "$subhash" \
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
	x_ cd "$tmpgit/util" && x_ rm -Rf crossgcc
	ln -s "../../$xtree/util/crossgcc" crossgcc || $err "$1: !xgcc link"
	) || $err "$1: !xgcc link"
}

move_repo()
{
	[ "$1" = "${1%/*}" ] || x_ mkdir -p "${1%/*}"
	mv "$tmpgit" "$1" || $err "git_prep: !mv $tmpgit $1"
}

# can delete from multi- and single-tree projects.
# called from script/trees when downloading sources.
nuke()
{
	e "config/${1%/}/nuke.list" f missing || while read -r nukefile; do
		rmf="src/${2%/}/$nukefile" && [ -L "$rmf" ] && continue
		e "$rmf" e missing || rm -Rf "$rmf" || $err "!rm $rmf, ${2%/}"
	done < "config/${1%/}/nuke.list"; return 0
}
