<div align="center">
  <img src="spotlightofficon.png" width="150" alt="Spotlight Off Icon" />

  # Spotlight Off

  **Automatically disables Spotlight indexing on external drives the moment they're connected.**

  ![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue?style=flat-square&logo=apple)
  ![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift)
  ![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)

</div>

---

## What it does

Every time you plug in an external drive, macOS quietly starts building a Spotlight index on it — consuming disk space and I/O you didn't ask for. **Spotlight Off** sits in your menu bar and takes care of it automatically.

- 🔌 **Detects** any external drive the moment it's mounted
- 🔍 **Checks** whether Spotlight indexing is currently enabled
- 🚫 **Disables** it instantly using `mdutil`, with a one-time admin prompt
- 📋 **Logs** every action in a live activity log inside the app
- 🚀 **Launches at login** so it's always running in the background
- 👋 **First-launch setup guide** walks you through all required permissions

---

## Screenshot

![Spotlight Off Screenshot](Screenshot%20Spotlight%20Off.jpg)

---

## Installation

1. Download the latest release from the [Releases](https://github.com/titleunknown/Spotlight-Off/releases) page
2. Move **Spotlight Off.app** to your `/Applications` folder
3. Launch it — the icon will appear in your menu bar
4. A **setup guide** will appear on first launch to walk you through the required permissions
5. Optionally enable **Launch at Login** in the settings window

### ⚠️ Gatekeeper warning
This app is not notarized (Apple Developer Program enrollment required for notarization). On first launch you will see a warning saying the app can't be verified. To open it:
1. Right-click **Spotlight Off.app** and choose **Open**
2. Click **Open** in the dialog that appears

You only need to do this once.

---

## First-time setup

When you first launch Spotlight Off, a setup guide will walk you through three things:

### 1. Full Disk Access
Both **Spotlight Off** and **osascript** need Full Disk Access. osascript is the built-in macOS tool the app uses to run `mdutil` with administrator privileges — if it doesn't have Full Disk Access, the command will fail even after you enter your password.

**System Settings → Privacy & Security → Full Disk Access**, then click **+** to add each one.

To add osascript manually:
1. Click the **+** button in the Full Disk Access list
2. Press **⌘ Shift G** to open the "Go to folder" dialog
3. Paste `/usr/bin/osascript` and press **Enter**
4. Click **Open**

> **Note:** osascript may not appear in the Full Disk Access list automatically. Adding it manually via the path above is the most reliable approach.

### 2. About the admin password prompt
When a drive is first processed, macOS will ask for your administrator password. This is handled securely by **osascript** — a built-in macOS tool that allows the app to run a single privileged command (`mdutil`) without the entire app needing root access. Your password is never stored or seen by Spotlight Off.

> You can reopen the setup guide at any time from the menu bar icon → **Setup Guide…**

---

## Usage

| Action | How |
|---|---|
| See recently processed drives | Click the menu bar icon |
| Open full history & settings | Click **History & Settings…** or press ⌘, |
| Reopen the setup guide | Click **Setup Guide…** in the menu |
| Remove a history entry | Select it in the list and press Delete |
| Clear all history | Click **Clear All** in the settings window |
| Enable launch at login | Toggle in the settings window |
| View activity log | Scroll to the bottom of the settings window |
| Quit | Click **Quit Spotlight Off** in the menu |

---

## How it works

When a volume mounts, Spotlight Off:

1. Reads the volume's metadata flags to confirm it's a local, non-root external volume
2. Waits 1.5 seconds for the volume to fully settle
3. Runs `mdutil -s` to check whether indexing is currently enabled
4. If enabled, runs `mdutil -i off` via `osascript` with administrator privileges
5. Records the result in the persistent history log

All history is stored locally in `UserDefaults`. No network requests are ever made.

---

## Requirements

- macOS 13 Ventura or later
- Administrator access (required once per drive, to run `mdutil`)

---

## Building from source

```bash
git clone https://github.com/titleunknown/Spotlight-Off.git
cd Spotlight-Off
open "Spotlight Off.xcodeproj"
```

Select your development team in **Signing & Capabilities**, then build and run.

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

MIT — see [LICENSE](LICENSE) for details.
