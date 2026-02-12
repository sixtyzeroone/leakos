#!/usr/bin/env bash
# =============================================================================
# LeakOS Linux Installer - BIOS/MBR ONLY (No EFI)
# Fixed GRUB: --target=i386-pc, UUID, recheck, force, bind mounts lengkap
# Keyboard: localectl + fallback loadkeys
# =============================================================================
set -euo pipefail

# =============================================================================
# BANNER - INTRO
# =============================================================================
zenity --info --title="LeakOS Installer (BIOS/MBR)" --width=420 --height=300 --text="
╔════════════════════════════════════════════════════════════╗
║ L E A K O S L I N U X ║
║ BIOS/MBR ONLY • No EFI • Indonesian Root ║
║ Custom LFS Distro - Pentest / Developer Ready ║
╚════════════════════════════════════════════════════════════╝
Installer khusus BIOS/MBR (Legacy Boot).
Klik OK untuk mulai.
"

# =============================================================================
# ENV & ROOT CHECK
# =============================================================================
export GTK_THEME=Adwaita
export NO_AT_BRIDGE=1

if [ "$(id -u)" -ne 0 ]; then
    zenity --error --text="Jalankan sebagai root!"
    exit 1
fi

# Dependency
for cmd in zenity lsblk cfdisk mkfs.ext4 rsync grub-install grub-mkconfig blkid genfstab loadkeys; do
    command -v "$cmd" >/dev/null 2>&1 || {
        zenity --error --text="Dependency hilang: $cmd"
        exit 1
    }
done

# =============================================================================
# CONFIRM & DISK SELECT
# =============================================================================
zenity --info --title="Peringatan" --width=420 --text="
⚠️ SEMUA DATA DI DISK AKAN DIHAPUS!
Gunakan VM atau disk kosong.
BIOS/MBR only (Legacy Boot).
"

TARGET_DISK=$(zenity --list \
    --title="Pilih Disk Target (BIOS/MBR)" \
    --radiolist \
    --column "Pilih" --column "Disk" --column "Ukuran" \
    $(lsblk -dno NAME,SIZE,TYPE | awk '$3=="disk"{print "FALSE /dev/"$1" "$2}') \
    --width=500 --height=300) || exit 1

[ -b "$TARGET_DISK" ] || exit 1

zenity --question --title="Konfirmasi" --text="Disk: $TARGET_DISK\nSEMUA DATA DIHAPUS!\nLanjut?" || exit 0

# =============================================================================
# PARTITIONING (MBR/DOS)
# =============================================================================
zenity --info --title="Partisi" --text="
Gunakan cfdisk:
- Buat label DOS (MBR)
- Buat 1 partisi Linux (ext4) full disk atau sesuai kebutuhan
- Set bootable flag pada partisi root
"
cfdisk "$TARGET_DISK"
partprobe "$TARGET_DISK"
sleep 3

# Deteksi root partisi (ext4, non-vfat)
ROOT_PART=""
while read -r name fstype size; do
    if [[ "$fstype" == "ext"* ]]; then
        ROOT_PART="/dev/$name"
        break
    fi
done < <(lsblk -ln -o NAME,FSTYPE,SIZE "$TARGET_DISK" | tail -n +2)

[ -b "$ROOT_PART" ] || {
    zenity --error --text="Partisi root (ext4) tidak ditemukan!"
    exit 1
}

ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")

# =============================================================================
# USER INPUT
# =============================================================================
USERNAME=$(zenity --entry --title="Username" --entry-text="leakos") || exit 1
HOSTNAME=$(zenity --entry --title="Hostname" --entry-text="leakos") || exit 1
PASSWORD=$(zenity --password --title="Password") || exit 1
PASSWORD2=$(zenity --password --title="Konfirmasi Password") || exit 1

[ "$PASSWORD" = "$PASSWORD2" ] || {
    zenity --error --text="Password tidak cocok!"
    exit 1
}

TIMEZONE=$(zenity --list --title="Timezone" --column="Pilih" \
    $(timedatectl list-timezones) --height=500) || exit 1

KEYBOARD_LAYOUT=$(zenity --list --title="Keyboard Layout" --column="Pilih" \
    "us" "United States" \
    "id" "Indonesia" \
    "fr" "France" \
    "de" "Germany" \
    --height=400) || exit 1

# =============================================================================
# INSTALL PROCESS
# =============================================================================
(
echo 5; echo "# Format partisi"
mkfs.ext4 -F -L "LeakOS" "$ROOT_PART" >/dev/null

echo 15; echo "# Mount root"
mkdir -p /mnt/leakos
mount "$ROOT_PART" /mnt/leakos

echo 30; echo "# Copy sistem (rsync)"
rsync -aHAX --info=progress2 / /mnt/leakos \
    --exclude={/dev/*,/proc/*,/sys/*,/run/*,/tmp/*,/mnt/*,/media/*,/lost+found,/boot/*}

echo 45; echo "# Copy kernel & initramfs"
mkdir -p /mnt/leakos/boot
cp -av /boot/vmlinuz* /mnt/leakos/boot/ 2>/dev/null || true

if ! ls /mnt/leakos/boot/vmlinuz* >/dev/null 2>&1; then
    echo "Kernel tidak ditemukan!"
    exit 1
fi

echo 55; echo "# Bind mounts (untuk chroot)"
mount --types proc /proc /mnt/leakos/proc
mount --rbind /sys /mnt/leakos/sys
mount --make-rslave /mnt/leakos/sys
mount --rbind /dev /mnt/leakos/dev
mount --make-rslave /mnt/leakos/dev
mount --bind /run /mnt/leakos/run
mount --make-slave /mnt/leakos/run
mount --bind /dev/pts /mnt/leakos/dev/pts  # Penting untuk terminal di chroot

echo 70; echo "# Setup di chroot"
chroot /mnt/leakos /bin/bash <<EOF
echo "$HOSTNAME" > /etc/hostname

useradd -m -G wheel,audio,video -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
#locale-gen

# Keyboard
echo "KEYMAP=$KEYBOARD_LAYOUT" > /etc/vconsole.conf
#localectl set-keymap $KEYBOARD_LAYOUT || true
loadkeys $KEYBOARD_LAYOUT || true

# fstab dengan UUID
genfstab -U / > /etc/fstab

EOF

echo 85; echo "# Install GRUB BIOS/MBR"
chroot /mnt/leakos grub-install --target=i386-pc --recheck --force --boot-directory=/boot "$TARGET_DISK"

chroot /mnt/leakos grub-mkconfig -o /boot/grub/grub.cfg

echo 100; echo "# Selesai!"
) | zenity --progress --title="Instalasi LeakOS (BIOS/MBR)" --percentage=0 --auto-close --width=500

# Cleanup
sync
umount -R /mnt/leakos 2>/dev/null || true
rmdir /mnt/leakos 2>/dev/null || true

zenity --info --title="Selesai" --width=420 --text="
Instalasi LeakOS BIOS/MBR selesai!

Reboot VM:
- Cabut ISO dari VirtualBox
- Settings > System > Boot Order: Hard Disk pertama
- Pastikan BIOS (bukan UEFI) di VM settings

Selamat mencoba LeakOS!
"

exit 0
