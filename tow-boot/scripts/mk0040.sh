#!/bin/sh
# Make patch 0040 (SD pin mux in SPL) on top of ub-patched (patch stack + 0039).
set -e
# W: work dir holding the pinebook-pro-towboot checkout and ub-patched (U-Boot tree with the patch stack)
W=${W:?set W to the work dir}
cd $W/ub-patched
python3 - <<'EOF'
p = "arch/arm/mach-rockchip/rk3399/rk3399.c"
s = open(p).read()
old = """	grf = syscon_get_first_range(ROCKCHIP_SYSCON_GRF);
	rk_clrreg(&grf->emmccore_con[11], 0x0ff);
#endif
"""
new = """	grf = syscon_get_first_range(ROCKCHIP_SYSCON_GRF);
	rk_clrreg(&grf->emmccore_con[11], 0x0ff);

#if !defined(CONFIG_TPL_BUILD)
	/*
	 * SD card pins (GPIO4_B0-B5) to the SD function, pull-up on data and
	 * CMD, none on CLK (as Linux sets them). The BootROM only sets them up
	 * when it boots from the card itself, and SPL's device tree has no
	 * pinctrl properties, so an SPL started from SPI couldn't talk to it.
	 */
	rk_clrsetreg(&grf->gpio4b_iomux,
		     GRF_GPIO4B0_SEL_MASK | GRF_GPIO4B1_SEL_MASK |
		     GRF_GPIO4B2_SEL_MASK | GRF_GPIO4B3_SEL_MASK |
		     GRF_GPIO4B4_SEL_MASK | GRF_GPIO4B5_SEL_MASK,
		     GRF_SDMMC_DATA0 << GRF_GPIO4B0_SEL_SHIFT |
		     GRF_SDMMC_DATA1 << GRF_GPIO4B1_SEL_SHIFT |
		     GRF_SDMMC_DATA2 << GRF_GPIO4B2_SEL_SHIFT |
		     GRF_SDMMC_DATA3 << GRF_GPIO4B3_SEL_SHIFT |
		     GRF_SDMMC_CLKOUT << GRF_GPIO4B4_SEL_SHIFT |
		     GRF_SDMMC_CMD << GRF_GPIO4B5_SEL_SHIFT);
	/* 2 bits per pin, 1 = pull-up */
	rk_clrsetreg(&grf->gpio4_p[1], 0xfff, 0x455);
#endif
#endif
"""
assert s.count(old) == 1
open(p, "w").write(s.replace(old, new))
EOF
git commit -qa -F - <<'EOF'
rockchip: rk3399: set up the SD card pins in SPL

SPL's device tree has its pinctrl properties removed
(OF_SPL_REMOVE_PROPS), so SPL never muxes the SD card pins. That works
when the BootROM itself booted from the card, because it leaves them set
up, but an SPL started from SPI that tries the card first (patch 0039)
finds GPIO4_B0-B5 still plain GPIOs: every command times out and SPL goes
on to SPI after ~20 ms, so a FIT on the card is never used.

Set them to the SD function in arch_cpu_init(), SPL only (not TPL), with
the pulls Linux uses: pull-up on D0-D3 and CMD, none on CLK.
EOF
git format-patch -1 --stdout --zero-commit | sed "s/^Date: .*/Date: $(date -R)/" > $W/pinebook-pro-towboot/patches/0040-rockchip-rk3399-set-up-the-SD-card-pins-in-SPL.patch
cd $W/pinebook-pro-towboot
python3 - <<'EOF'
s = open("nix/pbp2z-sd.nix").read()
p39 = "    ../patches/0039-pinebook-pro-let-SPL-load-U-Boot-and-TF-A-from-the-SD.patch\n"
assert s.count(p39) == 1
s = s.replace(p39, p39 + "    ../patches/0040-rockchip-rk3399-set-up-the-SD-card-pins-in-SPL.patch\n")
s = s.replace('releaseIdentifier = lib.mkForce "-pbp2z"', 'releaseIdentifier = lib.mkForce "-pbp2z2"')
s = s.replace("# 007-pbp2z-sd: pbp2y + SPL loads", "# 007-pbp2z2-sd: pbp2z-sd + SPL sets up the SD card pins itself (patch 0040; pbp2z-sd never\n# reached the card when started from SPI). Based on 007-pbp2z-sd: pbp2y + SPL loads", 1)
assert '"-pbp2z2"' in s and s.count("patches/0040") == 1
open("nix/pbp2z2-sd.nix", "w").write(s)
EOF
sed -n '/^diff/,$p' patches/0040-rockchip-rk3399-set-up-the-SD-card-pins-in-SPL.patch
