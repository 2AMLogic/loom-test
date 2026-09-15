#!/usr/bin/env bash
# Disk/state probe. Tests whether the runner accumulates state across jobs —
# the "are we exhausting the runner's disk" hypothesis — and whether anything
# is host-mounted (which would mean jobs are NOT disposable).
set -u
ARM="${ARM:-?}"
p() { echo "DISK arm=$ARM $*"; }

p "runner=${RUNNER_NAME:-?}"
p "in_container=$([ -f /.dockerenv ] && echo yes || echo no)"

# Host uptime leaks through /proc/uptime unless namespaced. A large value on a
# supposedly ephemeral runner means we are seeing long-lived host state.
up=$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1)
[ -n "${up:-}" ] && p "uptime_s=$up uptime_days=$((up/86400))"

for path in / "${RUNNER_WORKSPACE:-$PWD}" "$HOME"; do
  [ -d "$path" ] || continue
  df -Pk "$path" 2>/dev/null | awk -v a="$ARM" -v pth="$path" 'NR==2{
    printf "DISK arm=%s df path=%s size_gb=%.1f used_gb=%.1f avail_gb=%.1f use_pct=%s mount=%s\n",
           a, pth, $2/1048576, $3/1048576, $4/1048576, $5, $6 }'
  df -Pi "$path" 2>/dev/null | awk -v a="$ARM" -v pth="$path" 'NR==2{
    printf "DISK arm=%s inodes path=%s used_pct=%s avail=%s\n", a, pth, $5, $4 }'
done

# Host bind mounts on the work dirs => state survives the container => not disposable.
mount 2>/dev/null | grep -E " on (/home/runner|/__w|/actions-runner|/work)" | head -5 \
  | while IFS= read -r l; do p "mount $l"; done

# Anything large enough to accumulate run over run.
for d in "$HOME/.cargo" "$HOME/.rustup" "${RUNNER_WORKSPACE:-}" /var/lib/docker /tmp; do
  [ -n "$d" ] && [ -d "$d" ] && p "du dir=$d size_mb=$(timeout 20 du -sm "$d" 2>/dev/null | cut -f1)"
done

if command -v docker >/dev/null 2>&1; then
  p "docker_df=$(timeout 20 docker system df --format '{{.Type}}={{.Size}}({{.Reclaimable}})' 2>/dev/null | tr '\n' ' ')"
else
  p "docker=absent"
fi
