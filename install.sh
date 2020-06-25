#!/bin/bash

[ -z ${dotfilesrepo+x} ] && dotfilesrepo="https://github.com/thehnm/dotfiles.git"
[ -z ${vundlerepo+x} ] && vundlerepo="https://github.com/VundleVim/Vundle.vim.git"
[ -z ${lightdmconfig+x} ] && lightdmconfig=/etc/lightdm/lightdm.conf
[ -z ${lightdmgtkconfig+x} ] && lightdmgtkconfig=/etc/lightdm/lightdm-gtk-greeter.conf
[ -z ${dwmdesktopfile+x} ] && dwmdesktopfile=/usr/share/xsessions/dwm.desktop

###############################################################################

initialcheck() {
    pacman -S --noconfirm --needed dialog || { echo "Are you sure you're running this as the root user? Are you sure you're using an Arch-based distro? ;-) Are you sure you have an internet connection?"; exit; } ;}

welcomemsg() { \
    dialog --title "Welcome!" --msgbox "Welcome to thehnm's Arch Linux Installation Script!\\n\\nThis script will automatically install a fully-featured dwm Arch Linux desktop, which I use as my main machine.\\n\\n-thehnm" 10 60
}

preinstallmsg() { \
    dialog --title "Start installing the script!" --yes-label "Let's go!" --no-label "No, nevermind!" --yesno "It will take some time, but when done, you can relax even more with your complete system.\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || { clear; exit; }
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
    echo "$name:$pass1" | chpasswd
    unset pass1 pass2 ;
}

refreshkeys() { \
    dialog --infobox "Refreshing Arch Keyring..." 4 40
    pacman --noconfirm -Sy archlinux-keyring &>/dev/null
}

installyay() { \
    dialog --infobox "Installing yay, an AUR helper..." 8 50
    pacman --noconfirm -S git &>/dev/null
    sudo -u $name git clone https://aur.archlinux.org/yay.git /tmp/yay &>/dev/null
    cd /tmp/yay
    sudo -u $name makepkg --noconfirm -si &>/dev/null
}

pacmaninstall() { \
    dialog --title "Installation" --infobox "Installing \`$1\` ($n of $total)." 5 70
    pacman --noconfirm --needed -S "$1" &>/dev/null
}

singleinstall() { \
    dialog --title "Installation" --infobox "Installing \`$1\`." 5 70
    pacman --noconfirm --needed -S "$1" &>/dev/null
}

aurinstall() { \
    dialog --title "Installation" --infobox "Installing \`$1\` ($n of $total) from the AUR." 5 70
    sudo -u $name yay --noconfirm -S "$1" &>/dev/null
}

singleaurinstall() { \
    dialog --title "Installation" --infobox "Installing \`$1\` from the AUR." 5 70
    sudo -u $name yay --noconfirm -S "$1" &>/dev/null
}


editpackages() { \
    curl https://raw.githubusercontent.com/thehnm/tarbs/master/packages.csv > /tmp/packages.csv
    dialog --yesno "Do you want to edit the packages file?" 10 80 3>&2 2>&1 1>&3
    case $? in
        0 ) vim $1
            break;;
        1 ) break;;
    esac
}

install_dwm_pkgs() {
    dialog --infobox "Install dwm dependencies..." 8 50
    singleinstall "libxft"
    singleinstall "libxinerama"
}

setup_libinput() { \
    dialog --infobox "Configure libinput for laptops..." 8 50
    singleinstall "libinput"
    ln -s /usr/share/X11/xorg.conf.d/40-libinput.conf /etc/X11/xorg.conf.d/40-libinput.conf
    curl https://raw.githubusercontent.com/thehnm/tarbs/master/configs/40-libinput.conf > /usr/share/X11/xorg.conf.d/40-libinput.conf
}

install() {
    singleinstall "xorg-server"
    singleinstall "xorg-xinit"
    singleinstall "xorg-xsetroot"
    singleinstall "git"

    install_dwm_pkgs
    [ "$laptop" = 1 ] && setup_libinput

    total=$(wc -l < /tmp/packages.csv)
    aurinstalled=$(pacman -Qm | awk '{print $1}')
    while IFS=, read -r tag program; do
    n=$((n+1))
    case "$tag" in
        "") pacmaninstall "$program" ;;
        "A") aurinstall "$program" ;;
    esac
    done < /tmp/packages.csv ;
}

putgitrepo() { \
    # Downlods a gitrepo $1 and places the files in $2 only overwriting conflicts
    dialog --infobox "Downloading $1..." 4 60
    dir=$(mktemp -d)
    chown -R "$name":wheel "$dir"
    sudo -u "$name" git clone "$1" "$dir"/"$3" &>/dev/null &&
    sudo -u "$name" mkdir -p "$2" &&
    sudo -u "$name" cp -rT "$dir"/"$3" "$2"/"$3"
}

gitrootmakeinstall() { \
    dialog --infobox "Downloading and installing $3..." 4 60
    sudo -u $name git clone "$1" "$2/$3" &> /dev/null
    cd "$2/$3"
    make install &> /dev/null
}

installdotfiles() { \
    dialog --infobox "Installing my dotfiles..." 4 60
    userhome=/home/$name
    cd "$userhome"
    sudo -u "$name" git clone --bare "$dotfilesrepo" .dotfiles
    sudo -u "$name" git --git-dir="$userhome"/.dotfiles/ --work-tree="$userhome" checkout -f
    sudo -u "$name" git --git-dir="$username"/.dotfiles/ --work-tree="$userhome" config --local status.showUntrackedFiles no
    if [ "$?" = "1" ]; then
        dialog --msgbox "Installation of dotfiles failed! Check for preexisting files!" 5 80
    fi
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
    ln -sf $1 /bin/sh
}

setinteractiveshell() {
    dialog --infobox "Set interactive shell..." 10 50
    chsh -s $1
    chsh -s $1 $name
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

configurelightdm() {
    dialog --infobox "Set lightdm greeter session..." 10 50
    sed -i "s/#greeter-session=.*/greeter-session=lightdm-gtk-greeter/g" "$lightdmconfig"
    sed -i "s/#indicators=/indicators=/g" "$lightdmgtkconfig" # Remove panel
    sed -i -e "\$ahide-user-image=true" "$lightdmgtkconfig" # Hide user icon
}

adddwmsession() {
    dialog --infobox "Create dwm session file for lightdm..." 10 50
    mkdir -p /usr/share/xsessions/
    echo "[Desktop Entry]" >> "$dwmdesktopfile"
    echo "Encoding=UTF-8" >> "$dwmdesktopfile"
    echo "Name=dwm" >> "$dwmdesktopfile"
    echo "Comment=Execute dwm" >> "$dwmdesktopfile"
    echo "Exec=/etc/lightdm/Xsession" >> "$dwmdesktopfile"
    echo "Type=Application" >> "$dwmdesktopfile"
}

miscellaneous() {

    systembeepoff

    # Pulseaudio, if/when initially installed, often needs a restart to work immediately.
    [[ -f /usr/bin/pulseaudio ]] && resetpulse

    # Color pacman
    sed -i "s/^#Color/Color/g" /etc/pacman.conf
    # Fix audio problem
    sed -i 's/^ autospawn/; autospawn/g' /etc/pulse/client.conf
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

# Get and verify username and password.
getuserandpass

# Give warning if user already exists.
usercheck || { clear; exit; }

# Last chance for user to back out before install.
preinstallmsg || { clear; exit; }

islaptop

adduserandpass

editpackages "/tmp/packages.csv"

refreshkeys

newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

installyay

install

installdotfiles

setshell "/usr/bin/dash"

setinteractiveshell "/usr/bin/zsh"

gitrootmakeinstall "https://github.com/thehnm/dwm" "$userdatadir" "dwm"
gitrootmakeinstall "https://github.com/thehnm/st" "$userdatadir" "st"
gitrootmakeinstall "https://github.com/thehnm/dmenu" "$userdatadir" "dmenu"

sudo -u "$name" curl -sfL git.io/antibody | sh -s - -b /home/"$name"/.local/bin/

putgitrepo "$vundlerepo" "/home/$name/.config/nvim/bundle/" "Vundle.vim"

serviceinit NetworkManager

newperms "%wheel ALL=(ALL) ALL\\n%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay"

miscellaneous

finish && clear
