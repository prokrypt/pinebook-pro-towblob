#!/bin/sh
# pbp2z3-sd: pbp2z2-sd with Rockchip's DDR init blob as TPL (2026-10-28).
set -e
cd /tmp/claude/towboot/pinebook-pro-towboot
cp ../rkbin/bin/rk33/rk3399_ddr_800MHz_v1.30.bin blobs/
sha256sum blobs/rk3399_ddr_800MHz_v1.30.bin

# Tow-Boot's Rockchip module builds the SPI image with mkimage from U-Boot's own TPL; let
# ROCKCHIP_TPL (an additionalArguments entry, so an environment variable of the build) replace it.
m=build/Tow-Boot/modules/hardware/rockchip/default.nix
cp $m $m.orig
python3 - "$m" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = "tools/mkimage -n rk3399 -T rkspi -d tpl/u-boot-tpl-dtb.bin:spl/u-boot-spl-dtb.bin spl.bin"
new = "tools/mkimage -n rk3399 -T rkspi -d ''${ROCKCHIP_TPL:-tpl/u-boot-tpl-dtb.bin}:spl/u-boot-spl-dtb.bin spl.bin"
assert s.count(old) == 1
open(p, "w").write(s.replace(old, new))
EOF
diff -u $m.orig $m > patches/towboot-nix-0001-rockchip-spi-image-external-tpl.patch || true
cat patches/towboot-nix-0001-rockchip-spi-image-external-tpl.patch

python3 - <<'EOF'
s = open("nix/pbp2z2-sd.nix").read()
s = s.replace('releaseIdentifier = lib.mkForce "-pbp2z2"', 'releaseIdentifier = lib.mkForce "-pbp2z3"')
anchor = "  Tow-Boot.builder.installPhase"
assert s.count(anchor) == 1
s = s.replace(anchor, '  # Rockchip\'s DDR init blob as TPL (needs towboot-nix-0001 in the Tow-Boot checkout)\n'
              '  Tow-Boot.builder.additionalArguments.ROCKCHIP_TPL = "${../blobs/rk3399_ddr_800MHz_v1.30.bin}";\n' + anchor, 1)
s = s.replace("# 007-pbp2z2-sd:", "# 007-pbp2z3-sd: pbp2z2-sd with Rockchip's DDR init blob (rkbin rk3399_ddr_800MHz_v1.30.bin) as TPL\n"
              "# instead of U-Boot's: the vendor BL31 can't change the DRAM rate after U-Boot's TPL (2026-10-28 tests).\n"
              "# Based on 007-pbp2z2-sd:", 1)
assert '"-pbp2z3"' in s and "ROCKCHIP_TPL" in s
open("nix/pbp2z3-sd.nix", "w").write(s)
EOF
scripts/build.sh pbp2z3-sd > ../build-pbp2z3-sd.log 2>&1; echo "exit $?" >> ../build-pbp2z3-sd.log
grep -A4 "Preparing image for SPI" ../build-pbp2z3-sd.log; tail -4 ../build-pbp2z3-sd.log
