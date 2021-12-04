# Installation Guide

This script will replicate my Arch Linux system configuration onto new machines.
See my [dotfiles](https://github.com/thehnm/dotfiles) for more information.

## Install Arch Linux Base System

Before you can use this script a basic Arch Linux installation is required since my script only configures an existing system.
The [Arch Linux Installation Guide](https://wiki.archlinux.org/index.php/Installation_guide) lists instructions for setting up a basic installation.
However, this script will already configure some settings such as locales, timezones and networking.

## Script

The next step after installing Arch Linux would be to download this script.

```bash
git clone https://github.com/thehnm/sexyarch
cd sexyarch
bash install.sh
```

## What this script will do

- Setup timezone
- Setup locale
- Set hostname
- Setup user
- Install programs needed for my configuraton/workflow. See packages.csv for further information
- Install my dotfiles
