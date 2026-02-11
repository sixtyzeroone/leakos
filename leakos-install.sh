#!/usr/bin/env bash
# =============================================================================
# LeakOS Linux - LiveCD → HDD Installer (Zenity GUI) - Versi ULTIMATE + cfdisk
# =============================================================================

set -euo pipefail

# Banner dense style - AMPERSAND SUDAH DI-ESCAPE dengan &amp;
LEAKOS_BANNER_PANGO="
<span foreground='#00ff00'>╔════════════════════════════════════════════════════════════╗</span>
<span foreground='#00ff00'>║</span>                  <span foreground='red'><b>L E A K O S   L I N U X</b></span>                  <span foreground='#00ff00'>║</span>
<span foreground='#00ff00'>║</span>     <span foreground='red'>Unleashed Freedom • Privacy First • Indonesian Root</span>     <span foreground='#00ff00'>║</span>
<span foreground='#00ff00'>║</span>          <span foreground='red'>Custom LFS Distro - Pentest / Developer Ready</span>           <span foreground='#00ff00'>║</span>
<span foreground='#00ff00'>╚════════════════════════════════════════════════════════════╝</span>

<span foreground='#00ff00'> LeakOS v1.x (C) 2025-2026 leakos.dev | Built on LFS</span>"

# Banner tanpa markup untuk fallback
LEAKOS_BANNER_PLAIN="
=============================================
          L E A K O S   L I N U X
     Unleashed Freedom • Privacy First
============================================="

# Pastikan dijalankan sebagai root
if [ "$(id -u)" -ne 0 ]; then
    zenity --error --title="Akses Ditolak" --text="Jalankan sebagai root:\nsudo bash $0" --width=400
    exit 1
fi

# Cek dependencies
command -v zenity >/dev/null 2>&1 || { echo "Zenity tidak ditemukan!"; exit 1; }
command -v cfdisk >/dev/null 2>&1 || { 
    zenity --error --text="cfdisk tidak ditemukan! Install dengan: apt install cfdisk" 
    exit 1
}

# Fix untuk missing icon
export GTK_THEME=Adwaita
export NO_AT_BRIDGE=1

# ------------------------------------------------------------------------------
# Fungsi Bantu dengan branding
# ------------------------------------------------------------------------------

die() { 
    zenity --error --title="LeakOS ERROR" --text="$1" --width=500
    exit 1
}

info() { 
    zenity --info --title="LeakOS Info" --text="$1" --width=600
}

confirm() { 
    # Gunakan banner plain untuk dialog untuk menghindari markup error
    zenity --question --title="LeakOS Konfirmasi" \
           --text="$LEAKOS_BANNER_PLAIN\n\n$1" \
           --width=700 --ok-label="Ya" --cancel-label="Batal" || exit 0
}

choose_list() {
    zenity --list --title="LeakOS - $1" \
           --column="Disk" --column="Size" --column="Type" --column="Model" \
           --width=700 --height=400 \
           --print-column=1 \
           "$@"
}

# ------------------------------------------------------------------------------
# Wizard Persiapan
# ------------------------------------------------------------------------------

confirm "SELAMAT DATANG DI INSTALLER LeakOS!\n\nPartisi disk akan dibuat manual via cfdisk.\nData bisa hilang jika diformat!\n\nLanjutkan?" || exit 0

# 1. Pilih disk untuk partitioning & GRUB - PERBAIKAN DISINI
disks=()
while IFS= read -r line; do 
    # Parse dengan lebih hati-hati
    name=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    tran=$(echo "$line" | awk '{print $3}')
    model=$(echo "$line" | cut -d' ' -f4-)
    disks+=("$name" "$size" "$tran" "$model")
done < <(lsblk -dno NAME,SIZE,TRAN,MODEL | grep -v '^loop')

if [ ${#disks[@]} -eq 0 ]; then
    die "Tidak ada disk yang ditemukan!"
fi

# Pilih disk
selected=$(zenity --list \
    --title="LeakOS - Pilih Disk" \
    --column="Disk" --column="Size" --column="Type" --column="Model" \
    --width=700 --height=400 \
    "${disks[@]}") || exit 0

if [ -z "$selected" ]; then
    die "Tidak ada disk yang dipilih!"
fi

TARGET_DISK="/dev/$selected"

# 2. Jalankan cfdisk interaktif - PERBAIKAN FORMAT TEXT
info_text="Buka cfdisk untuk mempartisi disk:\n\n\
Disk: $TARGET_DISK\n\n\
Cara partisi untuk UEFI:\n\
1. Pilih label [gpt]\n\
2. [New] → Ukuran 512M-1G → Type: EFI System\n\
3. [New] → Sisa space → Type: Linux filesystem\n\
4. Opsional: [New] → Swap\n\
5. [Write] → ketik 'yes' → [Quit]\n\n\
Tekan OK untuk melanjutkan ke cfdisk."

zenity --info --title="LeakOS - Panduan Partisi" \
       --text="$info_text" --width=700 --ok-label="Buka cfdisk"

# Jalankan cfdisk
cfdisk "$TARGET_DISK"

partprobe "$TARGET_DISK" 2>/dev/null || true
sleep 3

# 3. Pilih partisi root - PERBAIKAN PARSING
parts=()
while IFS= read -r line; do
    part_name=$(echo "$line" | awk '{print $1}')
    part_size=$(echo "$line" | awk '{print $2}')
    part_fstype=$(echo "$line" | awk '{print $3}')
    part_mount=$(echo "$line" | awk '{print $4}')
    [ -z "$part_mount" ] && part_mount="-"
    parts+=("$part_name" "$part_size" "$part_fstype" "$part_mount")
done < <(lsblk -no NAME,SIZE,FSTYPE,MOUNTPOINT "$TARGET_DISK" 2>/dev/null | tail -n +2 || true)

if [ ${#parts[@]} -eq 0 ]; then
    die "Tidak ada partisi di $TARGET_DISK! Jalankan cfdisk dulu."
fi

selected_part=$(zenity --list \
    --title="LeakOS - Pilih Partisi Root" \
    --column="Partisi" --column="Size" --column="FSType" --column="Mount" \
    --width=700 --height=400 \
    --text="Pilih partisi untuk sistem (akan diformat ext4)" \
    "${parts[@]}") || exit 0

if [ -z "$selected_part" ]; then
    die "Partisi root tidak dipilih!"
fi

TARGET_PART="/dev/$selected_part"

confirm "PERINGATAN!\nPartisi $TARGET_Part akan DIFORMAT ext4!\nSemua data akan hilang.\n\nLanjutkan?" || exit 0

# ------------------------------------------------------------------------------
# Input Konfigurasi
# ------------------------------------------------------------------------------

# Form user dengan validasi
while true; do
    USER_FORM=$(zenity --forms --title="LeakOS - Identitas Sistem" \
        --add-entry="Username" \
        --add-password="Password" \
        --add-password="Konfirmasi Password" \
        --add-entry="Hostname (default: leakos)" \
        --separator="|") || exit 0
    
    IFS='|' read -r NEW_USERNAME PW1 PW2 HOSTNAME <<< "$USER_FORM"
    
    if [ -z "$NEW_USERNAME" ] || [ -z "$PW1" ]; then
        zenity --error --text="Username dan password tidak boleh kosong!"
        continue
    fi
    
    if [ "$PW1" != "$PW2" ]; then
        zenity --error --text="Password tidak cocok!"
        continue
    fi
    
    if [ -z "$HOSTNAME" ]; then
        HOSTNAME="leakos"
    fi
    
    break
done

# Layout keyboard
KBD_LAYOUT=$(zenity --list --title="LeakOS - Layout Keyboard" \
    --column="Kode" --column="Deskripsi" \
    --width=400 --height=300 \
    --radiolist --hide-header \
    TRUE "us" "US English (Default)" \
    FALSE "id" "Indonesia" \
    FALSE "uk" "United Kingdom" \
    FALSE "jp" "Japan" \
    --print-column=2) || KBD_LAYOUT="us"

# Locale
LOCALE=$(zenity --list --title="LeakOS - Bahasa Sistem" \
    --column="Locale" --column="Bahasa" \
    --width=400 --height=200 \
    --radiolist \
    TRUE "en_US.UTF-8" "English (US)" \
    FALSE "id_ID.UTF-8" "Bahasa Indonesia" \
    --print-column=2) || LOCALE="en_US.UTF-8"

# Timezone
TIMEZONE=$(zenity --list --title="LeakOS - Zona Waktu" \
    --width=550 --height=500 \
    --column="Zona Waktu" --column="Lokasi" \
    --radiolist \
    TRUE "Asia/Jakarta" "Indonesia (WIB)" \
    FALSE "Asia/Makassar" "Indonesia (WITA)" \
    FALSE "Asia/Jayapura" "Indonesia (WIT)" \
    --print-column=2) || TIMEZONE="Asia/Jakarta"

# ------------------------------------------------------------------------------
# Instalasi utama
# ------------------------------------------------------------------------------

(
    echo "5"
    echo "# Memformat $TARGET_PART sebagai ext4..."
    mkfs.ext4 -F "$TARGET_PART" || exit 1

    echo "15"
    echo "# Mounting partisi..."
    mkdir -p /mnt/target
    mount "$TARGET_PART" /mnt/target

    # Deteksi EFI partition
    EFI_PART=$(lsblk -no NAME,PARTTYPE "$TARGET_DISK" | \
        grep -i 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b' | \
        head -1 | awk '{print "/dev/" $1}')
    
    if [ -n "$EFI_PART" ] && [ -d "/sys/firmware/efi" ]; then
        echo "25"
        echo "# Memformat EFI partition..."
        mkdir -p /mnt/target/boot/efi
        mkfs.fat -F32 "$EFI_PART" 2>/dev/null || true
        mount "$EFI_PART" /mnt/target/boot/efi
        HAS_EFI=true
    else
        HAS_EFI=false
    fi

    echo "35"
    echo "# Menyalin file sistem (rsync)..."
    rsync -aHAX / /mnt/target/ \
        --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/cow/*,/squash/*,/media/*,/lost+found}
    
    mkdir -p /mnt/target/{dev,proc,sys,run,tmp,boot}
    chmod 1777 /mnt/target/tmp

    echo "55"
    echo "# Setup fstab..."
    UUID_ROOT=$(blkid -s UUID -o value "$TARGET_PART")
    cat << EOF > /mnt/target/etc/fstab
UUID=$UUID_ROOT / ext4 defaults,noatime 0 1
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
EOF

    if [ "$HAS_EFI" = true ] && [ -n "$EFI_PART" ]; then
        UUID_EFI=$(blkid -s UUID -o value "$EFI_PART" 2>/dev/null || echo "")
        if [ -n "$UUID_EFI" ]; then
            echo "UUID=$UUID_EFI /boot/efi vfat defaults 0 2" >> /mnt/target/etc/fstab
        fi
    fi

    echo "70"
    echo "# Chroot configuration..."
    mount --bind /dev /mnt/target/dev
    mount --bind /proc /mnt/target/proc
    mount --bind /sys /mnt/target/sys
    mount --bind /run /mnt/target/run

    # Copy resolv.conf untuk network di chroot
    cp -L /etc/resolv.conf /mnt/target/etc/resolv.conf 2>/dev/null || true

    # Konfigurasi di dalam chroot
    chroot /mnt/target /bin/bash << 'CHROOT_CMD'
        set -e
        echo "Configuring system..."
        
        # Setup hostname
        echo "$HOSTNAME" > /etc/hostname
        
        # Setup timezone
        ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
        
        # Setup locale
        echo "$LOCALE UTF-8" >> /etc/locale.gen
        locale-gen
        echo "LANG=$LOCALE" > /etc/locale.conf
        
        # Setup keyboard
        echo "KEYMAP=$KBD_LAYOUT" > /etc/vconsole.conf
        
        # Create user
        useradd -m -G wheel,audio,video,storage -s /bin/bash "$NEW_USERNAME" 2>/dev/null || true
        echo "$NEW_USERNAME:$PW1" | chpasswd
        
        # Setup sudo
        echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel-group
        chmod 0440 /etc/sudoers.d/wheel-group
        
        # Disable root password
        passwd -d root 2>/dev/null || true
CHROOT_CMD

    echo "85"
    echo "# Install GRUB..."
    if [ "$HAS_EFI" = true ]; then
        chroot /mnt/target grub-install \
            --target=x86_64-efi \
            --efi-directory=/boot/efi \
            --bootloader-id=LeakOS \
            --recheck || true
    else
        chroot /mnt/target grub-install \
            --target=i386-pc \
            --recheck "$TARGET_DISK" || true
    fi
    
    chroot /mnt/target grub-mkconfig -o /boot/grub/grub.cfg || true

    echo "100"
    echo "# Instalasi selesai! Cleaning up..."
    sync
    umount -R /mnt/target 2>/dev/null || true

) | zenity --progress \
    --title="LeakOS Installer" \
    --text="Memulai instalasi..." \
    --percentage=0 \
    --auto-close \
    --width=700

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    success_msg="INSTALASI BERHASIL!\n\n\
Detail Sistem:\n\
- User: $NEW_USERNAME\n\
- Hostname: $HOSTNAME\n\
- Keyboard: $KBD_LAYOUT\n\
- Locale: $LOCALE\n\
- Timezone: $TIMEZONE\n\
- Disk: $TARGET_DISK\n\
- Partisi Root: $TARGET_PART\n\n\
Reboot sekarang dan lepaskan media instalasi.\n\n\
© 2025-2026 leakos.dev"
    
    zenity --info --title="LeakOS - Sukses" \
           --text="$LEAKOS_BANNER_PLAIN\n\n$success_msg" \
           --width=600 --ok-label="Reboot"
    
    # Confirm reboot
    if zenity --question --title="Reboot" \
            --text="Reboot sistem sekarang?" \
            --width=400; then
        reboot
    fi
else
    die "Instalasi gagal! Cek log di terminal."
fi
