# Workbench

Various tools and config optimizations useful for everyday use and cloud development specifically. Currently supports Debian based distros (including wsl) and Termux.

## Installation

Run `./setup.sh`

## Update

running `./setup.sh` again will check currently installed versions and updates if necessary.

## Device Custom Setups

Creating `$HOME/.workbench` allows you to add Device specific setup steps. This file gets sourced in the main script, so you can use all functionality from the main script

Example:

```
#!/bin/bash

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
