# pinebook-pro-towblob

DRAM frequency scaling (DMC devfreq) on the Pinebook Pro (RK3399, 4GB LPDDR4) with a mainline kernel,
by booting [Tow-Boot](https://github.com/Tow-Boot/Tow-Boot) with Rockchip's DDR blob as TPL and
Rockchip's BL31. Tow-Boot + blob = towblob.

**Status (2026-10-29): in daily use on one Pinebook Pro, loader in the SPI flash (eMMC copy as fallback). Private, not for others yet.**
Suspend/resume under the vendor BL31 works (drain 0.43%/h, same as upstream TF-A), with two
workarounds: after a real suspend the BL31 leaves the DDR monitor frozen (DMC sticks at its top speed),
re-armed from userspace at each wake (`ddrmon-rearm`); and the BL31's sleep settings (PWRMODE_CON,
VSEL pins) are sent once per boot by a small module (`rk_suspend_cfg`, SIP 0x82000003). Both live in
the laptop's own setup, not here yet.

## Why

The DRAM runs at a fixed speed with U-Boot's own TPL (800MHz) and upstream TF-A. Letting it
drop to 328MHz at idle saves **~0.4W** (measured: [results/](results/)), ~15% of the idle draw
with the screen on.

## What works

| | |
|---|---|
| Speeds | 328, 416, 666, 856, 928MHz (928 needs the 933MHz blob) |
| Governor | `simple_ondemand`: idle 328, video ~666, big-core memory load 856/928 |
| Boot speed | 856MHz with either blob |
| 928MHz | 5min memtester (2×512MB on the big cores) clean; longer runs pending |
| Kernel | mainline 7.3, `rk3399_dmc` + `rockchip_dfi`, no patches |

## How it fits together

1. **TPL = Rockchip DDR blob** (`rk3399_ddr_{800,933}MHz_v1.30.bin`, rkbin). It trains the DRAM
   at each speed in its lists and leaves the results at DRAM 0x100000 (5 × 1480-byte records,
   magic 0xfe12cd56).
2. **SPL = Tow-Boot's U-Boot SPL**, patched to load U-Boot + TF-A from the SD card
   ([tow-boot/](tow-boot/), patches 0039, 0040). The SPL flashed on my machine tries the SPI
   first (see below).
3. **BL31 = Rockchip's** (`rk3399_bl31_v1.36.elf`, in the FIT, see `tow-boot/pbp2z-a.nix`). Its
   `ROCKCHIP_SIP_DRAM_FREQ` SMC (0x82000008) does the switching, but **only to speeds the blob
   trained**: any other rate returns success and changes nothing (kernel: "Got wrong frequency").
   Upstream TF-A with the blob leaves the DMACs secure-only (no SPI flash, no sound).
4. **Kernel**: a DT overlay ([kernel/](kernel/)) enables `&dmc` with an OPP table of exactly the
   trained speeds, all at 900mV `vdd_center`.

## Findings

- The blobs' speed lists: table at offset 0x23710 = 856 666 416 328 528 (528 is ignored by the
  BL31); second list at 0x1ee58 = 328 666 **0** (800 blob) / 328 666 **928** (933 blob). The two
  blobs differ in 6 bytes.
- Rockchip's own LPDDR4 EVB (`rk3399-evb-ind.dtsi`, develop-4.19) enables the same four speeds
  and lists 928 as disabled.
- `simple_ondemand` never raises the clock for a little-core (A53) load: one A53 copying memory
  runs at 1451MB/s at 856 but 768MB/s at 328, yet leaves the controller too idle to trigger it.

## Build the loader

```
loader/build-idbloader.sh u-boot-spl.bin idbloader.img 933
sudo dd if=idbloader.img of=/dev/mmcblkN bs=512 seek=64 oflag=direct conv=fsync
```

The blob is downloaded from rkbin and checked against `loader/rkbin.sha256` (which also lists the
BL31 elf); no Rockchip binaries are stored here. The U-Boot FIT (vendor BL31) goes at sector 16384.

For the SPI flash, `mkimage -n rk3399 -T rkspi -d <blob>:<spl> idblock-spi.img` makes the
idblock (2KB of data per 4KB page, ~528KB, written at offset 0); the FIT goes at 1MB (patch 0041).

On my machine (since 2026-10-29): the rkspi idblock in **SPI 0–528KB**, the vendor-BL31 FIT at
**SPI 1MB**. The SPL's order is `spiflash, sdhci, sdmmc`, patched in the flashed binary only
(patch 0039 still has the card first), so a card with a U-Boot FIT at sector 16384 no longer
takes over the boot. The eMMC still holds the idblock at sector 64 and the FIT at 16384 as a
fallback; the boot ROM ignores them while the SPI has a valid idblock. Cold boot OK on
2026-10-29. If the SPI copy breaks, only maskrom recovers the machine.
Before that (2026-10-28/29) the idblock was on the eMMC with the card first, and a Manjaro/Armbian
card at power-on booted the blob under an upstream TF-A: DMA stayed secure and the first DRAM
rate change hung.

## Layout

- `loader/`: idblock build script, blob hashes
- `tow-boot/`: Tow-Boot patches and build configs
- `kernel/`: DMC device tree overlays
- `tests/`: `dmc-check.sh` (state after boot), `abtest.sh` + `analyse.py` (idle power A/B from
  battery voltage), `copy.py` (memory load), `memtest-928.sh`
- `results/`: raw data
- `tools/rkhdr.py`: decode a Rockchip idblock header

## Tow-Boot side

Built from [pinebook-pro-towboot](https://github.com/prokrypt/pinebook-pro-towboot) (its 007-pbp2y)
plus, in [tow-boot/](tow-boot/):

- `0039`: SPL loads U-Boot + TF-A from the SD card first (FIT at sector 16384), SPI as fallback (the SPL I flashed has spiflash first, binary-patched)
- `0040`: SPL sets up the SD card pins itself (needed when SPL starts from SPI)
- `0041`: U-Boot FIT at 1MB in SPI (blob + SPL no longer fit in 512KB)
- `towboot-nix-0001`: Tow-Boot's nix build takes an external TPL (`$ROCKCHIP_TPL`, `$SPI_UBOOT_PAD`)
- `pbp2z-sd.nix` → `pbp2z2-sd.nix` → `pbp2z3-sd.nix` (blob TPL) and `pbp2z-a.nix` (vendor BL31 FIT)
- `scripts/`: how the patches and nix files were generated

## Missing

- The spiflash-first SPL order as a patch in tow-boot/ (only binary-patched so far)
- The `ddrmon-rearm` and `rk_suspend_cfg` workarounds (in the laptop's setup, not here)
- Longer 928MHz memtester runs
