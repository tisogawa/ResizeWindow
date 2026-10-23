# ResizeWindow

A minimal macOS menu bar app that allows you to quickly resize and reposition the frontmost window.

## Features

- **Quick Resize**: Resize any window to your preferred dimensions (default: 1440x900)
- **Optional Repositioning**: Move windows to specific screen coordinates
- **Menu Bar Interface**: Lightweight popover UI accessible from the menu bar
- **Accessibility API**: Uses macOS Accessibility APIs to control windows across all applications
- **Inspect Tool**: Debug tool to view window hierarchy and properties

## Requirements

- macOS 26.7 or later
- Xcode 27.1 or later, Swift 6
- Accessibility permission (required for window manipulation)

## Installation

### Building from Source

1. Open `ResizeWindow.xcodeproj` in Xcode
2. Build the project: Product → Build (Cmd+B)
3. Run directly from Xcode: Product → Run (Cmd+R)

### Installing to /Applications

We use the **Debug build** for deployment because:
- The Release build requires code signing, which causes macOS to kill unsigned apps
- The Debug build works perfectly when run from Xcode or copied to /Applications
- Performance difference is negligible for this lightweight app
- Simpler deployment without dealing with signing certificates

**Installation steps:**

```bash
# Copy the Debug build to Applications
cp -R ~/Library/Developer/Xcode/DerivedData/ResizeWindow-*/Build/Products/Debug/ResizeWindow.app /Applications/

# Remove quarantine attribute
xattr -cr /Applications/ResizeWindow.app

# Launch the app
open /Applications/ResizeWindow.app
```

### Granting Accessibility Permission

The app **requires** Accessibility permission to manipulate windows:

1. Launch the app
2. Click "Open Accessibility Settings" in the popover
3. In System Settings → Privacy & Security → Accessibility
4. Enable ResizeWindow

**Note:** You may need to re-grant permission if you rebuild the app, as the signature changes.

## Usage

1. Click the ResizeWindow icon in the menu bar (rectangle expand icon)
2. Enter a width and height greater than 0 (the fields start at 1440 and 900)
3. Optionally enable "Move window" and enter both X and Y. The origin is the top-left of the primary display, and negative values reach other displays
4. Click "Resize". Empty or non-numeric values are rejected and do not change the window
5. The result reports the measured size and position. If the app clamps the size, both the measured value and the request are shown
6. Use "Check Frontmost Window" to debug window properties

## Architecture

- **Single-file design**: All app logic in `ResizeWindow/ResizeWindowApp.swift`
- **Unit tests**: `ResizeWindowTests/ResizeWindowTests.swift` covers dimension parsing and frontmost-window selection
- **No sandboxing**: Sandboxing is disabled (`ENABLE_APP_SANDBOX = NO`) because sandboxed apps cannot use Accessibility APIs to control other applications
- **SwiftUI + AppKit**: SwiftUI popover with AppKit status item integration

## Development

See [CLAUDE.md](CLAUDE.md) for detailed architecture documentation and development guidance.

### Key Implementation Details

- Uses `AXUIElement` APIs for window discovery and manipulation
- Prefers the frontmost app when it has an eligible on-screen window, then falls back to window z-order
- Filters out its own windows and system windows (Window Server, Dock, loginwindow)
- Runs window operations off the main actor so the popover stays responsive
- No code signing required for development builds

## License

This project is licensed under the [MIT License](LICENSE).

## Troubleshooting

**App won't resize windows:**
- Ensure Accessibility permission is granted
- Some apps (like System Settings) may not support window resizing via Accessibility APIs

**App killed on launch:**
- If using Release build, sign it: `codesign --force --deep --sign - ResizeWindow.app`
- Or use the Debug build (recommended)

**"No suitable window found" error:**
- Make sure another app's window is frontmost
- The app filters out its own windows and system windows
