#!/bin/bash

DOTFILES_REPO="Mansfera/dotfiles"
DOTFILES_PATH="$HOME/dotfiles"

[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -f /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"

brew install gh stow 1password ykman openssh

open -a "1Password"
echo "Login to 1Password, then press Enter to continue..."
read

echo "⚠️ Log in to GitHub..."
gh auth login

gh repo clone $DOTFILES_REPO $DOTFILES_PATH
cd $DOTFILES_PATH
stow .

sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

if [ "$SHELL" != "$(command -v zsh)" ]; then
    chsh -s "$(command -v zsh)"
fi

git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

open https://github.com/Gaulomatic/AirPodsSanity/releases
open https://github.com/fifty-six/Scarab/releases
open https://appstorrent.ru/2411-betterdisplay-pro.html
open https://appstorrent.ru/839-infuse.html
open https://appstorrent.ru/2431-aldente-delat.html
open https://appstorrent.ru/133-macbartender.html

cd ~/Backup
brew bundle install

# ---------------------------------------------------------------------------
# YubiKey SSH: one touch-only FIDO2 key per YubiKey, used for SSH and git
# commit signing (see ~/.ssh/config and ~/.ssh/git-ssh-sign.sh).
#
# Both keys are resident credentials ON the YubiKeys and survive a Mac wipe.
# ~/.ssh/yubikey_nano and yubikey_nfc are only stubs pointing at them; the .pub halves are
# tracked in dotfiles, so `ssh-keygen -K` re-downloads the SAME keys and each
# one is matched to its file by public key. GitHub and every server that
# already trusts them keep working - nothing to re-register.
#
# NOTE: this script may be running with its stdin attached to a pipe (curl|bash),
# so every interactive prompt reads from /dev/tty explicitly.
# ---------------------------------------------------------------------------
setup_yubikey() {
    local SSH_DIR="${SSH_DIR:-$HOME/.ssh}"
    local KEYS="yubikey_nano yubikey_nfc"
    local name missing reply TMP f body matched existing title

    echo "==> Restoring YubiKey SSH keys..."
    while :; do
        missing=""
        for name in $KEYS; do
            [ -f "$SSH_DIR/$name" ] || missing="$missing $name"
        done
        [ -z "$missing" ] && break

        echo "    missing:$missing"
        printf "    Press Enter, type the YubiKey's FIDO2 PIN, then touch the YubiKey to restore (s to skip) "
        read -r reply < /dev/tty
        case "$reply" in [Ss]*) break ;; esac

        TMP="$(mktemp -d)"
        ( cd "$TMP" && ssh-keygen -K < /dev/tty ) || echo "    ⚠️  download failed"
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

    # --- GitHub registration (idempotent; skips keys already on the account) --
    printf "Register missing keys on GitHub? [y/N] "
    read -r reply < /dev/tty
    case "$reply" in
        [Yy]*)
            gh auth refresh -s admin:public_key,write:ssh_signing_key < /dev/tty
            existing="$(gh ssh-key list 2>/dev/null)"
            for name in $KEYS; do
                [ -f "$SSH_DIR/$name.pub" ] || continue
                case "$name" in
                    yubikey_nano)       title="Yubikey 5C Nano" ;;
                    *)                  title="Yubikey 5C NFC" ;;
                esac
                body="$(cut -d' ' -f2 "$SSH_DIR/$name.pub")"
                if printf '%s' "$existing" | grep -qF "$body"; then
                    echo "    $title already on GitHub"
                else
                    gh ssh-key add "$SSH_DIR/$name.pub" --type authentication --title "$title"
                    gh ssh-key add "$SSH_DIR/$name.pub" --type signing        --title "$title"
                    echo "    $title registered"
                fi
            done ;;
    esac

    echo "==> YubiKey ready."
}

setup_yubikey

echo "🎉 Setup complete! Restart your terminal."
