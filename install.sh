#!/bin/bash

DOTFILES_REPO="Mansfera/dotfiles"
DOTFILES_PATH="$HOME/dotfiles"

[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -f /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"

brew install gh stow 1password

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

echo "🎉 Setup complete! Restart your terminal."