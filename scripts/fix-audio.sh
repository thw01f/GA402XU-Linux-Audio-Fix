#!/usr/bin/env bash
set -euo pipefail

# GA402XU Linux Audio Fix
# Tested on Kali Linux / Debian-like systems.
#
# This script:
#   - installs Cirrus firmware
#   - rebuilds initramfs
#   - finds an ALSA card containing Master/Speaker/PCM controls
#   - backs up and resets WirePlumber default-routes
#   - restarts WirePlumber
#   - restores ALSA + PipeWire volume to unity
#   - performs basic verification
#
# It does NOT modify kernel parameters, disable CS35L41 protection,
# or force volume above 100%.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${HOME}/.local/state/wireplumber-backup"
ROUTES_FILE="${HOME}/.local/state/wireplumber/default-routes"

log()  { printf '\n[+] %s\n' "$*"; }
warn() { printf '\n[!] %s\n' "$*" >&2; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -ne 0 ]] || die "Do not run this script as root. Run it as your normal user."

command -v sudo >/dev/null || die "sudo is required."
command -v amixer >/dev/null || die "amixer is required."
command -v wpctl >/dev/null || die "wpctl is required."

if ! command -v apt-get >/dev/null; then
    die "This automated installer currently supports apt-based systems (Kali/Debian). Use the manual README procedure on other distributions."
fi

log "Installing required packages"
sudo apt-get update
sudo apt-get install -y firmware-cirrus alsa-utils

if command -v update-initramfs >/dev/null; then
    log "Updating initramfs"
    sudo update-initramfs -u -k all
fi

log "Checking for ALC285"
if grep -Rni "ALC285" /proc/asound/card*/codec#* 2>/dev/null | head -n 1; then
    echo "ALC285 codec detected."
else
    warn "ALC285 was not detected in /proc/asound. Continuing, but verify your hardware."
fi

log "Checking for ASUS GA402XU CS35L41 firmware"
if find /usr/lib/firmware/cirrus -type f -o -type l 2>/dev/null \
    | grep -q '10431463'; then
    echo "ASUS 10431463 CS35L41 firmware files found."
else
    warn "No 10431463 firmware filename was found. Check firmware-cirrus and dmesg manually."
fi

log "Finding ALSA card with Master/Speaker/PCM controls"

CARD=""
for card_dir in /proc/asound/card[0-9]*; do
    [[ -d "$card_dir" ]] || continue
    card_num="${card_dir#*/card}"

    controls="$(amixer -c "$card_num" scontrols 2>/dev/null || true)"

    if grep -q '"Master"' <<<"$controls" &&
       grep -q '"Speaker"' <<<"$controls" &&
       grep -q '"PCM"' <<<"$controls"; then
        CARD="$card_num"
        break
    fi
done

if [[ -z "$CARD" ]]; then
    warn "Could not automatically find a card containing Master/Speaker/PCM."
    echo
    echo "Run:"
    echo "  cat /proc/asound/cards"
    echo "  amixer -l"
    echo
    die "No suitable ALSA card found."
fi

log "Using ALSA card: $CARD"
amixer -c "$CARD" scontrols

log "Backing up WirePlumber default-routes"

if [[ -f "$ROUTES_FILE" ]]; then
    mkdir -p "$BACKUP_DIR"
    backup_file="${BACKUP_DIR}/default-routes.$(date +%Y%m%d-%H%M%S)"
    cp -a "$ROUTES_FILE" "$backup_file"
    echo "Backup: $backup_file"
    rm -f "$ROUTES_FILE"
    echo "Removed active saved default-routes."
else
    echo "No active default-routes file found."
fi

log "Restarting WirePlumber"

if systemctl --user is-active --quiet wireplumber; then
    systemctl --user restart wireplumber
    sleep 2
else
    warn "WirePlumber is not currently active."
fi

log "Setting ALSA controls to 100%"

amixer -c "$CARD" sset Master 100%
amixer -c "$CARD" sset Speaker 100%
amixer -c "$CARD" sset PCM 100%

log "Setting PipeWire default sink to unity gain"

wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 || true
wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0

log "Checking final ALSA values"

amixer -c "$CARD" sget Master
amixer -c "$CARD" sget Speaker
amixer -c "$CARD" sget PCM

log "Checking PipeWire value"

wpctl get-volume @DEFAULT_AUDIO_SINK@

log "Checking audio services"

systemctl --user is-active pipewire || true
systemctl --user is-active pipewire-pulse || true
systemctl --user is-active wireplumber || true

log "Checking for stale i3 audio startup commands"

if grep -RniE "easyeffects|alsactl.*restore" \
    "$HOME/.config/i3" "$HOME/.config/autostart" "$HOME/.config/systemd/user" \
    2>/dev/null; then
    warn "Review the above startup entries. Old EasyEffects/alsactl restore commands can reapply unwanted audio state."
else
    echo "No matching stale startup command found in common user config locations."
fi

log "Checking CS35L41 kernel messages"

sudo dmesg | grep -iE "cs35l41|10431463" | tail -n 30 || true

cat <<'EOF'

[+] Fix procedure completed.

Recommended next step:
    ./scripts/verify-audio.sh

Then reboot and verify again:
    sudo reboot
    ./scripts/verify-audio.sh

Expected target:
    ALSA Master/Speaker/PCM = 100% / 0.00 dB
    PipeWire default sink = 1.00
EOF
