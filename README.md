# OBD2 Swift App (read-only 4Runner fork)

This fork turns the app into a **read-only** dashboard and drive logger for a 2024 Toyota 4Runner with an OBDLink CX (Bluetooth LE) adapter.

## What this fork changes

- **Read-only command gate.** `Packages/SwiftOBD2/Sources/SwiftOBD2/Safety/CommandGate.swift` is an allowlist checked before every adapter write, and again at the Bluetooth/Wi-Fi write. Only OBD modes 01, 03, 06, 07, 09, 0A, Toyota 21 82, a short list of adapter setup commands and headers 7DF/7E0/7E1 get through. Clear codes (04/14), session control, resets, security access, writes, I/O and routine control, downloads, STN commands, adapter EEPROM writes and any command with a line break in it are refused. Tests: `Packages/SwiftOBD2/Tests/SwiftOBD2Tests/CommandGateTests.swift`.
- **Clear Codes removed** from the library API and the Diagnostics screen.
- **One request at a time.** Adapter requests are serialized, and a manufacturer read (set header, request, restore header) runs as one locked unit.
- **SwiftOBD2 is vendored** in `Packages/SwiftOBD2` (MIT) and pinned, so an upstream change can't remove the gate.
- **Transmission fluid temp** (Toyota mode 21 PID 82) in `SwiftOBD2App/Toyota/ToyotaATF.swift`. **Unverified on this truck:** the PID and formula come from owner forums (GX460, Land Cruiser, Tacoma/4Runner). Raw bytes are logged with every reading so the formula can be corrected.
- **Drive screen** (Home > Drive): ATF pan/converter, coolant, speed, RPM, load; start/stop a logged drive.
- **Live Activity** (`DriveActivityExtension`): ATF and coolant on the lock screen, Dynamic Island and, on iOS 26, the CarPlay dashboard. Updates at most every 10 s, buzzes once when ATF turns hot (210°F warm, 240°F hot; starting guesses).
- **InfluxDB upload.** Each drive is buffered on the phone as line protocol and uploaded to InfluxDB v2 when the phone is on Wi-Fi (or with "Upload now"). Token in the Keychain; http only to LAN, `.local` or Tailscale (100.64/10) addresses.

## Why not a CarPlay app

Apple's CarPlay App Programming Guide limits driving-task apps to its templates, forbids refreshing data more than once every 10 seconds and names real-time engine data as not allowed. A Live Activity shows on the CarPlay dashboard in iOS 26 without the CarPlay entitlement.

## Setup

1. `brew install xcodegen && xcodegen`, then open `SwiftOBD2App.xcodeproj`.
2. Change `bundleIdPrefix` (and the extension's bundle ID) in `project.yml` to your own, and set your team.
3. A free Apple ID works, but the app expires after 7 days; a paid developer account ($99/yr) avoids that.
4. In InfluxDB, create a bucket (default name `obd`) and a token that can only write to it. Enter the URL, org, bucket and token under Drive > InfluxDB settings.
5. Grafana: query measurement `drive`, tags `vehicle` and `drive`, fields `atf_pan_f`, `atf_conv_f`, `coolant_f`, `speed_mph`, `rpm`, `load_pct`, `atf_raw`.

## Known gaps

- Nothing here has run against real hardware yet.
- Keep the app open on a mount while driving; polling in the background hasn't been tested.
- The CX's bonding window is the first 5 minutes after it's plugged in.

---

## Original README

Welcome to the OBD2 Swift App! This app will allow you to read error codes and view Parameter IDs (PIDs) from your vehicle's OBD2 system using Swift and CoreBluetooth.

https://github.com/kkonteh97/SmartOBD2/assets/55326260/40b862b7-44c1-44ae-b402-caa7cbda7683

## Getting Started

1. Clone this repository to your local machine.
2. Navigate to project directory on the terminal
```
cd SwiftOBD2App
```
3. Run command xcodegen
```
xcodegen
```
4. Open the Xcode project file (`SwiftOBD2App.xcodeproj`).
5. Build and run the app on a compatible iOS device.

## MileStones

- Connect to an OBD2 adapter via Bluetooth Low Energy (BLE) (completed)
- Retrieve error codes (DTCs) stored in the vehicle's OBD2 system (completed)
- View various OBD2 Parameter IDs (PIDs) for monitoring vehicle parameters (completed)
- Clean and intuitive user interface (in progress...)

## Current Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.5+

## Usage

1. Launch the app on your iOS device.
2. Make sure your OBD2 adapter is powered on and discoverable.

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are greatly appreciated.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement". Don't forget to give the project a star! Thanks again!


1. Fork the Project
2. Create your Feature Branch (git checkout -b feature/AmazingFeature)
3. Commit your Changes (git commit -m 'Add some AmazingFeature')
4. Push to the Branch (git push origin feature/AmazingFeature)
5. Open a Pull Request

## License

Distributed under the MIT License. See `LICENSE` for more information.



