#!/bin/bash
# DRAM 856 vs 328MHz idle power A/B: each phase 90s at a fixed speed (userspace governor),
# 1 sample/s of battery voltage + the gauge's current. swayidle/bdowner paused so brightness stays put.
D=/sys/class/devfreq/memory-controller; B=/sys/class/power_supply/cw2015-battery
BL=/sys/class/backlight/edp-backlight/brightness
OUT=/tmp/claude/dmc-power/run-$(date +%H%M).csv
PIDS=$(pgrep -x swayidle; pgrep -x bdowner)
restore() { echo simple_ondemand > $D/governor; [ -n "$PIDS" ] && kill -CONT $PIDS; echo "restored (governor $(cat $D/governor), resumed: $PIDS)"; }
trap 'restore; exit' INT TERM
trap restore EXIT
[ -n "$PIDS" ] && kill -STOP $PIDS
echo userspace > $D/governor
echo "t,phase,mhz,uv,ua,bl,status" > $OUT
t0=${EPOCHREALTIME%.*}; p=0
for f in 856 328 856 328 856 328; do
	p=$((p+1)); echo ${f}000000 > $D/userspace/set_freq
	for i in $(seq 90); do
		read v < $B/voltage_now; read c < $B/current_now; read s < $B/status; read b < $BL
		echo "$(( ${EPOCHREALTIME%.*} - t0 )),$p,$(( $(cat $D/cur_freq) / 1000000 )),$v,$c,$b,$s" >> $OUT
		[ "$s" = Charging ] && { echo "charger plugged in: stopped"; exit 1; }
		sleep 1
	done
done
echo "raw: $OUT"
