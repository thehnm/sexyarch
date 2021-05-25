#!/usr/bin/env bash

[ -z ${dotfilesrepo+x} ] && dotfilesrepo="https://github.com/thehnm/dotfiles.git"
[ -z ${editor+x} ] && editor="vim"
[ -z ${grub+x} ] && grub=0
[ -z ${editpackages+x} ] && editpackages=0
[ -z ${laptop+x} ] && laptop=0

###############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
PURPLE='\033[0;35m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

err() {
    printf "${RED}$1${NC}\n"
}

succ() {
    printf "${GREEN}$1${NC}\n"
}

info() {
    printf "# $1\n"
}

info2() {
    printf "  * $1\n"
}

warn() {
    printf "${ORANGE}WARNING! $1${NC}\n"
    yesnodialog "${ORANGE}Do you really want to continue?${NC}" "" "exit 1"
}

yesnodialog() {
    while true; do
        read -p "$(printf "$1 (y|n) ")" yn
        case $yn in
            y ) eval $2; break;;
            n ) eval $3; break;;
            * ) err "Please answer yes (y) or no (n).";;
        esac
    done
}

###############################################################################

usage() {
    printf "\n"
    printf "Usage: install.sh -u username [-hgdpltne]\n\n"
    printf "To simply install my dotfiles without configuring a full Arch Linux system:\n\n"
    printf "> ./install.sh -u username\n\n"
    printf "Required Arguments\n"
    printf "  -u username\n"
    printf "     Set user name\n\n"
    printf "Optional Arguments\n"
    printf "  -h Display help\n"
    printf "  -e editor\n"
    printf "     Choose another editor (default: $editor)\n"
    printf "  -f Edit the packages file (default: no)\n"
    printf "  -g Install GRUB bootloader (default: no)\n"
    printf "  -d directory\n"
    printf "     Specify EFI boot directory. Needed when installing GRUB\n"
    printf "  -p partition\n"
    printf "     Specify EFI boot partition. Needed when installing GRUB\n"
    printf "  -l locale\n"
    printf "     Set locale, e.g. en_US\n"
    printf "  -t timezone\n"
    printf "     Set timezone, e.g. Europe/London\n"
    printf "  -n hostname\n"
    printf "     Set hostname\n"
}

while getopts "u:hgd:p:l:t:n:fe:" arg; do
    case "${arg}" in
        u) name=$OPTARG ;;
        h) usage; exit 0 ;;
        g) grub=1 ;;
        d) efidir=$OPTARG ;;
        p) efipart=$OPTARG ;;
        l) locale=$OPTARG ;;
        t) timezone=$OPTARG ;;
        n) hostname=$OPTARG ;;
        f) editpackages=1 ;;
        e) editor=$OPTARG ;;
        ?) printf "Invalid option: -${OPTARG}.\n\n"; usage; exit 1 ;;
        :) printf "Invalid Option: -$OPTARG requires an argument\n\n"; usage; exit 1;;
    esac
done

[ -z ${name+x} ] && { err "Username [-u] has to be set!"; exit 1; }
shift $((OPTIND -1))

###############################################################################

initialcheck() {
    info "Initial check"
    pacman -S --noconfirm --needed git &>/dev/null || { err "You are not running this script as root."; exit 1; }

    namere="^[a-z_][a-z0-9_-]*$"
    ! [[ "${name}" =~ ${namere} ]] && err "Username not valid!" && exit 1

    [ -z "$(builtin type -p $editor)" ] && err "Editor \'${editor}\' not found" && exit 1

    # Check if all necessary variables for GRUB installation are correctly set
    if [ "$grub" = 1 -a -d /sys/firmware/efi ]; then
        [ -z ${efidir+x} ] && { err "Installation on UEFI system. EFI directory not set."; exit 1; }
        [ -z ${efipart+x} ] && { err "Installation on UEFI system. EFI partition not set."; exit 1; }

        [ -z "$(blkid | grep "$efipart")" ] && { err "Partition "" does not exist!"; exit 1; } # Check if partition exists
        [ -z "$(blkid $efipart| grep -E -- "fat|vfat")" ] && { err "Partition is not a FAT32 partition!"; exit 1; } # Check if FAT

        mountpoint=$(df -h | grep $efipart | rev | cut -d ' ' -f1 | rev)
        [ -n "$mountpoint" ] && [ "$mountpoint" != "$efidir" ] && err "Partition \'$efipart\' is already mounted elsewhere" && exit 1
    fi

    [ -n "${timezone}" ] && [ ! -e /usr/share/zoneinfo/"$timezone" ] && err "Timezone \'$timezone\' not found. Check if it is correctly spelled, e.g. Europe/London" && exit 1

    [ -n "${locale}" ] && [ -z "$(grep $locale /etc/locale.gen)" ] && err "Locale \'$locale\' not found. Check if it is correctly spelled, e.g. en_US" && exit 1

    hostre="^[a-z0-9][a-z0-9.-_]*$"
    [ -n "${hostname}" ] && ! [[ "${hostname}" =~ ${hostre} ]] && err "Hostname \'$hostname\' not valid" && exit 1
}

usercheck() {
    ! (id -u $name &>/dev/null) || warn "User \'$name\' already exits.\nThe following steps will overwrite the user's password and settings"
}

getuserpass() {
    read -s -p "Enter password for $name: " pass1
    printf "\n"
    read -s -p "Reenter password for $name: " pass2
    printf "\n"

    while ! [[ ${pass1} == ${pass2} ]]; do
        unset pass1 pass2
        err "Passwords do not match. Please enter your password again"
        read -s -p "Enter password for $name: " pass1
        read -s -p "Reenter password for $name: " pass2
    done
}

downloadandeditpackages() {
    [ ! -f packages.csv ] && info "Downloading packages file" && curl https://raw.githubusercontent.com/thehnm/autoarch/master/packages.csv > packages.csv
    [ "$editpackages" = 1 ] && $editor packages.csv && clear
}

adduserandpass() {
    # Adds user `$name` with password $pass1.
    info "Add user \'$name\'"
    useradd -m -g wheel -s /bin/zsh "$name" &>/dev/null ||
    usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
    usermod -a -G video "$name"
    repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel $(dirname "$repodir")
    printf "$name:$pass1" | chpasswd
    unset pass1 pass2 ;
}

newperms() {
    # Set special sudoers settings for install (or after).
    info "Setting sudoers"
    sed -i "/#SCRIPT/d" /etc/sudoers
    printf "%b #SCRIPT\n" "$@" >> /etc/sudoers
}

installyay() {
    info "Installing yay"
    if [ ! -f /usr/bin/yay ]; then
        pacman --noconfirm -S git &>/dev/null
        sudo -u $name git clone https://aur.archlinux.org/yay.git /tmp/yay &>/dev/null
    (
        cd /tmp/yay
        sudo -u $name makepkg --noconfirm -si &>/dev/null
    )
    fi
}

refreshkeys() {
    info "Refreshing Arch Linux Keyring"
    pacman --noconfirm -Sy archlinux-keyring &>/dev/null
}

singleinstall() {
    info "Installing $1. $2"
    pacman --noconfirm --needed -S "$1" &>/dev/null
}

pacmaninstall() {
    info2 "[$n/$total] $1. $2"
    pacman --noconfirm --needed -S "$1" &>/dev/null
}

aurinstall() {
    info2 "[$n/$total] $1. $2"
    yes | sudo -u $name yay --noconfirm -S "$1" &>/dev/null
}

putgitrepo() { # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
    [ -z "$3" ] && branch="master" || branch="$3"
    tempdir=$(mktemp -d)
    [ ! -d "$2" ] && mkdir -p "$2"
    chown -R "$name":wheel "$tempdir" "$2"
    sudo -u "$name" git clone --recursive -b "$branch" --depth 1 "$1" "$tempdir" >/dev/null 2>&1
    sudo -u "$name" cp -rfT "$tempdir" "$2"
}

# Requires the git repository to have some kind of build file/Makefile
gitinstall() {
    progname="$(basename "$1" .git)"
    dir="$repodir/$progname"
    info "[$n/$total] $1. $2"
    putgitrepo "$1" "$dir"
    (
        cd "$dir" || exit
        make install >/dev/null 2>&1
    )
}

configurelibinput() {
    [ "$laptop" = 0 ] && return
    info "Configure touchpad for laptops"
    pacman --noconfirm --needed -S libinput &>/dev/null
    ln -s /usr/share/X11/xorg.conf.d/40-libinput.conf /etc/X11/xorg.conf.d/40-libinput.conf

    printf 'Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
    Option "Tapping" "on"
	Option "NaturalScrolling" "true"
	Option "DisableWhileTyping" "off"
EndSection' > /usr/share/X11/xorg.conf.d/40-libinput.conf
}

install() {
    total=$(wc -l < packages.csv)
    total=$(( total - 1 )) # Remove header line
    while IFS=, read -r tag program comment; do
        case "$tag" in
            "") pacmaninstall "$program" "$comment" ;;
            "A") aurinstall "$program" "$comment" ;;
            "G") gitinstall "$program" "$comment" ;;
        esac
        n=$((n+1))
    done < packages.csv ;
}

serviceinit() {
    info "Enable services"
    for service in "$@"; do
        info2 "Enabling \"$service\""
        systemctl enable "$service" &>/dev/null
        systemctl start "$service" &>/dev/null
    done
}

installantibody() {
    info "Install antibody zsh plugin manager"
    sudo -u $name curl -sfL git.io/antibody | sh -s - -b /home/$name/.local/bin/ &>/dev/null
}

installdotfiles() {
    info "Installing dotfiles"
(
    putgitrepo "$dotfilesrepo" "/home/$name"
    cd /home/"$name" && sudo -u "$name" git config --local status.showUntrackedFiles no
)
}

systembeepoff() {
    info "Disabling beep sound"
    rmmod pcspkr
    printf "blacklist pcspkr\n" > /etc/modprobe.d/nobeep.conf
}

resetpulse() { \
    info "Resetting Pulseaudio"
    killall pulseaudio &>/dev/null
    sudo -u "$name" pulseaudio --start
}

miscellaneous() {
    info "Setting miscellaneous stuff"

    ln -sf /usr/bin/dash /bin/sh

    systembeepoff

    # Pulseaudio, if/when initially installed, often needs a restart to work immediately.
    [[ -f /usr/bin/pulseaudio ]] && resetpulse

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
}

settimezone() {
    [ -z ${timezone+x} ] && return

    info "Setting timezone"
    ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime &>/dev/null
    hwclock --systohc
}

genlocale() {
    [ -z ${locale+x} ] && return

    info "Generating locale"
    sed -i "s/\#$locale/$locale/" /etc/locale.gen
    locale-gen &>/dev/null
    info "Setting locale"
    printf "LANG=$locale.UTF-8\n" > /etc/locale.conf
    printf "LC_ALL=$locale.UTF-8\n" >> /etc/locale.conf
}

sethostname() {
    [ -z ${hostname+x} ] && return

    info "Setting hostname"
    printf "$hostname\n" > /etc/hostname
    printf "127.0.0.1 localhost\n" > /etc/hosts
    printf "::1 localhost\n" >> /etc/hosts
    printf "127.0.1.1 $hostname.localdomain $hostname\n" >> /etc/hosts
}

installgrub() {
    [ "$grub" = 0 ] && return

    singleinstall grub "Bootloader"
    singleinstall os-prober "Detects other operating systems"
    singleinstall ntfs-3g "Driver for detecting Windows partition"

    if [ -d /sys/firmware/efi ]; then
        singleinstall efibootmgr "EFI Boot Manager"
        [ ! -d $efidir ] && { info "Creating EFI dir"; mkdir -p "$efidir" &>/dev/null; }

        info "Mounting partition \'$efipart\' to \'$efidir\'"
        mount $efipart $efidir &>/dev/null

        info "Setting up GRUB"
        grub-install --efi-directory="$efidir" --bootloader-id=GRUB --target=x86_64-efi &>/dev/null
    else
        part="$(df -h | grep -e "/$" | cut -d ' ' -f1)"
        part=${part%?}

        info "Setting up GRUB"
        grub-install "$part" &>/dev/null
    fi

    grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null
}

cleanup() {
    printf "\n"
    unset pass1 pass2
    err "Installation aborted"
    exit 1
}

###############################################################################

trap cleanup INT SIGINT SIGTERM

clear

initialcheck

usercheck

getuserpass

downloadandeditpackages

adduserandpass

newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

installyay || { err 'yay has to be installed to continue'; exit 1; }

refreshkeys

install

configurelibinput

installdotfiles

installantibody

newperms "%wheel ALL=(ALL) ALL\n%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay"

serviceinit NetworkManager cronie ntpdate sshd

miscellaneous

settimezone

genlocale

sethostname

installgrub

succ 'Installation is done. You can reboot now'
