#!/bin/bash

# Replace your username for DOTFILES_REPO
DOTFILES_REPO="Mansfera/dotfiles"
DOTFILES_PATH="$HOME/dotfiles"
echo "✅ Installing Homebrew..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
export PATH="/opt/homebrew/bin:$PATH"
echo "✅ Homebrew added to PATH for this session."

echo "✅ Installing gh, git, and stow..."
brew install gh git stow

echo "⚠️ Please log in to GitHub when prompted..."

echo "✅ Cloning dotfiles..."
gh repo clone $DOTFILES_REPO $DOTFILES_PATH
cd $DOTFILES_PATH

echo "✅ Running stow..."
stow .

echo "✅ Installing Oh My Zsh..."
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

if [ "$SHELL" != "/bin/zsh" ] && [ "$SHELL" != "/usr/bin/zsh" ]; then
    read -r -p "Do you want to set Zsh as your default shell? (y/N) " response
    case "$response" in
        [yY][eE][sS]|[yY])
            if command -v zsh >/dev/null 2>&1; then
                chsh -s "$(command -v zsh)"
                echo "Zsh set as the default shell. You may need to restart your terminal for changes to take effect."
            else
                echo "Error: zsh command not found, cannot set as default shell."
            fi
            ;;
        *)
            echo "Skipping setting Zsh as the default shell."
            ;;
    esac
fi

git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

echo "✅ Installing applications via Brewfile..."
brew bundle install

echo "🎉 Setup complete! Please **restart your terminal**."