#!/bin/bash
# Restore this Mac from scratch:   curl -fsSL https://i.mansfera.com | bash
# (i.mansfera.com just redirects to this file on GitHub.)
#
#   Phase 1 - you're needed (~5 min): password, GitHub, YubiKeys, App Store.
#   Phase 2 - walk away (long):       every brew/cask/App Store app, macOS defaults.
#   Phase 3 - manual checklist:       stuff macOS or vendors won't let a script do.

# Piped from curl, stdin is the script itself, so nothing interactive works.
# Re-run from a file with the keyboard as stdin instead.
if [ ! -t 0 ] && [ -z "${RESTORE_REEXEC:-}" ]; then
    f="$(mktemp)"
    curl -fsSL https://raw.githubusercontent.com/Mansfera/Backup/main/install.sh -o "$f" || exit 1
    RESTORE_REEXEC=1 exec bash "$f" < /dev/tty
fi

BACKUP_PATH="$HOME/Backup"
DOTFILES_REPO="Mansfera/dotfiles"
DOTFILES_PATH="$HOME/dotfiles"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m❌ %s\033[0m\n' "$*"; exit 1; }

# =============================================================================
# Phase 1 - interactive
# =============================================================================

step "Password (the only time you'll type it)"
sudo -v || die "sudo failed"
# Keep sudo alive for the whole run so cask installers never ask again.
while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
# Touch ID for sudo from now on.
[ -f /etc/pam.d/sudo_local ] || sed "s/^#auth/auth/" /etc/pam.d/sudo_local.template | sudo tee /etc/pam.d/sudo_local >/dev/null
# Don't let the Mac sleep through the long install.
caffeinate -dimsu -w $$ &

# Sign in while Homebrew installs below; confirmed at the end of phase 1.
open -a "App Store"
echo "    App Store opened - sign in there while Homebrew installs (no need to wait)."

step "Homebrew"
if ! command -v brew >/dev/null && [ ! -x /opt/homebrew/bin/brew ] && [ ! -x /usr/local/bin/brew ]; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || die "Homebrew install failed"
fi
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1

brew install git gh stow openssh || die "bootstrap formulae failed"

if [ -d "$BACKUP_PATH/.git" ]; then
    git -C "$BACKUP_PATH" pull --ff-only || true
else
    git clone https://github.com/Mansfera/Backup.git "$BACKUP_PATH" || die "clone Backup failed"
fi

step "GitHub - press Enter, then approve in the browser (YubiKey passkey or password)"
# Every scope up front, so the YubiKey step below never needs a second login.
gh auth status >/dev/null 2>&1 ||
    gh auth login -h github.com -p https -w -s admin:public_key,write:ssh_signing_key ||
    die "GitHub login failed"

step "Dotfiles"
[ -d "$DOTFILES_PATH/.git" ] || gh repo clone "$DOTFILES_REPO" "$DOTFILES_PATH" || die "clone dotfiles failed"
# Real dirs first, so stow links single files instead of whole app folders
# (otherwise apps would dump their caches into the dotfiles repo).
mkdir -p "$HOME/.config" \
         "$HOME/Library/Application Support/Cursor/User" \
         "$HOME/Library/Application Support/Sublime Text/Packages/User"
( cd "$DOTFILES_PATH" && stow . ) || die "stow failed - move the conflicting files away and re-run"

# After stow, and told to keep .zshrc, otherwise it replaces the dotfiles symlink.
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    KEEP_ZSHRC=yes RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi
FZF_TAB="$HOME/.oh-my-zsh/custom/plugins/fzf-tab"
[ -d "$FZF_TAB" ] || git clone --depth=1 https://github.com/Aloxaf/fzf-tab "$FZF_TAB"
[ "$SHELL" = "/bin/zsh" ] || chsh -s /bin/zsh

# ---------------------------------------------------------------------------
# YubiKey SSH: one touch-only FIDO2 key per YubiKey, used for SSH and git
# commit signing (see ~/.ssh/config and ~/.ssh/git-ssh-sign.sh).
#
# Both keys are resident credentials ON the YubiKeys and survive a Mac wipe.
# ~/.ssh/yubikey_nano and yubikey_nfc are only stubs pointing at them; the .pub halves are
# tracked in dotfiles, so `ssh-keygen -K` re-downloads the SAME keys and each
# one is matched to its file by public key. GitHub and every server that
# already trusts them keep working - nothing to re-register.
# ---------------------------------------------------------------------------
setup_yubikey() {
    local SSH_DIR="${SSH_DIR:-$HOME/.ssh}"
    local KEYS="yubikey_nano yubikey_nfc"
    local name missing reply TMP f body matched existing title

    step "YubiKeys"
    while :; do
        missing=""
        for name in $KEYS; do
            [ -f "$SSH_DIR/$name" ] || missing="$missing $name"
        done
        [ -z "$missing" ] && break

        echo "    missing:$missing"
        printf "    Plug in a YubiKey, press Enter, type its FIDO2 PIN, touch it (s to skip) "
        read -r reply
        case "$reply" in [Ss]*) break ;; esac

        TMP="$(mktemp -d)"
        ( cd "$TMP" && ssh-keygen -K ) || echo "    ⚠️  download failed"
        for f in "$TMP"/id_*_rk*.pub; do
            [ -f "$f" ] || continue
            body="$(cut -d' ' -f2 "$f")"
            matched=""
            for name in $KEYS; do
                if [ -f "$SSH_DIR/$name.pub" ] && grep -qF "$body" "$SSH_DIR/$name.pub"; then
                    mv "${f%.pub}" "$SSH_DIR/$name"
                    chmod 600 "$SSH_DIR/$name"
                    echo "    restored $name"
                    matched=1
                fi
            done
            [ -n "$matched" ] || echo "    skipped unknown credential $(basename "$f" .pub)"
        done
        rm -rf "$TMP"
    done

    # GitHub registration: idempotent, normally a no-op since the keys survive.
    existing="$(gh ssh-key list 2>/dev/null)"
    for name in $KEYS; do
        [ -f "$SSH_DIR/$name.pub" ] || continue
        case "$name" in
            yubikey_nano) title="Yubikey 5C Nano" ;;
            *)            title="Yubikey 5C NFC" ;;
        esac
        body="$(cut -d' ' -f2 "$SSH_DIR/$name.pub")"
        if printf '%s' "$existing" | grep -qF "$body"; then
            echo "    $title already on GitHub"
        else
            gh ssh-key add "$SSH_DIR/$name.pub" --type authentication --title "$title"
            gh ssh-key add "$SSH_DIR/$name.pub" --type signing        --title "$title"
            echo "    $title registered on GitHub"
        fi
    done
}
setup_yubikey

step "Last question"
printf "    Signed in to the App Store? (needed for Xcode, Infuse, etc.) Press Enter when done "
read -r _

printf '\n\033[1;32m✅ That was the last prompt - you can walk away now.\033[0m\n'

# =============================================================================
# Phase 2 - unattended
# =============================================================================

step "Installing everything from Brewfile (this takes a while)"
if brew bundle install --file="$BACKUP_PATH/Brewfile"; then
    BUNDLE_OK=1
else
    BUNDLE_OK=""
fi

[ -d /Applications/Xcode.app ] && sudo xcodebuild -license accept 2>/dev/null

step "macOS defaults"
bash "$BACKUP_PATH/macos-defaults.sh"
# Default apps per file type (Ghostty as terminal). Needs the apps installed above.
command -v duti >/dev/null && duti "$BACKUP_PATH/duti.conf"

# =============================================================================
# Phase 3 - manual
# =============================================================================

step "Opening the manual bits"
open https://github.com/Gaulomatic/AirPodsSanity/releases
open https://github.com/fifty-six/Scarab/releases
open https://github.com/ExpressLRS/ExpressLRS-Configurator/releases
open https://appstorrent.ru/2411-betterdisplay-pro.html
open https://appstorrent.ru/839-infuse.html
open https://appstorrent.ru/2431-aldente-delat.html
open https://appstorrent.ru/133-macbartender.html
for f in "$BACKUP_PATH"/*.rayconfig; do [ -f "$f" ] && open -a Raycast "$f"; done

cat <<'EOF'

────────────────────────────────────────────────────────────────────
 Manual checklist
────────────────────────────────────────────────────────────────────
 [ ] Install the apps from the browser tabs that just opened
 [ ] Raycast: finish the import dialog (export password)
 [ ] System Settings → Privacy & Security: allow Karabiner driver,
     Accessibility for Raycast / Karabiner / BetterDisplay /
     Bartender / AlDente, VPN configs for Tailscale / TunnelBear
 [ ] Sign in to apps (browsers, Google Drive, Telegram, Discord…)
 [ ] FinderMenu (samiyuru) - not on Homebrew, install by hand
 [ ] Tokens/keys go in ~/.secrets.zsh (untracked, loaded by .zshrc)
 [ ] Log out and back in so keyboard repeat and other defaults apply
────────────────────────────────────────────────────────────────────
EOF

if [ -n "$BUNDLE_OK" ]; then
    echo "🎉 Setup complete!"
else
    echo "⚠️  Some Brewfile entries failed (scroll up). Re-run to retry: brew bundle install --file=~/Backup/Brewfile"
fi
