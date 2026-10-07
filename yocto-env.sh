# Source this file to initialize a target; custom configuration is preserved.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then echo 'Source this script.' >&2; exit 2; fi
root=/home/yocto/orin
export ORIN_MACHINE=${ORIN_MACHINE:-p3768-0000-p3767-0000}
[[ -f $root/sources/repos/meta-tegra/conf/machine/$ORIN_MACHINE.conf ]] || { echo "Unknown MACHINE $ORIN_MACHINE, or run ./orin sync first." >&2; return 1; }
orin_build_dir="$root/builds/$ORIN_MACHINE"
mkdir -p "$orin_build_dir/conf"
if [[ ! -f $orin_build_dir/conf/bblayers.conf ]]; then
    cat > "$orin_build_dir/conf/bblayers.conf" <<CONF
LCONF_VERSION = "8"
BBPATH = "\${TOPDIR}"
BBFILES ?= ""
BBLAYERS = "$root/sources/repos/openembedded-core/meta $root/sources/repos/meta-openembedded/meta-oe $root/sources/repos/meta-tegra /opt/orin-layers/meta-orin-qdma"
CONF
fi
if [[ ! -f $orin_build_dir/conf/local.conf ]]; then
    cat > "$orin_build_dir/conf/local.conf" <<CONF
MACHINE = "$ORIN_MACHINE"
DISTRO = "orin-qdma"
CONF
fi
if ! grep -qxF 'require /opt/orin-config/build-policy.inc' "$orin_build_dir/conf/local.conf"; then
    cat >> "$orin_build_dir/conf/local.conf" <<'CONF'
require /opt/orin-config/build-policy.inc
include conf/orin-policy.conf
CONF
fi
export BITBAKEDIR="$root/sources/repos/bitbake"
source "$root/sources/repos/openembedded-core/oe-init-build-env" "$orin_build_dir" || return
