#!/bin/bash

DOTFILES_REPO="Mansfera/dotfiles"
DOTFILES_PATH="$HOME/dotfiles"

[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -f /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"

brew install gh stow 1password ykman yubico-piv-tool openssh

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
# YubiKey: PIV-backed SSH auth + git commit signing via a launchd ssh-agent,
# with the FIDO2 (ed25519-sk) key as a touch-based fallback.
#
# Both keys live ON the YubiKey and survive a Mac wipe:
#   - PIV slot 9A: only the public half needs re-exporting.
#   - FIDO2 key: created with -O resident, so `ssh-keygen -K` re-downloads the
#     SAME key. Because it is not regenerated, GitHub and every server that
#     already trusts it keep working - nothing to re-register anywhere.
#
# NOTE: this script may be running with its stdin attached to a pipe (curl|bash),
# so every interactive prompt reads from /dev/tty explicitly.
# ---------------------------------------------------------------------------
setup_yubikey() {
    local BREW_PREFIX PKCS11 AGENT_DIR PLIST UID_N reply TMP priv email body existing k
    BREW_PREFIX="$(brew --prefix)"
    PKCS11="$BREW_PREFIX/lib/libykcs11.dylib"
    AGENT_DIR="$HOME/.ssh/agent"
    PLIST="$HOME/Library/LaunchAgents/com.user.piv-ssh-agent.plist"
    UID_N="$(id -u)"

    echo "==> Setting up YubiKey PIV ssh-agent..."
    mkdir -p "$AGENT_DIR" "$HOME/Library/LaunchAgents"
    chmod 700 "$HOME/.ssh" "$AGENT_DIR" 2>/dev/null || true

    # Normally stowed in from the dotfiles repo; write it if that did not happen.
    if [ ! -x "$AGENT_DIR/start-piv-agent.sh" ]; then
        cat > "$AGENT_DIR/start-piv-agent.sh" <<AGENTEOF
#!/bin/sh
SOCK="\$HOME/.ssh/agent/piv.sock"
rm -f "\$SOCK"
# Publish to the launchd session so GUI apps (git clients, editors) see the agent.
launchctl setenv SSH_AUTH_SOCK "\$SOCK"
# -P must cover the Cellar realpath: ssh-agent resolves symlinks before matching.
exec $BREW_PREFIX/bin/ssh-agent -D -a "\$SOCK" -P '$BREW_PREFIX/lib/*,$BREW_PREFIX/Cellar/*'
AGENTEOF
        chmod 700 "$AGENT_DIR/start-piv-agent.sh"
    fi

    cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.user.piv-ssh-agent</string>
  <key>ProgramArguments</key>
  <array><string>$AGENT_DIR/start-piv-agent.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
PLISTEOF

    launchctl bootout "gui/$UID_N/com.user.piv-ssh-agent" 2>/dev/null || true
    launchctl bootstrap "gui/$UID_N" "$PLIST" 2>/dev/null || true
    echo "    agent service loaded"

    # macOS's own PIV driver competes with libykcs11 for the smartcard. When it
    # wins, ykman reports "Failed to connect to YubiKey" and pivload cannot load
    # the key until you replug.
    printf "Disable macOS's built-in PIV smartcard driver (recommended unless you unlock this Mac with the YubiKey)? [y/N] "
    read -r reply < /dev/tty
    case "$reply" in
        [Yy]*) sudo defaults write /Library/Preferences/com.apple.security.smartcard \
                   DisabledTokens -array com.apple.CryptoTokenKit.pivtoken \
                   && echo "    disabled (reboot for full effect)" ;;
    esac

    if [ -z "$(ykman list 2>/dev/null)" ]; then
        echo "⚠️  No YubiKey detected. Plug it in, then run:  setup_yubikey"
        return 0
    fi

    # --- PIV public key ------------------------------------------------------
    if ykman piv keys info 9a >/dev/null 2>&1; then
        ssh-keygen -D "$PKCS11" 2>/dev/null | head -1 | cut -d' ' -f1,2 \
            | sed 's/$/ piv9a-yubikey/' > "$HOME/.ssh/id_piv9a.pub"
        chmod 600 "$HOME/.ssh/id_piv9a.pub"
        echo "    PIV 9A public key exported"
    else
        echo "    ⚠️  PIV slot 9A is empty. Create a key then re-run setup_yubikey:"
        echo "        ykman piv keys generate 9a --pin-policy once --touch-policy cached ~/piv.pub"
        echo "        ykman piv certificates generate --subject 'CN=SSH' 9a ~/piv.pub"
    fi

    # --- FIDO2 fallback key (resident -> re-downloadable, same key) ----------
    if [ ! -f "$HOME/.ssh/id_ed25519_sk_yubikey" ]; then
        echo "==> Restoring FIDO2 fallback key from the YubiKey (needs FIDO PIN + touch)..."
        TMP="$(mktemp -d)"
        if ( cd "$TMP" && ssh-keygen -K < /dev/tty ); then
            priv="$(find "$TMP" -maxdepth 1 -name 'id_ed25519_sk_rk*' ! -name '*.pub' | head -1)"
            if [ -n "$priv" ] && [ -f "$priv.pub" ]; then
                mv "$priv"     "$HOME/.ssh/id_ed25519_sk_yubikey"
                mv "$priv.pub" "$HOME/.ssh/id_ed25519_sk_yubikey.pub"
                chmod 600 "$HOME/.ssh/id_ed25519_sk_yubikey"
                chmod 644 "$HOME/.ssh/id_ed25519_sk_yubikey.pub"
                echo "    restored: $(ssh-keygen -lf "$HOME/.ssh/id_ed25519_sk_yubikey.pub")"
            else
                echo "    ⚠️  no resident ed25519-sk credential found on this YubiKey"
            fi
        else
            echo "    ⚠️  could not download resident keys - fallback unavailable"
        fi
        rm -rf "$TMP"
    fi

    # --- allowed_signers (local signature verification) ----------------------
    email="$(git config --global user.email)"
    touch "$HOME/.ssh/allowed_signers"
    for k in id_piv9a id_ed25519_sk_yubikey; do
        [ -f "$HOME/.ssh/$k.pub" ] || continue
        body="$(cut -d' ' -f1,2 "$HOME/.ssh/$k.pub")"
        grep -qF "$body" "$HOME/.ssh/allowed_signers" \
            || echo "$email $body" >> "$HOME/.ssh/allowed_signers"
    done

    # --- GitHub registration (idempotent; skips keys already on the account) --
    printf "Register these keys on GitHub now? [Y/n] "
    read -r reply < /dev/tty
    case "$reply" in
        [Nn]*) echo "    skipped" ;;
        *)
            gh auth refresh -s admin:public_key,write:ssh_signing_key < /dev/tty
            existing="$(gh ssh-key list 2>/dev/null)"
            for k in id_piv9a id_ed25519_sk_yubikey; do
                [ -f "$HOME/.ssh/$k.pub" ] || continue
                body="$(cut -d' ' -f2 "$HOME/.ssh/$k.pub")"
                if printf '%s' "$existing" | grep -qF "$body"; then
                    echo "    $k already on GitHub"
                else
                    gh ssh-key add "$HOME/.ssh/$k.pub" --type authentication --title "$k"
                    gh ssh-key add "$HOME/.ssh/$k.pub" --type signing        --title "$k"
                    echo "    $k registered"
                fi
            done ;;
    esac

    echo "==> YubiKey ready. Unlock the agent with:  pivload"
}

setup_yubikey

echo "🎉 Setup complete! Restart your terminal."