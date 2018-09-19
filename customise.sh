
#!/bin/bash
echo "Enter the name of the ISO, for example: ubuntu-18.04.1-desktop-amd64.iso"
read iso

echo "Enter the name of the distro, for example: ubuntu-18.04.1-desktop-amd64"
read distro

echo "Enter the official name of the volume, for example: Ubuntu 18.04.1 LTS"
read volume

echo "Copying $distro to working directory..."
mkdir $distro
cp $iso $distro
cd $distro
mkdir mnt
echo "Mounting the .iso as 'mnt' in the local directory. Password-up, please."
sudo mount -o loop $iso mnt

mkdir extract-cd
sudo rsync --exclude=/casper/filesystem.squashfs -a mnt/ extract-cd
sudo dd if=$iso bs=512 count=1 of=extract-cd/isolinux/isohdpfx.bin
sudo unsquashfs mnt/casper/filesystem.squashfs
sudo mv squashfs-root edit

sudo umount mnt

rm $iso

sudo cp /etc/resolv.conf edit/etc/
sudo mount --bind /dev/ edit/dev

cat << EOF | sudo chroot chroot

mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts

export HOME=/root
export LC_ALL=C
dbus-uuidgen > /var/lib/dbus/machine-id
dpkg-divert --local --rename --add /sbin/initctl
ln -s /bin/true /sbin/initctl

echo "deb http://gb.archive.ubuntu.com/ubuntu/ bionic universe" | sudo tee -a /etc/apt/sources.list

add-apt-repository ppa:starlabs/ppa -y
apt update
apt upgrade -y
apt dist-upgrade -y
apt install intel-microcode -y
apt install starlabs-custom -y
apt autoremove -y

sed -i 's#deb http://gb.archive.ubuntu.com/ubuntu/ bionic universe##g' /etc/apt/sources.list
rm -rf /tmp/* ~/.bash_history
rm /var/lib/dbus/machine-id
rm /sbin/initctl

dpkg-divert --rename --remove /sbin/initctl

umount /proc || umount -lf /proc
umount /sys
umount /dev/pts


exit

EOF



if [ $(dpkg-query -W -f='${Status}' xorriso 2>/dev/null | grep -c "ok installed") -eq 0 ];
then
 sudo apt install xorriso;
fi



cd $distro
sudo umount edit/dev

echo "Regenerate the manifest"
 
sudo chmod +w extract-cd/casper/filesystem.manifest
sudo chroot edit dpkg-query -W --showformat='${Package} ${Version}\n' | sudo tee extract-cd/casper/filesystem.manifest
sudo cp extract-cd/casper/filesystem.manifest extract-cd/casper/filesystem.manifest-desktop
sudo sed -i '/ubiquity/d' extract-cd/casper/filesystem.manifest-desktop
sudo sed -i '/casper/d' extract-cd/casper/filesystem.manifest-desktop

sudo mksquashfs edit extract-cd/casper/filesystem.squashfs -b 1048576

printf $(sudo du -sx --block-size=1 edit | cut -f1) | sudo tee extract-cd/casper/filesystem.size

cd extract-cd
sudo rm md5sum.txt
find -type f -print0 | sudo xargs -0 md5sum | grep -v isolinux/boot.cat | sudo tee md5sum.txt

sudo xorriso -as mkisofs -isohybrid-mbr isolinux/isohdpfx.bin -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img -volid "$volume" -no-emul-boot -isohybrid-gpt-basdat -o ../../$distro-sls.iso .

sudo fdisk -lu ../../$distro-sls.iso

