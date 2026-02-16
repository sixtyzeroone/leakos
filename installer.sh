#!/usr/bin/env bash
# =============================================================================
# LeakOS Linux Installer (ZENITY + BOOTABLE FIX + MBR (BIOS) + Lokasi dan Keyboard)
# =============================================================================

set -euo pipefail

# =============================================================================
# BANNER - INTRO
# =============================================================================
zenity --info --title="LeakOS Installer" --width=420 --height=300 --text="
╔════════════════════════════════════════════════════════════╗
║                  L E A K O S   L I N U X                  ║
║     Unleashed Freedom • Privacy First • Indonesian Root    ║
║          Custom LFS Distro - Pentest / Developer Ready     ║
╚════════════════════════════════════════════════════════════╝

Ini adalah Installer LeakOS.
Klik OK untuk memulai instalasi.
"

# =============================================================================
# ENV FIX
# =============================================================================
export GTK_THEME=Adwaita
export NO_AT_BRIDGE=1
export XDG_DATA_DIRS=/usr/share:/usr/share/icons

# =============================================================================
# ROOT CHECK
# =============================================================================
if [ "$(id -u)" -ne 0 ]; then
    zenity --error --title="LeakOS Installer" \
        --text="Installer harus dijalankan sebagai root!"
    exit 1
fi

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================
for cmd in zenity lsblk cfdisk mkfs.ext4 rsync grub-install grub-mkconfig; do
    command -v "$cmd" >/dev/null 2>&1 || {
        zenity --error --text="Dependency hilang: $cmd"
        exit 1
    }
done

# =============================================================================
# BANNER - KONFIRMASI
# =============================================================================
zenity --info --title="LeakOS Installer" --width=420 --text="
LeakOS Linux Installer

⚠️ PERINGATAN:
• SEMUA DATA AKAN DIHAPUS
• Gunakan mesin kosong / VM

Klik OK untuk lanjut
"

# =============================================================================
# DISK SELECT
# =============================================================================
TARGET_DISK=$(zenity --list \
    --title="Pilih Disk Target" \
    --radiolist \
    --column "Pilih" --column "Disk" --column "Ukuran" \
    $(lsblk -dno NAME,SIZE,TYPE | awk '$3=="disk"{print "FALSE /dev/"$1" "$2}') \
    --width=500 --height=300) || exit 1

[ -b "$TARGET_DISK" ] || exit 1

# =============================================================================
# CONFIRM
# =============================================================================
zenity --question --title="Konfirmasi" --text="
Disk: $TARGET_DISK
SEMUA DATA AKAN DIHAPUS

Lanjutkan?" || exit 0

# =============================================================================
# PARTITIONING (MBR)
# =============================================================================
zenity --info --title="Partisi" --text="
BIOS (MBR):
- DOS
- 1 Linux filesystem
"

cfdisk "$TARGET_DISK"
partprobe "$TARGET_DISK"
sleep 2

# =============================================================================
# DETECT PARTITIONS
# =============================================================================
ROOT_PART=""

while read -r name fstype size; do
    if [[ "$fstype" != "ext4" ]]; then
        ROOT_PART="/dev/$name"
    fi
done < <(lsblk -ln -o NAME,FSTYPE,SIZE "$TARGET_DISK" | tail -n +2)

[ -b "$ROOT_PART" ] || {
    zenity --error --text="Root partition tidak ditemukan"
    exit 1
}

# =============================================================================
# USER INPUT
# =============================================================================
USERNAME=$(zenity --entry --title="User" --text="Username" --entry-text="leakos") || exit 1
HOSTNAME=$(zenity --entry --title="Hostname" --text="Hostname" --entry-text="leakos") || exit 1
PASSWORD=$(zenity --password --title="Password") || exit 1
PASSWORD2=$(zenity --password --title="Konfirmasi") || exit 1

[ "$PASSWORD" = "$PASSWORD2" ] || {
    zenity --error --text="Password tidak cocok"
    exit 1
}

# =============================================================================
# LOCATION AND KEYBOARD CONFIGURATION
# =============================================================================
# Lokasi / Timezone
TIMEZONE=$(zenity --list --title="Pilih Waktu" --column="Pilih" \
    $(timedatectl list-timezones) --height=500 --width=500) || exit 1

# Keyboard Layout
KEYBOARD_LAYOUT=$(zenity --list --title="Pilih Layout Keyboard" --column="Pilih" \
    "us" "United States" \
    "id" "Indonesia" \
    "fr" "France" \
    "de" "Germany" \
    "es" "Spain" \
    "it" "Italy" \
    "pt" "Portugal" \
    "se" "Sweden" \
    "no" "Norway" \
    "dk" "Denmark" \
    "fi" "Finland" \
    "pl" "Poland" \
    "ru" "Russia" \
    "ua" "Ukraine" \
    "cz" "Czech Republic" \
    "tr" "Turkey" \
    "cn" "China" \
    "jp" "Japan" \
    "kr" "South Korea" \
    "vn" "Vietnam" \
    "br" "Brazil" \
    "ph" "Philippines" \
    "sg" "Singapore" \
    --height=500 --width=500) || exit 1

# =============================================================================
# INSTALL
# =============================================================================
(
echo 5;  echo "# Format root"
mkfs.ext4 -F "$ROOT_PART" >/dev/null

echo 15; echo "# Mount root"
mkdir -p /mnt/leakos
mount "$ROOT_PART" /mnt/leakos

echo 35; echo "# Copy system"
rsync -aHAX / /mnt/leakos \
--exclude={/dev/*,/proc/*,/sys/*,/run/*,/tmp/*,/mnt/*,/media/*,/lost+found}

# =============================================================================
# KERNEL FIX (INSTALL KERNEL DARI ISO)
# =============================================================================
echo 55; echo "# Install kernel"
mkdir -p /mnt/leakos/boot

cp -v /boot/vmlinuz* /mnt/leakos/boot/ 2>/dev/null || true
cp -v /boot/initrd.img-5.16.16* /mnt/leakos/boot/ 2>/dev/null || true
#cp -v /run/media/*/boot/vmlinuz* /mnt/leakos/boot/ 2>/dev/null || true
#cp -v /run/media/*/boot/initramfs* /mnt/leakos/boot/ 2>/dev/null || true

ls /mnt/leakos/boot/vmlinuz* >/dev/null 2>&1 || {
    zenity --error --text="Kernel tidak ditemukan!\nInstaller dihentikan."
    exit 1
}

# =============================================================================
# SYSTEM SETUP
# =============================================================================
echo 70; echo "# Setup system"
mount --bind /dev  /mnt/leakos/dev
mount --bind /proc /mnt/leakos/proc
mount --bind /sys  /mnt/leakos/sys
mount --bind /dev/pts /mnt/leakos/dev/pts   # Tambah ini untuk stabilitas chroot

chroot /mnt/leakos /bin/bash <<EOF
echo "$HOSTNAME" > /etc/hostname
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

# Set timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
# Set locale
#echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
#locale-gen

# Set keyboard layout
#localectl set-keymap $KEYBOARD_LAYOUT

ROOT_UUID=\$(blkid -s UUID -o value "$ROOT_PART")

cat > /etc/fstab <<EOT
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a device; this may
# be used with UUID= as a more robust way to name devices that works even if
# disks are added and removed. See fstab(5).

# Root filesystem (ext4)
UUID=\$ROOT_UUID    /               ext4    defaults        0       1
EOF

# =============================================================================
# GRUB INSTALL (BIOS / MBR)
# =============================================================================
echo 85; echo "# Install GRUB (BIOS)"
chroot /mnt/leakos grub-install \
    --target=i386-pc --recheck "$TARGET_DISK"

chroot /mnt/leakos grub-mkconfig -o /boot/grub/grub.cfg

echo 100; echo "# Selesai"
) | zenity --progress --title="LeakOS Installer" --percentage=0 --auto-close

# =============================================================================
# FINISH
# =============================================================================
sync
umount -R /mnt/leakos || true

# =============================================================================
# BANNER - FINAL
# =============================================================================
zenity --info --title="LeakOS Installer" --width=420 --text="
╔════════════════════════════════════════════════════════════╗
║                  L E A K O S   L I N U X                  ║
║             Instalasi Selesai • Reboot untuk memulai       ║
╚════════════════════════════════════════════════════════════╝
"

zenity --info --title="LeakOS Installer" \
--text="Instalasi selesai!\nSilakan reboot."

exit 0
