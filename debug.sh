#!/bin/bash

[ -z ${dotfilesrepo+x} ] && dotfilesrepo="https://github.com/thehnm/dotfiles.git"
[ -z ${lang+x} ] && lang="LANG=en_US.UTF-8"
[ -z ${lcall+x} ] && lcall="LC_ALL=en_US.UTF-8"
[ -z ${editor+x} ] && editor="vim"
[ -z ${timezone+x} ] && timezone="Europe/Berlin"

###############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
PURPLE='\033[0;35m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

err() {
    printf "${RED}$1${NC}\n"
}

succ() {
    printf "${GREEN}$1${NC}\n"
}

info1() {
    printf "${CYAN}$1${NC}\n"
}

info2() {
    printf "> $1\n"
}

info3() {
    printf "$1\n"
}

warn() {
    printf "${ORANGE}WARNING! $1${NC}\n"
    yesnodialog "${ORANGE}Do you really want to continue?${NC}" "" "exit 1"
}

yesnodialog() {
    while true; do
        read -p "$(info3 "$1 (y|n)") " yn
        case $yn in
            y ) eval $2; break;;
            n ) eval $3; break;;
            * ) err "Please answer yes (y) or no (n).";;
        esac
    done
}

infodialog() {
    printf "$1\n"
    yesnodialog "Do you want to continue?" "" "exit 1"
}

queue() {
for command in "$@"; do
    printf "\n"
    eval "$command"
done
}

initialcheck() {
    info2 "Initial check"
    [ $debug = 0 ] && { pacman -S --noconfirm --needed git &>/dev/null || { err "You are not running this script as root."; exit 1; } }
}

preinstallmsg() {
    infodialog "This script will install a ready-to-use Arch Linux system with my personal configuration."
}

settimezone() {
    while true; do
        read -p "Please enter your continent: " continent
        read -p "Please enter an appropriate city from your timezone: " city
        info2 "Setting timezone"
        if [ $debug = 0 ]; then
            ln -sf /usr/share/zoneinfo/"$continent"/"$city" /etc/localtime &>/dev/null
            [ ! -e /etc/localtime ] && err "Please enter correct values!" && continue
            hwclock --systohc
        fi
        break
    done
}

genlocale() {
    yesnodialog "The following locale will be set: en_US\nDo you want to keep this?\nOtherwise, edit /etc/locale.gen directly." "" "read -p 'Enter locale to use: ' locale"
    info2 "Generating locale"
    [ "$yn" = "y" ] && locale="en_US"
    if [ $debug = 0 ]; then
        sed -i "s/\#en_US/en_US/" /etc/locale.gen
        locale-gen
        info2 "Setting locale"
        echo "LANG=$locale.UTF-8" > /etc/locale.conf
        echo "LC_ALL=$locale.UTF-8" >> /etc/locale.conf
    fi
}

sethostname() {
    read -p "Please enter your hostname: " hostname
    info2 "Setting hostname"
    if [ $debug = 0 ]; then
        echo "$hostname" > /etc/hostname
        echo "127.0.0.1 localhost" > /etc/hosts
        echo "::1 localhost" >> /etc/hosts
        echo "127.0.1.1 $hostname.localdomain $hostname" >> /etc/hosts
    fi
}

installfullsystem() {
    yesnodialog "This script will set these settings:\n- Timezone = Europe/Berlin\n- Locale = en_US\nDo you wish to configure these?" "queue settimezone genlocale"
}

islaptop() {
    yesnodialog "Do you install this on a laptop?" "laptop=1" "laptop=0"
}

getuserandpass() {
    read -p "Please enter your username: " name
    namere="^[a-z_][a-z0-9_-]*$"
    while ! [[ "${name}" =~ ${namere} ]]; do
        err "Username not valid. Please reenter your username"
        read -p "Please enter your username: " name
    done

    read -s -p "Enter password for $name: " pass1
    printf "\n"
    read -s -p "Reenter password for $name: " pass2
    printf "\n"

    while ! [[ ${pass1} == ${pass2} ]]; do
        unset pass1 pass2
        err "Passwords do not match. Please enter your password again"
        read -s -p "Enter password for $name: " pass1
        printf "\n"
        read -s -p "Reenter password for $name: " pass2
        printf "\n"
    done
}

usercheck() {
    ! (id -u $name &>/dev/null) && preinstallmsg || warn "User \'$name\' already exits. The following steps will overwrite the user's password and settings"
}

adduserandpass() { \
    # Adds user `$name` with password $pass1.
    info2 "Add user \'$name\'"
    if [ $debug = 0 ]; then
        useradd -m -g wheel -s /bin/zsh "$name" &>/dev/null ||
        usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
        usermod -a -G video "$name"
        repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel $(dirname "$repodir")
        echo "$name:$pass1" | chpasswd
    fi
    unset pass1 pass2 ;
}

newperms() { \
    # Set special sudoers settings for install (or after).
    info2 "Setting sudoers"
    if [ $debug = 0 ]; then
        sed -i "/#SCRIPT/d" /etc/sudoers
        echo -e "$@ #SCRIPT" >> /etc/sudoers
    fi
}

###############################################################################

downloadandeditpackages() { \
    cd "$1"
    [ ! -f packages.csv ] && curl https://raw.githubusercontent.com/thehnm/tarbs/master/packages.csv > packages.csv
    yesnodialog "Do you want to edit the list of packages to be installed?" "$editor packages.csv"
}

refreshkeys() { \
    info2 "Refreshing Arch Linux Keyring"
    [ $debug = 0 ] && pacman --noconfirm -Sy archlinux-keyring &>/dev/null
}

installyay() { \
    info2 "Installing yay"
    if [ $debug = 0 ]; then
        if [ ! -f /usr/bin/yay ]; then
            pacman --noconfirm -S git &>/dev/null
            sudo -u $name git clone https://aur.archlinux.org/yay.git /tmp/yay &>/dev/null
            cd /tmp/yay
            sudo -u $name makepkg --noconfirm -si &>/dev/null
        fi
    fi
}

pacmaninstall() { \
    info2 "Install $1. \"$2\""
    [ $debug = 0 ] && pacman --noconfirm --needed -S "$1" &>/dev/null
}

looppacmaninstall() {
    info2 "[$n/$total] $1. $2"
    [ $debug = 0 ] && pacman --noconfirm --needed -S "$1" &>/dev/null
}

loopaurinstall() { \
    info2 "[$n/$total] $1. $2"
    [ $debug = 0 ] && yes | sudo -u $name yay --noconfirm -S "$1" &>/dev/null
}

putgitrepo() { # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
    #info2 "Downloading $1"
    if [ $debug = 0 ]; then
        [ -z "$3" ] && branch="master" || branch="$3"
        tempdir=$(mktemp -d)
        [ ! -d "$2" ] && mkdir -p "$2"
        chown -R "$name":wheel "$tempdir" "$2"
        sudo -u "$name" git clone --recursive -b "$branch" --depth 1 "$1" "$tempdir" >/dev/null 2>&1
        sudo -u "$name" cp -rfT "$tempdir" "$2"
    fi
}

# Requires the git repository to have some kind of build file/Makefile
loopgitinstall() {
    progname="$(basename "$1" .git)"
    dir="$repodir/$progname"
    info2 "[$n/$total] $1. $2"
    if [ $debug = 0 ]; then
        putgitrepo "$1" "$dir"
        cd "$dir" || exit
        make install >/dev/null 2>&1
        cd "$currentdir" || return ;
    fi
}

setup_libinput() { \
    pacmaninstall "libinput" "Input device management and event handling library"
    info2 "Configure libinput for laptops"
    if [ $debug = 0 ]; then
        ln -s /usr/share/X11/xorg.conf.d/40-libinput.conf /etc/X11/xorg.conf.d/40-libinput.conf
        if [ -f configs/40-libinput.conf ]; then
            cp configs/40-libinput.conf /usr/share/X11/xorg.conf.d/40-libinput.conf
        else
            curl https://raw.githubusercontent.com/thehnm/tarbs/master/configs/40-libinput.conf > /usr/share/X11/xorg.conf.d/40-libinput.conf
        fi
    fi
}

install() {
    cd "$1"
    pacmaninstall "xorg-server" "Xorg X Server"
    pacmaninstall "xorg-xinit" "X.Org initialisation program"
    pacmaninstall "xorg-xsetroot" "Utility for setting root window to pattern or color"
    pacmaninstall "xorg-xrandr" "Interface for RandR interface"
    pacmaninstall "libxinerama" "X11 Xinerama extension library"

    [ "$laptop" = 1 ] && setup_libinput

    total=$(wc -l < packages.csv)
    total=$(( total - 1 ))
    #aurinstalled=$(pacman -Qm | awk '{print $1}')
    while IFS=, read -r tag program comment; do
        case "$tag" in
            "") looppacmaninstall "$program" "$comment" ;;
            "A") loopaurinstall "$program" "$comment" ;;
            "G") loopgitinstall "$program" "$comment" ;;
        esac
        n=$((n+1))
    done < packages.csv ;
}

serviceinit() {
    for service in "$@"; do
        info2 "Enabling \"$service\""
        if [ $debug = 0 ]; then
            systemctl enable "$service" &>/dev/null
            systemctl start "$service" &>/dev/null
        fi
    done
}

installantibody() {
    info2 "Install antibody zsh plugin manager"
    [ $debug = 0 ] && sudo -u $name curl -sfL git.io/antibody | sh -s - -b /home/$name/.local/bin/ &>/dev/null
}

installdotfiles() {
    info2 "Installing dotfiles"
    putgitrepo "$dotfilesrepo" "/home/$name"
    [ $debug = 0 ] && cd /home/"$name" && sudo -u "$name" git config --local status.showUntrackedFiles no
}

systembeepoff() {
    info2 "Disabling beep sound"
    if [ $debug = 0 ]; then
        rmmod pcspkr
        echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
    fi
}

resetpulse() { \
    info2 "Resetting Pulseaudio"
    if [ $debug = 0 ]; then
        killall pulseaudio &>/dev/null
        sudo -u "$name" pulseaudio --start
    fi
}

miscellaneous() {
    info2 "Setting miscellaneous stuff"

    [ $debug = 0 ] && ln -sf /usr/bin/dash /bin/sh

    systembeepoff

    # Pulseaudio, if/when initially installed, often needs a restart to work immediately.
    [[ -f /usr/bin/pulseaudio ]] && resetpulse

    if [ $debug = 0 ]; then
        # Color pacman
        sed -i "s/^#Color/Color/g" /etc/pacman.conf
        # Fix audio problem
        sed -i 's/^ autospawn/; autospawn/g' /etc/pulse/client.conf

        # Create configuration directories
        sudo -u "$name" mkdir -p /home/"$name"/.config/zsh ## Stores the zshrc
        sudo -u "$name" mkdir -p /home/"$name"/.local/share/zsh ## Stores history file for zsh
        sudo -u "$name" mkdir -p /home/"$name"/.config/notmuch ## Required by mutt-wizard
        sudo -u "$name" mkdir -p /home/"$name"/.config/newsboat ## Stores newsboat config
        sudo -u "$name" mkdir -p /home/"$name"/.local/share/newsboat ## Stores the cache and history file

        # Create XDG user directories
        sudo -u "$name" mkdir -p /home/"$name"/dl # Download directory
        sudo -u "$name" mkdir -p /home/"$name"/docs
        sudo -u "$name" mkdir -p /home/"$name"/music
        sudo -u "$name" mkdir -p /home/"$name"/pics
    fi
}

cleanup() {
    printf "\n"
    unset pass1 pass2
    err "Installation aborted"
    exit 1
}

###############################################################################

trap "cleanup" SIGINT SIGTERM

debug=1

currentdir=$(pwd)

clear

queue "initialcheck" \
      "sethostname" \
      "installfullsystem" \
      "getuserandpass" \
      "usercheck" \
      "adduserandpass" \
      "newperms \"%wheel ALL=(ALL) ALL\\n%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay\"" \
      "islaptop" \
      "downloadandeditpackages $currentdir" \
      "refreshkeys" \
      "installyay || { err 'yay has to be installed to continue'; exit 1; }" \
      "install $currentdir" \
      "installdotfiles" \
      "installantibody" \
      "serviceinit NetworkManager cronie ntpdate ssh" \
      "miscellaneous" \
      "succ 'Installation is done. You can reboot now'"