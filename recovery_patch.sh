#!/bin/bash

INPUT_BOOT="boot.img"
OFOX_ZIP="ofox.zip"
OUTPUT_BOOT="boot-ofox.img"
OFOX_JSON_URL="https://raw.githubusercontent.com/PipaDB/Releases/refs/heads/main/ofox.json"

G='\033[0;32m'
R='\033[0;31m'
B='\033[0;34m'
Y='\033[1;33m'
C='\033[0;36m'
M='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

msg() { echo -e "${B}::${NC} ${BOLD}$1${NC}"; }
success() { echo -e "${G}==>${NC} ${BOLD}$1${NC}"; }
err() { echo -e "${R}[ERROR]${NC} $1"; exit 1; }

human_size() {
    numfmt --to=iec-i --suffix=B --format="%.2f" "$1" 2>/dev/null || echo "$1 bytes"
}

for cmd in magiskboot unzip jq curl wget file numfmt strings sha256sum; do
    command -v "$cmd" >/dev/null || err "$cmd is missing."
done

if [ ! -f "$OFOX_ZIP" ]; then
    msg "Fetching OrangeFox metadata..."
    OFOX_URL=$(curl -sL "$OFOX_JSON_URL" | jq -r '.url')
    [[ -z "$OFOX_URL" || "$OFOX_URL" == "null" ]] && err "Failed to parse JSON."

    msg "Downloading OrangeFox..."
    wget -q --show-progress --progress=bar:force:noscroll -O "$OFOX_ZIP" "$OFOX_URL"
    echo -ne "\033[1A\033[K"
    success "OrangeFox downloaded."
else
    success "Using existing $OFOX_ZIP"
fi

[ -f "$INPUT_BOOT" ] || err "$INPUT_BOOT not found."
rm -rf work_rec && mkdir -p work_rec
cp "$INPUT_BOOT" work_rec/boot.img

msg "Unpacking Boot Image & Generating Report..."
cd work_rec || exit 1
DUMP_LOG=$(magiskboot unpack -h boot.img 2>&1)

echo -e "${M}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${M}┃${NC}${C}${BOLD}              BOOT IMAGE METADATA REPORT                   ${NC}${M}┃${NC}"
echo -e "${M}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"

print_row() {
    local label=$1
    local value=$2
    if [[ -n "$value" && "$value" != "Unknown" && "$value" != "null" ]]; then
        printf "${M}┃${NC} ${Y}%-18s${NC} : %-37s ${M}┃${NC}\n" "$label" "$value"
    fi
}

[[ -f "header" ]] && source <(sed 's/=/="/;s/$/"/' header)

[[ -z "$boot_magic" ]] && boot_magic=$(echo "$DUMP_LOG" | grep -oP "HEADER_VER \[\K[^\]]+")
[[ -z "$os_version" ]] && os_version=$(echo "$DUMP_LOG" | grep -oP "OS_VER \[\K[^\]]+")
[[ -z "$os_patch_level" ]] && os_patch_level=$(echo "$DUMP_LOG" | grep -oP "PATCH_LEVEL \[\K[^\]]+")

print_row "Magic" "$boot_magic"
print_row "Header Version" "$header_version"
print_row "Kernel Size" "$kernel_size"
print_row "Ramdisk Size" "$ramdisk_size"
print_row "OS Version" "$os_version"
print_row "Security Patch" "$os_patch_level"
print_row "Page Size" "$page_size"

if [ -f "kernel" ]; then
    K_VER=$(strings kernel | grep -m1 "Linux version" | cut -d' ' -f3)
    print_row "Kernel Version" "$K_VER"
fi

if [ -f "ramdisk.cpio" ]; then
    COMP_TYPE=$(file -b ramdisk.cpio | cut -d' ' -f1)
    [[ "$COMP_TYPE" == "ASCII" ]] && COMP_TYPE="CPIO (Standard)"
    print_row "Ramdisk Comp" "$COMP_TYPE"
fi

CMD=$(grep 'cmdline=' header | cut -d= -f2-)
if [[ -n "$CMD" ]]; then
    echo -e "${M}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
    echo -e "${M}┃${NC} ${Y}Command Line:${NC}                                             ${M}┃${NC}"
    echo "$CMD" | fold -s -w 57 | while read -r line; do
        printf "${M}┃${NC} ${C}%-58s${NC} ${M}┃${NC}\n" "$line"
    done
fi
echo -e "${M}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
cd ..

msg "Extracting OrangeFox Ramdisk..."
unzip -pq "$OFOX_ZIP" recovery.img > work_rec/recovery.img
cd work_rec || exit 1
magiskboot unpack -h recovery.img >/dev/null 2>&1
mv ramdisk.cpio ../ramdisk-ofox.cpio
rm -f kernel dtb recovery.img header
cd ..

msg "Injecting OrangeFox into Boot..."
cd work_rec || exit 1
magiskboot unpack -h boot.img >/dev/null 2>&1
cp ../ramdisk-ofox.cpio ramdisk.cpio

if [ -f "header" ]; then
    CMDLINE=$(grep '^cmdline=' header | cut -d= -f2-)
    CLEAN_CMDLINE=$(echo "$CMDLINE" | sed -e 's/skip_override//' -e 's/  */ /g' -e 's/[ \t]*$//')
    sed -i "s|cmdline=$CMDLINE|cmdline=$CLEAN_CMDLINE|" header
fi

msg "Repacking..."
magiskboot repack boot.img >/dev/null 2>&1
mv new-boot.img "../$OUTPUT_BOOT"
cd ..

rm -rf work_rec ramdisk-ofox.cpio
OLD_SIZE=$(stat -c%s "$INPUT_BOOT")
NEW_SIZE=$(stat -c%s "$OUTPUT_BOOT")
SHA=$(sha256sum "$OUTPUT_BOOT" | cut -d' ' -f1 | cut -c1-16)

echo -e "\n${G}==>${NC} ${BOLD}Patching successful!${NC}"
printf "${BOLD}%-15s${NC} : %s (%'d bytes)\n" "Original Size" "$(human_size $OLD_SIZE)" "$OLD_SIZE"
printf "${BOLD}%-15s${NC} : %s (%'d bytes)\n" "Patched Size" "$(human_size $NEW_SIZE)" "$NEW_SIZE"
printf "${BOLD}%-15s${NC} : ${C}%s...${NC}\n" "SHA256 (part)" "$SHA"
echo -e "${G}Final Image:${NC} ${Y}${BOLD}$(pwd)/$OUTPUT_BOOT${NC}\n"
