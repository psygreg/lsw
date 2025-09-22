#!/bin/bash

if zenity --question --text "Do you want to revert all changes? WARNING: This will ERASE all Docker Compose data!" --width 360 --height 300; then
    docker compose down --rmi=all --volumes
    if command -v rpm-ostree &> /dev/null; then
        sudo rpm-ostree remove lsw-atom-shortcuts
    else
        for item in lsw-on.sh lsw-off.sh lsw-refresh.sh lsw-on.png lsw-off.png lsw-refresh.png; do
            if [ -f "/usr/bin/$item" ]; then
                sudo rm -f "/usr/bin/$item"
            fi
        done
        for item2 in lsw-on.desktop lsw-off.desktop lsw-refresh.desktop; do
            if [ -f "/usr/share/applications/$item2" ]; then
                sudo rm -f "/usr/share/applications/$item2"
            fi
        done
    fi
    if [ -d "$HOME/.config/winapps" ]; then
        rm -rf $HOME/.config/winapps
    fi
    exit 0
fi