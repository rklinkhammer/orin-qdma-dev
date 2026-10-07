#!/bin/bash
set -euo pipefail
source /opt/orin-config/versions.sh
root=/home/yocto/orin
exec 8>"$root/.sources.lock"
flock -n -x 8 || { echo 'A build or sync is active.' >&2; exit 1; }
cd "$root"
fetch_pinned() {
    local directory=$1 url=$2 revision=$3
    if [[ ! -e $directory/.git ]]; then
        git init "$directory"
        git -C "$directory" remote add origin "$url"
    fi
    [[ -z $(git -C "$directory" status --porcelain --ignore-submodules=all) ]] || { echo "Local changes in $directory; refusing sync." >&2; exit 1; }
    if ! git -C "$directory" cat-file -e "$revision^{commit}" 2>/dev/null; then
        git -C "$directory" fetch --depth=1 origin "$revision"
    fi
    git -C "$directory" checkout --detach "$revision"
    [[ $(git -C "$directory" rev-parse HEAD) == "$revision" ]]
}
fetch_pinned sources "$DEMO_REPO" "$DEMO_REV"
git -C sources submodule update --init --depth 1 --jobs 2 repos/bitbake repos/openembedded-core repos/meta-openembedded repos/meta-tegra
fetch_pinned sources/repos/bitbake https://github.com/openembedded/bitbake.git "$BITBAKE_REV"
fetch_pinned sources/repos/openembedded-core https://github.com/openembedded/openembedded-core.git "$CORE_REV"
[[ $(git -C sources/repos/meta-tegra rev-parse HEAD) == "$TEGRA_REV" ]]
fetch_pinned dma_ip_drivers "$QDMA_REPO" "$QDMA_REV"
git -C sources rev-parse HEAD > /artifacts/manifest.txt
git -C sources submodule status >> /artifacts/manifest.txt
git -C dma_ip_drivers rev-parse HEAD >> /artifacts/manifest.txt
find sources dma_ip_drivers -name AGENTS.md -not -path '*/.git/*' -print > /artifacts/source-instructions.txt
echo 'Sources pinned. Review any source-instructions.txt before editing upstream sources.'
