# mint-pin-unlock

Windows-Hello-style PIN auto-submit for Linux Mint Cinnamon. Patches
`cinnamon-screensaver` (lock screen), `slick-greeter` (LightDM login
screen), and Cinnamon's built-in polkit authentication dialog (the
`Authentication Required` prompt that `pkexec` / Update Manager / etc.
raise) so that, once a fixed PIN length is configured, the unlock attempt
fires automatically the moment the entry reaches that many characters — no
Enter key required.

## How it works

All three patches read `/etc/pin-unlock/length`, a one-line file containing
a positive integer (the length of your PIN). If the file is missing, empty,
or invalid, every program behaves exactly as upstream — auto-submit stays
off.

The PIN *is* your account password. No PAM module, no extra credential
store. If your current password already has a known fixed length, you can
use it as-is; otherwise change it to a value of the desired length with
`passwd`.

The length is read once and cached, so editing the file requires a
re-lock (screensaver), a logout (greeter), or a Cinnamon restart (polkit
dialog) to take effect.

## Requirements

- Linux Mint Cinnamon edition (tested target — should work on any distro
  shipping these two packages).
- Build toolchain: `meson`, `ninja`, `valac`, plus per-package `-dev`
  headers. The installer pulls them in via `apt build-dep`.

## Install

```bash
git clone https://github.com/emilichu/mint-pin-unlock.git
cd mint-pin-unlock
chmod +x install.sh
./install.sh
```

The script will:

1. Ask for your desired PIN length and write `/etc/pin-unlock/length`.
2. Offer to run `passwd` if you want a fresh password — skip this if your
   existing password is already the right length.
3. Install build dependencies, clone + patch + build `cinnamon-screensaver`
   and `slick-greeter`, patch Cinnamon's polkit JS in place, and
   `apt-mark hold` all three packages so updates don't overwrite the
   patched files.

The script is idempotent: re-run it to change the length, reapply the
patches, or recover from a partial install. Subsequent runs skip the
rebuild if the patches are already in place.

## Test

- Lock screen: `cinnamon-screensaver-command --lock`. Type your PIN — it
  should submit on the last digit without you pressing Enter.
- Login screen: reboot or `sudo systemctl restart lightdm` (this kicks
  you out of your session — save first).
- Polkit dialog: restart Cinnamon (Alt+F2, type `r`, Enter) to pick up the
  JS change, then `pkexec /bin/true`.

## Disable (soft)

Remove `/etc/pin-unlock/length` (or set its contents to `0`) and re-lock /
re-log-in / restart Cinnamon. All three patched components fall back to
standard Enter-to-submit behavior; the patched binaries stay installed.

## Uninstall

To fully revert — drop the length file, unhold the packages, and reinstall
the stock versions from apt:

```bash
./uninstall.sh
```

After it finishes, restart Cinnamon (Alt+F2 → `r` → Enter) to drop the
patched polkit JS from memory.

## Security caveats

- **Length oracle.** Anyone shoulder-surfing learns your PIN length by
  watching how many keystrokes you type. Fine for a personal laptop;
  not for shared or public machines.
- **Short numeric passwords are weak.** Pair this with full-disk
  encryption (LUKS). The Windows Hello model assumes the TPM + encrypted
  disk are doing the heavy lifting; the PIN is a convenience layer over
  that, not a replacement for strong credential storage.
- **`apt upgrade` after `unhold` will replace your patched binaries**
  with stock ones. Re-apply the patches.

---

## Manual install

If you'd rather run the steps yourself — or the script failed partway and
you want to resume — here's the full sequence.

### 1. Choose a PIN length and create the config

```bash
sudo mkdir -p /etc/pin-unlock
echo 6 | sudo tee /etc/pin-unlock/length     # e.g. 6-digit PIN
passwd                                       # optional: only if your password isn't already 6 chars
```

The file must be world-readable (the default for files in `/etc`). The
greeter runs as user `lightdm` and needs to read it.

### 2. Install build dependencies

```bash
sudo apt build-dep cinnamon-screensaver slick-greeter
sudo apt install git meson ninja-build valac
```

### 3. Clone this repo

```bash
git clone https://github.com/emilichu/mint-pin-unlock.git
cd mint-pin-unlock
```

### 4. Patch and build cinnamon-screensaver

```bash
git clone https://github.com/linuxmint/cinnamon-screensaver.git
cd cinnamon-screensaver
git apply ../cinnamon-screensaver-pin-autosubmit.patch
meson setup builddir --prefix=/usr --buildtype=release
ninja -C builddir
sudo ninja -C builddir install
cd ..
```

### 5. Patch and build slick-greeter

```bash
git clone https://github.com/linuxmint/slick-greeter.git
cd slick-greeter
git apply ../slick-greeter-pin-autosubmit.patch
meson setup builddir --prefix=/usr --buildtype=release
ninja -C builddir
sudo ninja -C builddir install
cd ..
```

### 6. Patch Cinnamon's polkit auth dialog

Cinnamon ships its own polkit agent as JavaScript, so no rebuild is needed
— the patch goes against the installed file directly.

```bash
sudo patch --batch --forward -p1 -d / \
    < cinnamon-polkit-pin-autosubmit.patch
```

Restart Cinnamon (Alt+F2, type `r`, Enter) to pick up the change.

### 7. Pin the packages so apt doesn't overwrite your build

```bash
sudo apt-mark hold cinnamon-screensaver slick-greeter cinnamon-common
```

To re-enable updates later: `sudo apt-mark unhold cinnamon-screensaver slick-greeter cinnamon-common`.
You'll then need to re-clone upstream and re-apply the patches against the new source.

## Updating after upstream changes

When you `unhold` and `apt upgrade` pulls new versions, your patches will
be wiped (apt installs binaries, not source). To re-apply, either re-run
`./install.sh` or repeat the manual steps above.

If a patch fails to apply because upstream changed the function
surroundings, `git apply` will tell you which hunks failed; the anchor
points are `on_password_entry_text_changed` (cinnamon-screensaver), the
`construct` block in `dash-entry.vala` (slick-greeter), and the
`text-changed` connect on `_passwordEntry` in `polkitAuthenticationAgent.js`
(cinnamon).

## License

GPL-3.0-or-later. These patches are derivative works of GPL-3.0 code
(`linuxmint/cinnamon-screensaver`, `linuxmint/slick-greeter`,
`linuxmint/cinnamon`) and inherit that license. See `LICENSE`.
