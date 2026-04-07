# CleaningMode

A tiny macOS menu bar utility that lets you clean your keyboard and screen without triggering anything.

## Features

- Blocks all keyboard, mouse, and trackpad input
- Pitch black screen overlay for safe screen wiping
- Lives in the menu bar for quick access
- Hold ESC for 2 seconds to exit cleaning mode
- Open on Startup option

## Install

Download the latest `CleaningMode.dmg` from [Releases](https://github.com/TuDePi/CleaningMode/releases), open it, and drag CleaningMode to Applications.

## Build from source

```bash
git clone https://github.com/TuDePi/CleaningMode.git
cd CleaningMode
./build.sh
open CleaningMode.app
```

## Requirements

- macOS 13.0+
- Accessibility permission (System Settings > Privacy & Security > Accessibility)

## Usage

1. Launch CleaningMode — it appears in your menu bar
2. Click the icon and select **Start Cleaning**
3. Screen goes black, all input is blocked
4. **Hold ESC for 2 seconds** to exit

## License

MIT
