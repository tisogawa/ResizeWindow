# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ResizeWindow is a minimal macOS menu bar app built with Swift and SwiftUI that resizes and repositions the frontmost window. The app appears as a status bar item and provides a popover for window manipulation.

It targets this Mac only: macOS 26.7 or later, Xcode 27.1, Swift 6 language mode. The deployment target is 26.7 even though Xcode 27 ships the macOS 27 SDK, because this machine is macOS 26.7.1.

## Build and Run

**Build and run:**
```bash
xcodebuild -project ResizeWindow.xcodeproj -scheme ResizeWindow -configuration Debug build
```

**Run the unit tests:**
```bash
xcodebuild -project ResizeWindow.xcodeproj -scheme ResizeWindow -configuration Debug -destination 'platform=macOS' test
```

**Run from Xcode:**
Open `ResizeWindow.xcodeproj` in Xcode and press Cmd+R.

**Run the built app:**
```bash
open ~/Library/Developer/Xcode/DerivedData/ResizeWindow-*/Build/Products/Debug/ResizeWindow.app
```

**Build and run in one command:**
```bash
xcodebuild -project ResizeWindow.xcodeproj -scheme ResizeWindow -configuration Debug build && open ~/Library/Developer/Xcode/DerivedData/ResizeWindow-*/Build/Products/Debug/ResizeWindow.app
```

**Clean rebuild** (useful when permission issues occur):
```bash
xcodebuild -project ResizeWindow.xcodeproj -scheme ResizeWindow clean
```

## Installation and Deployment

**For /Applications deployment, use the Debug build:**

The Debug build is preferred over Release because:
- Release builds require code signing, and macOS kills unsigned apps
- Debug builds work when copied to /Applications
- Performance difference is negligible for this lightweight app
- Avoids complexity of managing signing certificates

**Installation steps:**
```bash
# Build and copy to Applications
xcodebuild -project ResizeWindow.xcodeproj -scheme ResizeWindow -configuration Debug build
cp -R ~/Library/Developer/Xcode/DerivedData/ResizeWindow-*/Build/Products/Debug/ResizeWindow.app /Applications/

# Remove quarantine attribute (required)
xattr -cr /Applications/ResizeWindow.app

# Launch
open /Applications/ResizeWindow.app
```

## Architecture

### Project Structure

- `ResizeWindow/ResizeWindowApp.swift` — app, popover UI, geometry parsing, target selection, and Accessibility calls
- `ResizeWindow/Assets.xcassets` — app icon and accent color
- `ResizeWindowTests/ResizeWindowTests.swift` — tests for parsing and target selection
- Project configuration (`.xcodeproj`) and documentation (`README.md`, `CLAUDE.md`) live at the repo root

### UI

`ResizeWindowApp` uses `@NSApplicationDelegateAdaptor`. `AppDelegate` owns the status item and a transient popover. The popover's `NSHostingController` uses `sizingOptions = [.preferredContentSize]`, so the SwiftUI view is not given a fixed height.

`ResizeContentView` takes width and height, an optional move toggle with X and Y, and shows the selected target app. Buttons are Resize, Check Frontmost Window, Open Accessibility Settings, and Quit. Resize and Check are disabled while a request is in flight. The last result stays in the hosting controller, so reopening the popover shows it again.

Width and height must be finite numbers greater than 0. Move requires both X and Y; negative coordinates are valid. Invalid input is reported in the popover and does not call the Accessibility API. X and Y are points from the top-left of the primary display.

### Target selection

`WindowTargetSelector` is a pure function over window records:

1. If the frontmost app is not this process and has an eligible on-screen window, use that app.
2. Otherwise walk CGWindow z-order from front to back.
3. Skip PID 0, this process, owners whose names contain "window server", "dock", or "loginwindow", and windows whose layer is present and not 0. A missing layer stays eligible.

The focused AX window of that app is resized. If it cannot be read, the first AX window is used.

### Applying a resize

`WindowResizer` is `nonisolated` and is called from `Task.detached`, so Accessibility work does not block the popover. The background task receives the parsed geometry and the frontmost PID captured on the main actor. Each app element gets an Accessibility messaging timeout of 2 seconds.

Size is written first. If that fails, position is left unchanged. If a move was requested and only the position write fails, the result says the size was applied and the position was not. After a successful size write, size and position are read back. The completion text uses those measurements. A difference of more than 1 point from the request is included. A failed readback does not claim that the requested size was applied.

`WindowResizer.ResizerError` has three cases:
- `.accessibilityNotTrusted`
- `.noSuitableWindow`
- `.axError(String)`

Check Frontmost Window writes its text to `~/Library/Logs/ResizeWindowApp.log` from the background task. The file is recreated after it grows past 1MB. Debug diagnostics go to `Logger` subsystem `com.isogawa.ResizeWindow`.

## Permissions Required

The app requires Accessibility permission:

**System Settings → Privacy & Security → Accessibility**

Open Accessibility Settings prompts with `AXIsProcessTrustedWithOptions` when needed, then opens:

1. `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility`
2. `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`

Do not use the `x-apple.systemsettings` scheme. It has no handler on this OS.

## Key Implementation Details

- **Menu bar-only app** (`INFOPLIST_KEY_LSUIElement = YES`). It does not appear in the Dock or Command-Tab switcher.
- **Sandboxing is off** (`ENABLE_APP_SANDBOX = NO`). Sandboxed apps cannot control other applications through Accessibility.
- Development signing is ad hoc (`CODE_SIGN_IDENTITY = "-"`). `SWIFT_VERSION` is 6.0 and the default actor isolation remains MainActor. `WindowResizer`, `WindowGeometry`, and `WindowTargetSelector` opt out with `nonisolated`.
- The popover is `.transient` and closes when clicking outside.
- Rebuilding can change the signature, so Accessibility permission may need to be granted again.

## Troubleshooting

**App won't resize windows:**
- Verify Accessibility permission is granted in System Settings
- Some apps, including System Settings, do not support resizing through Accessibility
- The app filters out its own windows and system windows (Window Server, Dock, loginwindow)

**"No suitable window found" error:**
- Make sure another app has an on-screen window
- Windows on a non-zero layer are skipped when the layer value is present

**App killed immediately on launch (Release build):**
- Sign the app: `codesign --force --deep --sign - /path/to/ResizeWindow.app`
- Or use the Debug build

**Permission needs to be re-granted after rebuild:**
- The app signature changes with each build
- Use `xattr -cr` on the built app to minimize permission prompts
