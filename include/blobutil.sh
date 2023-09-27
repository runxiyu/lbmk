# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: 2023 Leah Rowe <leah@libreboot.org>

agent="Mozilla/5.0 (Windows NT 10.0; rv:91.0) Gecko/20100101 Firefox/91.0"

_7ztest="a"

_b=""
blobdir="blobs"
appdir="${blobdir}/app"

for x in ec_url ec_url_bkup ec_hash dl_hash dl_url dl_url_bkup dl_path \
    e6400_vga_dl_hash e6400_vga_dl_url e6400_vga_dl_url_bkup e6400_vga_offset \
    e6400_vga_romname sch5545ec_dl_url sch5545ec_dl_url_bkup \
    sch5545ec_dl_hash; do
	eval "${x}=\"\""
done

for x in sname archive _filetype rom board modifygbe new_mac release \
    releasearchive vendor_rom; do
	eval "${x}=\"\""
done

cbdir="coreboot/default"
cbcfgsdir="config/coreboot"
ifdtool="cbutils/default/ifdtool"
cbfstool="cbutils/default/cbfstool"
nvmutil="util/nvmutil/nvm"
boarddir=""
pciromsdir="pciroms"

mecleaner="$(pwd)/me_cleaner/me_cleaner.py"
me7updateparser="$(pwd)/util/me7_update_parser/me7_update_parser.py"
e6400_unpack="$(pwd)/bios_extract/dell_inspiron_1100_unpacker.py"
kbc1126_ec_dump="$(pwd)/${cbdir}/util/kbc1126/kbc1126_ec_dump"
pfs_extract="$(pwd)/biosutilities/Dell_PFS_Extract.py"
uefiextract="$(pwd)/uefitool/uefiextract"

for x in _me_destination _gbe_destination _ifd_destination \
    CONFIG_BOARD_DELL_E6400 CONFIG_HAVE_MRC CONFIG_HAVE_ME_BIN \
    CONFIG_ME_BIN_PATH CONFIG_KBC1126_FIRMWARE CONFIG_KBC1126_FW1 \
    CONFIG_KBC1126_FW1_OFFSET CONFIG_KBC1126_FW2 CONFIG_KBC1126_FW2_OFFSET \
    CONFIG_VGA_BIOS_FILE CONFIG_VGA_BIOS_ID CONFIG_GBE_BIN_PATH \
    CONFIG_INCLUDE_SMSC_SCH5545_EC_FW CONFIG_SMSC_SCH5545_EC_FW_FILE \
    CONFIG_IFD_BIN_PATH; do
	eval "${x}=\"\""
done
