#!/usr/bin/env bash
set -u

log() { printf '\n=== %s ===\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }

echo "GA402XU Linux Audio Verification"
echo "================================"

log "Hardware / codecs"

if grep -Rni "ALC285" /proc/asound/card*/codec#* 2>/dev/null | head -n 5; then
    :
else
    warn "ALC285 was not found in /proc/asound."
fi

echo
grep -RniE "CS35L41|10431463" /proc/asound/card*/codec#* 2>/dev/null | head -n 20 || \
    warn "CS35L41 was not found in ALSA codec information."

log "ALSA cards"

cat /proc/asound/cards

log "ALSA mixer cards"

amixer -l 2>/dev/null || true

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

log "Detected internal-style ALSA card"

if [[ -n "$CARD" ]]; then
    echo "Card: $CARD"

    echo
    echo "--- Master ---"
    amixer -c "$CARD" sget Master 2>/dev/null || true

    echo
    echo "--- Speaker ---"
    amixer -c "$CARD" sget Speaker 2>/dev/null || true

    echo
    echo "--- PCM ---"
    amixer -c "$CARD" sget PCM 2>/dev/null || true
else
    warn "Could not automatically identify a card with Master/Speaker/PCM."
fi

log "PipeWire default sink"

wpctl status 2>/dev/null || true

echo
echo "Default sink volume:"
wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true

log "PipeWire / WirePlumber services"

for service in pipewire pipewire-pulse wireplumber; do
    printf '%-16s' "$service"
    if systemctl --user is-active --quiet "$service"; then
        echo "active"
    else
        echo "NOT active"
    fi
done

log "CS35L41 firmware messages"

sudo dmesg | grep -iE "cs35l41|10431463|spkid|wmfw" | tail -n 60 2>/dev/null || \
    warn "No matching kernel messages were available."

log "Stale audio startup entries"

grep -RniE "easyeffects|alsactl.*restore" \
    "$HOME/.config/i3" "$HOME/.config/autostart" "$HOME/.config/systemd/user" \
    2>/dev/null || echo "No matching stale startup entry found."

log "Verification target"

cat <<'EOF'
For the tested GA402XU setup, the desired final state is approximately:

    ALSA Master:  100% / 0.00 dB
    ALSA Speaker: 100% / 0.00 dB
    ALSA PCM:     100% / 0.00 dB
    PipeWire:     1.00

If those values survive a reboot and the internal speakers sound normal,
the configuration is behaving as expected.
EOF
