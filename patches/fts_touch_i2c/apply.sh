#!/usr/bin/env bash
set -euo pipefail

EXPECTED_SHA="26853b6f7d8426ad725c1bcc8e8ec0b002ab2f7644799108bf785009ac20b1c6"
KERNEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

patch_file() {
    local target="$1"
    local base="$(basename "$target")"

    if [[ ! -f "$target" ]]; then
        echo "Target $target not found" >&2
        return 1
    fi

    # Verify matching original before touching bytes
    local current_sha
    current_sha="$(sha256sum "$target" | awk '{print $1}')"
    if [[ "$current_sha" != "$EXPECTED_SHA" ]]; then
        if [[ -f "${target}.orig" ]]; then
            local orig_sha
            orig_sha="$(sha256sum "${target}.orig" | awk '{print $1}')"
            if [[ "$orig_sha" == "$EXPECTED_SHA" ]]; then
                cp -f "${target}.orig" "$target"
            else
                echo "Checksum mismatch and backup invalid for $target" >&2
                return 1
            fi
        else
            echo "Checksum mismatch for $target: $current_sha" >&2
            return 1
        fi
    fi

    cp -n "$target" "${target}.orig"

    # P1: 0x0000cfc8: b.ne 0x800cfe4 (e1000054) -> b 0x800cfe4 (07000014)
    # Bypasses proximity suspend early return, ensuring gesture mode initialization.
    printf '\x07\x00\x00\x14' | dd of="$target" bs=1 seek=$((0xcfc8)) count=4 conv=notrunc status=none

    # P2: 0x0000d008: tbnz w8, 0, 0x800d014 (68000037) -> b 0x800d014 (03000014)
    # Forces gesture_support=1 on suspend, preventing deep sleep poweroff.
    printf '\x03\x00\x00\x14' | dd of="$target" bs=1 seek=$((0xd008)) count=4 conv=notrunc status=none

    # P3: 0x0000d02c: b.gt 0x800d04c (0c010054) -> b 0x800d04c (08000014)
    # Forces 0xCF FOD enable and 0xD0 doubletap enable even when fod_status is 0.
    printf '\x08\x00\x00\x14' | dd of="$target" bs=1 seek=$((0xd02c)) count=4 conv=notrunc status=none

    # P4: 0x0000c58c: cbz w9, 0x800c5b4 (890f0034) -> nop (1f2003d5)
    # Prevents dropping suspended touch-down when fod_status is 0.
    printf '\x1f\x20\x03\xd5' | dd of="$target" bs=1 seek=$((0xc58c)) count=4 conv=notrunc status=none

    # Verify patched offsets
    local p1 p2 p3 p4
    p1="$(xxd -p -s $((0xcfc8)) -l 4 "$target")"
    p2="$(xxd -p -s $((0xd008)) -l 4 "$target")"
    p3="$(xxd -p -s $((0xd02c)) -l 4 "$target")"
    p4="$(xxd -p -s $((0xc58c)) -l 4 "$target")"

    if [[ "$p1" != "07000014" || "$p2" != "03000014" || "$p3" != "08000014" || "$p4" != "1f2003d5" ]]; then
        echo "Verification failed for $target: p1=$p1 p2=$p2 p3=$p3 p4=$p4" >&2
        cp -f "${target}.orig" "$target"
        return 1
    fi

    echo "Successfully patched $target"
}

patch_file "$KERNEL_DIR/modules_dlkm/fts_touch_i2c.ko"
patch_file "$KERNEL_DIR/modules_ramdisk/fts_touch_i2c.ko"
