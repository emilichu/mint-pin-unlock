#!/usr/bin/env bash
# One-click installer for mint-pin-unlock.
# Prompts for PIN length, optionally lets you set a new password,
# then patches and installs cinnamon-screensaver and slick-greeter.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

if [[ ! -f cinnamon-screensaver-pin-autosubmit.patch || ! -f slick-greeter-pin-autosubmit.patch ]]; then
    echo "ERROR: run this script from the root of the mint-pin-unlock repo" >&2
    exit 1
fi

# ---- PIN length + optional password change ----

read -rp "PIN length (positive integer, e.g. 6): " LENGTH
if ! [[ "$LENGTH" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: '$LENGTH' is not a positive integer" >&2
    exit 1
fi

echo "==> Writing /etc/pin-unlock/length"
sudo mkdir -p /etc/pin-unlock
echo "$LENGTH" | sudo tee /etc/pin-unlock/length >/dev/null
sudo chmod 644 /etc/pin-unlock/length

read -rp "Change your password now? Skip if your current password is already ${LENGTH} characters. [y/N]: " CHANGE_PW
if [[ "$CHANGE_PW" =~ ^[Yy]$ ]]; then
    echo "==> Running passwd — enter a value of exactly ${LENGTH} characters"
    passwd
fi

# ---- Build dependencies, patch, build, install, hold ----

echo "==> Installing build dependencies"
sudo apt build-dep -y cinnamon-screensaver slick-greeter
sudo apt install -y git meson ninja-build valac

build_and_install() {
    local pkg="$1"
    shift
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
        echo "       Upstream may have changed; see README 'Manual install'." >&2
        exit 1
    fi

    meson setup builddir --prefix=/usr --buildtype=release --wipe "$@"
    ninja -C builddir
    sudo ninja -C builddir install

    cd "$REPO_ROOT"
}

echo "==> Patching and building cinnamon-screensaver"
# use-debian-pam picks the @include common-auth PAM file; without it,
# meson installs the Fedora/Arch variant that includes system-auth and
# breaks authentication on Mint/Debian/Ubuntu.
build_and_install cinnamon-screensaver -Duse-debian-pam=true

echo "==> Patching and building slick-greeter"
build_and_install slick-greeter

echo "==> Holding packages so apt won't overwrite the patched binaries"
sudo apt-mark hold cinnamon-screensaver slick-greeter

echo
echo "Done."
echo "  Lock screen test:  cinnamon-screensaver-command --lock"
echo "  Login screen:      change takes effect on next login"
echo "                     (or: sudo systemctl restart lightdm — this kills your session)"
