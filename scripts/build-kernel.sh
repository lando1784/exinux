#!/usr/bin/env bash
# Fetch the LineageOS Exynos 990 kernel, apply exinux patches/config, build
# Image + the DT table image that goes into boot.img.
#
# Output: $OUT/kernel/{Image,dtb.img,dtbo.img,config}
set -euo pipefail
. "$(dirname "$0")/../config.sh"

SRC=$WORK/kernel-src
BUILD=$WORK/kernel-build
DEST=$OUT/kernel
JOBS=${JOBS:-$(nproc)}
# LineageOS builds this tree with AOSP clang 12; upstream clang 14 works too.
CLANG_SUFFIX=${CLANG_SUFFIX:--14}

fetch() {
    if [ ! -d "$SRC/.git" ]; then
        git init -q "$SRC"
        git -C "$SRC" remote add origin "$KERNEL_REPO"
    fi
    if ! git -C "$SRC" cat-file -e "$KERNEL_COMMIT^{commit}" 2>/dev/null; then
        git -C "$SRC" fetch --depth 1 origin "$KERNEL_COMMIT" ||
            git -C "$SRC" fetch --depth 1 origin "$KERNEL_BRANCH"
    fi
    git -C "$SRC" checkout -q -f "$KERNEL_COMMIT"
    git -C "$SRC" clean -qfdx
    for p in "$TOP"/kernel/patches/*.patch; do
        [ -e "$p" ] || continue
        echo ">> applying $(basename "$p")"
        git -C "$SRC" apply "$p"
    done
}

fetch_mkdtboimg() {
    local d=$WORK/libufdt
    if [ ! -f "$d/utils/src/mkdtboimg.py" ]; then
        rm -rf "$d"
        git init -q "$d"
        git -C "$d" remote add origin "$LIBUFDT_REPO"
        git -C "$d" fetch -q --depth 1 origin "$LIBUFDT_COMMIT"
        git -C "$d" checkout -q FETCH_HEAD
    fi
    MKDTBOIMG="python3 $d/utils/src/mkdtboimg.py"
}

kmake() {
    make -C "$SRC" O="$BUILD" ARCH=arm64 \
        LLVM=1 CC="clang$CLANG_SUFFIX" LD="ld.lld$CLANG_SUFFIX" \
        AR="llvm-ar$CLANG_SUFFIX" NM="llvm-nm$CLANG_SUFFIX" \
        OBJCOPY="llvm-objcopy$CLANG_SUFFIX" OBJDUMP="llvm-objdump$CLANG_SUFFIX" \
        STRIP="llvm-strip$CLANG_SUFFIX" \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        "$@"
}

configure() {
    mkdir -p "$BUILD"
    local frags=()
    for f in $KERNEL_FRAGMENTS; do frags+=("$SRC/arch/arm64/configs/$f"); done
    frags+=("$TOP/kernel/exinux.config")
    kmake "$KERNEL_DEFCONFIG"
    "$SRC/scripts/kconfig/merge_config.sh" -m -O "$BUILD" "$BUILD/.config" "${frags[@]}"
    kmake olddefconfig

    # Fail loudly if Kconfig silently dropped something we rely on.
    local missing=0
    while IFS= read -r line; do
        case "$line" in CONFIG_*=*) ;; *) continue ;; esac
        grep -qxF "$line" "$BUILD/.config" || { echo "!! not applied: $line"; missing=1; }
    done < "$TOP/kernel/exinux.config"
    [ "$missing" = 0 ] || { echo "!! fix kernel/exinux.config dependencies"; exit 1; }
}

build() {
    kmake -j"$JOBS" Image dtbs
    mkdir -p "$DEST"
    cp "$BUILD/arch/arm64/boot/Image" "$DEST/Image"
    cp "$BUILD/.config" "$DEST/config"

    # Samsung's bootloader reads the DTB from boot.img as a DT table, keyed by
    # custom0/custom1 (see universal9830-common/configs/kernel/*.cfg).
    local dts=$BUILD/arch/arm64/boot/dts
    cat > "$WORK/dtb.cfg" <<EOF
$dts/exynos/exynos9830.dtb
  custom0=0x00000000
  custom1=0xff000000
EOF
    cat > "$WORK/dtbo.cfg" <<EOF
$dts/samsung/exynos990-r8s_eur_open_00.dtbo
    custom0=0x00000000
    custom1=0x00000001

$dts/samsung/exynos990-r8s_eur_open_02.dtbo
    custom0=0x00000002
    custom1=0x00000004

$dts/samsung/exynos990-r8s_eur_open_05.dtbo
    custom0=0x00000005
    custom1=0x000000ff
EOF
    $MKDTBOIMG cfg_create "$DEST/dtb.img" "$WORK/dtb.cfg"
    $MKDTBOIMG cfg_create "$DEST/dtbo.img" "$WORK/dtbo.cfg"
    echo ">> kernel ready in $DEST"
}

mkdir -p "$WORK" "$OUT"
fetch
fetch_mkdtboimg
configure
build
