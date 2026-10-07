#!/bin/bash
set -eo pipefail
root=/home/yocto/orin
action=${1:?Action required}
exec 8>"$root/.sources.lock"
flock -n -s 8 || { echo 'Source sync is active.' >&2; exit 1; }
mkdir -p "$root/builds/${ORIN_MACHINE}"
exec 9>"$root/builds/${ORIN_MACHINE}/.build.lock"
flock -n 9 || { echo 'Another build uses this MACHINE.' >&2; exit 1; }
case "$action" in
  smoke-*) exec /opt/orin-scripts/smoke.sh "${action#smoke-}" ;;
esac
source /opt/orin-scripts/yocto-env.sh
case "$action" in
  check) bitbake -n qdma-tools qdma ;;
  tools) bitbake qdma-tools ;;
  kernel) bitbake -c compile virtual/kernel ;;
  driver) bitbake qdma ;;
  focused) bitbake qdma-tools qdma ;;
  export) exec python3 /opt/orin-scripts/export.py "$BUILDDIR" ;;
  *) echo 'Unknown build action' >&2; exit 2 ;;
esac
