# Location Changer

[![Build macOS app](https://github.com/OceanBlvd07/LocationChanger/actions/workflows/build.yml/badge.svg)](https://github.com/OceanBlvd07/LocationChanger/actions/workflows/build.yml)

A native macOS interface for simulating an iPhone's location through its developer services. Find a place, drag a marker to refine the coordinates, and start a simulation from a Liquid Glass sidebar.

Built with **SwiftUI, AppKit, and MapKit**, with **pymobiledevice3** providing the local connection to the iPhone.

> **Project status:** working developer prototype with USB and Wi-Fi operation tested through an iPhone Personal Hotspot. Build with Xcode, then run the built app directly if desired. A separately installed Python backend is still required; a self-contained distribution is not provided.

## Contents

- [Features](#features)
- [Requirements and compatibility](#requirements-and-compatibility)
- [Getting started](#getting-started)
- [Wi-Fi setup](#wi-fi-setup)
- [Using the app](#using-the-app)
- [Running without Xcode](#running-without-xcode)
- [Stopping, disconnecting, and quitting](#stopping-disconnecting-and-quitting)
- [How it works](#how-it-works)
- [Project structure](#project-structure)
- [Privacy and local data](#privacy-and-local-data)
- [Development and CI](#development-and-ci)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [Acknowledgments and licensing](#acknowledgments-and-licensing)

## Features

- Native macOS interface with a Liquid Glass sidebar.
- Apple Maps place and address search.
- Click-to-place location marker.
- Native draggable marker with coordinate updates while dragging.
- Editable latitude and longitude fields linked to the marker.
- Center-on-selection action.
- Connected-device discovery and JSON decoding.
- USB and Wi-Fi discovery badges, device details, and a last-checked timestamp.
- Wireless operation on reachable local networks, tested using an iPhone Personal Hotspot.
- A scrollable control area with a separate device-status section.
- Start simulation and explicit location-clear commands.
- Time-limited waits during shutdown.
- Process-exit notifications.
- Cleanup retry after reconnecting a device.
- Cleanup attempts during normal application quitting.
- Backend file picker with a locally remembered selection.
- GitHub Actions build checks.

Changing the map selection does **not** change a running simulation. Stop the existing session, choose another location, and start again.

## Requirements and compatibility

| Component | Requirement or current status |
| --- | --- |
| Host | A Mac running a system compatible with the project's deployment target |
| UI | macOS 26 APIs, including Liquid Glass |
| Current deployment setting | `MACOSX_DEPLOYMENT_TARGET = 26.6.2` in the checked project |
| Build tools | Xcode with an SDK that supports the configured deployment target |
| Python | Python 3.13 used for the documented setup |
| Backend | `pymobiledevice3`, installed separately |
| Device | A compatible iPhone, paired with the Mac, with Developer Mode enabled |
| Connection | USB or a reachable local Wi-Fi connection; initial pairing and wireless enablement use USB |
| Network | Needed for dependency installation, map content, search, and developer-image downloads when required |

### Tested development setup

The project's manual development testing used:

- iPhone 17 Pro Max running **iOS 26.6.2**.
- Python **3.13.7**.
- `pymobiledevice3` **11.45.0**.
- USB discovery, simulation, and cleanup.
- Wireless discovery, developer-service access, and simulation through the iPhone’s Personal Hotspot.

Wireless discovery did not work on the residence Wi-Fi used during development, while the hotspot did. The network policy responsible has not been confirmed.

This is a record of one development setup, not a broad compatibility guarantee. No Intel/Apple Silicon compatibility matrix or comprehensive iOS-version matrix has been established.

**The iPhone's iOS version and the Mac app's deployment target are separate settings.** The app uses macOS 26 features, but the checked project currently specifies the more restrictive target `26.6.2`. Review that value in Xcode before claiming support for every macOS 26 release. Older macOS support would require availability handling and UI changes.

## Getting started

### 1. Clone the repository

```sh
git clone https://github.com/OceanBlvd07/LocationChanger.git
cd LocationChanger
```

For a private repository, authenticate with an account that has access.

### 2. Check the developer tools

```sh
xcodebuild -version
python3.13 --version
```

If `xcodebuild` reports that the active developer directory is Command Line Tools rather than Xcode, select Xcode in **Xcode → Settings → Locations → Command Line Tools**, or use:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

Adjust that path if Xcode is installed elsewhere. Complete any first-launch setup requested by Xcode.

### 3. Install the Python backend

From the repository root:

```sh
python3.13 -m venv .venv
.venv/bin/python -m pip install pymobiledevice3
.venv/bin/pymobiledevice3 --help
```

To reproduce the backend version used during development instead of installing the latest release:

```sh
.venv/bin/python -m pip install 'pymobiledevice3==11.45.0'
```

Choose one installation approach. Backend behavior may change between versions; record the installed version when reporting problems:

```sh
.venv/bin/python -m pip show pymobiledevice3
```

The app does not install or update this dependency automatically. The `.venv/` directory is excluded from Git.

### 4. Pair the iPhone

1. Connect the iPhone to the Mac using USB.
2. Unlock the phone.
3. Approve **Trust This Computer** if prompted.
4. Enter the device passcode on the iPhone itself.

Verify discovery:

```sh
.venv/bin/pymobiledevice3 usbmux list
```

The result should contain the connected device. Connect only one device when starting a simulation with this prototype.

### 5. Enable Developer Mode

On the iPhone, open **Settings → Privacy & Security → Developer Mode** and follow the restart and confirmation prompts.

If the option is missing, consult the backend's current setup documentation. Developer Mode reduces some device security protections; enable it deliberately for development.

The desktop app does not ask for your Apple Account password.

### 6. Prepare developer support

Keep the phone connected and unlocked:

```sh
.venv/bin/pymobiledevice3 mounter auto-mount
```

This prepares the Developer Disk Image used by the developer services and may download support files. If it reports that an image is already mounted, preparation may already be complete; do not uninstall it simply because this message appears.

Check the developer connection:

```sh
.venv/bin/pymobiledevice3 developer dvt device-information
```

Transport and developer-image behavior depend on the installed backend and iOS versions. Use the [upstream documentation](https://doronz88.github.io/pymobiledevice3/) when these preparation steps fail.

### 7. Open and run the app

```sh
open LocationChanger.xcodeproj
```

In Xcode:

1. Select the **LocationChanger** scheme.
2. Select **My Mac** as the run destination.
3. Use the **Debug** configuration.
4. Press **⌘R**.

The checked project disables App Sandbox for Debug to allow the external Python backend to run. Release still has Sandbox enabled and is not an equivalent, ready-to-distribute configuration.

### 8. Select the backend

Click the gear button in the sidebar. Select:

```text
<repository-root>/.venv/bin/pymobiledevice3
```

Select the executable file, not the Python interpreter or the `.venv` directory. The picker displays hidden files. You can also press **⌘⇧G** in the picker and enter the full path.

The selection is stored locally and restored on subsequent launches. Choose it again if you move, delete, or recreate the environment at a different path.

Click **Refresh connection** to verify that the UI can invoke the selected backend.

## Wi-Fi setup

USB is useful for initial preparation, but the phone does not need to stay physically connected when a working wireless developer connection is available.

### One-time enablement

Stop any active simulation. Connect the iPhone by USB, unlock it, and run from the repository root:

```sh
# Allow wireless connections for paired computers.
.venv/bin/pymobiledevice3 lockdown wifi-connections on
```

Wireless enablement normally persists, so this command is not intended to run before every session. Re-pairing, device settings changes, or environment changes can require setup to be repeated.

### Connect over a local network

1. Connect the Mac and iPhone to the same Wi-Fi network, or connect the Mac to the iPhone's **Personal Hotspot**.
2. Disconnect USB and keep the phone unlocked for the initial check.
3. Allow a few seconds for discovery, then run:

```sh
.venv/bin/pymobiledevice3 usbmux list
```

Wireless discovery should report:

```json
"ConnectionType": "Network"
```

The command is named `usbmux list`, but it can report both USB and network device entries. Confirm access to the developer services without a cable:

```sh
.venv/bin/pymobiledevice3 developer dvt device-information
```

If both checks succeed, open the app, click **Refresh connection**, and test Start and Stop while keeping the Mac awake and the network connection available. Verify the real location after clearing, just as with USB.

No separate Wi-Fi toggle in the app is required for the tested setup: the existing backend discovers the network connection.

### Everyday wireless use

After initial setup:

1. Establish the local network connection or hotspot.
2. Open the app and refresh discovery.
3. Start the simulation only after the phone is reachable.
4. Keep the Mac, app, and network connection running.
5. Stop and verify cleanup before disconnecting the network.

This is **wireless operation with a reachable Mac**, not standalone operation on the iPhone. Seamless transfer of an active session from USB to Wi-Fi is not implemented or guaranteed. Start the session using the intended connection rather than assuming it will migrate when the cable is removed.

### Residence, campus, guest, and public networks

Sharing an SSID does not guarantee that two devices can communicate. A network may restrict client-to-client traffic or discovery such as Bonjour/mDNS. In the development setup, using the iPhone's hotspot allowed discovery when residence Wi-Fi did not; that comparison suggests a network-specific restriction but does not identify the exact policy.

A computer appearing under **Finder → Network** does not prove that iPhone discovery or developer services are reachable. Use `usbmux list` and the developer-information command as the checks for this workflow. An iPhone is not expected to appear there as an ordinary file-sharing computer.

If wireless discovery fails:

- Confirm that the devices are on the intended network rather than separate guest and main networks.
- Confirm that USB pairing works before debugging Wi-Fi.
- If applicable, check **Finder → iPhone → General → Show this iPhone when on Wi-Fi**, then Apply while connected by USB.
- Check whether the network has device registration or a personal-device grouping feature.
- Ask the administrator whether communication between your own devices and Bonjour/mDNS discovery are supported.
- Compare with a trusted home network or Personal Hotspot.

Enabling File Sharing on the Mac is not required. If client isolation is enforced by the network, there is no general Mac setting that overrides it.

See the backend's [wireless transport documentation](https://doronz88.github.io/pymobiledevice3/guides/ios17-tunnels/) for version-specific connection requirements.

## Using the app

### Select a location

Use any of these methods:

- **Search:** enter a place or address, then click Search or press Return. The current implementation selects the first result.
- **Map:** click the map to place the marker.
- **Drag:** select the marker, then click-and-hold and drag to refine its position.
- **Coordinates:** edit latitude and longitude directly. Valid values move the marker; press Return or use **Center on selection** to bring it into view.

Latitude must be between `-90` and `90`; longitude must be between `-180` and `180`. Use a decimal point. Incomplete or invalid input temporarily removes the marker and disables Start.

The map can be panned and zoomed without changing the selected geographic location. Rotation and pitch are disabled in the native map component.

### Read the connection section

The sidebar lists discovered device entries with their names, iOS versions, and transport badges:

| Badge | Backend value | Meaning |
| --- | --- | --- |
| USB | `USB` | The phone was discovered through USB |
| Wi-Fi | `Network` | The phone was discovered through the network |
| Unknown or another value | Missing or unrecognized value | The reported transport is not one of the known labels |

The same phone may appear twice when both routes are available. That is not necessarily two physical devices.

**These badges describe the last discovery result, not a live connection monitor or confirmation of the simulation's chosen transport.** Check the **Last checked** timestamp and use **Refresh connection** after changing the connection. Starting a simulation also refreshes the discovery snapshot. If discovery fails, the previous snapshot is cleared rather than shown as a fresh result.

### Start a simulation

1. Make the prepared iPhone reachable by USB or Wi-Fi and unlock it for setup.
2. Select a location.
3. Click **Start simulation**.
4. Open Apple Maps on the iPhone and check the reported current location.

The app checks that exactly one unique device identifier is discoverable, then launches the simulation command. The same phone appearing through both USB and Wi-Fi counts as one device.

**“Simulation launched” means the process was launched. It is not device-side confirmation that the location changed.** Check the phone separately. Behavior in Find My and third-party applications should be verified individually and may vary or be cached.

### Stop a simulation

1. Keep or reconnect the iPhone to the Mac.
2. Click **Stop / restore location**.
3. Wait for the result.
4. In Apple Maps, request the current location and verify that a fresh fix represents your real position.

A successful clear command is not proof of a fresh GPS fix. A grey dot, an old timestamp, or a stale position is not sufficient verification.

## Running without Xcode

Once a working **Debug** build exists, it can be launched directly:

1. End any active simulation and quit the app.
2. Build in Xcode with **⌘B** using the Debug configuration.
3. Choose **Product → Show Build Folder in Finder**.
4. Locate **Products → Debug → LocationChanger.app**.
5. Copy the app into **Applications** and launch it there.

Keep the project's Python environment at its selected location. Copying the `.app` does not bundle Python or `pymobiledevice3`. The saved backend selection should remain available for the same user and app identity; select it again if necessary.

Rebuild and replace the Applications copy after code or asset changes. The project includes app-icon assets, but an older copied build will not pick up new icons automatically.

This is local use of a development build, not a signed and notarized installer workflow. Release remains sandboxed and needs a separate packaging and access review.

## Stopping, disconnecting, and quitting

### Shutdown sequence

The current backend wrapper:

1. Sends an interrupt to the simulation process.
2. Waits up to three seconds.
3. Requests termination if necessary and waits up to three more seconds.
4. Attempts the separate `clear` command even if the original process did not exit.
5. Waits up to twenty seconds for that command.
6. Checks both the clear command's exit status and whether the original process remains alive.

Session references and the cleanup-needed flag are reset only after those checks succeed. These bounds prevent indefinite waits in the implemented shutdown checks; they do not guarantee all processes or device operations have stopped after a timeout.

### Losing the active connection

Wireless sessions can work without USB when the phone remains reachable over the local network. However, removing USB during an existing USB session is not a guaranteed handoff to Wi-Fi. Losing the hotspot, leaving the network, or putting the Mac to sleep can also break reachability.

The phone may retain a simulated location, revert, or display a stale location after a connection is lost. Persistence away from the Mac is not guaranteed.

If Stop fails, restore a working network connection or reconnect by USB, then retry. A cleanup failure keeps recovery controls available rather than assuming restoration succeeded.

### Normal quitting

During normal quitting, such as **⌘Q**, the app attempts cleanup if a session still needs it. If cleanup fails, it cancels quitting and displays an alert so the device can be reconnected and cleanup retried.

Closing a window is not necessarily the same as quitting a macOS app. The implementation handles application termination; it does not provide a separate window-close cleanup guarantee.

**Xcode Stop, Force Quit, crashes, and abrupt shutdown can bypass normal quit handling.** Do not assume that ending the desktop app clears the phone's simulated location.

Avoid pressing Stop and Quit simultaneously: serialization between those cleanup paths remains unfinished.

### Recovery

If the phone does not regain a fresh real location:

1. Stop starting new simulations.
2. Reconnect and unlock the iPhone.
3. Retry cleanup.
4. If necessary, stop the desktop app and restart the iPhone, then check Apple Maps again.

During development, explicit cleanup can also be requested from the repository root:

```sh
.venv/bin/pymobiledevice3 developer dvt simulate-location clear
```

If the app still owns a running session, use its Stop action first. Do not run multiple simulation controllers against the same phone.

## How it works

```text
SwiftUI sidebar and coordinate state
                 │
        ┌────────┴─────────┐
        │                  │
Native MKMapView     LocationSearchService
marker and gestures      Apple Maps search
        │
Selected coordinates
        │
DeviceConnection → Foundation.Process
        │
Locally installed pymobiledevice3
        │
USB or local Wi-Fi transport
        │
iPhone developer services
```

- **SwiftUI** provides the screen, state bindings, and Liquid Glass surface.
- **AppKit** provides the file picker, alerts, and application lifecycle hooks.
- **MKMapView**, embedded through `NSViewRepresentable`, manages geographic positioning and native draggable annotations.
- A coordinator bridges map clicks and drag updates into SwiftUI bindings.
- **MapKit search** resolves a query and returns the first matching map item.
- **Foundation.Process** launches the selected backend directly with separate arguments, without constructing a shell command.
- Device discovery output is decoded into Swift models using `JSONDecoder`, including the optional `ConnectionType` field.
- Physical devices are counted by identifier so duplicate USB and Wi-Fi discovery entries do not prevent startup.
- Blocking discovery and shutdown work runs in background tasks; UI updates return to the main actor.

The native interface is Swift. The iPhone transport and developer protocol implementation are supplied by Python, not reimplemented in Swift.

### Backend commands

```sh
# Discover connected devices.
pymobiledevice3 usbmux list

# Start a fixed location simulation.
pymobiledevice3 developer dvt simulate-location set -- LATITUDE LONGITUDE

# Request removal of a simulated location.
pymobiledevice3 developer dvt simulate-location clear
```

In the tested backend version, the set command waits for **SIGINT or SIGTERM**. Sending a newline to stdin is not the stop mechanism. The Swift wrapper retains an input pipe, but uses process signals for shutdown.

## Project structure

```text
LocationChanger/
├── .github/
│   └── workflows/
│       └── build.yml
├── .gitignore
├── LocationChanger.xcodeproj/
│   └── xcshareddata/xcschemes/LocationChanger.xcscheme
└── LocationChanger/
    ├── MyApp.swift
    ├── AppDelegate.swift
    ├── ContentView.swift
    ├── LocationMapView.swift
    ├── LocationSearch.swift
    ├── DeviceConnection.swift
    ├── ConnectedDevice.swift
    └── Assets.xcassets/
```

| File | Responsibility |
| --- | --- |
| `MyApp.swift` | SwiftUI entry point and shared connection injection |
| `AppDelegate.swift` | Owns the connection and handles normal quit cleanup |
| `ContentView.swift` | Sidebar, view state, search actions, device actions, and status messages |
| `LocationMapView.swift` | Native map wrapper, annotation dragging, coordinate bindings, and recenter requests |
| `LocationSearch.swift` | Contains `LocationSearchService`, which performs MapKit search |
| `DeviceConnection.swift` | Backend selection, discovery, process lifecycle, and clear commands |
| `ConnectedDevice.swift` | Decodable device fields and USB / Wi-Fi display labels and symbols |
| `build.yml` | GitHub Actions build workflow |

There is no separate screen model in the current design. Screen state intentionally remains in `ContentView` while map and backend behavior live in separate components.

## Privacy and local data

The current Swift application has:

- No account system or Apple Account credential form.
- No application-owned telemetry or upload server implemented in the checked source.
- No location-history database or saved-location collection.
- A backend path stored in `UserDefaults` under `backendExecutablePath`.
- Session, selected-coordinate, and last-discovery snapshot state held in memory.
- Backend output and diagnostics printed to the development console.

**This does not make the complete workflow offline.** Apple Maps content and place search use Apple's services, and dependency installation and developer-image preparation may contact external services. The separately installed Python backend has its own behavior, dependencies, caches, and pairing data.

Executable-file validation checks whether a selected file can be executed. It does not verify its publisher or establish that it is trustworthy. Select the backend installed for this project.

Device-discovery output includes identifiers. Remove device identifiers, personal device names, and private paths before posting diagnostic output publicly. Keep pairing records private.

For details about Apple Maps data handling, consult [Apple Maps & Privacy](https://www.apple.com/legal/privacy/data/en/apple-maps/).

### What location simulation does not change

This app uses the iPhone's developer location-simulation services. It does not rewrite the physical GPS receiver, change your public IP address, act as a VPN, or change an account's billing/store region. A website checking country by IP can still see the country of your internet connection. A browser or app requesting system geolocation may receive simulated coordinates, while other signals and cached data may differ.

## Development and CI

### Local build

From the repository root:

```sh
xcodebuild \
  -project LocationChanger.xcodeproj \
  -scheme LocationChanger \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

This checks compilation without requiring signing certificates. A successful build does not verify device communication or restore behavior.

### Continuous integration

The **Build macOS app** workflow runs on pushes, pull requests, and manual dispatch. It:

- Uses a `macos-26` GitHub-hosted runner.
- Checks out the repository.
- Prints the selected Xcode version.
- Builds the shared `LocationChanger` scheme in Debug with signing disabled.
- Cancels superseded runs in the same concurrency group.

CI does not connect an iPhone, install or exercise the Python backend, test GPS recovery, or produce a signed release. The runner's installed Xcode must support the project's deployment target; inspect the printed Xcode version when diagnosing build failures.

[View workflow runs](https://github.com/OceanBlvd07/LocationChanger/actions/workflows/build.yml).

### Manual verification

Before describing a change as working, check the relevant paths:

- Search returns a location and centers the map.
- Clicking places the marker.
- Dragging updates coordinates without moving the map unexpectedly.
- Panning and zooming preserve the marker's geographic position.
- Manual coordinate edits update the marker; Return recenters it.
- Invalid coordinates disable Start.
- Backend selection persists across launches.
- Starting without a connected phone is rejected.
- Starting with more than one unique device identifier is rejected.
- The same phone discovered over USB and Wi-Fi counts as one physical device.
- Discovery shows correct transport labels and a timestamp after refresh.
- Wireless discovery and developer-service access work on the intended network.
- A wireless session can be started and cleared, with recovery checked on the phone.
- Scrolling the sidebar does not overlap the fixed connection section.
- A connected session can be started and cleared, with real location verified on the phone.
- Cleanup can be retried after reconnecting.
- Normal quitting attempts cleanup and cancels quitting on failure.

Some behaviors were manually exercised during development; this list is a regression checklist, not evidence of automated test coverage.

## Troubleshooting

### “Choose your pymobiledevice3 executable first”

Use the sidebar gear button to select `.venv/bin/pymobiledevice3`. Confirm that the environment still exists at the saved path.

### “The file pymobiledevice3 doesn't exist” even though Terminal sees it

Check both the executable and its interpreter:

```sh
ls -l .venv/bin/pymobiledevice3
head -n 1 .venv/bin/pymobiledevice3
.venv/bin/python --version
```

A virtual environment contains absolute interpreter paths and may need to be recreated after moving the project. The app's access restrictions can also differ from Terminal's.

The documented configuration uses **Debug with App Sandbox disabled**. Release remains sandboxed. Do not assume that changing file permissions solves a sandbox restriction.

### No iPhone is detected

Check the USB cable, unlock the phone, confirm trust, and run:

```sh
.venv/bin/pymobiledevice3 usbmux list
```

If discovery fails in Terminal too, resolve pairing or transport before debugging the interface.

### USB works but residence Wi-Fi does not

Test on the Personal Hotspot or another trusted network. Compare both discovery and developer-service access; a device listing alone does not establish that the developer connection works. Ask the network administrator about client isolation, peer traffic, and Bonjour/mDNS rather than assuming Finder's Network list proves reachability.

### USB and Wi-Fi show the same phone twice

This is expected when two discovery routes are available. The sidebar displays both entries, while startup counts unique identifiers. The UI does not currently let you choose a transport explicitly.

### The connection badge still says Wi-Fi after disconnecting

It is a last-checked snapshot. Click **Refresh connection** and inspect the timestamp. Continuous connection monitoring is not implemented.

### Discovery succeeds, but simulation fails

Discovery alone does not prove developer services are ready. Verify Developer Mode, developer-image preparation, and the developer connection using the setup commands above.

### Start is disabled

Check for invalid coordinates, an operation in progress, or a session still requiring cleanup. If a session is pending cleanup, reconnect the device and retry Stop instead of launching another session.

### Stop fails after unplugging or losing Wi-Fi

Restore reachability and unlock the phone, then retry Stop. Wireless cleanup has worked on the tested hotspot setup, but automatic transport handoff or recovery after a connection change is not guaranteed. Reconnecting by USB remains a recovery option.

### Stop reports success but Maps shows an old or grey dot

The clear command completed, but the phone may not have a fresh real-location fix. Request the current location in Maps and verify it independently. If necessary, use the recovery steps above. Do not treat a successful process exit as proof of GPS restoration.

### The app stays open after Quit

Cleanup failed and the app deliberately canceled quitting. Reconnect the phone and retry cleanup. Force Quit bypasses that recovery workflow.

### Input borders or focus rings look clipped

The scroll view uses `scrollClipDisabled(false)` to keep content out of the fixed device section. Its content has internal horizontal and vertical padding to leave room for field borders and focus rings. Disabling clipping globally can let instructional text overlap the device rows.

### Liquid Glass or MapKit availability errors

Check the deployment target and SDK version. This interface uses macOS 26 APIs, including `glassEffect` and `MKMapItem.location`.

### Unexpected ANSI color codes in discovery output

Discovery sets `NO_COLOR=1` and `TERM=dumb` for plain output. Confirm those environment values are still applied in `listDevices()`. Other backend commands may still print terminal formatting to the console.

## Known limitations

- External Python setup is required; there is no bundled runtime or one-click installer.
- Debug and Release sandbox configurations differ.
- Only one unique device is supported at simulation startup; there is no explicit device or transport selector. USB and Wi-Fi entries for the same identifier count as one device.
- A successful device check can be followed immediately by a disconnect or backend failure.
- “Session launched” is a process-level state, not a confirmed device-level simulation state.
- A process-exit callback does not detect every connection loss if the process stays running.
- Discovery does not yet have an explicit timeout.
- Stop and Quit cleanup paths are not fully serialized against each other.
- A timed-out clear process is asked to terminate; forced termination and comprehensive child-process management are not implemented.
- Cleanup-needed state is not persisted across crashes or Force Quit.
- Multiple windows and competing session controllers have not been validated.
- Coordinate edits do not update a running simulation.
- Search selects the first result; no result list or autocomplete is implemented.
- The map extends behind the sidebar, so some map content can be obscured by it.
- Wi-Fi operation has been tested through a Personal Hotspot, not across every router or managed network.
- Connection labels are discovery snapshots, not continuous monitoring or the selected session transport.
- No automatic USB-to-Wi-Fi session handoff, reconnection policy, or standalone operation away from a reachable Mac.
- No guarantee that Find My or every third-party app uses or displays the simulated location in the same way.
- No claim that simulation is undetectable. Apple exposes location-source information that apps can inspect.
- Recovery can require restarting the iPhone.

## Roadmap

- [ ] A single session state machine shared by the UI and lifecycle handler.
- [ ] Serialized Start, Stop, and Quit operations.
- [ ] Discovery timeouts and better backend error capture.
- [ ] More reliable recovery and process cleanup.
- [ ] Explicit device selection and identity checks.
- [x] Document and manually exercise wireless operation through Personal Hotspot.
- [x] Show USB / Wi-Fi discovery labels with a last-checked timestamp.
- [ ] Continuous connection-loss reporting and explicit transport selection.
- [ ] Controlled reconnection and USB / Wi-Fi handoff.
- [ ] Automated tests for validation, discovery decoding, and session transitions.
- [ ] Search suggestions and multiple-result selection.
- [ ] Bookmarks and optional local location history.
- [ ] Route and GPX playback.
- [ ] A reviewed minimum macOS deployment target and wider compatibility testing.
- [ ] Dependency version management and reproducible setup.
- [ ] Reviewed licensing and packaging for a distributable release.
- [ ] Signed and notarized builds with a bundled backend, if pursued.

Checked items are implemented or manually exercised as described above. Unchecked items are planned improvements, not existing features.

## Contributing

For a bug report, include:

- macOS and Xcode versions.
- iPhone model and iOS version.
- Python and `pymobiledevice3` versions.
- Whether the issue occurs in Terminal, the app, or both.
- Whether USB, home Wi-Fi, a managed network, or Personal Hotspot was used.
- The discovery connection type and the time it was checked.
- Steps to reproduce and expected behavior.
- Relevant errors with private identifiers removed.

Keep contributions focused and explain how they were verified. Changes to cleanup should cover normal stopping, early process exit, disconnection, retry, and normal quitting.

Do not commit `.venv`, build output, Xcode user settings, credentials, pairing records, or private diagnostic logs.

Use only devices you own or are authorized to test. Location simulation can affect multiple apps; verify real location after testing and respect the rules of services you use.

## Acknowledgments and licensing

- [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) supplies the device communication and location-simulation backend.
- [matt-ceran/location-changer](https://github.com/matt-ceran/location-changer) inspired the small desktop-wrapper approach.
- [MapKit](https://developer.apple.com/documentation/mapkit), [SwiftUI](https://developer.apple.com/documentation/swiftui), and [AppKit](https://developer.apple.com/documentation/appkit) provide the native interface and platform integration.

The installed `pymobiledevice3` version reports **GPL-3.0-or-later**. Its license and the licenses of bundled dependencies need to be reviewed before distributing a packaged application. Calling an external executable does not, by itself, settle every licensing question for a future distribution.

**This repository has not yet selected a project license in a LICENSE file.** This README does not grant an MIT license or relicense any dependency. Add an appropriate project license before inviting reuse under specific terms.

