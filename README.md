# pinebook-pro-towblob

DRAM frequency scaling (DMC devfreq) on the Pinebook Pro (RK3399, 4GB LPDDR4) with a mainline kernel,
by booting [Tow-Boot](https://github.com/Tow-Boot/Tow-Boot) with Rockchip's DDR blob as TPL and
Rockchip's BL31. Tow-Boot + blob = towblob.

**Status (2026-11-17): in daily use on one Pinebook Pro since 2026-10-29, loader in the SPI flash
(eMMC copy as fallback), DRAM at 328/416/666/856MHz.** Tested on that one machine only. This
replaces your boot loader: read [Recovery](#recovery) before flashing anything.

Suspend/resume under the vendor BL31 works (drain 0.43%/h, same as upstream TF-A) with two
workarounds, both in [suspend/](suspend/): the BL31 leaves the DDR monitor frozen after a real
suspend (DMC sticks at its top speed), and it needs its sleep settings sent once per boot.

## Why

The DRAM runs at a fixed speed with U-Boot's own TPL (800MHz) and upstream TF-A. Letting it
drop to 328MHz at idle saves **~0.4W** (measured: [results/](results/)), ~15% of the idle draw
with the screen on.

## What works

| | |
|---|---|
| Speeds | 328, 416, 666, 856MHz ([kernel/pbp-dmc-4step.dts](kernel/pbp-dmc-4step.dts)) |
| 928MHz | **Considered unstable, use with caution**: see below |
| Governor | `simple_ondemand`: idle 328, video ~666, big-core memory load 856 |
| Boot speed | 856MHz with either blob |
| Kernel | mainline 7.3, `rk3399_dmc` + `rockchip_dfi`, no patches |

### 928MHz: unstable

The 933MHz blob trains a 928MHz step and [kernel/pbp-dmc-928.dts](kernel/pbp-dmc-928.dts) enables
it, but **we consider 928MHz unstable on our machine and don't use it.** It runs at the same 900mV
`vdd_center` as the other steps; Rockchip lists 928 as disabled on its own LPDDR4 EVB, and Gru
Chromebooks needed 925mV for it. A 5min memtester run passed, which proves little: DRAM errors
show up as silent bit flips (possibly written to disk), not clean crashes. If you try it, do it
on a test boot without data you care about, and never make it the default. 856MHz at 900mV is
already above Rockchip's own 800MHz at that voltage.

## How it fits together

1. **TPL = Rockchip DDR blob** (`rk3399_ddr_{800,933}MHz_v1.30.bin`, rkbin). It trains the DRAM
   at each speed in its lists and leaves the results at DRAM 0x100000 (5 × 1480-byte records,
   magic 0xfe12cd56).
2. **SPL = Tow-Boot's U-Boot SPL**, loading the U-Boot FIT from the SPI flash, then the eMMC,
   then the SD card ([tow-boot/](tow-boot/), patches 0039–0042).
3. **BL31 = Rockchip's** (`rk3399_bl31_v1.36.elf`, in the FIT, see `tow-boot/pbp2z-a.nix`). Its
   `ROCKCHIP_SIP_DRAM_FREQ` SMC (0x82000008) does the switching, but **only to speeds the blob
   trained**: any other rate returns success and changes nothing (kernel: "Got wrong frequency").
   Upstream TF-A with the blob leaves the DMACs secure-only (no SPI flash, no sound), and the
   first DRAM rate change hangs.
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

## Build

The Tow-Boot side builds inside a checkout of
[pinebook-pro-towboot](https://github.com/prokrypt/pinebook-pro-towboot) (its 007-pbp2y): copy
the patches from [tow-boot/](tow-boot/) into its `patches/`, the `.nix` files into its `nix/`,
apply `towboot-nix-0001` to its Tow-Boot tree, put the rkbin blobs in its `blobs/`, and build
`pbp2z3-sd` (SPL) and `pbp2z-a` (FIT with the vendor BL31) with its `scripts/build.sh`.

Then the idblock (DDR blob + SPL):

```
loader/build-idbloader.sh u-boot-spl.bin idbloader.img 933
```

The blob is downloaded from rkbin and checked against `loader/rkbin.sha256` (which also lists the
BL31 elf); no Rockchip binaries are stored here.

- **SPI flash** (what I use): `mkimage -n rk3399 -T rkspi -d <blob>:<spl> idblock-spi.img` makes the
  idblock (2KB of data per 4KB page, ~528KB) for offset 0; the FIT goes at 1MB (patch 0041).
- **eMMC / SD**: `sudo dd if=idbloader.img of=/dev/mmcblkN bs=512 seek=64 oflag=direct conv=fsync`;
  the FIT goes at sector 16384.

Patch 0042 was test-built on 2026-11-17: its SPL is byte-for-byte the one in daily use since
2026-10-29 (which had the same boot order binary-patched into its device tree).

## Recovery

The boot ROM reads SPI → eMMC → SD and takes the first valid idblock. With the loader in SPI,
a broken SPI copy can't be bypassed with the eMMC switch or a card: only maskrom recovers the
machine. Keep a dump of your SPI flash (`/dev/mtd0`) before writing it. Putting the idblock on
the eMMC instead (sector 64) keeps an easier way back: eMMC switch off + a bootable card.

Patch 0039 alone (card first) is a trap: a Manjaro/Armbian card with a U-Boot FIT at sector
16384 inserted at power-on boots its upstream TF-A under the blob, and the first DRAM rate change
hangs. Always build with 0042 on top.

## Suspend workarounds

- [suspend/ddrmon-rearm](suspend/ddrmon-rearm): after a real suspend the vendor BL31 leaves the
  DDR monitor (DFI) in hardware mode with its counters frozen, so devfreq sees no load and the
  DMC sticks at its top speed. This puts it back in software counting mode through `/dev/mem`
  (needs root, and a kernel without `IO_STRICT_DEVMEM`). Run it after each resume, e.g. with
  [suspend/ddrmon-rearm.sleep](suspend/ddrmon-rearm.sleep) as a systemd system-sleep hook.
- [suspend/rk-suspend-cfg/](suspend/rk-suspend-cfg/): DKMS module that sends the BL31 the
  Pinebook Pro sleep settings (power mode, wakeup sources, VSEL pins; SIP 0x82000003) that
  Rockchip's vendor kernel would. Load it once per boot (`rk_suspend_cfg.conf` →
  `/etc/modules-load.d/`). Under upstream TF-A it logs one line and does nothing.

## Layout

- `loader/`: idblock build script, blob hashes
- `tow-boot/`: Tow-Boot patches and build configs
- `kernel/`: DMC device tree overlays
- `suspend/`: the two suspend workarounds
- `tests/`: `dmc-check.sh` (state after boot), `abtest.sh` + `analyse.py` (idle power A/B from
  battery voltage), `copy.py` (memory load), `memtest-928.sh`
- `results/`: raw data
- `tools/rkhdr.py`: decode a Rockchip idblock header

## Tow-Boot patches

On top of pinebook-pro-towboot's 007-pbp2y:

- `0039`: SPL loads U-Boot + TF-A from the SD card first (FIT at sector 16384); replaced by 0042's order
- `0040`: SPL sets up the SD card pins itself (needed when SPL starts from SPI)
- `0041`: U-Boot FIT at 1MB in SPI (blob + SPL no longer fit in 512KB)
- `0042`: SPL boot order SPI flash → eMMC → SD card
- `towboot-nix-0001`: Tow-Boot's nix build takes an external TPL (`$ROCKCHIP_TPL`, `$SPI_UBOOT_PAD`)
- `pbp2z-sd.nix` → `pbp2z2-sd.nix` → `pbp2z3-sd.nix` (blob TPL) and `pbp2z-a.nix` (vendor BL31 FIT)
- `scripts/`: how the patches and nix files were generated (`W` = work dir)

## License

GPL-2.0 ([LICENSE](LICENSE)), like U-Boot and Tow-Boot.
