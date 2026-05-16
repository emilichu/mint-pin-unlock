#!/usr/bin/env bash
# One-click install: README steps 2 through 6.
# Run from the root of this repo after completing step 1 (PIN length + password).

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

if [[ ! -f cinnamon-screensaver-pin-autosubmit.patch || ! -f slick-greeter-pin-autosubmit.patch ]]; then
    echo "ERROR: run this script from the root of the mint-pin-unlock repo" >&2
    exit 1
fi

echo "==> [2/5] Installing build dependencies"
sudo apt build-dep -y cinnamon-screensaver slick-greeter
sudo apt install -y git meson ninja-build valac

build_and_install() {
    local pkg="$1"
    local patch="$REPO_ROOT/${pkg}-pin-autosubmit.patch"

    if [[ -d "$pkg" ]]; then
        echo "    '$pkg' already cloned — reusing"
    else
        git clone "https://github.com/linuxmint/${pkg}.git"
    fi

    cd "$pkg"

    if git apply --reverse --check "$patch" 2>/dev/null; then
        echo "    Patch already applied"
    elif git apply --check "$patch" 2>/dev/null; then
        git apply "$patch"
    else
        echo "ERROR: ${patch##*/} does not apply cleanly to ${pkg}" >&2
        echo "       Upstream may have changed; see README 'Updating after upstream changes'." >&2
        exit 1
    fi

    meson setup builddir --prefix=/usr --buildtype=release --wipe
    ninja -C builddir
    sudo ninja -C builddir install

    cd "$REPO_ROOT"
}

echo "==> [3/5] Patching and building cinnamon-screensaver"
build_and_install cinnamon-screensaver

echo "==> [4/5] Patching and building slick-greeter"
build_and_install slick-greeter

echo "==> [5/5] Holding packages so apt won't overwrite the patched binaries"
sudo apt-mark hold cinnamon-screensaver slick-greeter

echo
echo "Done."
echo "  Lock screen test:  cinnamon-screensaver-command --lock"
echo "  Login screen:      change takes effect on next login"
echo "                     (or: sudo systemctl restart lightdm — this kills your session)"
