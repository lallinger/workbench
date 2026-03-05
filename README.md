# Workbench

Various tools and config optimizations useful for everyday use and cloud development specifically. Currently supports Debian based distros (including wsl) and Termux.

## Installation

Run `./setup.sh`

## Update

running `./setup.sh` again will check currently installed versions and updates if necessary.

## Customization

Creating `$HOME/.workbench` allows you to add Device specific setup steps. This file gets sourced in the main script, so you can use all functionality from the main script

Example:

```
#!/bin/bash

# Use this if you have your own neovim setup, if not https://github.com/lallinger/neovim will be used,
# which is derived from LazyVim with a ton of custom keybindings
# I highly recommend tracking your neovim customizations in your own git repo, as the setup.sh script will reset $HOME/.config/nvim everytime it is run!
export NEOVIM_SOURCE_GIT="https://github.com/your/neovim"

# Add this if you your neovim config should never be changed by the script. If you aren't using Termux you are not missing out, as there just get some fixes applied for the Android environment
#export NEOVIM_NO_TOUCHY=true

function custom_install() {
  $USE_SUDO apt install -y sway foot
  echo 'default_border pixel 0
for_window [app_id="foot"] floating disable
exec bash -c "foot tmux || pkill sway && pkill sway"
output * scale 1

input * {
    xkb_layout "de"
}' >$HOME/.config/sway/config

  add_to_profile ssh 'alias server="ssh me@example.com"'
}
```

## Termux

```
pkg install -y git
git clone https://github.com/lallinger/workbench
pushd workbench
./setup.sh
```
