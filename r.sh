#!/usr/bin/env bash
# =============================================================================
# LeakOS Linux Installer (MBR/BIOS ONLY - NO EFI)
# =============================================================================

set -euo pipefail

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
# BANNER & CEK BIOS
# =============================================================================
# Cek apakah booting dalam mode UEFI
if [ -d /sys/firmware/efi ]; then
    zenity --error --title="❌ UEFI DETECTED" \
        --text="ANDA BOOTING DALAM MODE UEFI!\n\nScript ini KHUSUS UNTUK MBR/BIOS.\n\nSolusi:\n1. Restart komputer\n2. Masuk BIOS\n3. Disable UEFI / Enable CSM\n4. Set boot mode ke Legacy/BIOS\n\nAtau gunakan VM dengan BIOS/Legacy mode."
    exit 1
fi

zenity --info --title="LeakOS Installer (MBR ONLY)" --width=450 --text="
╔══════════════════════════════════════╗
║     LEAKOS LINUX - MBR/BIOS MODE     ║
╚══════════════════════════════════════╝

💻 MODE: LEGACY / BIOS / MBR
🚫 TIDAK MENDUKUNG UEFI
⚠️  SEMUA DATA AKAN DIHAPUS

Pastikan:
✅ Booting mode: BIOS/Legacy (bukan UEFI)
✅ Disk akan dipartisi sebagai MBR/DOS
✅ GRUB akan diinstall ke MBR

Klik OK untuk lanjut
"

# =============================================================================
# DISK SELECT
# =============================================================================
TARGET_DISK=$(zenity --list \
    --title="💾 Pilih Disk Target (MBR)" \
    --radiolist \
    --column "Pilih" --column "Disk" --column "Ukuran" --column "Model" \
    $(lsblk -dno NAME,SIZE,MODEL,TYPE | awk '$4=="disk"{print "FALSE /dev/"$1" "$2" "$3}') \
    --width=600 --height=300) || exit 1

[ -b "$TARGET_DISK" ] || exit 1

# =============================================================================
# KONFIRMASI
# =============================================================================
zenity --question --title="⚠️  Konfirmasi Penghapusan Data" \
    --text="DISK TARGET: $TARGET_DISK\nMODE: MBR/BIOS (LEGACY)\n\nSEMUA DATA DI DISK INI AKAN DIHAPUS!\n\nLanjutkan?" \
    --width=400 || exit 0

# =============================================================================
# PARTITIONING MBR
# =============================================================================
zenity --info --title="📋 Petunjuk Partisi MBR" \
    --text="PARTISI UNTUK MBR/BIOS:\n\n1. Pilih 'dos' untuk partition table\n2. Buat partisi:\n   - Minimal 1 partisi EXT4 (root)\n   - Boleh tambah swap (opsional)\n3. SET BOOTABLE FLAG pada partisi root\n4. Write perubahan\n\n⚠️ JANGAN buat partisi EFI system partition!" \
    --width=500

# Jalankan cfdisk
cfdisk "$TARGET_DISK"
partprobe "$TARGET_DISK"
sleep 3
sync

# =============================================================================
# DETECT PARTITIONS (MBR ONLY)
# =============================================================================
ROOT_PART=""
SWAP_PART=""

echo "🔍 Mendeteksi partisi pada $TARGET_DISK..."

# Loop untuk baca partisi
while read -r part_name fstype size; do
    full_path="/dev/$part_name"
    
    # Skip disk itu sendiri
    [[ "$full_path" == "$TARGET_DISK" ]] && continue
    
    # Cek apakah partisi bootable?
    bootable=$(fdisk -l "$TARGET_DISK" | grep "$full_path" | grep -i "Boot" || true)
    
    # Deteksi swap
    if [[ "$fstype" == "swap" ]] || [[ "$fstype" == "linux-swap" ]]; then
        SWAP_PART="$full_path"
        echo "✅ Swap partition: $full_path"
    
    # Deteksi root (ext4 atau partisi dengan boot flag)
    elif [[ "$fstype" == "ext4" ]] || [[ "$fstype" == "ext3" ]] || [[ "$fstype" == "ext2" ]] || [[ -n "$bootable" ]]; then
        ROOT_PART="$full_path"
        echo "✅ Root partition: $full_path (bootable: ${bootable:-no})"
    fi
    
done < <(lsblk -ln -o NAME,FSTYPE,SIZE "$TARGET_DISK" | grep -v "^$(basename $TARGET_DISK)$")

# Fallback: ambil partisi pertama
if [ -z "$ROOT_PART" ]; then
    FIRST_PART=$(lsblk -ln -o NAME "$TARGET_DISK" | grep -v "^$(basename $TARGET_DISK)$" | head -1)
    if [ -n "$FIRST_PART" ]; then
        ROOT_PART="/dev/$FIRST_PART"
        echo "⚠️  Fallback: menggunakan $ROOT_PART sebagai root"
    fi
fi

# Validasi root partition
[ -b "$ROOT_PART" ] || {
    zenity --error --title="❌ Partisi Error" \
        --text="Root partition TIDAK ditemukan!\n\nPastikan Anda sudah membuat minimal 1 partisi EXT4 dan menulis perubahannya di cfdisk."
    exit 1
}

# =============================================================================
# USER INPUT
# =============================================================================
USERNAME=$(zenity --entry --title="👤 Username" --text="Masukkan username:" --entry-text="leakos") || exit 1
[ -z "$USERNAME" ] && USERNAME="leakos"

HOSTNAME=$(zenity --entry --title="💻 Hostname" --text="Masukkan hostname:" --entry-text="leakos") || exit 1
[ -z "$HOSTNAME" ] && HOSTNAME="leakos"

while true; do
    PASSWORD=$(zenity --password --title="🔑 Password" --text="Masukkan password untuk $USERNAME:") || exit 1
    PASSWORD2=$(zenity --password --title="🔑 Konfirmasi Password" --text="Ketik ulang password:") || exit 1
    
    if [ "$PASSWORD" = "$PASSWORD2" ] && [ -n "$PASSWORD" ]; then
        break
    else
        zenity --error --title="❌ Error" --text="Password tidak cocok atau kosong!\nCoba lagi."
    fi
done

# =============================================================================
# PROSES INSTALASI
# =============================================================================
(
echo 0; echo "# Memulai instalasi..."
sleep 1

# -----------------------------------------------------------------------------
echo 5; echo "# 🔨 Format partisi root..."
# -----------------------------------------------------------------------------
mkfs.ext4 -F -L "LeakOS" "$ROOT_PART" >/dev/null 2>&1 || {
    echo "Format gagal!"
    exit 1
}

# -----------------------------------------------------------------------------
echo 10; echo "# 📁 Mount partisi root..."
# -----------------------------------------------------------------------------
mkdir -p /mnt/leakos
mount "$ROOT_PART" /mnt/leakos || {
    echo "Mount gagal!"
    exit 1
}

# -----------------------------------------------------------------------------
echo 15; echo "# 💤 Setup swap..."
# -----------------------------------------------------------------------------
if [ -n "$SWAP_PART" ]; then
    mkswap "$SWAP_PART" >/dev/null 2>&1
    swapon "$SWAP_PART" 2>/dev/null || true
    echo "✅ Swap terdeteksi: $SWAP_PART"
fi

# -----------------------------------------------------------------------------
echo 20; echo "# 📦 Menyalin system (ini agak lama)..."
# -----------------------------------------------------------------------------
rsync -aHAX --info=progress2 --no-inc-recursive \
    --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/boot/efi"} \
    / /mnt/leakos/ 2>&1 | while read -r line; do
    if [[ "$line" =~ ([0-9]+)% ]]; then
        percent=${BASH_REMATCH[1]}
        # Mapping rsync progress 20-50%
        prog=$((20 + percent * 30 / 100))
        echo "$prog"
        echo "# Menyalin file... $percent%"
    fi
done

# -----------------------------------------------------------------------------
echo 50; echo "# 🧠 Mengcopy kernel..."
# -----------------------------------------------------------------------------
mkdir -p /mnt/leakos/boot

# Copy kernel dan initramfs
cp -f /boot/vmlinuz-* /mnt/leakos/boot/ 2>/dev/null || true
cp -f /boot/initrd.img-* /mnt/leakos/boot/ 2>/dev/null || true
cp -f /boot/initramfs-* /mnt/leakos/boot/ 2>/dev/null || true

# Fallback
if ! ls /mnt/leakos/boot/vmlinuz-* >/dev/null 2>&1; then
    cp -f /run/media/*/boot/vmlinuz-* /mnt/leakos/boot/ 2>/dev/null || true
    cp -f /run/media/*/boot/initrd.img-* /mnt/leakos/boot/ 2>/dev/null || true
    cp -f /run/media/*/boot/initramfs-* /mnt/leakos/boot/ 2>/dev/null || true
fi

# Cek kernel
if ! ls /mnt/leakos/boot/vmlinuz-* >/dev/null 2>&1; then
    echo "❌ KERNEL TIDAK DITEMUKAN!"
    exit 1
fi

# -----------------------------------------------------------------------------
echo 60; echo "# 🔧 Setup system..."
# -----------------------------------------------------------------------------
# Mount virtual filesystem
mount --bind /dev /mnt/leakos/dev
mount --bind /dev/pts /mnt/leakos/dev/pts
mount --bind /proc /mnt/leakos/proc
mount --bind /sys /mnt/leakos/sys
mount --bind /run /mnt/leakos/run

# -----------------------------------------------------------------------------
echo 65; echo "# ⚙️  Konfigurasi system..."
# -----------------------------------------------------------------------------
chroot /mnt/leakos /bin/bash <<EOF
# Hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
127.0.1.1   $HOSTNAME
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
HOSTS

# User
useradd -m -G users,wheel,audio,video,cdrom,plugdev -s /bin/bash "$USERNAME" 2>/dev/null || true
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Fstab
UUID=\$(blkid -s UUID -o value "$ROOT_PART")
cat > /etc/fstab <<FSTAB
# /etc/fstab: LeakOS MBR/BIOS
UUID=\$UUID / ext4 defaults,noatime,errors=remount-ro 0 1
FSTAB
EOF

# Tambah swap ke fstab
if [ -n "$SWAP_PART" ]; then
    chroot /mnt/leakos /bin/bash <<EOF
SWAP_UUID=\$(blkid -s UUID -o value "$SWAP_PART")
echo "UUID=\$SWAP_UUID none swap sw 0 0" >> /etc/fstab
EOF
fi

# -----------------------------------------------------------------------------
echo 75; echo "# 📀 Install GRUB ke MBR..."
# -----------------------------------------------------------------------------
# Config GRUB untuk MBR
cat > /mnt/leakos/etc/default/grub <<'GRUB'
# GRUB untuk MBR/BIOS - LeakOS
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="LeakOS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL_INPUT="console"
GRUB_TERMINAL_OUTPUT="console"
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_DISABLE_LINUX_UUID=false
GRUB_DISABLE_RECOVERY=false
GRUB_DISABLE_OS_PROBER=false
GRUB_ENABLE_CRYPTODISK=n
GRUBUB

# Install GRUB ke MBR
chroot /mnt/leakos grub-install \
    --target=i386-pc \
    --force \
    --recheck \
    --boot-directory=/boot \
    "$TARGET_DISK" 2>&1

if [ $? -ne 0 ]; then
    echo "❌ GRUB install gagal!"
    exit 1
fi

# -----------------------------------------------------------------------------
echo 85; echo "# 📝 Generate GRUB config..."
# -----------------------------------------------------------------------------
chroot /mnt/leakos grub-mkconfig -o /boot/grub/grub.cfg 2>&1

# -----------------------------------------------------------------------------
echo 90; echo "# 🔄 Finalisasi..."
# -----------------------------------------------------------------------------
# Fix symlinks
chroot /mnt/leakos /bin/bash <<EOF
cd /boot
[ -f vmlinuz-* ] && ln -sf vmlinuz-* vmlinuz 2>/dev/null || true
[ -f initrd.img-* ] && ln -sf initrd.img-* initrd.img 2>/dev/null || true
[ -f initramfs-* ] && ln -sf initramfs-* initramfs 2>/dev/null || true
EOF

# Regenerate initramfs (Debian/Ubuntu)
if [ -f /mnt/leakos/etc/debian_version ]; then
    chroot /mnt/leakos update-initramfs -u -k all 2>/dev/null || true
fi

# Regenerate GRUB sekali lagi
chroot /mnt/leakos grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null

sync
sleep 2

# -----------------------------------------------------------------------------
echo 95; echo "# 🧹 Cleanup..."
# -----------------------------------------------------------------------------
# Unmount
umount -l /mnt/leakos/dev/pts 2>/dev/null || true
umount -l /mnt/leakos/dev 2>/dev/null || true
umount -l /mnt/leakos/proc 2>/dev/null || true
umount -l /mnt/leakos/sys 2>/dev/null || true
umount -l /mnt/leakos/run 2>/dev/null || true
umount -l /mnt/leakos 2>/dev/null || true

# -----------------------------------------------------------------------------
echo 100; echo "# ✅ SELESAI!"
# -----------------------------------------------------------------------------

) | zenity --progress \
    --title="📀 LeakOS Installer (MBR/BIOS)" \
    --text="Memulai instalasi..." \
    --percentage=0 \
    --auto-close \
    --width=600

# =============================================================================
# FINISH
# =============================================================================
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    zenity --info --title="✅ Instalasi Berhasil" \
        --text="LEAKOS LINUX (MBR/BIOS MODE)\n━━━━━━━━━━━━━━━━━━━━━━━\n\n✔️ Sistem terinstall: $TARGET_DISK\n✔️ Root partition: $ROOT_PART\n✔️ GRUB di MBR: $TARGET_DISK\n\n💡 INSTRUKSI:\n1. Cabut live USB\n2. Reboot\n3. Boot dari hard disk\n\n⚠️ Pastikan BIOS boot mode: LEGACY/CSM" \
        --width=500
else
    zenity --error --title="❌ Instalasi Gagal" \
        --text="Instalasi GAGAL!\n\nCek log:\n- /tmp/grub_install.log\n- /tmp/grub_config.log"
fi

exit 0
