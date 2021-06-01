#!/usr/bin/env bash

[ -z ${dotfilesrepo+x} ] && dotfilesrepo="https://github.com/thehnm/dotfiles.git"
[ -z ${editor+x} ] && editor="vim"

###############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

bold() {
    printf "${BOLD}$1${NORMAL}"
}

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

newperms() {
    # Set special sudoers settings for install (or after).
    info "Setting sudoers"
    sed -i "/#SCRIPT/d" /mnt/etc/sudoers
    printf "%b #SCRIPT\n" "$@" >> /mnt/etc/sudoers
}

createyayscript() {
    printf "if [ ! -f /usr/bin/yay ]; then
    pacman --noconfirm -S git &>/dev/null
    sudo -u $name git clone https://aur.archlinux.org/yay.git /tmp/yay &>/dev/null
    (
        cd /tmp/yay
        sudo -u $name makepkg --noconfirm -si &>/dev/null
    )
fi" > /mnt/installyay.sh
}

singleinstall() {
    info2 "Installing $1. $2"
    arch-chroot /mnt pacman --noconfirm --needed -S "$1" &>/dev/null
}

pacmaninstall() {
    info2 "[$n/$total] $1. $2"
    arch-chroot /mnt pacman --noconfirm --needed -S "$1" &>/dev/null
}

aurinstall() {
    info2 "[$n/$total] $1. $2"
    arch-chroot /mnt sudo -u $name yay --noconfirm -S "$1" &>/dev/null
}

putgitrepo() { # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
    [ -z "$3" ] && branch="master" || branch="$3"
    tempdir=$(arch-chroot /mnt mktemp -d)
    [ ! -d "/mnt/$2" ] && mkdir -p "/mnt/$2"
    arch-chroot /mnt chown -R "$name":wheel "$tempdir" "$2"
    arch-chroot /mnt sudo -u "$name" git clone --recursive -b "$branch" --depth 1 "$1" "$tempdir" >/dev/null 2>&1
    arch-chroot /mnt sudo -u "$name" cp -rfT "$tempdir" "$2"
}

# Requires the git repository to have some kind of build file/Makefile
gitinstall() {
    progname="$(basename "$1" .git)"
    dir="$repodir/$progname"
    info "[$n/$total] $1. $2"
    putgitrepo "$1" "$dir"
    arch-chroot /mnt bash -c "cd /mnt/$dir && make install >/dev/null 2>&1"
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
        arch-chroot /mnt systemctl enable "$service" &>/dev/null
    done
}

cleanup() {
    printf "\n"
    unset pass1 pass2
    err "Installation aborted"
    exit 1
}

usage() {
    printf "\
Usage: bash install.sh -u $(bold name)
Usage: bash install.sh --user $(bold name)

Options:
    -u, --user $(bold username)
        Set the username. Mandatory option.
    -f, --fullinstall $(bold disk)
        Install a full system. Specify a $(bold disk) to install the system.
        If not set, then the options (-l|--locale), (-z|--zone) and (-h|--host)
        will be ignored even if they are set.
    -p, --packageedit
        Edit the package list before installing the system.
    -l, --locale $(bold locale)
        Set system locale, e.g. en_US.
    -n, --host $(bold host)
        Set the hostname of this system.
    -z, --zone $(bold timezone)
        Set timezone of the system, e.g. Europe/London.
    -t, --touchpad
        Install necessary dependencies for activating the touchpad on laptops.
    -e, --editor $(bold editor)
        Set the editor to use when editing files. Default: $(bold vim)
    -h, --help
        Print usage information.\n"
}

###############################################################################

trap 'cleanup' INT SIGINT SIGTERM ERR KILL

options=$(getopt -o f:pl:z:n:u:te:h \
                 --long fullinstall: \
                 --long packageedit \
                 --long locale: \
                 --long zone: \
                 --long host: \
                 --long user: \
                 --long touchpad \
                 --long editor: \
                 --long help \
                 -- "$@")

[ $? -eq 0 ] || {
    printf "Incorrect options provided\n\n"
    usage
    exit 1
}

eval set -- "$options"
while true; do
    case "$1" in
        -f|--fullinstall)
            fullinstall=1
            shift
            [ ! -e "$1" ] && err "Disk $1 not found. Check if it is correctly spelled, e.g. /dev/sda" && exit 1
            part=$1
            ;;
        -p|--packageedit)
            packageedit=1
            ;;
        -l|--locale)
            shift
            [ -z "$(grep $1 /etc/locale.gen)" ] && err "Locale \'$1\' not found. Check if it is correctly spelled, e.g. en_US" && exit 1
            locale=$1
            ;;
        -z|--zone)
            shift
            [ ! -e /usr/share/zoneinfo/"$1" ] && err "Timezone \'$1\' not found. Check if it is correctly spelled, e.g. Europe/London" && exit 1
            zone=$1
            ;;
        -n|--host)
            shift
            host=$1
            ;;
        -u|--user)
            shift
            namere="^[a-z_][a-z0-9_-]*$"
            ! [[ "$1" =~ ${namere} ]] && err "Username not valid!" && exit 1
            name=$1
            ;;
        -t|--touchpad)
            touchpad=1
            ;;
        -e|--editor)
            shift
            [ -z "$(builtin type -p $1)" ] && err "Editor \'$1\' not found" && exit 1
            editor=$1
            ;;
        -h|--help)
            usage
            exit 1
            ;;
        --)
            shift
            break
            ;;
    esac

    shift
done

info "Initial check"
[ -z "$name" ] && err "Username not set" && exit 1

clear

read -s -p "Create password for $name: " pass1
printf "\n"
read -s -p "Reenter password for $name: " pass2
printf "\n"
while ! [[ $pass1 == $pass2 ]]; do
    unset pass1 pass2
    err "Passwords do not match. Please enter your password again"
    read -s -p "Create password for $name: " pass1
    printf "\n"
    read -s -p "Reenter password for $name: " pass2
    printf "\n"
done

[ ! -f packages.csv ] && info "Downloading packages file" && curl https://raw.githubusercontent.com/thehnm/autoarch/master/packages.csv > packages.csv
[ $packageedit ] && $editor packages.csv && clear

if [ $fullinstall ]; then
    [ -d /sys/firmware/efi ] && uefi=1
    if [ $(ls ${part}* | wc -l) -gt 1 ]; then
        err "Please delete old partitions from $(bold $part)"
        cleanup
        exit 1
    fi

    if [ $uefi ]; then
        parted -s "$part" -- mklabel gpt \
            mkpart ESP fat32 1MiB 512MiB \
            set 1 boot on \
            mkpart primary ext4 512MiB 100%

        mainpart="${part}2"
        mkfs.vfat -F32 "${part}1"
    else
        parted -s "$part" -- mklabel gpt mkpart primary ext4 1MiB 100%
        mainpart="${part}1"
    fi

    mkfs.ext4 "$mainpart"
    mount "$mainpart" /mnt

    info "Install base system"
    pacstrap /mnt base base-devel linux linux-firmware vi vim man zsh &> /dev/null
    genfstab -Up /mnt > /mnt/etc/fstab
    [ $uefi ] && mkdir -p /mnt/boot/efi && mount "${part}1" /mnt/boot/efi

    info "Install bootloader"
    singleinstall grub "Bootloader"
    singleinstall os-prober "Detects other operating systems"
    singleinstall ntfs-3g "Driver for detecting Windows partition"
    if [ $uefi ]; then
        singleinstall efibootmgr "EFI Boot Manager"
        mount "${part}1" /mnt/boot/efi
        arch-chroot /mnt grub-install --efi-directory="/boot/efi" --bootloader-id=GRUB --target=x86_64-efi &>/dev/null
    else
        arch-chroot /mnt grub-install "${part}" &>/dev/null
    fi
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$zone" /etc/localtime

    printf "$host" > /mnt/etc/hostname
    printf "127.0.0.1   localhost\n" > /mnt/etc/hosts
    printf "::1         localhost\n" > /mnt/etc/hosts
    printf "127.0.1.1   $host.localdomain     $host" > /mnt/etc/hosts

    sed -i "s/\#$locale/$locale/" /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen &>/dev/null
    printf "LANG=$locale.UTF-8\n" > /mnt/etc/locale.conf
    printf "LC_ALL=$locale.UTF-8\n" >> /mnt/etc/locale.conf
fi

! (arch-chroot /mnt id -u $name &>/dev/null) || warn "User \'$name\' already exits.\nThe following steps will overwrite the user's password and settings"

arch-chroot /mnt useradd -mU -s /usr/bin/zsh -G wheel,uucp,video,audio,storage,games,input "$name"
arch-chroot /mnt chsh -s /usr/bin/zsh
repodir="/home/$name/.local/src"
arch-chroot /mnt sudo -u "$name" mkdir -p "$repodir"

printf "$name:$pass1" | chpasswd --root /mnt
unset pass1 pass2

newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

info "Install yay AUR helper"
printf "\
if [ ! -f /usr/bin/yay ]; then
    pacman --noconfirm -S git &>/dev/null
    sudo -u $name git clone https://aur.archlinux.org/yay.git /tmp/yay &>/dev/null
    (
        cd /tmp/yay
        sudo -u $name makepkg --noconfirm -si &>/dev/null
    )
fi" > /mnt/installyay.sh
arch-chroot /mnt bash installyay.sh

arch-chroot /mnt pacman --noconfirm -Sy archlinux-keyring

install

info "Installing dotfiles"
putgitrepo "$dotfilesrepo" "/home/$name"
arch-chroot /mnt bash -c "cd /home/$name && sudo -u $name git config --local status.showUntrackedFiles no"

info "Install antibody zsh plugin manager"
arch-chroot /mnt bash -c "sudo -u $name curl -sfL git.io/antibody | sh -s - -b /home/$name/.local/bin/ &>/dev/null"

info "Set dash shell"
arch-chroot ln -sf /usr/bin/dash /bin/sh

info "Disabling beep sound"
arch-chroot /mnt rmmod pcspkr
printf "blacklist pcspkr\n" > /mnt/etc/modprobe.d/nobeep.conf

if [ -f /mnt/usr/bin/pulseaudio ]; then
    info "Restart pulseaudio"
    arch-chroot /mnt killall pulseaudio &>/dev/null
    arch-chroot /mnt sudo -u "$name" pulseaudio --start
fi

info "Enable pacman colors"
sed -i "s/^#Color/Color/g" /mnt/etc/pacman.conf

info "Enable autospawn in pulseaudio"
sed -i 's/^ autospawn/; autospawn/g' /mnt/etc/pulse/client.conf

info "Create user directories"
arch-chroot /mnt sudo -u "$name" mkdir -p /home/"$name"/.config/zsh ## Stores the zshrc
arch-chroot /mnt sudo -u "$name" mkdir -p /home/"$name"/.local/share/zsh ## Stores history file for zsh
arch-chroot /mnt sudo -u "$name" mkdir -p /home/"$name"/.config/notmuch ## Required by mutt-wizard
arch-chroot /mnt sudo -u "$name" mkdir -p /home/"$name"/.config/newsboat ## Stores newsboat config
arch-chroot /mnt sudo -u "$name" mkdir -p /home/"$name"/.local/share/newsboat ## Stores the cache and history file
arch-chroot /mnt sudo -u "$name" mkdir -p /home/"$name"/{dl, docs, music, pics}

info "Setting permissions"
newperms "%wheel ALL=(ALL) ALL\n%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay"

serviceinit NetworkManager cronie ntpdate sshd

if [ $touchpad ]; then
    info "Configure touchpad for laptops"
    singleinstall libinput "Input device management library"
    ln -s /mnt/usr/share/X11/xorg.conf.d/40-libinput.conf /mnt/etc/X11/xorg.conf.d/40-libinput.conf
    printf 'Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
        Option "Tapping" "on"
        Option "NaturalScrolling" "true"
        Option "DisableWhileTyping" "off"
    EndSection' > /mnt/usr/share/X11/xorg.conf.d/40-libinput.conf
fi

succ 'Installation is done. You can reboot now'
