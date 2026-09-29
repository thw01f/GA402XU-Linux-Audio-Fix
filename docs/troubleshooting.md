# Troubleshooting Notes

## Tested hardware

```text
ASUS ROG Zephyrus G14 GA402XU
Realtek ALC285
2 × Cirrus Logic CS35L41
Subsystem: 10431463
```

## Key observations

The internal speaker path worked correctly when:

```text
ALSA Master  = 100%
ALSA Speaker = 100%
ALSA PCM     = 100%
PipeWire     = 1.00
```

The system also required the ASUS-specific CS35L41 firmware supplied by `firmware-cirrus`.

## Firmware verification

Use:

```bash
sudo dmesg | grep -iE "cs35l41|10431463|spkid|wmfw"
```

The expected firmware family contains the ASUS subsystem ID:

```text
10431463
```

## State restoration

WirePlumber and PipeWire can restore device/stream state. If a previously saved route or old startup command repeatedly restores an unwanted volume:

```bash
ls -la ~/.local/state/wireplumber/
```

Back up and remove only:

```text
~/.local/state/wireplumber/default-routes
```

Then:

```bash
systemctl --user restart wireplumber
```

Restore the desired volume:

```bash
amixer -c <CARD> sset Master 100%
amixer -c <CARD> sset Speaker 100%
amixer -c <CARD> sset PCM 100%
wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0
```

## EasyEffects

During troubleshooting, EasyEffects was found to be part of the application audio path and was removed from the test configuration.

For a clean baseline, test without:

- EasyEffects
- EQ
- compressors
- limiters
- other audio filters

## Direct ALSA test

```bash
speaker-test -D plughw:<CARD>,0 -c 2 -t wav
```

If direct ALSA playback works but browser playback does not, investigate PipeWire/application routing.

## PipeWire test

```bash
wpctl status
wpctl get-volume @DEFAULT_AUDIO_SINK@
pactl list sinks
pactl list sink-inputs
```

## i3 startup audit

```bash
grep -RniE "easyeffects|alsactl.*restore|amixer|wpctl" \
  ~/.config/i3 ~/.config/autostart ~/.config/systemd/user 2>/dev/null
```

Remove or comment obsolete audio restoration commands.

## Important

Do not:

- disable CS35L41 protection
- use volume above 100% to compensate for configuration problems
- copy firmware from unrelated machines
- apply random kernel parameters
- repeatedly delete all WirePlumber state when the system already works
