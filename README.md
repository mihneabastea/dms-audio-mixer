# DMS Audio Mixer

A compact PipeWire volume mixer for [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell).

Control output devices and individual applications directly from DMS.

## Features

- Per-device volume and mute
- Per-app volume and mute
- Route applications to different outputs
- Set the default output device
- Hide unused output devices
- Scroll over sliders to adjust volume
- Configurable maximum application volume
- Configurable 1%, 2% or 5% scroll step
- Theme-aware output selector and tooltips
- DMS-style interface

## Requirements

- DankMaterialShell
- PipeWire / WirePlumber
- `pw-metadata`

## Installation

Clone the repository, then copy the `AudioMixer` folder to your DMS plugins directory:

```bash
cp -r AudioMixer ~/.config/DankMaterialShell/plugins/
dms restart
```

Then enable **Volume Mixer** in DMS.

## Configuration

Open the plugin settings in DMS to change the maximum application volume and the scroll step. The maximum-volume range is 1–300%, with a default of 150%. Supported scroll steps are 1%, 2% and 5%.

Hidden output devices can be restored from the **Hidden devices** section in the mixer.

## Updating

Pull the latest changes, replace the installed `AudioMixer` folder, and restart DMS:

```bash
rm -rf ~/.config/DankMaterialShell/plugins/AudioMixer
cp -r AudioMixer ~/.config/DankMaterialShell/plugins/
dms restart
```
