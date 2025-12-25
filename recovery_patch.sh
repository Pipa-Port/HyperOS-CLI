#!/bin/bash
# patch_recovery.sh

# --- Config ---
INPUT_BOOT="boot.img"
OFOX_ZIP="ofox.zip"
OUTPUT_BOOT="boot-ofox.img"

# --- Logic ---
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

err() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
command -v magiskboot >/dev/null || err "magiskboot missing"
command -v unzip >/dev/null || err "unzip missing"

rm -rf work_rec && mkdir -p work_rec

echo -e "${GREEN}Extracting Ramdisk...${NC}"
unzip -p "$OFOX_ZIP" recovery.img > work_rec/recovery.img || err "Failed to unzip recovery.img"
cd work_rec
magiskboot unpack -h recovery.img >/dev/null 2>&1
[ -f ramdisk.cpio ] || err "No ramdisk found"
mv ramdisk.cpio ../ramdisk-ofox.cpio
cd ..

echo -e "${GREEN}Patching Boot Image...${NC}"
cp "$INPUT_BOOT" work_rec/boot.img
cd work_rec
magiskboot unpack -h boot.img >/dev/null 2>&1

cp ../ramdisk-ofox.cpio ramdisk.cpio

# Header Patch (remove skip_override)
if [ -f "header" ]; then
    sed -i "s|$(grep '^cmdline=' header | cut -d= -f2-)|$(grep '^cmdline=' header | cut -d= -f2- | sed -e 's/skip_override//' -e 's/  */ /g' -e 's/[ \t]*$//')|" header
fi

magiskboot repack boot.img >/dev/null 2>&1
[ -f new-boot.img ] || err "Repack failed"
mv new-boot.img "../$OUTPUT_BOOT"
cd ..

rm -rf work_rec ramdisk-ofox.cpio
echo -e "${GREEN}Done! Output: $OUTPUT_BOOT${NC}"

