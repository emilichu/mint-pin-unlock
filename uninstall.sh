#!/usr/bin/env bash
# Uninstaller for mint-pin-unlock. Reverses install.sh:
#   - removes /etc/pin-unlock/length
#   - unholds the three patched packages
#   - reinstalls them from apt so the stock binaries / PAM file / polkit JS
#     come back
#
# Safe to re-run: each step is a no-op if there's nothing to undo.

set -euo pipefail

PACKAGES=(cinnamon-screensaver slick-greeter cinnamon-common)
CINNAMON_JS=/usr/share/cinnamon/js/ui/polkitAuthenticationAgent.js
SCREENSAVER_PY=/usr/share/cinnamon-screensaver/unlock.py

echo "==> Removing PIN length config"
sudo rm -f /etc/pin-unlock/length
sudo rmdir /etc/pin-unlock 2>/dev/null || true

echo "==> Unholding packages"
sudo apt-mark unhold "${PACKAGES[@]}"

# Detect whether anything actually needs reinstalling: a hold, or a leftover
# patch marker in either of the installed files we can grep. If everything
# already looks stock, skip the apt round-trip.
need_reinstall=false
if [[ -n "$(apt-mark showhold | grep -Fx -f <(printf '%s\n' "${PACKAGES[@]}") || true)" ]]; then
    need_reinstall=true
elif grep -q "_getPinLength" "$CINNAMON_JS" 2>/dev/null; then
    need_reinstall=true
elif grep -q "_get_pin_length" "$SCREENSAVER_PY" 2>/dev/null; then
    need_reinstall=true
fi

if $need_reinstall; then
    echo "==> Reinstalling stock versions"
    # --force-confnew makes dpkg replace our modified
    # /etc/pam.d/cinnamon-screensaver with the package version. Non-conffile
    # files (Python, Vala-compiled binary, JS) are overwritten unconditionally.
    sudo apt install --reinstall -y \
        -o Dpkg::Options::="--force-confnew" \
        "${PACKAGES[@]}"
else
    echo "==> Stock versions already installed — skipping apt reinstall"
fi

echo
echo "Done."
echo "  Lock screen + greeter: stock behavior on next lock / next login."
echo "  Polkit dialog:         restart Cinnamon to drop the patched JS"
echo "                         (Alt+F2, type 'r', Enter — or log out and back in)."
echo
read -rp "Press Enter to close..." _
