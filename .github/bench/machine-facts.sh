#!/usr/bin/env bash
# Machine facts + three microbenchmarks, ~30s total. Every probe is guarded so
# a missing tool degrades one line instead of voiding the whole measurement.
set -u
ARM="${ARM:-?}"; REP="${REP:-?}"
p() { echo "BENCH arm=$ARM rep=$REP $*"; }

p "runner_name=${RUNNER_NAME:-?}"
p "nproc=$(nproc 2>/dev/null || echo '?')"
p "mem_gb=$(awk '/MemTotal/{printf "%.1f", $2/1048576}' /proc/meminfo 2>/dev/null || echo '?')"
p "cpu_model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | xargs || echo '?')"
p "in_container=$([ -f /.dockerenv ] && echo yes || echo no)"

# 1. CPU, single core. Fixed work unit, so the number is comparable across hosts.
start=$(date +%s%N)
for _ in $(seq 1 300000); do :; done
p "cpu_single_ms=$(( ( $(date +%s%N) - start ) / 1000000 ))"

# 2. Process spawn rate. nextest runs process-per-test (#4385), so fork/exec
#    throughput is the mechanism most likely to differ in a container slot.
start=$(date +%s%N)
for _ in $(seq 1 2000); do /bin/true; done
p "spawn_2000_ms=$(( ( $(date +%s%N) - start ) / 1000000 ))"

# 3. Disk write, the other thing a shared host contends on.
start=$(date +%s%N)
dd if=/dev/zero of=./bench.tmp bs=1M count=256 conv=fdatasync status=none 2>/dev/null \
  && p "disk_write_256mb_ms=$(( ( $(date +%s%N) - start ) / 1000000 ))" \
  || p "disk_write_256mb_ms=?"
rm -f ./bench.tmp
