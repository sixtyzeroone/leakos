#!/usr/bin/env bash
# =============================================================================
# LeakOS Linux - LiveCD → HDD Installer (VIRTUALBOX FIX)
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

# Fix untuk VirtualBox - Skip CD-ROM dan pilih HDD
export GTK_THEME=Adwaita
export NO_AT_BRIDGE=1

# Cek root
if [ "$(id -u)" -ne 0 ]; then
    zenity --error --title="Akses Ditolak" --text="Jalankan sebagai root:\nsudo bash $0" --width=400
    exit 1
fi

# Cek dependencies
command -v zenity >/dev/null 2>&1 || { echo "Zenity tidak ditemukan!"; exit 1; }
command -v cfdisk >/dev/null 2>&1 || { 
    zenity --error --text="cfdisk tidak ditemukan! Install: apt install cfdisk" 
    exit 1
}

# =============================================================================
# VIRTUALBOX FIX: Explicitly filter out CD-ROM and loop devices
# =============================================================================
echo "Mendeteksi hard disk di VirtualBox..."

# Method 1: Pilih disk yang BUKAN sr0, BUKAN loop, dan BUKAN removable
AVAILABLE_DISKS=()
DISK_NAMES=()
DISK_SIZES=()
DISK_MODELS=()

while read -r name size tran model; do
    # Skip CD-ROM, loop, dan removable media
    if [[ "$name" == "sr0" ]] || [[ "$name" == "loop"* ]] || [[ "$tran" == "usb" ]]; then
        continue
    fi
    
    # Di VirtualBox, hard disk biasanya sda, sdb, atau vda
    if [[ "$name" == "sda" ]] || [[ "$name" == "sdb" ]] || [[ "$name" == "vda" ]]; then
        AVAILABLE_DISKS+=("$name")
        DISK_NAMES+=("$name")
        DISK_SIZES+=("$size")
        DISK_MODELS+=("$model")
    fi
done < <(lsblk -dno NAME,SIZE,TRAN,MODEL 2>/dev/null | grep -v '^loop' | awk '{print $1, $2, $3, substr($0, index($0,$4))}')

# Jika tidak ada, ambil semua kecuali sr0
if [ ${#AVAILABLE_DISKS[@]} -eq 0 ]; then
    while read -r name size tran model; do
        if [[ "$name" != "sr0" ]] && [[ "$name" != "loop"* ]]; then
            AVAILABLE_DISKS+=("$name")
            DISK_NAMES+=("$name")
            DISK_SIZES+=("$size")
            DISK_MODELS+=("$model")
        fi
    done < <(lsblk -dno NAME,SIZE,TRAN,MODEL 2>/dev/null | grep -v '^loop' | awk '{print $1, $2, $3, substr($0, index($0,$4))}')
fi

# =============================================================================
# Pilih Disk dengan Zenity List (Clear UI)
# =============================================================================

if [ ${#AVAILABLE_DISKS[@]} -eq 0 ]; then
    zenity --error --text="TIDAK ADA HARD DISK DITEMUKAN!\n\nPastikan VirtualBox sudah menambahkan hard disk.\nCek dengan: lsblk" --width=500
    exit 1
fi

# Build array untuk zenity
ZENITY_LIST=()
for i in "${!DISK_NAMES[@]}"; do
    ZENITY_LIST+=("${DISK_NAMES[$i]}")
    ZENITY_LIST+=("${DISK_SIZES[$i]}")
    ZENITY_LIST+=("${DISK_MODELS[$i]:-Virtual Disk}")
done

# Tampilkan pilihan disk
selected=$(zenity --list \
    --title="LeakOS - Pilih Hard Disk (VirtualBox)" \
    --text="<span foreground='red'><b>⚠️  PILIH HARD DISK, BUKAN CD-ROM (/dev/sr0) ⚠️</b></span>\n\n$LEAKOS_BANNER" \
    --column="Disk" \
    --column="Size" \
    --column="Model" \
    --width=700 \
    --height=400 \
    --radiolist \
    --print-column=1 \
    "${ZENITY_LIST[@]}")

# Jika cancel, exit
if [ -z "$selected" ]; then
    zenity --info --text="Instalasi dibatalkan." --width=400
    exit 0
fi

TARGET_DISK="/dev/$selected"
echo "Selected disk: $TARGET_DISK"

# =============================================================================
# Konfirmasi dan Jalankan cfdisk
# =============================================================================

# Confirm disk selection
zenity --question \
    --title="Konfirmasi Disk" \
    --text="ANDA MEMILIH: <b>$TARGET_DISK</b>\n\nAPAKAH INI HARD DISK YANG BENAR?\n\nBUKAN /dev/sr0 (CD-ROM)!\n\nSemua data di disk ini AKAN DIHAPUS!" \
    --width=600 \
    --ok-label="Ya, ini Hard Disk" \
    --cancel-label="Batal" || exit 0

# Tampilkan panduan partisi
cat << EOF | zenity --text-info \
    --title="LeakOS - Panduan Partisi VirtualBox" \
    --width=700 \
    --height=500 \
    --font="monospace" \
    --ok-label="Buka cfdisk" \
    --cancel-label="Batal"

$LEAKOS_BANNER

╔══════════════════════════════════════════════════════════════════╗
║                    PANDUAN PARTISI VIRTUALBOX                    ║
╚══════════════════════════════════════════════════════════════════╝

DISK TARGET: $TARGET_DISK

LANGKAH-LANGKAH DI cfdisk:

1. PILIH LABEL:
   → Pilih [gpt] untuk UEFI (recommended untuk VirtualBox)

2. BUAT PARTISI EFI (hanya untuk UEFI):
   → [New] → Size: 512M → Type: [EFI System]

3. BUAT PARTISI ROOT:
   → [New] → Size: (sisa space) → Type: [Linux filesystem]

4. OPSIONAL - SWAP:
   → [New] → Size: 2-4GB → Type: [Linux swap]

5. WRITE & QUIT:
   → [Write] → ketik 'yes' → [Quit]

⚠️  PERINGATAN: Data di $TARGET_DISk akan dihapus!

Tekan OK untuk membuka cfdisk...
EOF

# Jalankan cfdisk
cfdisk "$TARGET_DISK"

# Tunggu kernel update
partprobe "$TARGET_DISK" 2>/dev/null || true
sleep 3

# =============================================================================
# Deteksi Partisi yang Baru Dibuat
# =============================================================================

# Function: get partition list
get_partitions() {
    local disk=$1
    lsblk "$disk" -o NAME,SIZE,FSTYPE,MOUNTPOINT -l -n 2>/dev/null | grep -v "^${disk##*/}" | grep -v "^sr" | awk '{print $1, $2, $3, $4}'
}

echo "Mendeteksi partisi di $TARGET_DISK..."
PARTITIONS=()
while read -r name size fstype mount; do
    if [[ "$name" != "" ]] && [[ "$name" != "sr"* ]]; then
        PARTITIONS+=("/dev/$name" "$size" "${fstype:--}" "${mount:--}")
    fi
done < <(get_partitions "$TARGET_DISK")

if [ ${#PARTITIONS[@]} -eq 0 ]; then
    zenity --error --text="Tidak ada partisi ditemukan di $TARGET_DISK!\nJalankan cfdisk dulu." --width=500
    exit 1
fi

# =============================================================================
# Pilih Partisi Root
# =============================================================================

# Filter partisi dengan size > 1GB untuk root candidate
ROOT_CANDIDATES=()
for i in "${!PARTITIONS[@]}"; do
    if (( i % 4 == 0 )); then
        part="${PARTITIONS[$i]}"
        size="${PARTITIONS[$((i+1))]}"
        fstype="${PARTITIONS[$((i+2))]}"
        
        # Skip EFI partition (biasanya 512M) dan swap
        if [[ "$part" != *"EFI"* ]] && [[ "$fstype" != "swap" ]] && [[ "$size" != *"512M"* ]]; then
            ROOT_CANDIDATES+=("$part" "$size" "$fstype")
        fi
    fi
done

# Jika tidak ada candidate, ambil semua partisi non-EFI
if [ ${#ROOT_CANDIDATES[@]} -eq 0 ]; then
    ROOT_CANDIDATES=("${PARTITIONS[@]}")
fi

# Pilih partisi root
selected_root=$(zenity --list \
    --title="LeakOS - Pilih Partisi Root" \
    --text="<span foreground='red'><b>⚠️  PILIH PARTISI UNTUK SISTEM (akan diformat ext4) ⚠️</b></span>" \
    --column="Partisi" \
    --column="Size" \
    --column="Filesystem" \
    --width=600 \
    --height=400 \
    --radiolist \
    --print-column=1 \
    "${ROOT_CANDIDATES[@]}")

if [ -z "$selected_root" ]; then
    zenity --error --text="Partisi root tidak dipilih!" --width=400
    exit 1
fi

TARGET_PART="$selected_root"

# =============================================================================
# Deteksi EFI Partition
# =============================================================================

EFI_PART=""
if [ -d "/sys/firmware/efi" ]; then
    # Cari partisi EFI (type: c12a7328-f81f-11d2-ba4b-00a0c93ec93b)
    for part in /dev/${TARGET_DISK##/dev/}*; do
        if [ -b "$part" ]; then
            part_type=$(blkid -o value -s PART_ENTRY_TYPE "$part" 2>/dev/null || echo "")
            if [[ "$part_type" == *"c12a7328-f81f-11d2-ba4b-00a0c93ec93b"* ]]; then
                EFI_PART="$part"
                break
            fi
        fi
    done
    
    # Fallback: cari partisi dengan size 512M yang belum diformat
    if [ -z "$EFI_PART" ]; then
        while read -r name size fstype mount; do
            if [[ "$size" == "512M" ]] || [[ "$size" == "1G" ]]; then
                EFI_PART="/dev/$name"
                break
            fi
        done < <(get_partitions "$TARGET_DISK")
    fi
fi

# =============================================================================
# Form Konfigurasi User
# =============================================================================

# User form sederhana
USERNAME=$(zenity --entry --title="LeakOS - Username" --text="Masukkan username:" --entry-text="leakos")
[ -z "$USERNAME" ] && USERNAME="leakos"

while true; do
    PASSWORD=$(zenity --password --title="LeakOS - Password" --text="Masukkan password untuk $USERNAME:")
    PASSWORD2=$(zenity --password --title="LeakOS - Konfirmasi Password" --text="Ketik ulang password:")
    
    if [ "$PASSWORD" = "$PASSWORD2" ] && [ -n "$PASSWORD" ]; then
        break
    else
        zenity --error --text="Password tidak cocok atau kosong!" --width=400
    fi
done

HOSTNAME=$(zenity --entry --title="LeakOS - Hostname" --text="Masukkan hostname:" --entry-text="leakos-vb")
[ -z "$HOSTNAME" ] && HOSTNAME="leakos-vb"

# =============================================================================
# INSTALASI
# =============================================================================

# Konfirmasi akhir
zenity --question \
    --title="Konfirmasi Instalasi" \
    --text="<b>RINGKASAN INSTALASI:</b>\n\n\
Disk: $TARGET_DISK\n\
Partisi Root: $TARGET_PART (akan DIFORMAT ext4)\n\
Partisi EFI: ${EFI_PART:-Tidak ada (Legacy/BIOS)}\n\
Username: $USERNAME\n\
Hostname: $HOSTNAME\n\n\
<span foreground='red'><b>PERINGATAN: Semua data di $TARGET_PART akan dihapus!</b></span>\n\n\
LANJUTKAN INSTALASI?" \
    --width=700 \
    --ok-label="Install LeakOS" \
    --cancel-label="Batal" || exit 0

# Progress instalasi
(
    echo "10"
    echo "# Memformat $TARGET_PART..."
    mkfs.ext4 -F "$TARGET_PART" > /dev/null 2>&1 || exit 1
    
    echo "20"
    echo "# Mounting partisi..."
    mkdir -p /mnt/leakos
    mount "$TARGET_PART" /mnt/leakos || exit 1
    
    if [ -n "$EFI_PART" ]; then
        echo "25"
        echo "# Memformat EFI partition..."
        mkdir -p /mnt/leakos/boot/efi
        mkfs.fat -F32 "$EFI_PART" > /dev/null 2>&1 || true
        mount "$EFI_PART" /mnt/leakos/boot/efi || true
    fi
    
    echo "30"
    echo "# Menyalin system files..."
    rsync -aHAX / /mnt/leakos/ \
        --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/cow/*,/squash/*,/lost+found,/boot/efi} \
        --progress > /dev/null 2>&1
    
    echo "50"
    echo "# Membuat direktori penting..."
    mkdir -p /mnt/leakos/{dev,proc,sys,run,tmp,boot/efi}
    chmod 1777 /mnt/leakos/tmp
    
    echo "60"
    echo "# Setup fstab..."
    UUID_ROOT=$(blkid -s UUID -o value "$TARGET_PART")
    cat > /mnt/leakos/etc/fstab << FSTAB
UUID=$UUID_ROOT / ext4 defaults,noatime 0 1
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
FSTAB
    
    if [ -n "$EFI_PART" ]; then
        UUID_EFI=$(blkid -s UUID -o value "$EFI_PART" 2>/dev/null || echo "")
        if [ -n "$UUID_EFI" ]; then
            echo "UUID=$UUID_EFI /boot/efi vfat defaults 0 2" >> /mnt/leakos/etc/fstab
        fi
    fi
    
    echo "70"
    echo "# Setup system di chroot..."
    mount --bind /dev /mnt/leakos/dev
    mount --bind /proc /mnt/leakos/proc
    mount --bind /sys /mnt/leakos/sys
    mount --bind /run /mnt/leakos/run
    
    cp /etc/resolv.conf /mnt/leakos/etc/resolv.conf 2>/dev/null || true
    
    # Chroot commands
    chroot /mnt/leakos /bin/bash << CHROOT
        set -e
        
        # Setup hostname
        echo "$HOSTNAME" > /etc/hostname
        
        # Setup timezone
        ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
        
        # Setup locale
        echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
        locale-gen
        echo "LANG=en_US.UTF-8" > /etc/locale.conf
        
        # Create user
        useradd -m -G wheel -s /bin/bash $USERNAME 2>/dev/null || true
        echo "$USERNAME:$PASSWORD" | chpasswd
        
        # Setup sudo
        echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel-group
        chmod 0440 /etc/sudoers.d/wheel-group
        
        # Setup network
        systemctl enable NetworkManager 2>/dev/null || true
        
        # Install GRUB
        if [ -n "$EFI_PART" ] && [ -d /sys/firmware/efi ]; then
            grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=LeakOS --recheck
        else
            grub-install --target=i386-pc --recheck $TARGET_DISK
        fi
        
        grub-mkconfig -o /boot/grub/grub.cfg
CHROOT
    
    echo "90"
    echo "# Cleanup..."
    sync
    umount -R /mnt/leakos 2>/dev/null || true
    
    echo "100"
    echo "# Instalasi selesai!"
    
) | zenity --progress \
    --title="LeakOS Installer" \
    --text="Memulai instalasi..." \
    --percentage=0 \
    --auto-close \
    --width=600

# =============================================================================
# Selesai
# =============================================================================

if [ $? -eq 0 ]; then
    zenity --question \
        --title="LeakOS - Instalasi Berhasil" \
        --text="<b><span foreground='green'>✓ INSTALASI BERHASIL!</span></b>\n\n\
$LEAKOS_BANNER\n\n\
Detail Sistem:\n\
• Disk: $TARGET_DISK\n\
• Root: $TARGET_PART\n\
• Boot: ${EFI_PART:-Legacy/BIOS}\n\
• User: $USERNAME\n\
• Hostname: $HOSTNAME\n\n\
Reboot sekarang dan lepaskan media instalasi.\n\n\
© 2025-2026 leakos.dev" \
        --width=700 \
        --ok-label="Reboot" \
        --cancel-label="Exit"
    
    if [ $? -eq 0 ]; then
        reboot
    fi
else
    zenity --error --text="Instalasi gagal! Cek log di terminal." --width=500
fi
