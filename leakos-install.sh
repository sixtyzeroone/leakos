#!/usr/bin/env bash
# =============================================================================
# LeakOS Linux Installer (ZENITY SAFE VERSION)
# =============================================================================

set -eo pipefail

# =============================================================================
# ENV FIX (GTK + VIRTUALBOX)
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
    if ! command -v "$cmd" >/dev/null 2>&1; then
        zenity --error --title="LeakOS Installer" \
            --text="Dependency hilang: $cmd"
        exit 1
    fi
done

# =============================================================================
# BANNER
# =============================================================================
zenity --info --title="LeakOS Installer" --width=400 \
--text="\
LeakOS Linux Installer

⚠️ PERINGATAN:
• Semua data akan DIHAPUS
• Gunakan hanya di mesin kosong
• Direkomendasikan VirtualBox

Klik OK untuk lanjut"

# =============================================================================
# ZENITY DISK SELECT (ANTI NULL)
# =============================================================================
zenity_select_disk() {
    local output rc

    output=$(zenity --list \
        --title="Pilih Disk Target" \
        --text="Pilih hard disk tujuan instalasi\nSEMUA DATA AKAN DIHAPUS" \
        --radiolist \
        --column "Pilih" --column "Disk" --column "Ukuran" \
        $(lsblk -dno NAME,SIZE,TYPE | awk '$3=="disk"{print "FALSE /dev/"$1" "$2}') \
        --width=500 --height=300
    )
    rc=$?

    if [ $rc -ne 0 ] || [ -z "$output" ]; then
        return 1
    fi

    if [ ! -b "$output" ]; then
        return 1
    fi

    echo "$output"
}

if ! TARGET_DISK=$(zenity_select_disk); then
    zenity --error --title="LeakOS Installer" \
        --text="Tidak ada disk dipilih.\nInstalasi dibatalkan."
    exit 1
fi

# =============================================================================
# KONFIRMASI DISK
# =============================================================================
zenity --question --title="Konfirmasi Disk" --width=400 \
--text="\
Disk terpilih:
$TARGET_DISK

Ukuran: $(lsblk -dno SIZE "$TARGET_DISK")

SEMUA DATA AKAN DIHAPUS!

Lanjutkan?"

if [ $? -ne 0 ]; then
    exit 0
fi

# =============================================================================
# PARTITIONING
# =============================================================================
zenity --info --title="Partisi" --width=450 \
--text="\
Panduan cfdisk:

UEFI:
• GPT
• 512M EFI System
• Sisa Linux filesystem

BIOS:
• DOS
• 1 Linux filesystem

Klik OK untuk membuka cfdisk"

cfdisk "$TARGET_DISK"

partprobe "$TARGET_DISK" || true
sleep 3

# =============================================================================
# DETEKSI PARTISI ROOT & EFI
# =============================================================================
EFI_PART=""
ROOT_PART=""

while read -r part fstype size; do
    if [[ "$fstype" == "vfat" ]] || [[ "$size" == "512M" ]]; then
        EFI_PART="/dev/$part"
    else
        ROOT_PART="/dev/$part"
    fi
done < <(lsblk -ln -o NAME,FSTYPE,SIZE "$TARGET_DISK" | tail -n +2)

if [ ! -b "$ROOT_PART" ]; then
    zenity --error --title="LeakOS Installer" \
        --text="Partisi root tidak ditemukan!"
    exit 1
fi

# =============================================================================
# USER INPUT
# =============================================================================
USERNAME=$(zenity --entry --title="User" --text="Username:" --entry-text="leakos") || exit 1
HOSTNAME=$(zenity --entry --title="Hostname" --text="Hostname:" --entry-text="leakos-vb") || exit 1

PASSWORD=$(zenity --password --title="Password") || exit 1
PASSWORD2=$(zenity --password --title="Konfirmasi Password") || exit 1

if [ "$PASSWORD" != "$PASSWORD2" ] || [ -z "$PASSWORD" ]; then
    zenity --error --text="Password tidak cocok!"
    exit 1
fi

# =============================================================================
# FINAL CONFIRM
# =============================================================================
zenity --question --title="Mulai Instalasi?" --width=450 \
--text="\
Ringkasan:

Disk: $TARGET_DISK
Root: $ROOT_PART
EFI: ${EFI_PART:-Tidak ada}
User: $USERNAME
Hostname: $HOSTNAME

Mulai instalasi sekarang?"

if [ $? -ne 0 ]; then
    exit 0
fi

# =============================================================================
# INSTALLATION
# =============================================================================
(
echo "10"; echo "# Memformat root..."
mkfs.ext4 -F "$ROOT_PART" >/dev/null 2>&1

echo "30"; echo "# Mount root..."
mkdir -p /mnt/leakos
mount "$ROOT_PART" /mnt/leakos

if [ -n "$EFI_PART" ] && [ -d /sys/firmware/efi ]; then
    echo "40"; echo "# Setup EFI..."
    mkdir -p /mnt/leakos/boot/efi
    mkfs.fat -F32 "$EFI_PART" >/dev/null 2>&1
    mount "$EFI_PART" /mnt/leakos/boot/efi
fi

echo "55"; echo "# Copy system..."
rsync -aHAX / /mnt/leakos \
--exclude={/dev/*,/proc/*,/sys/*,/run/*,/tmp/*,/mnt/*,/media/*,/lost+found,/boot/efi}

echo "70"; echo "# Setup system..."
mount --bind /dev /mnt/leakos/dev
mount --bind /proc /mnt/leakos/proc
mount --bind /sys /mnt/leakos/sys

chroot /mnt/leakos /bin/bash <<EOF
echo "$HOSTNAME" > /etc/hostname
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
EOF

echo "85"; echo "# Install GRUB..."
if [ -n "$EFI_PART" ] && [ -d /sys/firmware/efi ]; then
    chroot /mnt/leakos grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=LeakOS
else
    chroot /mnt/leakos grub-install --target=i386-pc "$TARGET_DISK"
fi
chroot /mnt/leakos grub-mkconfig -o /boot/grub/grub.cfg

echo "100"; echo "# Selesai"
) | zenity --progress --title="LeakOS Installer" --percentage=0 --auto-close

# =============================================================================
# FINISH
# =============================================================================
sync
umount -R /mnt/leakos || true

zenity --info --title="LeakOS Installer" \
--text="Instalasi selesai!\nSilakan reboot."

exit 0
