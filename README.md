# iOSMiner

A real Bitcoin SHA-256d miner for jailbroken iOS devices. Connects to Stratum v1 mining pools, performs proof-of-work on the device CPU, and submits valid shares.

Built with SwiftUI and deployed as a `.deb` package via [Theos](https://theos.dev) for palera1n rootless jailbreaks.

## Features

- **Stratum v1 protocol** — Full TCP client with subscribe, authorize, job handling, and share submission
- **SHA-256d mining** — Correct block header construction with multi-threaded nonce iteration
- **Auto-reconnect** — TCP keepalive + exponential backoff reconnection on pool disconnect
- **Three mining modes** — Full (all cores), Eco (half), Tiny (1 thread)
- **Background mining** — Silent AVFoundation audio session keeps mining when the app is backgrounded
- **Live stats dashboard** — Session and lifetime stats with hashrate/shares graphs
- **Mining visualizer** — Bitcoin-themed particle system that reacts to hashrate with share explosion effects
- **WidgetKit extension** — Home screen widgets with near-real-time updates via timeline burst trick
- **Local notifications** — Configurable alerts for share acceptance, rejection, and pool disconnection
- **Pool presets** — HMPool, Solo CKPool, CKPool, Braiins, Kano, or custom
- **Silent mode** — Disables stats/logs/widget overhead for maximum hash throughput
- **1% dev fee** — 1 share per 100 accepted is mined to support development

## Requirements

- **Jailbroken iOS device** — Tested on iPad 6th gen (A10) with palera1n rootless
- **iPadOS/iOS 17.0+**
- **Theos** build system with iPhoneOS 17.0 SDK
- **Xcode** toolchain (for the Swift compiler)

## Project Structure

```
iOSMiner/
├── iOSMiner/                    # Swift source files
│   ├── iOSMinerApp.swift        # App entry point
│   ├── ContentView.swift        # Main TabView + MinerTab
│   ├── SettingsView.swift       # Pool, wallet, performance, notifications config
│   ├── StatsView.swift          # Live stats dashboard with graphs
│   ├── LogsView.swift           # Color-coded stratum log viewer
│   ├── ScreensaverView.swift    # Mining visualizer (CADisplayLink particles)
│   ├── MiningManager.swift      # Central coordinator: lifecycle, auto-reconnect, stats
│   ├── StratumClient.swift      # Stratum v1 TCP client (Network.framework)
│   ├── MiningEngine.swift       # Multi-threaded SHA-256d nonce iteration
│   ├── SHA256Util.swift         # Hex utils, double SHA-256, 256-bit difficulty target
│   ├── MiningMode.swift         # Full / Eco / Tiny mode definitions
│   ├── BackgroundHelper.swift   # Silent audio session for background execution
│   ├── DevFeeManager.swift      # 1% dev fee logic
│   ├── GlobalStats.swift        # Persisted lifetime mining statistics
│   ├── PoolPreset.swift         # Built-in pool presets
│   ├── SharedMiningData.swift   # Shared JSON file for widget data exchange
│   └── NotificationManager.swift # Local notification system
├── theos-build/                 # Theos build configuration
│   ├── Makefile                 # Build config (app + widget appex targets)
│   ├── control                  # Debian package metadata
│   ├── Info.plist               # iOS app bundle plist
│   ├── Entitlements.plist       # Network + App Groups entitlements
│   ├── deploy.sh                # Build + SCP + SSH install script
│   ├── icon.png                 # App icon source
│   ├── widget/                  # WidgetKit extension
│   │   ├── iOSMinerWidget.swift # Widget with timeline burst trick
│   │   ├── Info.plist           # Extension plist
│   │   └── WidgetEntitlements.plist
│   └── layout/DEBIAN/           # postinst / postrm scripts
└── iOSMiner.xcodeproj/         # Xcode project (secondary build path)
```

## Building

### Prerequisites

1. Install [Theos](https://theos.dev/docs/installation)
2. Ensure `$THEOS` is set (typically `~/theos`)
3. Symlink or copy the iPhoneOS 17.0 SDK into `$THEOS/sdks/iPhoneOS17.0.sdk`
   (needed for `Observation` framework support)

### Build

```bash
cd theos-build
make package FINALPACKAGE=1
```

The `.deb` is output to `theos-build/packages/`.

### Deploy

Create a `deploy.sh` in `theos-build/` (gitignored for security):

```bash
#!/bin/bash
set -e

DEVICE_IP="YOUR_DEVICE_IP"
DEVICE_USER="mobile"
DEVICE_PORT="22"
SUDO_PASS="YOUR_SUDO_PASSWORD"

export THEOS=~/theos

if [ "$1" != "--skip" ]; then
    make clean 2>/dev/null || true
    make package FINALPACKAGE=1
fi

DEB=$(ls -t packages/*.deb 2>/dev/null | head -1)
scp -P "$DEVICE_PORT" "$DEB" "$DEVICE_USER@$DEVICE_IP:/tmp/_iosminer.deb"

ssh -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" \
    "echo '$SUDO_PASS' | sudo -S dpkg -i /tmp/_iosminer.deb 2>&1 && \
     echo '$SUDO_PASS' | sudo -S uicache -p /var/jb/Applications/iOSMiner.app 2>&1 && \
     rm -f /tmp/_iosminer.deb"

echo "Done!"
```

```bash
chmod +x deploy.sh
./deploy.sh          # build + deploy
./deploy.sh --skip   # redeploy last build only
```

### Manual install

```bash
# Copy .deb to device
scp -P 22 packages/*.deb mobile@DEVICE_IP:/tmp/_iosminer.deb

# SSH in and install
ssh mobile@DEVICE_IP
sudo dpkg -i /tmp/_iosminer.deb
sudo uicache -p /var/jb/Applications/iOSMiner.app
```

## Configuration

On first launch, go to the **Settings** tab and configure:

1. **Pool** — Select a preset or enter custom host:port
2. **Wallet** — Your Bitcoin payout address
3. **Worker** — Optional worker name (pool identity: `wallet.worker`)
4. **Mode** — Full / Eco / Tiny (controls thread count)
5. **Notifications** — Toggle share alerts, set frequency, enable connection alerts

Then switch to the **Miner** tab and tap **Start**.

## Technical Details

### Stratum v1 Flow

1. TCP connect to pool (with TCP keepalive: 30s idle, 15s interval)
2. `mining.subscribe` — receive `extranonce1` and `extranonce2_size`
3. `mining.authorize` — authenticate with `wallet.worker`
4. Receive `mining.set_difficulty` and `mining.notify` (jobs)
5. For each job: construct coinbase, compute merkle root, build 80-byte block header
6. SHA-256d nonce iteration across multiple threads (unique `extranonce2` per thread)
7. Submit valid shares via `mining.submit` (nonce as big-endian hex)

### Block Header Byte Order

- `version`, `ntime`, `nbits` from stratum are big-endian — reversed to little-endian for the header
- `prevhash` requires 4-byte chunk swapping (8 groups of 4 bytes)
- Nonce submitted to pool as big-endian hex
- Difficulty target computed via byte-level 256-bit arithmetic (no floating-point precision loss)

### Widget

The WidgetKit extension reads mining state from a shared JSON file at:
```
/var/jb/var/mobile/Library/iOSMiner/widget.json
```
App Group `UserDefaults` doesn't work across app/extension boundaries on jailbreak, so a shared file is used instead. The widget uses a timeline burst trick (60 entries at 5-second intervals with `.atEnd` reload policy) for near-real-time updates.

### Auto-Reconnect

On pool disconnect (NWError 53, server close, etc.):
- Mining engine pauses
- Exponential backoff: 3s, 6s, 12s, 24s, capped at 30s
- Up to 50 reconnect attempts before stopping
- Session timers and stats persist across reconnects
- Backoff resets on successful re-authorization

## Donate

If you find iOSMiner useful, consider donating:

**BTC:** `16JXoJL46hAZSjtWrKYyoMcur1VtwWAbeB`

## License

MIT License. See [LICENSE](LICENSE).
