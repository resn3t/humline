#!/usr/bin/env bash
# Measure the shell's footprint in the current state and print one Markdown row.
#
#   tools/footprint.sh <label> [seconds]
#
# Run it once per state (e.g. "humline playing", "humline paused",
# "omarchy.media playing") with the same track, the same bar layout and the
# card closed. It samples the Omarchy shell (quickshell) process:
#   RSS      resident memory of the shell, in MB
#   CPU      average CPU of the shell plus its child processes, in % of one core
#   procs    number of child processes the shell has spawned
#   children names of those child processes
# Only reads /proc; changes nothing.
set -euo pipefail

label=${1:?usage: footprint.sh <label> [seconds]}
secs=${2:-20}
pid=$(pgrep -xo quickshell || true)
[ -n "$pid" ] || { echo "no running quickshell" >&2; exit 1; }
hz=$(getconf CLK_TCK)

descendants() { # pid -> all descendant pids
  local p c
  for c in $(pgrep -P "$1" || true); do echo "$c"; descendants "$c"; done
}
ticks() { # sum utime+stime of the shell and its descendants
  local total=0 p t
  for p in "$pid" $(descendants "$pid"); do
    t=$(awk '{print $14+$15}' "/proc/$p/stat" 2>/dev/null || echo 0)
    total=$((total + t))
  done
  echo "$total"
}

t0=$(ticks); sleep "$secs"; t1=$(ticks)
rss=$(awk '/VmRSS/ {printf "%.0f", $2/1024}' "/proc/$pid/status")
kids=$(descendants "$pid" | while read -r c; do [ -n "$c" ] && cat "/proc/$c/comm" 2>/dev/null; done | sort | uniq -c | awk '{printf "%s×%s ", $2, $1}')
n=$(descendants "$pid" | grep -c . || true)
cpu=$(awk -v d=$((t1 - t0)) -v hz="$hz" -v s="$secs" 'BEGIN {printf "%.1f", d / hz / s * 100}')

echo "| $label | ${rss} MB | ${cpu} % | ${n} | ${kids:-none} |"
