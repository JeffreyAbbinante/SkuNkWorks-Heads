#!/bin/bash -e
# depends on : wget sha256sum gunzip git python

# Purism source
RELEASES_GIT_HASH="4a4118536640ac8b6473f4c20216b6c3b6de004a"
PURISM_SOURCE="https://source.puri.sm/coreboot/releases/raw/${RELEASES_GIT_HASH}"

# Librem 13 v1 and Librem 15 v2 binary blob hashes
BDW_UCODE_SHA="69537c27d152ada7dce9e35bfa16e3cede81a18428d1011bd3c33ecae7afb467"
BDW_DESCRIPTOR_SHA="d7377417b28550b70c5076833548abc05dcf9fb1bd40a298e671d46dbb47bcbe"
BDW_ME_SHA="d679f6323f0e7c85464aa06649485223b6db6926159d848377f9e9aa195be7ad"
BDW_MRC_SHA="dd05ab481e1fe0ce20ade164cf3dbef3c479592801470e6e79faa17624751343"
BDW_REFCODE_SHA="8a919ffece61ba21664b1028b0ebbfabcd727d90c1ae2f72b48152b8774323a4"
BDW_VBIOS_SHA="e1cd1b4f2bd21e036145856e2d092eb47c27cdb4b717c3b182a18d8c0b1d0f01"

# cbfstool, ifdtool, coreboot image from Purism repo
CBFSTOOL_FILE="cbfstool.gz"
CBFSTOOL_URL="$PURISM_SOURCE/tools/$CBFSTOOL_FILE"
CBFSTOOL_SHA="3994cba01a51dd34388c8be89fd329f91575c12e499dfe1b81975d9fd115ce58"
CBFSTOOL_BIN="./cbfstool"

COREBOOT_IMAGE="coreboot-l13v1.rom"
COREBOOT_IMAGE_FILE="$COREBOOT_IMAGE.gz"
COREBOOT_IMAGE_URL="$PURISM_SOURCE/librem_13v1/$COREBOOT_IMAGE_FILE"
COREBOOT_IMAGE_SHA="04a793e8a3096985333fc54a672886edc5ae06898f1ee7630cee74d7645e36fb"

ME_CLEANER_CMD="python me_cleaner/me_cleaner.py -r -t -d -O /tmp/out.bin -D descriptor.bin -M me.bin ${COREBOOT_IMAGE}"

die () {
    local msg=$1

    echo ""
    echo "$msg"
    exit 1
}

check_and_get_url () {
    local filename=$1
    local url=$2
    local hash=$3
    local description=$4

    if [ -f "$filename" ]; then
        sha=$(sha256sum "$filename" | awk '{print $1}')
    fi
    if [ "$sha" != "$hash" ]; then
        echo "    Downloading $description..."
        wget -O "$filename" "$url" >/dev/null 2>&1
        sha=$(sha256sum "$filename" | awk '{print $1}')
        if [ "$sha" != "$hash" ]; then
            die "Downloaded $description has the wrong SHA256 hash"
        fi
        if [ "${filename: -3}" == ".gz" ]; then
            gunzip -k $filename
        fi
    fi
    
}

check_and_get_blob () {
    local filename=$1
    local hash=$2
    local description=$3

    echo "Checking $filename"
    if [ -f "$filename" ]; then
        sha=$(sha256sum "$filename" | awk '{print $1}')
    fi
    if [ "$sha" != "$hash" ]; then
        # get tools
        check_and_get_tools
        
        # extract from coreboot image
        check_and_get_url ${LOCAL_FIRMWARE_PATH} ${COREBOOT_IMAGE_FILE} ${COREBOOT_IMAGE_URL} ${COREBOOT_IMAGE_SHA} "precompiled coreboot image"

        echo "Extracting $filename"
        if [[ $filename = "descriptor.bin" || $filename = "me.bin" ]]; then
            get_me_cleaner
            $ME_CLEANER_CMD
        elif [ $filename = "vgabios.bin" ]; then
            ${CBFSTOOL_BIN} ${COREBOOT_IMAGE} extract -n pci8086,1616.rom -f $filename >/dev/null 2>&1
            [ $? -ne 0 ] && die "Error extracting ${filename}"
        elif [ $filename = "refcode.elf" ]; then
            ${CBFSTOOL_BIN} ${COREBOOT_IMAGE} extract -n fallback/refcode -f $filename -m x86 >/dev/null 2>&1
            [ $? -ne 0 ] && die "Error extracting ${filename}"
        else
            ${CBFSTOOL_BIN} ${COREBOOT_IMAGE} extract -n $filename -f $filename >/dev/null 2>&1
            [ $? -ne 0 ] && die "Error extracting ${filename}"
        fi
        sha=$(sha256sum "$filename" | awk '{print $1}')
        if [ "$sha" != "$hash" ]; then
            die "Downloaded $description has the wrong SHA256 hash"
        fi
    fi
}

check_and_get_tools() {
    check_and_get_url $CBFSTOOL_FILE $CBFSTOOL_URL $CBFSTOOL_SHA "cbfstool"
    chmod +x $CBFSTOOL_BIN
}

get_me_cleaner() {

    if [ ! -d me_cleaner ]; then
        git clone https://github.com/corna/me_cleaner.git 2>/dev/null
        (
            cd me_cleaner
            git checkout v1.2  2>/dev/null
        )
    else
        (
            cd me_cleaner
            git fetch  2>/dev/null
            git fetch --tags  2>/dev/null
            git checkout v1.2  2>/dev/null
        )
    fi
}

echo ""

# get/verify blobs
check_and_get_blob descriptor.bin $BDW_DESCRIPTOR_SHA "Intel Flash Descriptor"
check_and_get_blob me.bin $BDW_ME_SHA "Intel ME firmware"
check_and_get_blob mrc.bin $BDW_MRC_SHA "Memory Reference Code"
check_and_get_blob refcode.elf $BDW_REFCODE_SHA "Silicon Init Reference Code"
check_and_get_blob cpu_microcode_blob.bin $BDW_UCODE_SHA "Intel Microcode Update"
check_and_get_blob vgabios.bin $BDW_VBIOS_SHA "VGA BIOS"

#clean up after ourselves
rm -f $CBFSTOOL_BIN >/dev/null 2>&1
rm -f $COREBOOT_IMAGE >/dev/null 2>&1
rm -f *.gz >/dev/null 2>&1
rm -rf ./me_cleaner >/dev/null 2>&1

echo ""
echo "All blobs have been verified and are ready for use"