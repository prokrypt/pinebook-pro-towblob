#!/bin/sh
# First thing on a dmc-test boot (2026-10-28): stop psd + sync (a lockup must not cost the browser profiles
# or unwritten files), then show which BL31 runs and what the DMC devfreq device is doing.
systemctl --user stop psd 2>/dev/null; sync
echo "psd: $(systemctl --user is-active psd)"
sudo dmesg | grep -E 'psci: PSCI|SMC Calling' | head -2
sudo dmesg | grep -iE 'dmc|devfreq|dfi' | head -20
for d in /sys/class/devfreq/*; do
	[ "$(basename "$(readlink -f "$d/device")")" = memory-controller ] || continue
	echo "== $d"
	echo "governor $(cat "$d/governor")  cur $(cat "$d/cur_freq")  min $(cat "$d/min_freq")  max $(cat "$d/max_freq")"
	echo "available $(cat "$d/available_frequencies")"
	cat "$d/trans_stat"
done
