#!/bin/bash
# Usage: build-idbloader.sh <u-boot-spl.bin> <out.img> [933|800]
# SD-card idblock (write at sector 64) = Rockchip's DDR blob as TPL + U-Boot SPL. The blob is fetched
# from rkbin and checked against rkbin.sha256; blobs are never stored in this repo.
# 933 (default) trains 328/416/666/856/928MHz, 800 the same minus 928. Both boot at 856MHz.
set -e
spl=$1; out=$2; v=${3:-933}
[ -r "$spl" ] && [ -n "$out" ] || { sed -n 2,5p "$0"; exit 1; }
here=$(dirname "$(readlink -f "$0")"); blob=rk3399_ddr_${v}MHz_v1.30.bin
cache=${XDG_CACHE_HOME:-$HOME/.cache}/towblob; mkdir -p "$cache"
# download to .part first: a partial file under the final name would never be fetched again
[ -f "$cache/$blob" ] || { curl -fsSL -o "$cache/$blob.part" "https://github.com/rockchip-linux/rkbin/raw/master/bin/rk33/$blob" && mv "$cache/$blob.part" "$cache/$blob"; }
(cd "$cache" && grep " $blob\$" "$here/rkbin.sha256" | sha256sum -c --quiet) || { echo "$blob: sha256 mismatch"; exit 1; }
mkimage -n rk3399 -T rksd -d "$cache/$blob:$spl" "$out" >/dev/null
echo "$out: $(stat -c %s "$out") bytes, sha256 $(sha256sum "$out" | cut -c1-16)…; write with: dd of=/dev/mmcblkN bs=512 seek=64 oflag=direct conv=fsync"
