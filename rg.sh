#!/usr/bin/env bash
# =============================================================
# install-tools-leakos-grouped-menu-fixed-v2.sh
# Sudah dihapus semua 'local' di luar function → kompatibel
# =============================================================

set -euo pipefail

INSTALL_DIR="${HOME}/tools"
DESKTOP_DIR="${HOME}/.local/share/applications/leakos"
mkdir -p "$INSTALL_DIR" "$DESKTOP_DIR"

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' NC='\033[0m'

log()  { echo -e "${GREEN}[+] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }

something_installed=false

# ────────────────────────────────────────────────
# Definisi submenu
# ────────────────────────────────────────────────

declare -A SUBMENUS
SUBMENUS["1"]="Intelligent Gathering"
SUBMENUS["2"]="Vulnerability Analysis"
SUBMENUS["3"]="Web Applications"
SUBMENUS["4"]="Database Attacks"
SUBMENUS["5"]="Password Attack"

# ────────────────────────────────────────────────
# Tools & info install (terpusat)
# ────────────────────────────────────────────────

declare -A TOOL_REPO TOOL_TYPE TOOL_EXTRA TOOL_DESC

# Intelligent Gathering
TOOL_REPO["subfinder"]="projectdiscovery/subfinder"    ; TOOL_TYPE["subfinder"]="go"     ; TOOL_EXTRA["subfinder"]=""               ; TOOL_DESC["subfinder"]="Subfinder - Subdomain enumeration"
TOOL_REPO["amass"]="owasp-amass/amass"                 ; TOOL_TYPE["amass"]="go"           ; TOOL_EXTRA["amass"]=""                    ; TOOL_DESC["amass"]="Amass - Attack surface mapping"
TOOL_REPO["httpx"]="projectdiscovery/httpx"            ; TOOL_TYPE["httpx"]="go"           ; TOOL_EXTRA["httpx"]=""                    ; TOOL_DESC["httpx"]="HTTPX - HTTP probing"
TOOL_REPO["katana"]="projectdiscovery/katana"          ; TOOL_TYPE["katana"]="go"          ; TOOL_EXTRA["katana"]=""                   ; TOOL_DESC["katana"]="Katana - Advanced crawler"
TOOL_REPO["gau"]="lc/gau"                              ; TOOL_TYPE["gau"]="go"             ; TOOL_EXTRA["gau"]=""                      ; TOOL_DESC["gau"]="gau - GetAllUrls from archives"

# Vulnerability Analysis
TOOL_REPO["nuclei"]="projectdiscovery/nuclei"          ; TOOL_TYPE["nuclei"]="go"          ; TOOL_EXTRA["nuclei"]="nuclei -update-templates" ; TOOL_DESC["nuclei"]="Nuclei - Fast vuln scanner"

# Web Applications
TOOL_REPO["ffuf"]="ffuf/ffuf"                          ; TOOL_TYPE["ffuf"]="go"            ; TOOL_EXTRA["ffuf"]=""                     ; TOOL_DESC["ffuf"]="FFUF - Fast web fuzzer"
TOOL_REPO["dalfox"]="hahwul/dalfox"                    ; TOOL_TYPE["dalfox"]="go"          ; TOOL_EXTRA["dalfox"]=""                   ; TOOL_DESC["dalfox"]="Dalfox - XSS scanner"

# Database Attacks
TOOL_REPO["sqlmap"]="sqlmapproject/sqlmap"             ; TOOL_TYPE["sqlmap"]="git-python" ; TOOL_EXTRA["sqlmap"]=""                   ; TOOL_DESC["sqlmap"]="SQLMap - SQL injection"

# Password Attack
TOOL_REPO["hydra"]="vanhauser-thc/thc-hydra"           ; TOOL_TYPE["hydra"]="manual"       ; TOOL_EXTRA["hydra"]=""                    ; TOOL_DESC["hydra"]="Hydra - Brute force"

# ────────────────────────────────────────────────
# Fungsi install tool
# ────────────────────────────────────────────────

install_tool() {
    local name="$1"
    local repo="${TOOL_REPO[$name]}"
    local tipe="${TOOL_TYPE[$name]}"
    local extra="${TOOL_EXTRA[$name]}"

    if [[ -z "$repo" ]]; then
        warn "Tool $name belum dikonfigurasi"
        return 1
    fi

    log "Menginstall $name ($repo) ..."

    case "$tipe" in
        go)
            go install "github.com/$repo@latest" && log "→ $name berhasil via go"
            ;;
        git-python)
            cd "$INSTALL_DIR" || return 1
            [[ ! -d "$name" ]] && git clone "https://github.com/$repo" "$name"
            cd "$name" || return 1
            python3 -m pip install --user -r requirements.txt 2>/dev/null
            python3 -m pip install --user . 2>/dev/null
            log "→ $name berhasil via git + pip"
            ;;
        *)
            warn "Tipe '$tipe' belum didukung untuk $name"
            return 1
            ;;
    esac

    if [[ -n "$extra" ]]; then
        log "Extra: $extra"
        eval "$extra" 2>/dev/null || warn "Extra gagal"
    fi

    # Buat .desktop (sementara pakai kategori sederhana, bisa disesuaikan nanti)
    cat > "$DESKTOP_DIR/${name}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Exec=$name
Terminal=true
Categories=LEAKOS-${name//_/-};
StartupNotify=false
EOF

    something_installed=true
    log "→ .desktop dibuat untuk $name"
}

# ────────────────────────────────────────────────
# Fungsi tampilkan tools di submenu tertentu
# ────────────────────────────────────────────────

show_submenu_tools() {
    local submenu_num="$1"
    local submenu_name="${SUBMENUS[$submenu_num]}"

    echo -e "\n${YELLOW}Submenu: $submenu_name${NC}"

    local tools=()
    case "$submenu_name" in
        "Intelligent Gathering") tools=(subfinder amass httpx katana gau) ;;
        "Vulnerability Analysis") tools=(nuclei) ;;
        "Web Applications") tools=(ffuf dalfox) ;;
        "Database Attacks") tools=(sqlmap) ;;
        "Password Attack") tools=(hydra) ;;
        *) echo -e "${YELLOW}Submenu ini kosong atau belum dikonfigurasi.${NC}"; return ;;
    esac

    echo "Tools yang tersedia:"
    local i=1
    for tool in "${tools[@]}"; do
        printf "  %d) %s - %s\n" "$i" "$tool" "${TOOL_DESC[$tool]}"
        ((i++))
    done

    echo "  a) Install SEMUA tools di submenu ini"
    echo "  0) Kembali ke menu utama"

    read -p "Pilih nomor tool, 'a', atau 0: " choice

    if [[ "$choice" == "0" ]]; then
        return
    elif [[ "$choice" == "a" || "$choice" == "A" ]]; then
        for tool in "${tools[@]}"; do
            install_tool "$tool"
            echo ""
        done
    elif [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#tools[@]}" ]]; then
        local selected="${tools[$((choice-1))]}"
        install_tool "$selected"
    else
        warn "Pilihan tidak valid"
    fi
}

# ────────────────────────────────────────────────
# Menu utama (loop submenu)
# ────────────────────────────────────────────────

echo -e "\n${GREEN}Installer Tools LeakOS - Pilih Submenu${NC}"
echo "=========================================="

while true; do
    echo ""
    for key in $(echo "${!SUBMENUS[@]}" | tr ' ' '\n' | sort -n); do
        submenu_name="${SUBMENUS[$key]}"   # ← tanpa local
        echo "$key) $submenu_name"
    done
    echo "0) Keluar"

    read -p "Masukkan nomor submenu: " submenu_choice

    if [[ "$submenu_choice" == "0" ]]; then
        break
    elif [[ -n "${SUBMENUS[$submenu_choice]}" ]]; then
        show_submenu_tools "$submenu_choice"
    else
        warn "Submenu tidak ditemukan"
    fi
done

# ────────────────────────────────────────────────
# Akhir script
# ────────────────────────────────────────────────

if $something_installed; then
    log "Memperbarui database menu desktop..."
    update-desktop-database "$(dirname "$DESKTOP_DIR")" 2>/dev/null || true
    log "Selesai. Cek menu LeakOS di XFCE."
else
    log "Tidak ada tool yang diinstall."
fi

echo -e "\n${GREEN}Installer selesai.${NC}"
