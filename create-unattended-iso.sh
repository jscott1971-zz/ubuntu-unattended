#!/usr/bin/env bash

# file names & paths
tmp="$HOME"  # destination folder to store the final iso file
tmphtml=$tmp/tmphtml

# define spinner function for slow tasks
# courtesy of http://fitnr.com/showing-a-bash-spinner.html
spinner()
{
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    tput civis;

    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done

    printf "    \b\b\b\b"
    tput cnorm;
}

# define download function
# courtesy of http://fitnr.com/showing-file-download-progress-using-wget.html
download()
{
    local url=$1
    echo -n "    "
    wget --progress=dot $url 2>&1 | grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE"
}

# define function to check if program is installed
# courtesy of https://gist.github.com/JamieMason/4761049
function program_is_installed {
    # set to 1 initially
    local return_=1
    # set to 0 if not found
    type $1 >/dev/null 2>&1 || { local return_=0; }
    # return value
    echo $return_
}

# print a pretty header
echo
echo " +---------------------------------------------------+"
echo " |            UNATTENDED UBUNTU ISO MAKER            |"
echo " +---------------------------------------------------+"
echo

# This script must be run with root privileges
if [ ${UID} -ne 0 ]; then
    echo " [-] This script must be runned with root privileges."
    echo " [-] sudo ${0}"
    echo
    exit 1
fi

# Get the latest versions of Ubuntu LTS
rm $tmphtml >/dev/null 2>&1
wget -O $tmphtml 'http://releases.ubuntu.com/' >/dev/null 2>&1

prec=$(fgrep Precise $tmphtml | head -1 | awk '{print $3}')
trus=$(fgrep Trusty $tmphtml | head -1 | awk '{print $3}')
xenn=$(fgrep Xenial $tmphtml | head -1 | awk '{print $3}')
# Uncomment the following when bug is fixed.
# https://bugs.launchpad.net/bugs/1745744
# artt=$(fgrep Artful $tmphtml | head -1 | awk '{print $3}')
artt="17.10.1"

# ask whether to include vmware tools or not
while true; do
    echo "Which ubuntu edition would you like to remaster:"
    echo
    echo "  [1] Ubuntu $prec LTS Server amd64 - Precise Pangolin"
    echo "  [2] Ubuntu $trus LTS Server amd64 - Trusty Tahr"
    echo "  [3] Ubuntu $xenn LTS Server amd64 - Xenial Xerus"
    echo "  [4] Ubuntu $artt LTS server amd64 - Artful Aardvark"
    echo
    read -p "Please enter your preference: [1|2|3|4]: " ubver
    case $ubver in
        [1]* )  download_file="ubuntu-$prec-server-amd64.iso"           # filename of the iso to be downloaded
                download_location="http://releases.ubuntu.com/$prec/"   # location of the file to be downloaded
                new_iso_name="ubuntu-$prec-server-amd64-unattended.iso" # filename of the new iso file to be created
                break;;
        [2]* )  download_file="ubuntu-$trus-server-amd64.iso"           # filename of the iso to be downloaded
                download_location="http://releases.ubuntu.com/$trus/"   # location of the file to be downloaded
                new_iso_name="ubuntu-$trus-server-amd64-unattended.iso" # filename of the new iso file to be created
                break;;
        [3]* )  download_file="ubuntu-$xenn-server-amd64.iso"           # filename of the iso to be downloaded
                download_location="http://releases.ubuntu.com/$xenn/"   # location of the file to be downloaded
                new_iso_name="ubuntu-$xenn-server-amd64-unattended.iso" # filename of the new iso file to be created
                break;;
	[4]* )  download_file="ubuntu-$artt-server-amd64.iso"           # filename of the iso to be downloaded
                download_location="http://releases.ubuntu.com/$artt/"   # location of the file to be downloaded
                new_iso_name="ubuntu-$artt-server-amd64-unattended.iso" # filename of the new iso file to be created
                break;;
        * ) echo " please answer [1], [2], [3] or [4]";;
    esac
done

if ! timezone=`cat /etc/timezone 2> /dev/null`; then
    timezone="US/Eastern"
fi

# ask the user questions about his/her preferences
read -ep "Please enter your preferred timezone: " -i "${timezone}" timezone
read -ep "Please enter your preferred hostname: " -i "ubuntu" hostname
read -ep "Please enter your preferred username: " -i "`logname`" username

# Check if the passwords match
while true; do
    read -sp "Please enter your preferred password: " password
    printf "\n"
    read -sp "Confirm your preferred password: " password2
    printf "\n"
    if [[ "$password" != "$password2" ]]; then
        echo "Your passwords do not match; please try again"
	echo
    else
        break
    fi
done

read -ep "Make ISO bootable via USB: " -i "yes" bootable

read -p "Autostart installation on boot(y/n)? " choice
case "$choice" in 
  y|Y ) autostart=true;;
  * ) autostart=false;;
esac

# download the ubunto iso.
# If it already exists, do not delete in the end.
cd $tmp
if [[ ! -f $tmp/$download_file ]]; then
    echo -n " downloading $download_file: "
    download "$download_location$download_file"
elif [[ ! -f $tmp/$download_file ]]; then
    echo "Error: Failed to download ISO: $download_location$download_file"
    echo "This file may have moved or may no longer exist."
    echo
    echo "You can download it manually and move it to $tmp/$download_file"
    echo "Then run this script again."
    exit 1
fi

read -ep "Please enter partition type (regular_ext4/lvm) : " -i "regular_ext4" partition_type

# ask user with type of partition type to use
while true; do
    case ${partition_type} in
        regular_ext4) seed_file="regular_ext4.seed" ; break ;;
        * ) echo "Please enter only regular_ext4." ;;
    esac
done

# download seed file
if [[ ! -f $tmp/$seed_file ]]; then
    echo -n " downloading $seed_file: "
    download "https://raw.githubusercontent.com/jscott1971/ubuntu-unattended/master/$seed_file"
fi

# install required packages
echo " installing required packages"
if [ $(program_is_installed "mkpasswd") -eq 0 ] || [ $(program_is_installed "mkisofs") -eq 0 ]; then
    (apt-get -y update > /dev/null 2>&1) &
    spinner $!
    (apt-get -y install whois genisoimage > /dev/null 2>&1) &
    spinner $!

    # thanks to rroethof
    if [ ! -f /usr/bin/mkisofs ]; then
      ln -s /usr/bin/genisoimage /usr/bin/mkisofs
    fi
fi

if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
    if [ $(program_is_installed "isohybrid") -eq 0 ]; then
        #16.04
        if [ $ub1604 == "yes" ]; then
	    (apt-get -y install syslinux syslinux-utils > /dev/null 2>&1) &
            spinner $!
        else
            (apt-get -y install syslinux > /dev/null 2>&1) &
            spinner $!
        fi
    fi
fi

# create working folders
echo " remastering your iso file"
mkdir -p $tmp
mkdir -p $tmp/iso_org
mkdir -p $tmp/iso_new

# mount the image
if grep -qs $tmp/iso_org /proc/mounts ; then
    echo " image is already mounted, continue"
else
    (mount -o loop $tmp/$download_file $tmp/iso_org > /dev/null 2>&1)
fi

# copy the iso contents to the working directory
(cp -rT $tmp/iso_org $tmp/iso_new > /dev/null 2>&1) &
spinner $!

# set the language for the installation menu
cd $tmp/iso_new
echo en > $tmp/iso_new/isolinux/lang

# set timeout to 1 decisecond to skip language & boot menu option selection.
if $autostart ; then
    sed -i "s/timeout 0/timeout 1/" $tmp/iso_new/isolinux/isolinux.cfg
fi

# set late command
late_command="chroot /target wget -O /home/$username/start.sh https://github.com/${seed_file}/ubuntu-unattended/raw/master/start.sh ;\
    chroot /target chmod +x /home/$username/start.sh ;"

# copy the seed file to the iso
cp -rT $tmp/$seed_file $tmp/iso_new/preseed/$seed_file

# include firstrun script
echo "
# setup firstrun script
d-i preseed/late_command                                    string      $late_command" >> $tmp/iso_new/preseed/$seed_file

# generate the password hash
pwhash=$(echo $password | mkpasswd -s -m sha-512)

# update the seed file to reflect the users' choices
# the normal separator for sed is /, but both the password and the timezone may contain it
# so instead, I am using @
sed -i "s@{{username}}@$username@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{pwhash}}@$pwhash@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{hostname}}@$hostname@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{timezone}}@$timezone@g" $tmp/iso_new/preseed/$seed_file

# calculate checksum for seed file
seed_checksum=$(md5sum $tmp/iso_new/preseed/$seed_file)

# add the autoinstall option to the menu
sed -i "/label install/ilabel autoinstall\n\
  menu label ^Autoinstall Ubuntu Server\n\
  kernel /install/vmlinuz\n\
  append file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/${seed_file} preseed/file/checksum=$seed_checksum --" $tmp/iso_new/isolinux/txt.cfg


echo " creating the remastered iso"
cd $tmp/iso_new
(mkisofs -D -r -V "Ubuntu unattended server" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $tmp/$new_iso_name . > /dev/null 2>&1) &
sleep 15

# make iso bootable (for dd'ing to  USB stick)
if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
    isohybrid $tmp/$new_iso_name
fi

# cleanup
umount $tmp/iso_org
rm -rf $tmp/iso_new
rm -rf $tmp/iso_org
rm -rf $tmphtml

# print info to user
echo " -----"
echo " finished remastering your ubuntu iso file"
echo " the new file is located at: $tmp/$new_iso_name"
echo " your username is: $username"
echo " your password is: $password"
echo " your hostname is: $hostname"
echo " your timezone is: $timezone"
echo

# unset vars
unset username
unset password
unset password2
unset hostname
unset timezone
unset pwhash
unset download_file
unset download_location
unset new_iso_name
unset tmp
unset seed_file
