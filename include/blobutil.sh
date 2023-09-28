# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: 2023 Leah Rowe <leah@libreboot.org>

agent="Mozilla/5.0 (Windows NT 10.0; rv:91.0) Gecko/20100101 Firefox/91.0"

_7ztest="a"

_b=""
blobdir="blobs"
appdir="${blobdir}/app"

setvars="EC_url=\"\""
for x in EC_url_bkup EC_hash DL_hash DL_url DL_url_bkup dl_path \
    E6400_VGA_DL_hash E6400_VGA_DL_url E6400_VGA_DL_url_bkup E6400_VGA_offset \
    E6400_VGA_romname SCH5545EC_DL_url SCH5545EC_DL_url_bkup \
    SCH5545EC_DL_hash; do
	setvars="${setvars}; ${x}=\"\""
done

for x in sname archive _filetype rom board modifygbe new_mac release \
    releasearchive vendor_rom; do
	setvars="${setvars}; ${x}=\"\""
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
	setvars="${setvars}; ${x}=\"\""
done

eval "${setvars}"
