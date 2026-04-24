<div align="center">
  <img src="spotlightofficon.png" width="150" alt="Spotlight Off Icon" />

  # Spotlight Off

  **Automatically disables Spotlight indexing on external drives the moment they're connected.**

  ![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue?style=flat-square&logo=apple)
  ![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift)
  ![License](https://img.shields.io/badge/license-CC%20BY--NC%204.0-green?style=flat-square)
  ![Notarized](https://img.shields.io/badge/Apple%20Notarized-%E2%9C%93-brightgreen?style=flat-square&logo=apple)

</div>

---

## What it does

Every time you plug in an external drive, macOS quietly starts building a Spotlight index on it — consuming disk space and I/O you didn't ask for. **Spotlight Off** sits in your menu bar and takes care of it automatically.

- 🔌 **Detects** any external drive the moment it's mounted
- 🔍 **Checks** whether Spotlight indexing is currently enabled
- 🚫 **Disables** it instantly using `mdutil` — no password prompt required
- 🧾 **Logs** every action in a colour-coded activity log with green for success, red for failure
- 🔔 **Notifies** you with a subtle toast notification when a drive is processed
- 🚀 **Launches at login** so it's always running in the background
- 👋 **First-launch setup guide** walks you through the one required permission

Works with **APFS, HFS+, and exFAT** volumes. Disk images (.dmg files) and Time Machine volumes are automatically ignored.

---

## Screenshot

![Spotlight Off Screenshot](Screenshot%20Spotlight%20Off.jpg)

---

## Installation

1. Download the latest release from the [Releases](https://github.com/titleunknown/Spotlight-Off/releases) page
2. Move **Spotlight Off.app** to your `/Applications` folder
3. Launch it — the icon will appear in your menu bar
4. A **setup guide** will appear on first launch to walk you through the one required permission
5. Optionally enable **Launch at Login** in the settings window

---

## First-time setup

Spotlight Off only needs one permission: **Full Disk Access**.

### Full Disk Access

Open **System Settings → Privacy & Security → Full Disk Access** and make sure **Spotlight Off** is toggled on. That's it — no admin password prompt, no additional tools needed.

> Full Disk Access is what allows `mdutil` to disable Spotlight indexing without requiring root. Once granted, drives are processed automatically and silently every time they connect.

> You can reopen the setup guide at any time via the menu bar icon → **Setup Guide…**

---

## Usage

| Action | How |
|---|---|
| See recently processed drives | Click the menu bar icon |
| Open full history & settings | Click **History & Settings…** or press ⌘, |
| Reopen the setup guide | Click **Setup Guide…** in the menu |
| Remove a history entry | Select it in the list and press Delete |
| Clear all history | Click **Clear All** in the Settings & History tab |
| Enable launch at login | Toggle in the Settings & History tab |
| View activity log | Click the **Activity Log** tab in the settings window |
| Copy the activity log | Click **Copy All** in the Activity Log tab |
| Quit | Click **Quit Spotlight Off** in the menu |

---

## How it works

When a volume mounts, Spotlight Off:

1. Ignores disk images, Time Machine volumes, and internal or virtual volumes
2. Reads the volume's metadata flags to confirm it's a local, non-root, non-internal volume
3. Waits 4 seconds for the volume to fully initialise
4. Runs `mdutil -s` to check whether indexing is currently enabled
5. If enabled, runs `mdutil -i off` directly — no shell, no escalation
6. Records the result in the activity log and persistent history

Full Disk Access grants `mdutil` the permissions it needs to disable indexing without requiring root. All history is stored locally in `UserDefaults`. No network requests are made except for the optional update check against the GitHub releases API.

---

## Requirements

- macOS 14 Sonoma or later
- Full Disk Access (granted once in System Settings)

---

## Building from source

```bash
git clone https://github.com/titleunknown/Spotlight-Off.git
cd Spotlight-Off
open "Spotlight Off.xcodeproj"
```

Set your deployment target to **macOS 14.0**, select your development team in **Signing & Capabilities**, then build and run.

---

## Support development

Spotlight Off is free and open source. If it saves you time, consider buying me a coffee ☕

<div align="center">

  [![PayPal](https://img.shields.io/badge/Donate-PayPal-0070BA?style=for-the-badge&logo=paypal&logoColor=white)](https://www.paypal.com/donate/?hosted_button_id=AEY7AC82BKH5C)
  [![Venmo](https://img.shields.io/badge/Donate-Venmo-3D95CE?style=for-the-badge&logo=venmo&logoColor=white)](https://account.venmo.com/u/FAINI)
  [![Buy Me a Coffee](https://img.shields.io/badge/Buy_Me_a_Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/fainimade)

</div>

---

## License

Spotlight Off is licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). Free for personal and non-commercial use. For commercial licensing contact [fainimade.com](https://www.fainimade.com).
