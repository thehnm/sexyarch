#!/bin/bash

[ -z ${dotfilesrepo+x} ] && dotfilesrepo="https://github.com/thehnm/dotfiles.git"
[ -z ${lang+x} ] && lang="LANG=en_US.UTF-8"
[ -z ${lcall+x} ] && lcall="LC_ALL=en_US.UTF-8"
[ -z ${editor+x} ] && editor="vim"
[ -z ${timezone+x} ] && timezone="Europe/Berlin"

###############################################################################

infobox() {
    dialog --infobox "$1" "$2" "$3"
    eval "$4" &>/dev/null
}

initialcheck() {
    pacman -S --noconfirm --needed dialog git || { echo "Are you sure you're running this as the root user? Are you sure you're using an Arch-based distro? ;-) Are you sure you have an internet connection?"; exit; } ;}

welcomemsg() { \
    dialog --title "Welcome!" --msgbox "Welcome to thehnm's Arch Linux Installation Script!\\n\\nThis script will automatically install a fully-featured dwm Arch Linux desktop, which I use as my main machine.\\n\\n-thehnm" 10 60
}

preinstallmsg() { \
    dialog --title "Start installing the script!" --yes-label "Let's go!" --no-label "No, nevermind!" --yesno "It will take some time, but when done, you can relax even more with your complete system.\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || { clear; exit; }
}

settimezone() {
    dialog --title "Timezone" --yes-label "Change timezone" --no-label "Keep going" --yesno "The following timezone will be used:\n\n$timezone" 10 50
    [ "$?" = "0" ] && timezone=$(dialog --inputbox "Enter the timezone" 10 60 3>&1 1>&2 2>&3 3>&1)
    ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime
    while [[ "$?" = "1" ]]; do
        timezone=$(dialog --inputbox "Wrong format <Continent/City>. Reenter the timezone" 10 60 3>&1 1>&2 2>&3 3>&1)
        ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime
    done
    hwclock --systohc
}

genlocale() {
    dialog --title "locale.gen" --yes-label "Edit locale.gen" --no-label "Keep going" --yesno "The following locale will be generated:\n\nen_US UTF-8" 10 50
    case $? in
        0 ) eval "$editor /etc/locale.gen"
            break;;
        1 ) sed -i "s/\#en_US/en_US/" /etc/locale.gen
            break;;
    esac
    locale-gen &> /dev/null
}

genandeditlocaleconf() {
    echo "$lang" > /etc/locale.conf
    echo "$lcall" >> /etc/locale.conf
    dialog --title "The following locale is set:" --yes-label "Edit defaults" --no-label "Don't edit" --yesno "$lang\n$lcall" 10 50
    [ "$?" = "0" ] && eval "$editor /etc/locale.conf"
}

sethostname() {
    hostname=$(dialog --inputbox "Enter your hostname" 10 60 3>&1 1>&2 2>&3 3>&1)
    echo "$hostname" > /etc/hostname
    echo "127.0.0.1 localhost" > /etc/hosts
    echo "::1 localhost" >> /etc/hosts
    echo "127.0.1.1 $hostname.localdomain $hostname" >> /etc/hosts
}

islaptop() { \
    dialog --yesno "Do you install this config on a laptop?" 10 80 3>&2 2>&1 1>&3
    case $? in
        0 ) laptop=1
            break;;
        1 ) laptop=0
            break;;
    esac
}

getuserandpass() {
    # Prompts user for new username an password.
    # Checks if username is valid and confirms passwd.
    name=$(dialog --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit
    namere="^[a-z_][a-z0-9_-]*$"
    while ! [[ "${name}" =~ ${namere} ]]; do
            name=$(dialog --no-cancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
    done
    userdatadir=/home/"$name"/.local/share
    pass1=$(dialog --no-cancel --insecure --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
    pass2=$(dialog --no-cancel --insecure --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
    while ! [[ ${pass1} == ${pass2} ]]; do
            unset pass2
            pass1=$(dialog --no-cancel --insecure --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
            pass2=$(dialog --no-cancel --insecure --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
    done ;
}

usercheck() { \
    ! (id -u $name &>/dev/null) ||
    dialog --colors --title "WARNING!" --yes-label "CONTINUE" --no-label "No wait..." --yesno "The user \`$name\` already exists on this system. This script can install for a user already existing, but it will \\Zboverwrite\\Zn any conflicting settings/dotfiles on the user account.\\n\\nThis script will \\Zbnot\\Zn overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that this script will change $name's password to the one you just gave." 14 70
}

adduserandpass() { \
    # Adds user `$name` with password $pass1.
    dialog --infobox "Adding user \"$name\"..." 4 50
    useradd -m -g wheel -s /bin/bash "$name" &>/dev/null ||
    usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
    usermod -a -G video "$name"
    repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel $(dirname "$repodir")
    echo "$name:$pass1" | chpasswd
    unset pass1 pass2 ;
}

refreshkeys() { \
    dialog --infobox "Refreshing Arch Keyring..." 4 40
    pacman --noconfirm -Sy archlinux-keyring &>/dev/null
}

setup_libinput() { \
    dialog --infobox "Configure libinput for laptops..." 8 50
    singleinstall "libinput" "Input device management and event handling library"
    ln -s /usr/share/X11/xorg.conf.d/40-libinput.conf /etc/X11/xorg.conf.d/40-libinput.conf
    curl https://raw.githubusercontent.com/thehnm/tarbs/master/configs/40-libinput.conf > /usr/share/X11/xorg.conf.d/40-libinput.conf
}

downloadandeditpackages() { \
    curl https://raw.githubusercontent.com/thehnm/tarbs/master/packages.csv > /tmp/packages.csv
    dialog --yesno "Do you want to edit the packages file?" 10 80 3>&2 2>&1 1>&3
    case $? in
        0 ) eval "$editor /tmp/packages.csv"
            break;;
        1 ) break;;
    esac
}

installyay() { \
    dialog --infobox "Installing yay, an AUR helper..." 8 50
    [ -f /usr/bin/yay ] && return 0
    pacman --noconfirm -S git &>/dev/null
    sudo -u $name git clone https://aur.archlinux.org/yay.git /tmp/yay &>/dev/null
    cd /tmp/yay
    sudo -u $name makepkg --noconfirm -si &>/dev/null
}

pacmaninstall() { \
    dialog --title "Installation" --infobox "Installing \`$1\` ($n of $total). $2" 5 70
    pacman --noconfirm --needed -S "$1" &>/dev/null
}

singleinstall() { \
    dialog --title "Installation" --infobox "Installing \`$1\`. $2" 5 70
    pacman --noconfirm --needed -S "$1" &>/dev/null
}

aurinstall() { \
    dialog --title "Installation" --infobox "Installing \`$1\` ($n of $total) from the AUR. $2" 5 70
    yes | sudo -u $name yay --noconfirm -S "$1" &>/dev/null
}

putgitrepo() { # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
    dialog --infobox "Downloading and installing config files..." 4 60
    [ -z "$3" ] && branch="master" || branch="$3"
    tempdir=$(mktemp -d)
    [ ! -d "$2" ] && mkdir -p "$2"
    chown -R "$name":wheel "$tempdir" "$2"
    sudo -u "$name" git clone --recursive -b "$branch" --depth 1 "$1" "$tempdir" >/dev/null 2>&1
    sudo -u "$name" cp -rfT "$tempdir" "$2"
}

# Requires the git repository to have some kind of build file/Makefile
gitmakeinstall() {
    progname="$(basename "$1" .git)"
    dir="$repodir/$progname"
    dialog --title "Installation" --infobox "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $2" 5 70
    sudo -u "$name" git clone --depth 1 "$1" "$dir" >/dev/null 2>&1 || { cd "$dir" || return ; sudo -u "$name" git pull --force origin master;}
    cd "$dir" || exit
    make >/dev/null 2>&1
    make install >/dev/null 2>&1
    cd /tmp || return ;
}

install() {
    singleinstall "xorg-server" "Xorg X Server"
    singleinstall "xorg-xinit" "X.Org initialisation program"
    singleinstall "xorg-xsetroot" "Utility for setting root window to pattern or color"
    singleinstall "libxinerama" "X11 Xinerama extension library"

    [ "$laptop" = 1 ] && setup_libinput

    total=$(wc -l < /tmp/packages.csv)
    aurinstalled=$(pacman -Qm | awk '{print $1}')
    while IFS=, read -r tag program comment; do
    n=$((n+1))
    case "$tag" in
        "") pacmaninstall "$program" "$comment" ;;
        "A") aurinstall "$program" "$comment" ;;
        "G") gitmakeinstall "$program" "$comment" ;;
    esac
    done < /tmp/packages.csv ;
}

serviceinit() {
    for service in "$@"; do
        dialog --infobox "Enabling \"$service\"..." 4 40
        systemctl enable "$service"
        systemctl start "$service"
    done
}

newperms() { \
    # Set special sudoers settings for install (or after).
    dialog --infobox "Setting sudoers settings..." 10 50
    sed -i "/#SCRIPT/d" /etc/sudoers
    echo -e "$@ #SCRIPT" >> /etc/sudoers
}

setshell() {
    dialog --infobox "Set shell..." 10 50
    ln -sf /usr/bin/dash /bin/sh

    dialog --infobox "Set interactive shell..." 10 50
    chsh -s /usr/bin/zsh
    chsh -s /usr/bin/zsh $name

    infobox "Install antibody zsh plugin manager" "4" "80" "sudo -u $name curl -sfL git.io/antibody | sh -s - -b /home/$name/.local/bin/"
}

installdotfiles() {
    putgitrepo "$dotfilesrepo" "/home/$name"
    cd /home/"$name" && sudo -u "$name" git config --local status.showUntrackedFiles no
    cd /home/"$name" && sudo -u "$name" git update-index --assume-unchanged README.md
    cd /home/"$name" && sudo -u "$name" rm README.md
}

systembeepoff() { \
    dialog --infobox "Getting rid of that retarded error beep sound..." 10 50
    rmmod pcspkr
    echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
}

resetpulse() { \
    dialog --infobox "Reseting Pulseaudio..." 4 50
    killall pulseaudio
    sudo -n "$name" pulseaudio --start
}

miscellaneous() {

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
}

finish() { \
    dialog --title "Welcome" --msgbox "The installation is done! You can reboot your system now." 10 80
}

##########################################################################################################################

mv install.sh /tmp/install.sh

# Check if user is root on Arch distro. Install dialog.
initialcheck

# Welcome user.
welcomemsg

settimezone

genlocale

genandeditlocaleconf

sethostname

# Get and verify username and password.
getuserandpass

# Give warning if user already exists.
usercheck || { clear; exit; }

# Last chance for user to back out before install.
preinstallmsg || { clear; exit; }

islaptop

adduserandpass

downloadandeditpackages

refreshkeys

newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

installyay

install

setshell

installdotfiles

serviceinit NetworkManager cronie ntpdate

newperms "%wheel ALL=(ALL) ALL\\n%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay"

miscellaneous

finish && clear
