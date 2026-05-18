#!/usr/bin/env bash
# One-click installer for mint-pin-unlock.
# Prompts for PIN length, optionally lets you set a new password,
# then patches cinnamon-screensaver, slick-greeter, and cinnamon's polkit
# auth dialog.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

REQUIRED_PATCHES=(
    cinnamon-screensaver-pin-autosubmit.patch
    slick-greeter-pin-autosubmit.patch
    cinnamon-polkit-pin-autosubmit.patch
)
for p in "${REQUIRED_PATCHES[@]}"; do
    if [[ ! -f "$p" ]]; then
        echo "ERROR: run this script from the root of the mint-pin-unlock repo" >&2
        exit 1
    fi
done

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

    # Idempotency: check the INSTALLED file, not the local source tree. A
    # previous run leaves the clone patched, so checking the source would
    # short-circuit even after `uninstall.sh` reverted the system to stock.
    local installed_marker_path installed_marker
    case "$pkg" in
        cinnamon-screensaver)
            installed_marker_path=/usr/share/cinnamon-screensaver/unlock.py
            installed_marker=_get_pin_length
            ;;
        slick-greeter)
            installed_marker_path=/usr/sbin/slick-greeter
            installed_marker=/etc/pin-unlock/length
            ;;
        *)
            echo "ERROR: unknown package '$pkg' in build_and_install" >&2
            exit 1
            ;;
    esac
    if grep -aq "$installed_marker" "$installed_marker_path" 2>/dev/null; then
        echo "    Installed files already patched — skipping rebuild"
        return 0
    fi

    if [[ -d "$pkg" ]]; then
        echo "    '$pkg' already cloned — reusing"
    else
        git clone "https://github.com/linuxmint/${pkg}.git"
    fi

    cd "$pkg"

    if git apply --reverse --check "$patch" 2>/dev/null; then
        echo "    Source already patched — rebuilding to install"
    elif git apply --check "$patch" 2>/dev/null; then
        git apply "$patch"
    else
        echo "ERROR: ${patch##*/} does not apply cleanly to ${pkg}" >&2
        echo "       Upstream may have changed; see README 'Manual install'." >&2
        exit 1
    fi

    if [[ -d builddir ]]; then
        meson setup --reconfigure builddir --prefix=/usr --buildtype=release "$@"
    else
        meson setup builddir --prefix=/usr --buildtype=release "$@"
    fi
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

echo "==> Patching cinnamon's polkit auth dialog"
# Cinnamon embeds its own polkit agent (JavaScript, no rebuild needed).
# Patch the installed file in place; the package is held below so apt
# upgrades won't overwrite it.
CINNAMON_JS=/usr/share/cinnamon/js/ui/polkitAuthenticationAgent.js
if grep -q "_getPinLength" "$CINNAMON_JS"; then
    echo "    Patch already applied"
elif sudo patch --batch --forward --dry-run -p1 -d / \
        < "$REPO_ROOT/cinnamon-polkit-pin-autosubmit.patch" >/dev/null 2>&1; then
    sudo patch --batch --forward -p1 -d / < "$REPO_ROOT/cinnamon-polkit-pin-autosubmit.patch"
else
    echo "ERROR: cinnamon-polkit-pin-autosubmit.patch does not apply cleanly to" >&2
    echo "       $CINNAMON_JS — upstream may have changed." >&2
    exit 1
fi

echo "==> Holding packages so apt won't overwrite the patched files"
sudo apt-mark hold cinnamon-screensaver slick-greeter cinnamon-common

echo
echo "Done."
echo "  Lock screen test:  cinnamon-screensaver-command --lock"
echo "  Login screen:      change takes effect on next login"
echo "                     (or: sudo systemctl restart lightdm — this kills your session)"
echo "  Polkit dialog:     restart Cinnamon to pick up the JS change"
echo "                     (Alt+F2, type 'r', Enter — or log out and back in),"
echo "                     then test with: pkexec /bin/true"
echo
read -rp "Press Enter to close..." _
