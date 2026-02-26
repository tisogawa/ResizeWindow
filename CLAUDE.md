# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ResizeWindow is a minimal macOS menu bar app built with Swift and SwiftUI that allows users to resize and reposition the frontmost window. The app appears as a status bar item and provides a popover interface for window manipulation.

## Build and Run

This is an Xcode project targeting macOS 26.2+.

**Build and run:**
```bash
xcodebuild -project ResizeWindow.xcodeproj -scheme ResizeWindow -configuration Debug build
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
- Debug builds work perfectly when copied to /Applications
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

**Source files are organized in the `ResizeWindow/` subdirectory:**
- `ResizeWindow/ResizeWindowApp.swift` - Main application logic (single-file implementation)
- `ResizeWindow/ContentView.swift` - Unused boilerplate from Xcode template
- `ResizeWindow/Assets.xcassets` - App icon and assets
- `ResizeWindow/ResizeWindow-Bridging-Header.h` - Objective-C bridging header (currently empty)

**Repo root contains:**
- Project configuration files (`.xcodeproj`, `.gitignore`)
- Documentation (`README.md`, `CLAUDE.md`)

### Key Components

**App Entry and Delegation (ResizeWindowApp.swift:12-50)**
- `ResizeWindowApp`: Main SwiftUI app entry point using `@NSApplicationDelegateAdaptor`
- `AppDelegate`: Manages the status bar item and popover lifecycle

**UI Layer (ResizeWindowApp.swift:54-196)**
- `ResizeContentView`: SwiftUI view providing the resize interface with width/height inputs, optional X/Y positioning, and action buttons
- Buttons: "Resize", "Check Frontmost Window"
- Inspection output shows frontmost window info including size (e.g., "Frontmost: iTerm2 (pid:48623) 1440 x 900")
- Logs inspection output to `~/Library/Logs/ResizeWindowApp.log`

**Window Management Layer (ResizeWindowApp.swift:200-508)**
- `WindowResizer`: Core singleton class that handles all window manipulation via macOS Accessibility APIs
- Uses `AXUIElement` APIs to discover and manipulate windows
- Two main resize modes:
  - `resizeFrontmost()`: Resizes the currently focused window
  - `resizeSecondFrontmost()`: Resizes the second frontmost window (currently unused in UI)

### Accessibility API Flow

1. Check if Accessibility permission is granted via `AXIsProcessTrusted()`
2. Get the target app's PID (process identifier)
3. Query for windows using `AXUIElementCopyAttributeValue` with `kAXWindowsAttribute`
4. Validate if size/position attributes are settable via `isAttributeSettable()`
5. Set new dimensions using `AXUIElementSetAttributeValue` with `kAXSizeAttribute` and `kAXPositionAttribute`

### Error Handling

The `WindowResizer.ResizerError` enum provides three failure modes:
- `.accessibilityNotTrusted`: User hasn't granted Accessibility permission
- `.noSuitableWindow`: No valid target window found
- `.axError(String)`: Low-level Accessibility API failure with diagnostic details

## Permissions Required

The app requires Accessibility permission to function. Users must manually enable this in:
**System Settings → Privacy & Security → Accessibility**

The app includes a button to open these settings directly via `x-apple.systempreferences:` URL scheme.

## Key Implementation Details

- **Menu bar-only app** (`INFOPLIST_KEY_LSUIElement = YES`) - the app runs exclusively in the menu bar and does not appear in the Dock or Command+Tab switcher
- **The app runs WITHOUT sandboxing** (`ENABLE_APP_SANDBOX = NO`) - this is critical because sandboxed apps cannot use Accessibility APIs to control other applications
- No code signing is required for development (`CODE_SIGN_IDENTITY = "-"`)
- The popover is transient (`.transient` behavior) and closes when clicking outside
- Window operations run on a background queue (`DispatchQueue.global(qos: .userInitiated)`) to avoid blocking the UI
- The `inspectFrontmost()` function provides diagnostic information about window z-order and AX hierarchy for debugging
- After any rebuild, you may need to re-grant Accessibility permission since the app signature changes

## Troubleshooting

**App won't resize windows:**
- Verify Accessibility permission is granted in System Settings
- Some apps (like System Settings itself) may not support window resizing via Accessibility APIs
- The app filters out its own windows and system windows (Window Server, Dock, loginwindow)

**"No suitable window found" error:**
- Ensure another app's window is frontmost and focused
- The target window must be on layer 0 (normal application windows)

**App killed immediately on launch (Release build):**
- Sign the app: `codesign --force --deep --sign - /path/to/ResizeWindow.app`
- Or use Debug build instead (recommended)

**Permission needs to be re-granted after rebuild:**
- This is expected behavior - the app signature changes with each build
- Use `xattr -cr` on the built app to minimize permission prompts
