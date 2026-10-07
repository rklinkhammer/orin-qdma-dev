#!/bin/bash
set -eo pipefail
root=/home/yocto/orin
action=${1:?Action required}
exec 8>"$root/.sources.lock"
flock -n -s 8 || { echo 'Source sync is active.' >&2; exit 1; }
case "$action" in
  smoke-*)
    mkdir -p "$root/smoke/${ORIN_MACHINE}"
    exec 9>"$root/smoke/${ORIN_MACHINE}/.smoke.lock"
    flock -n 9 || { echo 'Another smoke build uses this MACHINE.' >&2; exit 1; }
    exec /opt/orin-scripts/smoke.sh "${action#smoke-}" ;;
esac
mkdir -p "$root/builds/${ORIN_MACHINE}"
exec 9>"$root/builds/${ORIN_MACHINE}/.build.lock"
flock -n 9 || { echo 'Another build uses this MACHINE.' >&2; exit 1; }
source /opt/orin-scripts/yocto-env.sh
case "$action" in
  check) bitbake -n qdma-tools; bitbake -n -c install qdma ;;
  patch) bitbake -c patch qdma-tools qdma ;;
  tools) bitbake qdma-tools ;;
  kernel) bitbake -c compile virtual/kernel ;;
  # Module packaging asks for kernel package metadata and NVIDIA deploy tools.
  # Staged install gives a real .ko without crossing that proprietary boundary.
  driver) bitbake -c install qdma ;;
  focused) bitbake qdma-tools; bitbake -c install qdma ;;
  export) exec python3 /opt/orin-scripts/export.py "$BUILDDIR" ;;
  *) echo 'Unknown build action' >&2; exit 2 ;;
esac
