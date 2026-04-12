# ScreenTimeTracker

A native macOS menu bar app that tracks screen-on time (SOT) between full battery charge cycles on a MacBook. Shows a color-coded battery icon with percentage and your current session's screen-on time — all in the menu bar.

---

## What It Does

ScreenTimeTracker monitors how long your screen is actually on during each battery discharge cycle. Unlike macOS Screen Time, it focuses on battery usage patterns — giving you a clear picture of how much screen time you get per charge.

### Menu Bar Display
- **SOT time** — screen-on time for the current charge cycle, color coded:
  - 🟢 Green: 0–4 hours
  - 🟠 Orange: 4–8 hours
  - 🔴 Red: 8+ hours
  - ⚫ Grey + ⏸: SOT paused (charging or battery recovering)
- **Battery icon** — horizontal battery with % inside, color coded:
  - 🟢 Green: above 60%
  - 🟡 Yellow: 31–60%
  - 🟠 Orange: 16–30%
  - 🔴 Red: 15% and below
  - 🔵 Blue: charging

### Dropdown Menu
- Current session stats: Screen On (SOT), Total screen-on, Idle, Screen Off, Total since charge
- Usage stats: daily average, this week vs last week trend
- Screen-on averages: per session over 7d / 30d / 6mo / 1yr / all time
- Full charge equivalent: extrapolated SOT for a 100→0% discharge
- Session history: last 10 sessions with SOT, total time, drain %
- Actions: Reset session, Backup Now, Restore from Backup, Quit

### SOT Counting Rules
- SOT only counts when **discharging AND battery % ≤ plug-in %**
- When you plug in at 67%, SOT pauses until battery drains back to 67%
- Session resets only when battery reaches 98%+ (full charge)
- Handles lid-close charging, shutdown overnight charging, and reboots correctly

### Session Detection
- **Case 1**: App directly observes unplug at 98%+
- **Case 2**: On wake, battery jumped 5%+ from session start (lid-close charge)
- **Case 3**: On startup, gap ≥ 4 hours at 98%+ (shutdown overnight charge)

---

## Requirements

- macOS 13 or later
- Apple Silicon or Intel MacBook (requires a battery — desktop Macs not supported)
- No Homebrew, Python, or other dependencies needed

---

## Installation

### First Time
1. Download or build `ScreenTimeTracker.app`
2. Copy it to `/Applications/`
3. Double-click to launch
4. macOS may show an "unidentified developer" warning — go to **System Settings → Privacy & Security** and click **Open Anyway**
5. The battery icon will appear in your menu bar

### Auto-start on Login
1. Go to **System Settings → General → Login Items & Extensions**
2. Click **+** under "Open at Login"
3. Select **ScreenTimeTracker.app** → click Open

---

## Building from Source

### Requirements
- Xcode 15 or later
- macOS 13 SDK or later
- Apple Developer account (free tier is sufficient)

### Steps
1. Clone or download the repository
2. Open `ScreenTimeTracker.xcodeproj` in Xcode
3. Select your Apple ID team in **Signing & Capabilities**
4. Press **Cmd+R** to build and run
5. For a release build: **Product → Scheme → Edit Scheme** → set Run to Release, then **Cmd+B**
6. Find the built app at **Product → Show Build Folder in Finder → Products → Release**

---

## Installing on Another Mac

1. Copy `ScreenTimeTracker.app` to `/Applications/` on the new Mac
2. Follow the Installation steps above
3. Sessions start fresh — to transfer history, copy this file from your old Mac:
```
~/Library/Application Support/ScreenTimeTracker/sessions.json
```
4. Also create the backup folder if it doesn't exist:
```bash
mkdir -p ~/Documents/Backup\ files/MacScreenTime
```

---

## Data & Files

| File | Purpose |
|------|---------|
| `~/Library/Application Support/ScreenTimeTracker/sessions.json` | Session history and current session state |
| `~/Library/Application Support/ScreenTimeTracker/prefs.json` | App preferences (weekly notification state) |
| `~/Documents/Backup files/MacScreenTime/sessions_YYYY-MM-DD.json` | Daily automatic backups |

### Backups
- A backup is created automatically every day
- Up to 365 daily backups are kept
- You can create a manual backup any time via **Backup Now** in the dropdown
- Restore any backup via **Restore from Backup** in the dropdown

---

## Weekly Notifications
Every Monday morning (after 8am), the app sends a notification summarising:
- Last week's total screen-on time
- Trend vs the previous week
- Daily average

---

## Privacy
- All data is stored locally on your Mac
- No network requests are made
- Battery is read via IOKit (no shell commands or special permissions needed)
- No telemetry or analytics

---

## License

MIT License — feel free to use, modify, and distribute.

---

## Acknowledgements
Built with Swift and SwiftUI. Battery reading uses Apple's IOKit framework.
