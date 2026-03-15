# iOSMiner Widget — Implementation Plan

## Overview

Add a home screen WidgetKit widget to iOSMiner showing live mining stats.
The widget is a separate `.appex` (App Extension) embedded inside the main `.app` bundle.

## Architecture

```
iOSMiner.app/
  iOSMiner                    (main app binary)
  Info.plist
  PlugIns/
    iOSMinerWidget.appex/
      iOSMinerWidget           (widget binary)
      Info.plist
```

The main app writes mining stats to a **shared UserDefaults suite** (App Group).
The widget reads from the same suite to display current status.

## Data Flow

```
Main App  ──writes──>  UserDefaults(suiteName: "group.com.cooperwang.iosminer")
                            │
Widget    ──reads───>       │
```

### Shared keys (written by app, read by widget):

| Key                | Type   | Description                    |
|--------------------|--------|--------------------------------|
| `w_isMining`       | Bool   | Whether mining is active       |
| `w_hashrate`       | Double | Current H/s                    |
| `w_accepted`       | Int    | Session accepted shares        |
| `w_rejected`       | Int    | Session rejected shares        |
| `w_pool`           | String | Pool host:port                 |
| `w_uptime`         | Int    | Session elapsed seconds        |
| `w_lastUpdate`     | Double | TimeInterval since 1970        |
| `w_totalHashes`    | String | Lifetime total hashes (UInt64) |
| `w_totalAccepted`  | Int    | Lifetime accepted shares       |
| `w_bestHashrate`   | Double | Lifetime best H/s              |

## Widget Sizes

- **Small** (`.systemSmall`): Mining status icon + hashrate + accepted shares
- **Medium** (`.systemMedium`): All of small + pool name + uptime + rejected shares

## Implementation Steps

### Step 1: Shared Data Layer

Create `SharedMiningData.swift` in the main app source. This is a helper that
writes current mining state to the shared UserDefaults suite. Called from
`MiningManager` on a timer (every 2-5 seconds while mining).

Also used by the widget to read — so it needs a read-only interface too.
But since widget code is a separate binary, we duplicate the read logic in the
widget source (keeping it simple, no shared framework needed).

### Step 2: Widget Extension Source

Single file: `widget/iOSMinerWidget.swift`

Contains:
- `MinerEntry: TimelineEntry` — the data snapshot
- `MinerTimelineProvider: TimelineProvider` — reads from shared defaults
- `MinerWidgetSmallView` / `MinerWidgetMediumView` — SwiftUI views
- `@main struct iOSMinerWidget: Widget` — widget configuration

The timeline provider refreshes every 5 minutes (WidgetKit minimum is ~5 min).
For more frequent updates, the main app calls `WidgetCenter.shared.reloadAllTimelines()`
after each accepted share or state change — but this requires importing WidgetKit
in the main app (which is fine).

### Step 3: Widget Info.plist

```xml
NSExtension:
  NSExtensionPointIdentifier: com.apple.widgetkit-extension
CFBundleIdentifier: com.cooperwang.iosminer.widget
CFBundlePackageType: XPC!
```

### Step 4: Entitlements

**Widget** (`widget/WidgetEntitlements.plist`):
```xml
platform-application: true
com.apple.security.application-groups:
  - group.com.cooperwang.iosminer
```

**Main App** (`Entitlements.plist`) — add App Groups:
```xml
com.apple.security.application-groups:
  - group.com.cooperwang.iosminer
```

### Step 5: Makefile Changes

Theos has undocumented `appex.mk` support (`APPEX_NAME`). Use it:

```makefile
# After the APPLICATION include:
APPEX_NAME = iOSMinerWidget
iOSMinerWidget_SWIFT_FILES = widget/iOSMinerWidget.swift
iOSMinerWidget_FRAMEWORKS = SwiftUI WidgetKit
iOSMinerWidget_CODESIGN_FLAGS = -Swidget/WidgetEntitlements.plist
iOSMinerWidget_INSTALL_PATH = /Applications/iOSMiner.app/PlugIns
include $(THEOS_MAKE_PATH)/appex.mk
```

Plus an `after-` rule to copy the widget's `Info.plist` into the built `.appex`.

### Step 6: Main App Changes

1. Add `WidgetKit` framework to the main app's framework list
2. In `MiningManager`, write stats to shared defaults on a timer
3. Call `WidgetCenter.shared.reloadAllTimelines()` on state changes:
   - Mining started/stopped
   - Share accepted/rejected
   - Every ~30 seconds during mining

### Step 7: Deploy & Test

1. Build with `make package FINALPACKAGE=1`
2. SCP and install the `.deb`
3. Run `uicache -p /var/jb/Applications/iOSMiner.app`
4. Possibly respring: `killall SpringBoard`
5. Long-press home screen → Add Widget → search "iOSMiner"

## Fallback: If App Groups Don't Work

On jailbreak, if `UserDefaults(suiteName:)` doesn't cross the app/widget boundary:

Use a shared file at a known path:
```swift
let sharedPath = "/var/jb/var/mobile/Library/iOSMiner/widget_data.json"
```

Both app and widget can read/write this file since jailbreak removes sandbox.

## Risks

- **No known examples exist** of WidgetKit + Theos in the wild. This is uncharted territory.
- `chronod` (the widget daemon) may have issues launching extensions from `/var/jb/Applications/`.
- Tweak injection into the widget process could cause crashes.
- The `appex.mk` in Theos is undocumented and may have edge cases.
- If App Groups don't work, the shared file fallback should handle it.

## Files to Create/Modify

| File | Action |
|------|--------|
| `widget/iOSMinerWidget.swift` | **CREATE** — Widget extension code |
| `widget/Info.plist` | **CREATE** — Widget Info.plist |
| `widget/WidgetEntitlements.plist` | **CREATE** — Widget entitlements |
| `iOSMiner/SharedMiningData.swift` | **CREATE** — Shared data writer |
| `Entitlements.plist` | **MODIFY** — Add App Groups |
| `Makefile` | **MODIFY** — Add APPEX build |
| `iOSMiner/MiningManager.swift` | **MODIFY** — Write shared data + reload widget |
