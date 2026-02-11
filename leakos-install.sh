#!/usr/bin/env bash
# =============================================================================
# LeakOS Linux - LiveCD → HDD Installer (VIRTUALBOX FIX - FINAL)
# =============================================================================

set -euo pipefail

# Banner
LEAKOS_BANNER="
╔════════════════════════════════════════════════════════════╗
║                  L E A K O S   L I N U X                  ║
║     Unleashed Freedom • Privacy First • Indonesian Root    ║
║          Custom LFS Distro - Pentest / Developer Ready     ║
╚════════════════════════════════════════════════════════════╝
"

# Fix untuk VirtualBox
export GTK_THEME=Adwaita
export NO_AT_BRIDGE=1

# Cek root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Jalankan sebagai root!"
    exit 1
fi

# Cek dependencies
command -v zenity >/dev/null 2>&1 || { echo "Zenity tidak ditemukan!"; exit 1; }
command -v cfdisk >/dev/null 2>&1 || { echo "cfdisk tidak ditemukan!"; exit 1; }

# =============================================================================
# VIRTUALBOX FIX - METODE SEDERHANA & PASTI BERHASIL
# =============================================================================

echo ""
echo "$LEAKOS_BANNER"
echo ""
echo "=================================================="
echo "  LEAKOS INSTALLER - VIRTUALBOX EDITION"
echo "=================================================="
echo ""

# TAMPILAN SEDERHANA - PAKAI DIALOG BUKAN ZENITY DULU
echo "Mendeteksi hard disk di VirtualBox..."
echo ""

# Method: Ambil disk pertama yang BUKAN sr0 dan BUKAN loop
TARGET_DISK=""
while read -r disk; do
    if [[ "$disk" != "sr0" ]] && [[ "$disk" != "loop"* ]] && [[ "$disk" != "ram"* ]]; then
        TARGET_DISK="/dev/$disk"
        break
    fi
done < <(lsblk -dno NAME | head -5)

# Fallback: coba paksa pakai /dev/sda
if [ -z "$TARGET_DISK" ] || [ ! -b "$TARGET_DISK" ]; then
    if [ -b "/dev/sda" ]; then
        TARGET_DISK="/dev/sda"
    elif [ -b "/dev/vda" ]; then
        TARGET_DISK="/dev/vda"
    elif [ -b "/dev/hda" ]; then
        TARGET_DISK="/dev/hda"
    fi
fi

# Validasi
if [ -z "$TARGET_DISK" ] || [ ! -b "$TARGET_DISK" ]; then
    echo "ERROR: TIDAK ADA HARD DISK DITEMUKAN!"
    echo ""
    echo "Available devices:"
    lsblk -dno NAME,SIZE,TYPE | grep -v "rom\|loop"
    echo ""
    echo "Pastikan VirtualBox sudah menambahkan hard disk!"
    echo "Settings → Storage → Controller SATA → Add hard disk"
    exit 1
fi

echo "✅ Hard disk terdeteksi: $TARGET_DISK"
echo "   Size: $(lsblk -dno SIZE "$TARGET_DISK" 2>/dev/null || echo "Unknown")"
echo "   Model: $(lsblk -dno MODEL "$TARGET_DISK" 2>/dev/null || echo "Virtual Box")"
echo ""

# =============================================================================
# KONFIRMASI MANUAL
# =============================================================================

echo "⚠️  PERINGATAN: Semua data di $TARGET_DISK akan DIHAPUS!"
echo ""
read -p "Lanjutkan instalasi? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Instalasi dibatalkan."
    exit 0
fi
echo ""

# =============================================================================
# JALANKAN CFDISK
# =============================================================================

echo "Membuka cfdisk untuk partisi..."
echo "Panduan partisi VirtualBox:"
echo "  1. Pilih [gpt] untuk UEFI"
echo "  2. [New] → 512M → Type: EFI System"
echo "  3. [New] → sisa space → Type: Linux filesystem"
echo "  4. [Write] → ketik 'yes' → [Quit]"
echo ""
read -p "Tekan Enter untuk melanjutkan ke cfdisk..."
cfdisk "$TARGET_DISK"

# Tunggu partisi terdeteksi
partprobe "$TARGET_DISK" 2>/dev/null || true
sleep 3
echo ""

# =============================================================================
# DETEKSI PARTISI
# =============================================================================

echo "Mendeteksi partisi yang telah dibuat..."

# Deteksi partisi root (cari partisi terbesar yang bukan EFI)
ROOT_PART=""
EFI_PART=""

while read -r part; do
    part_path="/dev/$part"
    part_size=$(lsblk -dno SIZE "$part_path" 2>/dev/null | sed 's/G//g' | sed 's/M//g')
    part_fstype=$(lsblk -dno FSTYPE "$part_path" 2>/dev/null)
    part_label=$(lsblk -dno LABEL "$part_path" 2>/dev/null)
    
    # Deteksi EFI partition (biasanya 512M dan type vfat/efi)
    if [[ "$part_size" == "512" ]] || [[ "$part_fstype" == "vfat" ]] || [[ "$part_label" == "EFI"* ]]; then
        EFI_PART="$part_path"
        echo "✅ EFI partition terdeteksi: $EFI_PART"
    else
        # Ambil partisi terbesar sebagai root
        if [[ "$part_size" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            if [ -z "$ROOT_PART" ]; then
                ROOT_PART="$part_path"
            else
                current_size=$(lsblk -dno SIZE "${ROOT_PART}" | sed 's/G//g')
                if (( $(echo "$part_size > $current_size" | bc -l 2>/dev/null || echo "0") )); then
                    ROOT_PART="$part_path"
                fi
            fi
        fi
    fi
done < <(lsblk "${TARGET_DISK}" -lno NAME 2>/dev/null | grep -v "^${TARGET_DISK#/dev/}$")

# Fallback: ambil partisi kedua (biasanya root)
if [ -z "$ROOT_PART" ]; then
    ROOT_PART="${TARGET_DISK}1"
    if [ -b "${TARGET_DISK}2" ]; then
        ROOT_PART="${TARGET_DISK}2"
    elif [ -b "${TARGET_DISK}5" ]; then
        ROOT_PART="${TARGET_DISK}5"
    fi
fi

if [ ! -b "$ROOT_PART" ]; then
    echo "ERROR: Partisi root tidak ditemukan!"
    echo "Jalankan cfdisk dulu untuk membuat partisi!"
    exit 1
fi

echo "✅ Partisi root: $ROOT_PART"
echo "✅ Partisi EFI: ${EFI_PART:-Tidak ada (Legacy mode)}"
echo ""

# =============================================================================
# INPUT KONFIGURASI (SEDERHANA)
# =============================================================================

echo "=================================================="
echo "  KONFIGURASI SISTEM"
echo "=================================================="
echo ""

read -p "Username [leakos]: " USERNAME
USERNAME=${USERNAME:-leakos}

while true; do
    read -s -p "Password: " PASSWORD
    echo ""
    read -s -p "Konfirmasi Password: " PASSWORD2
    echo ""
    if [ "$PASSWORD" = "$PASSWORD2" ] && [ -n "$PASSWORD" ]; then
        break
    else
        echo "❌ Password tidak cocok atau kosong!"
    fi
done

read -p "Hostname [leakos-vb]: " HOSTNAME
HOSTNAME=${HOSTNAME:-leakos-vb}

echo ""

# =============================================================================
# KONFIRMASI INSTALASI
# =============================================================================

echo "=================================================="
echo "  RINGKASAN INSTALASI"
echo "=================================================="
echo "Disk: $TARGET_DISK"
echo "Partisi Root: $ROOT_PART (akan DIFORMAT ext4)"
echo "Partisi EFI: ${EFI_PART:-Tidak ada (Legacy/BIOS)}"
echo "Username: $USERNAME"
echo "Hostname: $HOSTNAME"
echo ""
echo "⚠️  PERINGATAN: Semua data di $ROOT_PART akan dihapus!"
echo ""
read -p "INSTALASI SEKARANG? (yes/no): " install_confirm
if [ "$install_confirm" != "yes" ]; then
    echo "Instalasi dibatalkan."
    exit 0
fi
echo ""

# =============================================================================
# PROSES INSTALASI
# =============================================================================

echo "=================================================="
echo "  MULAI INSTALASI..."
echo "=================================================="

# 1. Format root partition
echo "[1/8] Memformat $ROOT_PART sebagai ext4..."
mkfs.ext4 -F "$ROOT_PART" > /dev/null 2>&1 || { echo "❌ Gagal format!"; exit 1; }
echo "✅ Selesai"

# 2. Mount root partition
echo "[2/8] Mounting partisi..."
mkdir -p /mnt/leakos
mount "$ROOT_PART" /mnt/leakos || { echo "❌ Gagal mount!"; exit 1; }
echo "✅ Selesai"

# 3. Format dan mount EFI (jika ada)
if [ -n "$EFI_PART" ] && [ -d "/sys/firmware/efi" ]; then
    echo "[3/8] Memformat EFI partition..."
    mkdir -p /mnt/leakos/boot/efi
    mkfs.fat -F32 "$EFI_PART" > /dev/null 2>&1 || echo "⚠️  Gagal format EFI"
    mount "$EFI_PART" /mnt/leakos/boot/efi 2>/dev/null || echo "⚠️  Gagal mount EFI"
    echo "✅ Selesai"
fi

# 4. Copy system files
echo "[4/8] Menyalin system files (ini agak lama)..."
rsync -aHAX / /mnt/leakos/ \
    --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/cow/*,/squash/*,/lost+found,/boot/efi} \
    > /dev/null 2>&1 || { echo "❌ Gagal copy!"; exit 1; }
echo "✅ Selesai"

# 5. Setup fstab
echo "[5/8] Setup fstab..."
UUID_ROOT=$(blkid -s UUID -o value "$ROOT_PART")
cat > /mnt/leakos/etc/fstab << FSTAB
# LeakOS fstab
UUID=$UUID_ROOT / ext4 defaults,noatime 0 1
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
FSTAB

if [ -n "$EFI_PART" ] && [ -d "/sys/firmware/efi" ]; then
    UUID_EFI=$(blkid -s UUID -o value "$EFI_PART" 2>/dev/null || echo "")
    if [ -n "$UUID_EFI" ]; then
        echo "UUID=$UUID_EFI /boot/efi vfat defaults 0 2" >> /mnt/leakos/etc/fstab
    fi
fi
echo "✅ Selesai"

# 6. Chroot setup
echo "[6/8] Setup system di chroot..."
mount --bind /dev /mnt/leakos/dev
mount --bind /proc /mnt/leakos/proc
mount --bind /sys /mnt/leakos/sys
mount --bind /run /mnt/leakos/run
cp /etc/resolv.conf /mnt/leakos/etc/resolv.conf 2>/dev/null || true

chroot /mnt/leakos /bin/bash << CHROOT
    set -e
    
    # Hostname
    echo "$HOSTNAME" > /etc/hostname
    
    # Timezone
    ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
    
    # Locale
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen > /dev/null 2>&1
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    
    # User
    useradd -m -G wheel -s /bin/bash $USERNAME 2>/dev/null || true
    echo "$USERNAME:$PASSWORD" | chpasswd
    
    # Sudo
    echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel-group
    chmod 0440 /etc/sudoers.d/wheel-group
    
    # Network
    systemctl enable NetworkManager > /dev/null 2>&1 || true
CHROOT
echo "✅ Selesai"

# 7. Install GRUB
echo "[7/8] Install GRUB..."
if [ -n "$EFI_PART" ] && [ -d "/sys/firmware/efi" ]; then
    chroot /mnt/leakos grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=LeakOS --recheck > /dev/null 2>&1 || echo "⚠️  Gagal install GRUB EFI"
else
    chroot /mnt/leakos grub-install --target=i386-pc --recheck "$TARGET_DISK" > /dev/null 2>&1 || echo "⚠️  Gagal install GRUB BIOS"
fi
chroot /mnt/leakos grub-mkconfig -o /boot/grub/grub.cfg > /dev/null 2>&1 || echo "⚠️  Gagal generate grub.cfg"
echo "✅ Selesai"

# 8. Cleanup
echo "[8/8] Cleanup..."
sync
umount -R /mnt/leakos 2>/dev/null || true
echo "✅ Selesai"
echo ""

# =============================================================================
# SELESAI
# =============================================================================

echo "=================================================="
echo "  ✅ INSTALASI BERHASIL!"
echo "=================================================="
echo ""
echo "Detail Sistem:"
echo "  • Disk: $TARGET_DISK"
echo "  • Root: $ROOT_PART"
echo "  • Boot: ${EFI_PART:-Legacy/BIOS}"
echo "  • User: $USERNAME"
echo "  • Hostname: $HOSTNAME"
echo ""
echo "© 2025-2026 leakos.dev"
echo ""

read -p "Reboot sekarang? (yes/no): " reboot_confirm
if [ "$reboot_confirm" = "yes" ]; then
    echo "Rebooting..."
    reboot
else
    echo "Instalasi selesai! Silahkan reboot manual."
fi

exit 0
