#!/bin/sh
# pbp2z3-sd, second try: U-Boot FIT at 1 MB in SPI (Rockchip's DDR blob makes TPL+SPL ~540 KB, past 512 KB).
set -e
# W: work dir holding the pinebook-pro-towboot checkout and ub-patched (U-Boot tree with the patch stack)
W=${W:?set W to the work dir}
cd $W/ub-patched
python3 - <<'EOF'
p = "arch/arm/dts/rk3399-pinebook-pro-u-boot.dtsi"
s = open(p).read()
old = "u-boot,spl-payload-offset = <0x60000>; /* @ 384KB */"
assert s.count(old) == 1
open(p, "w").write(s.replace(old, "u-boot,spl-payload-offset = <0x100000>; /* @ 1MB */"))
EOF
git commit -qa -F - <<'EOF'
pinebook-pro: U-Boot FIT at 1 MB in the SPI flash

With Rockchip's DDR init blob as TPL (146 KB, twice U-Boot's TPL), TPL +
SPL take about 540 KB in the SPI flash (rkspi stores 2 KB per 4 KB page),
past the 512 KB where the U-Boot FIT used to start. Move it to 1 MB.
Tow-Boot's build rewrites this value from 0x60000 to its own 0x80000;
that sed no longer matches, so the 1 MB set here stays. The recipe sets
CONFIG_SYS_SPI_U_BOOT_OFFS and the image padding to match.
EOF
git format-patch -1 --stdout --zero-commit | sed "s/^Date: .*/Date: $(date -R)/" > $W/pinebook-pro-towboot/patches/0041-pinebook-pro-U-Boot-FIT-at-1-MB-in-the-SPI-flash.patch

cd $W/pinebook-pro-towboot
m=build/Tow-Boot/modules/hardware/rockchip/default.nix
python3 - "$m" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = "cat <(dd if=spl.bin bs=512K conv=sync) u-boot.itb"
new = "cat <(dd if=spl.bin bs=''${SPI_UBOOT_PAD:-512K} conv=sync) u-boot.itb"
assert s.count(old) == 1
open(p, "w").write(s.replace(old, new))
EOF
diff -u $m.orig $m > patches/towboot-nix-0001-rockchip-spi-image-external-tpl.patch || true
cat patches/towboot-nix-0001-rockchip-spi-image-external-tpl.patch

python3 - <<'EOF'
s = open("nix/pbp2z3-sd.nix").read()
p40 = "    ../patches/0040-rockchip-rk3399-set-up-the-SD-card-pins-in-SPL.patch\n"
assert s.count(p40) == 1 and "0041" not in s
s = s.replace(p40, p40 + "    ../patches/0041-pinebook-pro-U-Boot-FIT-at-1-MB-in-the-SPI-flash.patch\n")
a = '  Tow-Boot.builder.additionalArguments.ROCKCHIP_TPL'
assert s.count(a) == 1
s = s.replace(a, '  # TPL + SPL no longer fit in 512 KB: U-Boot FIT at 1 MB (patch 0041 for SPL\'s DT, the image padding here)\n'
              '  Tow-Boot.builder.additionalArguments.SPI_UBOOT_PAD = "1M";\n' + a, 1)
c = "      SF_DEFAULT_SPEED"
assert s.count(c) == 1
s = s.replace(c, '      SYS_SPI_U_BOOT_OFFS = lib.mkForce (freeform "0x100000");\n' + c, 1)
open("nix/pbp2z3-sd.nix", "w").write(s)
EOF
diff nix/pbp2z2-sd.nix nix/pbp2z3-sd.nix
scripts/build.sh pbp2z3-sd > ../build-pbp2z3-sd.log 2>&1; echo "exit $?" >> ../build-pbp2z3-sd.log
grep -A4 "Preparing image for SPI" ../build-pbp2z3-sd.log | grep -E "mkimage|Size|dd "; tail -5 ../build-pbp2z3-sd.log
