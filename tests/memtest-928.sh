#!/bin/bash
# 928MHz is considered unstable (see kernel/pbp-dmc-928.dts): run this on a test boot, not with data you care about.
# 5min memtester at a fixed 928MHz DRAM clock: 2 x 512MB, one per big core (cpu4, cpu5). Raw output per instance.
D=/sys/class/devfreq/memory-controller; O=${OUT_DIR:-.}/mt; mkdir -p "$O"
restore() { echo simple_ondemand > $D/governor; echo "governor back to $(cat $D/governor)"; }
trap restore EXIT
echo userspace > $D/governor; echo 928000000 > $D/userspace/set_freq
echo "start $(date +%T) dram $(cat $D/cur_freq)"
for c in 4 5; do timeout 300 taskset -c $c memtester 512M 100 > $O/mt-cpu$c.txt 2>&1 & done
for i in $(seq 60); do sleep 5; echo "$(date +%T) $(cat $D/cur_freq) $(cat /sys/class/thermal/thermal_zone0/temp)"; done > $O/freq.txt
wait
echo "end $(date +%T) dram $(cat $D/cur_freq)"
for c in 4 5; do echo "== cpu$c: $(grep -c -i 'ok' $O/mt-cpu$c.txt) ok, $(grep -c -i -E 'fail|error' $O/mt-cpu$c.txt) fail"; done
dmesg | grep -i -E 'wrong freq|dmc|ecc|oops|bug:|panic' | tail -5
