import re

s = open("nix/pbp2y.nix").read()
hdr = """# 007-pbp2z-sd: pbp2y + SPL loads U-Boot/TF-A from the SD card first (patch 0039), so a
# test FIT written to sector 0x4000 of the card boots instead of the one in SPI; without one
# SPL falls back to SPI. Test vehicle for DRAM frequency scaling (2026-10-28).
"""
s = hdr + s
s = s.replace('releaseIdentifier = lib.mkForce "-pbp2y"', 'releaseIdentifier = lib.mkForce "-pbp2z"')
p38 = "    ../patches/0038-board_f-rk3399-turn-the-data-cache-on-before-relocat.patch\n"
s = s.replace(p38, p38 + "    ../patches/0039-pinebook-pro-let-SPL-load-U-Boot-and-TF-A-from-the-SD.patch\n")
s = s.replace("cp u-boot u-boot.map", "cp u-boot.itb u-boot u-boot.map")
assert s.count("patches/0039") == 1 and '"-pbp2z"' in s and "u-boot.itb u-boot" in s
open("nix/pbp2z-sd.nix", "w").write(s)

a = s.replace("# 007-pbp2z-sd:", "# 007-pbp2z-a: pbp2z-sd with Rockchip's BL31 blob (rkbin rk3399_bl31_v1.36.elf) instead of\n"
              "# upstream TF-A + tfa-0001; only its u-boot.itb is meant to be used, from the SD card.\n"
              "# Based on 007-pbp2z-sd:", 1)
a, n = re.subn(r'Tow-Boot\.builder\.additionalArguments\.BL31 = lib\.mkForce "\$\{.*?\}/bl31\.elf";',
               'Tow-Boot.builder.additionalArguments.BL31 = lib.mkForce "${../blobs/rk3399_bl31_v1.36.elf}";',
               a, flags=re.S)
assert n == 1
a = a.replace('"-pbp2z"', '"-pbp2z-a"')
open("nix/pbp2z-a.nix", "w").write(a)
