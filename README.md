# GA402XU Linux Audio Fix

Fix and diagnostic guide for **ASUS ROG Zephyrus G14 GA402XU** internal speaker audio on Debian/Kali-based Linux.

This repository documents a working procedure for the GA402XU internal speakers using:

- Realtek **ALC285**
- 2 × Cirrus Logic **CS35L41** speaker amplifiers
- PipeWire
- WirePlumber
- ALSA

> **Tested environment:** Kali Linux, kernel `7.1.5+kali-amd64`, PipeWire `1.6.8`, WirePlumber `0.5.17`.

## Problem

Typical symptoms can include:

- Internal speakers sound quiet or distorted.
- Volume appears normal in the desktop UI but ALSA/PipeWire is attenuated.
- Audio changes after reboot.
- Firefox or another application appears to have a separate volume.
- CS35L41 amplifiers use generic firmware instead of the ASUS-specific tuning.
- Old EasyEffects or `alsactl` startup commands interfere with the normal audio stack.

On the tested GA402XU, the final working state was:

```text
ALSA Master:  100% / 0.00 dB
ALSA Speaker: 100% / 0.00 dB
ALSA PCM:     100% / 0.00 dB
PipeWire:     1.00 / 100%
```

The CS35L41 amplifiers also loaded the ASUS-specific firmware/tuning supplied by `firmware-cirrus`.

---

# Quick Fix

## 1. Clone the repository

```bash
git clone https://github.com/<YOUR-GITHUB-USERNAME>/GA402XU-Linux-Audio-Fix.git
cd GA402XU-Linux-Audio-Fix
```

## 2. Make the scripts executable

```bash
chmod +x scripts/*.sh
```

## 3. Run the fix

```bash
./scripts/fix-audio.sh
```

## 4. Verify

```bash
./scripts/verify-audio.sh
```

## 5. Reboot

```bash
sudo reboot
```

## 6. Verify again after reboot

```bash
cd ~/GA402XU-Linux-Audio-Fix
./scripts/verify-audio.sh
```

If your clone is in another directory, use that directory instead.

---

# Manual Procedure

The manual procedure is provided so you can understand exactly what the fix changes.

## Step 1 — Install the Cirrus Logic firmware

On Kali/Debian:

```bash
sudo apt update
sudo apt install firmware-cirrus alsa-utils
```

Then rebuild the initramfs:

```bash
sudo update-initramfs -u -k all
```

Verify that the package is installed:

```bash
dpkg -l | grep firmware-cirrus
```

Check for GA402XU-specific firmware:

```bash
find /usr/lib/firmware/cirrus -type f -o -type l | grep 10431463
```

The GA402XU firmware set should include files similar to:

```text
cs35l41-dsp1-spk-prot-10431463-spkid0-l0.bin
cs35l41-dsp1-spk-prot-10431463-spkid0-r0.bin
cs35l41-dsp1-spk-prot-10431463-spkid1-l0.bin
cs35l41-dsp1-spk-prot-10431463-spkid1-r0.bin
cs35l41-dsp1-spk-prot-10431463.wmfw
```

Do **not** download random CS35L41 firmware from unrelated laptops.

---

## Step 2 — Check the audio hardware

Find the HDA cards:

```bash
cat /proc/asound/cards
```

Find the ALC285 codec:

```bash
grep -Rni "ALC285" /proc/asound/card*/codec#* 2>/dev/null
```

You can also inspect the codecs:

```bash
grep -RniE "Realtek|CS35L41" /proc/asound/card*/codec#* 2>/dev/null
```

On the tested GA402XU, the internal audio device contains:

```text
Realtek ALC285
Cirrus Logic CS35L41
Cirrus Logic CS35L41
```

The exact ALSA card number can change. **Do not assume it is always card 2.**

---

## Step 3 — Find the correct ALSA card

List mixer cards:

```bash
amixer -l
```

Then inspect candidate cards:

```bash
amixer -c 0 scontrols
amixer -c 1 scontrols
amixer -c 2 scontrols
```

Replace the number with the card containing:

```text
Master
Speaker
PCM
```

For the tested machine it was card `2`.

---

## Step 4 — Set ALSA speaker controls to full scale

For the tested internal audio card:

```bash
amixer -c 2 sset Master 100%
amixer -c 2 sset Speaker 100%
amixer -c 2 sset PCM 100%
```

If your card number is different, replace `2`.

Verify:

```bash
amixer -c 2 sget Master
amixer -c 2 sget Speaker
amixer -c 2 sget PCM
```

The important target is:

```text
[100%] [0.00dB]
```

Do not blindly set unrelated mixer controls.

---

## Step 5 — Set PipeWire to unity gain

Set the default PipeWire sink to 100%:

```bash
wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0
```

Check it:

```bash
wpctl get-volume @DEFAULT_AUDIO_SINK@
```

Expected:

```text
Volume: 1.00
```

If the output contains:

```text
MUTED
```

unmute it:

```bash
wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
```

---

## Step 6 — Check the actual PipeWire sink

```bash
wpctl status
```

Then:

```bash
pactl list sinks
```

The internal speaker sink should normally look similar to:

```text
alsa_output.pci-0000_65_00.6.analog-stereo
```

The PCI address may differ on another system.

---

# Step 7 — Remove stale EasyEffects startup

If you previously configured EasyEffects to start automatically, check your i3 configuration:

```bash
grep -RniE "easyeffects|alsactl.*restore" ~/.config/i3 ~/.config/i3status 2>/dev/null
```

If you find old commands such as:

```text
exec --no-startup-id easyeffects --gapplication-service
```

or:

```text
exec --no-startup-id alsactl --file ~/.config/asound.state restore
```

remove or comment them.

Example:

```text
#exec --no-startup-id easyeffects --gapplication-service
#exec --no-startup-id alsactl --file ~/.config/asound.state restore
```

Reload i3:

```bash
i3-msg reload
```

If you are no longer using EasyEffects, removing it is also reasonable:

```bash
sudo apt purge easyeffects
```

Then:

```bash
sudo apt autoremove
```

Do not install an EQ/audio effect application while debugging the base speaker path.

---

# Step 8 — Reset WirePlumber's saved default routes

WirePlumber can remember device routes and volume state.

First inspect the state:

```bash
ls -la ~/.local/state/wireplumber/
```

If this file exists:

```text
~/.local/state/wireplumber/default-routes
```

back it up:

```bash
mkdir -p ~/.local/state/wireplumber-backup
cp ~/.local/state/wireplumber/default-routes \
   ~/.local/state/wireplumber-backup/default-routes.$(date +%Y%m%d-%H%M%S)
```

Then remove the active saved routes:

```bash
rm -f ~/.local/state/wireplumber/default-routes
```

Restart WirePlumber:

```bash
systemctl --user restart wireplumber
```

Then set the volume again:

```bash
amixer -c 2 sset Master 100%
amixer -c 2 sset Speaker 100%
amixer -c 2 sset PCM 100%
wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0
```

Verify:

```bash
amixer -c 2 sget Master
amixer -c 2 sget Speaker
amixer -c 2 sget PCM
wpctl get-volume @DEFAULT_AUDIO_SINK@
```

> The route reset is a troubleshooting step. Do not repeatedly delete WirePlumber state if your system is already working.

---

# Step 9 — Check PipeWire and WirePlumber

```bash
systemctl --user status pipewire --no-pager
systemctl --user status pipewire-pulse --no-pager
systemctl --user status wireplumber --no-pager
```

All three should normally be active.

You can restart them manually if required:

```bash
systemctl --user restart wireplumber
systemctl --user restart pipewire-pulse
systemctl --user restart pipewire
```

Then restore unity volume:

```bash
wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0
```

---

# Step 10 — Verify CS35L41 firmware

Check the kernel log:

```bash
sudo dmesg | grep -iE "cs35l41|10431463|spkid|wmfw"
```

A working GA402XU should show the ASUS subsystem/tuning and CS35L41 firmware being loaded.

You can also check:

```bash
sudo dmesg | grep -i "CS35L41"
```

The important point is that the amplifiers should use the ASUS-specific `10431463` firmware/tuning rather than only generic fallback firmware.

---

# Step 11 — Direct ALSA test

First determine the ALSA card number:

```bash
cat /proc/asound/cards
```

Then test the internal device:

```bash
speaker-test -D plughw:2,0 -c 2 -t wav
```

Replace `2` with your internal audio card number.

Stop with:

```text
Ctrl+C
```

This bypasses much of the desktop audio path and is useful for distinguishing ALSA/hardware problems from PipeWire/application problems.

---

# Step 12 — Check Firefox/application volume

List PipeWire/PulseAudio streams:

```bash
pactl list sink-inputs
```

Look for:

```text
application.name = "Firefox"
```

and:

```text
module-stream-restore.id = "sink-input-by-application-name:Firefox"
```

If Firefox is below 100%, set its volume through the desktop mixer or with the appropriate `pactl` sink-input command.

A clean test is to close Firefox completely and test another audio source.

---

# Step 13 — Reboot test

After everything is correct:

```bash
sudo reboot
```

After reboot:

```bash
amixer -c 2 sget Master
amixer -c 2 sget Speaker
amixer -c 2 sget PCM
wpctl get-volume @DEFAULT_AUDIO_SINK@
```

Expected target:

```text
Master:  [100%] [0.00dB]
Speaker: [100%] [0.00dB]
PCM:     [100%] [0.00dB]

PipeWire:
Volume: 1.00
```

If those values survive reboot and the speakers sound normal, the fix is persistent.

---

# One-command manual recovery

If you already installed `firmware-cirrus` and know the internal ALSA card is `2`:

```bash
amixer -c 2 sset Master 100% && \
amixer -c 2 sset Speaker 100% && \
amixer -c 2 sset PCM 100% && \
wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0
```

Verify:

```bash
amixer -c 2 sget Master
amixer -c 2 sget Speaker
amixer -c 2 sget PCM
wpctl get-volume @DEFAULT_AUDIO_SINK@
```

---

# Automated Fix Script

The repository includes:

```bash
./scripts/fix-audio.sh
```

The script:

1. Checks that the system is Debian/Kali-like.
2. Installs `firmware-cirrus` and `alsa-utils`.
3. Rebuilds initramfs.
4. Detects an ALC285 codec when possible.
5. Detects the ALSA card containing the required mixer controls.
6. Backs up WirePlumber `default-routes`.
7. Removes the saved default-route file if present.
8. Restarts WirePlumber.
9. Sets ALSA Master/Speaker/PCM to 100%.
10. Sets the PipeWire default sink to unity gain.
11. Verifies the result.
12. Warns about stale EasyEffects/`alsactl` i3 startup commands.

Run:

```bash
./scripts/fix-audio.sh
```

---

# Verification Script

Run:

```bash
./scripts/verify-audio.sh
```

It reports:

- detected ALC285 codec
- CS35L41 devices
- ALSA mixer values
- PipeWire default sink
- PipeWire volume
- WirePlumber status
- PipeWire status
- PipeWire Pulse compatibility service
- relevant CS35L41 firmware messages

---

# What Was Actually Fixed

The working procedure involved several layers.

### 1. CS35L41 firmware

The GA402XU uses two CS35L41 amplifiers. Installing:

```bash
sudo apt install firmware-cirrus
```

provided the ASUS-specific firmware/tuning associated with subsystem:

```text
10431463
```

### 2. ALSA attenuation

The internal mixer was restoring an attenuated Master value. Setting:

```bash
amixer -c 2 sset Master 100%
```

restored the ALSA master path to:

```text
100% / 0.00 dB
```

### 3. PipeWire attenuation

PipeWire could also have a separate sink volume. Setting:

```bash
wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0
```

restored the PipeWire sink to unity gain.

### 4. Persistent state

WirePlumber stores device/route state. Old saved state and old startup commands were removed or reset during troubleshooting.

### 5. Audio effects

EasyEffects was removed from the debugging path because it had been automatically routing Firefox through an effects sink.

---

# Important Notes

## Do not assume the ALSA card number

This repository was tested with:

```text
card 2
```

but ALSA card numbering is not guaranteed.

Always check:

```bash
cat /proc/asound/cards
```

and:

```bash
amixer -l
```

before replacing commands on another machine.

## Do not use volume above 100%

Do not use:

```bash
wpctl set-volume @DEFAULT_AUDIO_SINK@ 2.0
```

or similar values to compensate for a broken configuration.

This can introduce clipping and distortion.

## Do not disable speaker protection

Do not disable CS35L41 DSP protection, speaker-protection firmware, thermal protection, or impedance protection just to increase loudness.

## This is not a universal ASUS fix

The repository is specifically aimed at the:

```text
ASUS ROG Zephyrus G14 GA402XU
```

Other G14 models can have different:

- codec routing
- amplifier firmware
- subsystem IDs
- DSP firmware
- mixer controls
- speaker configuration

---

# Troubleshooting

## Audio is still quiet

Check:

```bash
amixer -c 2 sget Master
amixer -c 2 sget Speaker
amixer -c 2 sget PCM
wpctl get-volume @DEFAULT_AUDIO_SINK@
```

Then:

```bash
sudo dmesg | grep -iE "cs35l41|10431463|firmware"
```

## Audio is distorted

Check for:

- PipeWire volume above `1.00`
- application volume above normal
- EasyEffects/effects sinks
- EQ/limiter plugins
- duplicate audio processing

Check:

```bash
wpctl status
pactl list sink-inputs
```

## Volume resets after reboot

Check for old startup commands:

```bash
grep -RniE "alsactl.*restore|amixer|wpctl|easyeffects" \
    ~/.config/i3 ~/.config/autostart ~/.config/systemd/user 2>/dev/null
```

Also check WirePlumber state:

```bash
ls -la ~/.local/state/wireplumber/
```

## CS35L41 firmware does not load

Check:

```bash
dpkg -l | grep firmware-cirrus
```

and:

```bash
find /usr/lib/firmware/cirrus -type f -o -type l | grep 10431463
```

Then:

```bash
sudo update-initramfs -u -k all
sudo reboot
```

After reboot:

```bash
sudo dmesg | grep -iE "cs35l41|10431463"
```

---

# Collecting a Diagnostic Report

Run:

```bash
mkdir -p ~/ga402xu-audio-debug

cat /proc/asound/cards \
  > ~/ga402xu-audio-debug/asound-cards.txt

amixer -l \
  > ~/ga402xu-audio-debug/amixer-list.txt

wpctl status \
  > ~/ga402xu-audio-debug/wpctl-status.txt

wpctl get-volume @DEFAULT_AUDIO_SINK@ \
  > ~/ga402xu-audio-debug/wpctl-volume.txt

pactl list sinks \
  > ~/ga402xu-audio-debug/pactl-sinks.txt

pactl list sink-inputs \
  > ~/ga402xu-audio-debug/pactl-sink-inputs.txt

sudo dmesg | grep -iE "cs35l41|alc285|10431463|firmware" \
  > ~/ga402xu-audio-debug/audio-dmesg.txt
```

Do not publish private information from diagnostic logs without reviewing it first.

---

# Repository Layout

```text
GA402XU-Linux-Audio-Fix/
├── README.md
├── LICENSE
├── scripts/
│   ├── fix-audio.sh
│   └── verify-audio.sh
└── docs/
    └── troubleshooting.md
```

---

# Scope

This project documents a reproducible troubleshooting/fix procedure for Linux audio on the ASUS ROG Zephyrus G14 GA402XU.

It is not an official ASUS or Linux Foundation project.

---

# License

MIT License. See `LICENSE`.
