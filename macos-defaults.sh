#!/bin/bash
# macOS preferences, captured from the current Mac. Safe to re-run.

# Appearance
defaults write NSGlobalDomain AppleInterfaceStyle -string Dark

# Dock
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock tilesize -float 60
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock wvous-br-corner -int 1   # bottom-right hot corner: none

# Finder
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder FXPreferredViewStyle -string icnv
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Keyboard / typing
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 30
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

# Trackpad: tap to click, speed
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool false
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 0.875

# Menu bar clock with seconds
defaults write com.apple.menuextra.clock ShowSeconds -bool true

killall Dock Finder SystemUIServer 2>/dev/null
echo "    defaults applied (some need a logout)"
