#!/bin/bash

# check dependencies
depcheck () {

    # Enforce minimum RAM check
    local total_kb=$(grep MemTotal /proc/meminfo | awk '{ print $2 }')
    local available_kb=$(grep MemAvailable /proc/meminfo | awk '{ print $2 }')
    local total_gb=$(( total_kb / 1024 / 1024 ))
    local available_gb=$(( available_kb / 1024 / 1024 ))
    _cram=$(( total_gb / 3 ))
    if (( _cram < 4 )); then
        fatal "System RAM too low. At least 12GB total is required to continue."
        exit 1
    fi
    # Enforce availability with 1GB buffer (to avoid rounding issues)
    if (( available_gb < (_cram + 1) )); then
        fatal "Not enough free RAM. Close some applications and try again."
        exit 1
    fi
    # CPU thread check
    local _total_threads=$(nproc)
    _ccpu=$(( _total_threads / 2 ))
    if (( _ccpu < 2 )); then
        fatal "Not enough CPU threads to install Windows hypervisor, minimum 4."
        exit 6
    fi
    # install dependencies
    if [[ "$ID_LIKE" == *debian* ]] || [[ "$ID_LIKE" == *ubuntu* ]] || [ "$ID" == "ubuntu" ]; then
        declare -a _packages=()
        _packages+=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin dialog git iproute2 libnotify-bin netcat-openbsd)
        if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
            _packages+=(freerdp3-sdl)
        else
            _packages+=(freerdp3-x11)
        fi
        insta ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
            $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update
    elif [ "$ID" == "debian" ]; then
        declare -a _packages=()
        _packages+=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin dialog git iproute2 libnotify-bin netcat-openbsd)
        if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
            _packages+=(freerdp3-sdl)
        else
            _packages+=(freerdp3-x11)
        fi
        insta ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update
    elif [[ "$ID_LIKE" =~ (rhel|fedora) ]] || [[ "$ID" =~ (fedora) ]]; then
        sudo dnf -y install dnf-plugins-core
        sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        _packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin curl dialog freerdp git iproute libnotify nmap-ncat)
    elif [[ "$ID" =~ ^(arch|cachyos)$ ]] || [[ "$ID_LIKE" == *arch* ]] || [[ "$ID_LIKE" == *archlinux* ]]; then
        _packages=(docker docker-compose curl dialog freerdp git iproute2 libnotify gnu-netcat)
    elif [[ "$ID_LIKE" == *suse* ]]; then
        _packages=(docker docker-compose curl dialog freerdp git iproute2 libnotify-tools netcat-openbsd)
    fi
    _install_
    sudo usermod -aG docker $USER
    sudo systemctl enable --now docker
    sleep 2
}

# use port from LT Atom for SELinux compatibility
lsw_selinux () {

    if [[ "$ID" =~ "suse" ]] || [[ "$ID_LIKE" =~ "suse" ]]; then
        _packages=(dialog netcat freerdp freerdp-sdl iproute libnotify)
    else
        _packages=(dialog netcat freerdp iproute libnotify)
    fi
	_install_
    mkdir -p $HOME/.config/winapps
	cd $HOME/.config/winapps
	wget -nc https://raw.githubusercontent.com/psygreg/linuxtoys-atom/refs/heads/main/lsw-atom/winapps/compose.yaml
	wget -nc https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/winapps.conf
	# make necessary adjustments to compose file
    # Cap at 16GB
    if (( _cram > 16 )); then
        _winram=16
    else
        _winram=$_cram
    fi
    # get cpu threads
    _wincpu="$_ccpu"
    # get C size
    _csize=$(zenity --entry --title="LSW" --text="Enter Windows disk (C:) size in GB. Leave empty to use 50GB."  --entry-text "50" --height=300 --width=300)
    local available_gb=$(df -BG "/" | awk 'NR==2 { gsub("G","",$4); print $4 }')
    if [ -z "$_csize" ]; then
        _winsize="50"
    else
        # stop if input size is not a number
		if [[ -n "$_csize" && ! "$_csize" =~ ^[0-9]+$ ]]; then
			nonfatal "Invalid input for disk size. Please enter a number."
            return 10
        fi
        _winsize="$_csize"
    fi
    if (( _winsize < 40 )); then
		nonfatal "Minimum space to install Windows (C:) is 40GB."
        return 11
    fi
    if (( available_gb < _winsize )); then\
		nonfatal "Not enough disk space: ${_winsize} GB required, ${available_gb} GB available."
        exit 3
    fi
    sed -i "s|^\(\s*RAM_SIZE:\s*\).*|\1\"${_winram}G\"|" compose.yaml
    sed -i "s|^\(\s*CPU_CORES:\s*\).*|\1\"${_wincpu}\"|" compose.yaml
    sed -i "s|^\(\s*DISK_SIZE:\s*\).*|\1\"${_winsize}\"|" compose.yaml
	if command -v konsole &> /dev/null; then
        setsid konsole --noclose -e  "sudo docker compose --file ./compose.yaml up" >/dev/null 2>&1 < /dev/null &
	elif command -v ptyxis &> /dev/null; then
		setsid ptyxis bash -c "sudo docker compose --file ./compose.yaml up; exec bash" >/dev/null 2>&1 < /dev/null &
    elif command -v gnome-terminal &> /dev/null; then
        setsid gnome-terminal -- bash -c "sudo docker compose --file ./compose.yaml up; exec bash" >/dev/null 2>&1 < /dev/null &
    else
		nonfatal "No compatible terminal emulator found to launch Docker Compose."
        exit 4
    fi

}

# install windows on docker
windocker () {

    # get compose file
    if command -v getenforce &> /dev/null; then
        local selinux_status=$(getenforce)
        if [[ "$selinux_status" == "Enforcing" || "$selinux_status" == "Permissive" ]]; then
            lsw_selinux
            return 0
        fi
    fi
    mkdir -p $HOME/.config/winapps
	cd $HOME/.config/winapps
	wget -nc https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/compose.yaml
    # make necessary adjustments to compose file
    # Cap at 16GB
    if (( _cram > 16 )); then
        _winram=16
    else
        _winram=$_cram
    fi
    # get cpu threads
    _wincpu="$_ccpu"
    # get directory
    _cdir=""
    _cdir=$(zenity --entry --title="LSW" --text="Enter location for Windows installation. Leave empty for ${HOME}/Windows." --entry-text "${HOME}/Windows" --height=300 --width=360)
    if [ -z "$_cdir" ]; then
        _windir="${HOME}/Windows"
        mkdir -p "$_windir"
    else
        _windir="$_cdir"
        # Create directory if it doesn't exist
        mkdir -p "$_windir"
        # Verify the directory was created successfully
        if [ ! -d "$_windir" ]; then
            fatal "Failed to create directory: $_windir"
            exit 2
        fi
    fi
    _csize=$(zenity --entry --title="LSW" --text="Enter Windows disk (C:) size in GB. Leave empty to use 50GB." --entry-text "50" --height=300 --width=360)
    local available_gb=$(df -BG "$_windir" | awk 'NR==2 { gsub("G","",$4); print $4 }')
    if [ -z "$_csize" ]; then
        _winsize="50"
    else
        # stop if input size is not a number
        if [[ -n "$_csize" && ! "$_csize" =~ ^[0-9]+$ ]]; then
            fatal "Invalid number for disk size."
            return 10
        fi
        _winsize="$_csize"
    fi
    if (( _winsize < 40 )); then
        fatal "Not enough space to install Windows, minimum 40GB."
        exit 4
    fi
    if (( available_gb < _winsize )); then
        fatal "Not enough disk space in $_cdir: ${_winsize} GB required, ${available_gb} GB available."
        exit 3
    fi
    sed -i "s|^\(\s*RAM_SIZE:\s*\).*|\1\"${_winram}G\"|" compose.yaml
    sed -i "s|^\(\s*CPU_CORES:\s*\).*|\1\"${_wincpu}\"|" compose.yaml
    sed -i "s|^\(\s*device:\s*\).*|\1\"${_windir}\"|" compose.yaml
    sed -i "s|^\(\s*DISK_SIZE:\s*\).*|\1\"${_winsize}\"|" compose.yaml
    if command -v konsole &> /dev/null; then
        setsid konsole --noclose -e  "sudo docker compose --file ./compose.yaml up" >/dev/null 2>&1 < /dev/null &
    elif command -v gnome-terminal &> /dev/null; then
        setsid gnome-terminal -- bash -c "sudo docker compose --file ./compose.yaml up; exec bash" >/dev/null 2>&1 < /dev/null &
    else
        fatal "No compatible terminal emulator found to launch Docker Compose."
        exit 8
    fi

}

# configure winapps
winapp_config () {

    if [[ "$ID_LIKE" == *debian* ]] || [[ "$ID_LIKE" == *ubuntu* ]] || [ "$ID" == "ubuntu" ] || [ "$ID" == "debian" ]; then
        local _packages=(freerdp3-x11)
        _install_
    fi
    mkdir -p $HOME/.config/winapps
    cd $HOME
    wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/winapps.conf
    cp -f winapps.conf $HOME/.config/winapps/
    sleep 1
    rm winapps.conf
    sleep 2
    docker compose --file ~/.config/winapps/compose.yaml stop
    sleep 2
    docker compose --file ~/.config/winapps/compose.yaml start
    sleep 10
    # symlink xfreerdp on fedora due to the command having a different name
    if [ "$ID" == "fedora" ] || [[ "$ID_LIKE" == *fedora* ]]; then
        sudo ln -s /usr/bin/xfreerdp /usr/bin/xfreerdp3
    fi
    zenity --info --text "Now a test for RDP will be performed. It should show you the Windows 10 subsystem in a window, and it is safe to close once it logs in." --width 360 --height 300
    xfreerdp3 /u:"lsw" /p:"lsw" /v:127.0.0.1 /cert:tofu
    sleep 10
    curl -fsSL https://raw.githubusercontent.com/winapps-org/winapps/main/setup.sh | bash

}

# configure LSW menu entries
lsw_menu () {

    local selinux_status=$(getenforce)
    if [[ "$selinux_status" == "Enforcing" || "$selinux_status" == "Permissive" ]]; then
        cd $HOME
        mkdir -p lsw
        cd lsw
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/menu/lsw-off.desktop
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/menu/lsw-on.desktop
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/menu/lsw-refresh.desktop
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/lsw-selinux/lsw-off.sh
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/lsw-selinux/lsw-on.sh
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/lsw-selinux/lsw-refresh.sh
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/lsw-off.png
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/lsw-on.png
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/lsw-refresh.png
    else
        cd $HOME
        mkdir -p $HOME/.config/winapps
        cp -f compose.yaml $HOME/.config/winapps/
        rm compose.yaml
        sleep 2
        mkdir -p lsw
        cd lsw
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/menu/lsw-off.desktop
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/menu/lsw-on.desktop
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/menu/lsw-refresh.desktop
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/lsw-off.sh
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/lsw-on.sh
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/lsw-refresh.sh
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/lsw-off.png
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/lsw-on.png
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/lsw-refresh.png
    fi
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        if [[ "$ID" =~ "suse" ]] || [[ "$ID_LIKE" =~ "suse" ]]; then
            wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/lsw-suse/lsw-desktop.desktop
        else
            wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/menu/lsw-desktop.desktop
        fi
    else
        if [ "$ID" == "fedora" ] || [[ "$ID_LIKE" == *fedora* ]]; then
            sudo ln -s /usr/bin/xfreerdp /usr/bin/xfreerdp3
        fi
        wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/menu/lsw-desktop-x11.desktop
    fi
    wget https://raw.githubusercontent.com/psygreg/lsw/refs/heads/main/src/lsw-desktop.png
    sleep 1
    sudo_rq
    sudo mv *.desktop /usr/share/applications/
    sudo mv *.sh /usr/bin/
    sudo mv *.png /usr/bin/
    cd /usr/bin
    sleep 1
    chmod +x lsw-refresh.sh
    chmod +x lsw-on.sh
    chmod +x lsw-off.sh
    cd $HOME
    sleep 1
    rm -rf lsw
    zeninf "All done. Enjoy your Windows apps."
}

rmlsw () {

    if zenity --question --text "Do you want to revert all changes? WARNING: This will ERASE all Docker Compose data!" --width 360 --height 300; then
        bash <(curl https://raw.githubusercontent.com/winapps-org/winapps/main/setup.sh)
        sudo docker compose --file ~/.config/winapps/compose.yaml stop
        sleep 2
        sudo docker compose down --rmi=all --volumes
        sudo rm -f /usr/bin/lsw-on*
        sudo rm -f /usr/bin/lsw-off*
        sudo rm -f /usr/bin/lsw-refresh*
        sudo rm -f /usr/share/applications/lsw-on.desktop
        sudo rm -f /usr/share/applications/lsw-off.desktop
        sudo rm -f /usr/share/applications/lsw-refresh.desktop
        rm -rf ~/.config/winapps
        exit 0
    else
        return
    fi

}

lswcfg () {

    # step 2 - winapps config
    if zenity --question --text "Is the Windows installation finished?" --width 360 --height 300; then
        lsw_menu
        zeninf "Reboot to apply changes."
        exit 0
    else
        if zenity --question --text "Do you want to revert all changes? WARNING: This will ERASE all Docker Compose data!" --width 360 --height 300; then
            docker compose down --rmi=all --volumes
            exit 1
        fi
    fi

}

# runtime
. /etc/os-release
source <(curl -s https://raw.githubusercontent.com/psygreg/linuxtoys/refs/heads/master/p3/libs/linuxtoys.lib)
# step 1 - docker setup
if [ -e /dev/kvm ]; then
    # menu
    while true; do
        CHOICE=$(zenity --list --title="LSW" --text="Linux Subsystem for Windows:" \
            --column="Option" \
            "Install Standalone" \
            "Install WinApps" \
            "Uninstall" \
            "Cancel" \
            --width 300 --height 330)

        if [ $? -ne 0 ]; then
            break
        fi

        case $CHOICE in
        "Install Standalone") sudo_rq && depcheck && windocker && lswcfg ;;
        "Install WinApps") sudo_rq && winapp_config ;;
        "Uninstall") sudo_rq && rmlsw && break ;;
        "Cancel") break ;;
        *) echo "Invalid Option" ;;
        esac
    done
else
    zenwrn "KVM unavailable. Enable Intel VT-x or AMD SVM on BIOS and try again."
    exit 5
fi
