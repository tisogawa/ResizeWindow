# ResizeWindow

A minimal macOS menu bar app that allows you to quickly resize and reposition the frontmost window.

## Features

- **Quick Resize**: Resize any window to your preferred dimensions (default: 1440x900)
- **Optional Repositioning**: Move windows to specific screen coordinates
- **Menu Bar Interface**: Lightweight popover UI accessible from the menu bar
- **Accessibility API**: Uses macOS Accessibility APIs to control windows across all applications
- **Inspect Tool**: Debug tool to view window hierarchy and properties

## Requirements

- macOS 26.2 or later
- Xcode 26.2 or later (for building)
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
2. Enter desired width and height (default: 1440x900)
3. Optionally enable "Move window" and enter X/Y coordinates
4. Click "Resize" to apply to the frontmost window
5. Use "Inspect front-most" to debug window properties

## Architecture

- **Single-file design**: All logic in `ResizeWindow/ResizeWindowApp.swift`
- **No sandboxing**: Sandboxing is disabled (`ENABLE_APP_SANDBOX = NO`) because sandboxed apps cannot use Accessibility APIs to control other applications
- **SwiftUI + AppKit**: Modern SwiftUI interface with AppKit integration for menu bar functionality

## Development

See [CLAUDE.md](CLAUDE.md) for detailed architecture documentation and development guidance.

### Key Implementation Details

- Uses `AXUIElement` APIs for window discovery and manipulation
- Filters out system windows (Window Server, Dock, loginwindow)
- Runs window operations on background queue to avoid UI blocking
- No code signing required for development builds

## License

Personal project - use freely.

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
