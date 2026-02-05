// ResizeWindowApp.swift
// Minimal macOS menu bar app (Swift + SwiftUI) that resizes the front-most window
// - Put this file into an Xcode macOS App (SwiftUI) project's Sources (replace default)
// - Requires Accessibility permission for the built app (System Settings → Privacy & Security → Accessibility)

import SwiftUI
import AppKit
import ApplicationServices
import CoreGraphics

@main
struct ResizeWindowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create popover with SwiftUI content
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 220)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ResizeContentView())

        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.expand.vertical", accessibilityDescription: "Resize")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}

// MARK: - SwiftUI ResizeContentView

struct ResizeContentView: View {
    @State private var widthText: String = "1440"
    @State private var heightText: String = "900"
    @State private var xText: String = ""
    @State private var yText: String = ""
    @State private var useXY: Bool = false
    @State private var message: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Width")
                    TextField("Width", text: $widthText)
                        .frame(width: 120)
                }
                VStack(alignment: .leading) {
                    Text("Height")
                    TextField("Height", text: $heightText)
                        .frame(width: 120)
                }
            }

            HStack(spacing: 10) {
                Button("Resize") {
                    performResize(move: useXY, target: WindowResizer.WindowTarget.frontmost)
                }
                Button("Inspect front-most") {
                    DispatchQueue.global(qos: .userInitiated).async {
                        let diag = WindowResizer.shared.inspectFrontmost()
                        // write to message and append to log
                        DispatchQueue.main.async {
                            self.message = diag
                            // append to log
                            let logLine = "[\(Date())] INSPECT\n\(diag)\n"
                            let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ResizeWindowApp.log")
                            if let data = logLine.data(using: .utf8) {
                                if FileManager.default.fileExists(atPath: logURL.path) {
                                    if let fh = try? FileHandle(forWritingTo: logURL) {
                                        fh.seekToEndOfFile()
                                        fh.write(data)
                                        try? fh.close()
                                    }
                                } else {
                                    try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                                    try? data.write(to: logURL)
                                }
                            }
                        }
                    }
                }
            }

            Toggle(isOn: $useXY) {
                Text("Move window (provide X & Y)")
            }
            if useXY {
                HStack {
                    TextField("X", text: $xText)
                        .frame(width: 120)
                    TextField("Y", text: $yText)
                        .frame(width: 120)
                }
            }

            Divider()
            ScrollView {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)    // allow copy
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 100)

            Spacer()
            HStack {
                Button("Open Accessibility Settings") { openAccessibilitySettings() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 360, height: 220)
        .onAppear {
            if !AXIsProcessTrusted() {
                message = "Accessibility permission is required. Click the button below to open System Settings → Privacy & Security → Accessibility and enable this app."
            }
        }
    }
    
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func performResize(move: Bool, target: WindowResizer.WindowTarget) {
        message = "Working..."
        DispatchQueue.global(qos: .userInitiated).async {
            let w = CGFloat(Double(widthText) ?? 1200)
            let h = CGFloat(Double(heightText) ?? 800)
            var xVal: CGFloat? = nil
            var yVal: CGFloat? = nil
            if move {
                xVal = CGFloat(Double(xText) ?? 0)
                yVal = CGFloat(Double(yText) ?? 0)
            }

            let res: Result<WindowResizer.ResultInfo, Error>
            switch target {
            case .frontmost:
                res = WindowResizer.shared.resizeFrontmost(width: w, height: h, x: xVal, y: yVal)
            case .second:
                res = WindowResizer.shared.resizeSecondFrontmost(width: w, height: h, x: xVal, y: yVal)
            }

            DispatchQueue.main.async {
                switch res {
                case .success(let info):
                    let movedSuffix: String
                    if info.moved {
                        movedSuffix = " moved to (\(Int(info.x)) , \(Int(info.y)))"
                    } else {
                        movedSuffix = ""
                    }
                    message = "Done — pid:\(info.pid) size:\(Int(info.width))x\(Int(info.height))\(movedSuffix)"
                case .failure(let err):
                    let errorText: String
                    if let re = err as? WindowResizer.ResizerError {
                        errorText = re.description
                    } else {
                        // Use localizedDescription if available, otherwise a generic description
                        errorText = (err as NSError).localizedDescription
                    }
                    message = "Error: \(errorText)"
                }
            }
        }
    }
}

// MARK: - WindowResizer

final class WindowResizer {
    static let shared = WindowResizer()

    enum WindowTarget { case frontmost, second }

    struct ResultInfo {
        let pid: pid_t
        let width: CGFloat
        let height: CGFloat
        let moved: Bool
        let x: CGFloat
        let y: CGFloat
    }

    enum ResizerError: Error, CustomStringConvertible {
        case accessibilityNotTrusted
        case noSuitableWindow
        case axError(String)

        var description: String {
            switch self {
            case .accessibilityNotTrusted: return "Accessibility permission is not granted"
            case .noSuitableWindow: return "No suitable window found"
            case .axError(let s): return "AX error: \(s)"
            }
        }
    }

    private init() {}

    func isTrusted() -> Bool { AXIsProcessTrusted() }

    // New: resize the current front-most app's focused window (useful for menu bar invocation)
    func resizeFrontmost(width: CGFloat, height: CGFloat, x: CGFloat?, y: CGFloat?) -> Result<ResultInfo, Error> {
        guard AXIsProcessTrusted() else { return .failure(ResizerError.accessibilityNotTrusted) }
        do {
            let pid = try getFrontmostAppPID()
            print("DEBUG: Got frontmost PID: \(pid)")
            let window = try findWindow(for: pid, index: nil, titleSubstring: nil)
            print("DEBUG: Got window for PID \(pid)")

            var moved = false
            var finalX: CGFloat = 0
            var finalY: CGFloat = 0

            if let xv = x, let yv = y {
                try setWindowPositionAndSize(window: window, x: xv, y: yv, width: width, height: height)
                moved = true
                finalX = xv; finalY = yv
            } else {
                let pos = try getWindowPosition(window)
                try setWindowSize(window: window, width: width, height: height)
                finalX = pos.x; finalY = pos.y
            }

            return .success(ResultInfo(pid: pid, width: width, height: height, moved: moved, x: finalX, y: finalY))
        } catch let e as ResizerError {
            print("DEBUG: ResizerError: \(e.description)")
            return .failure(e)
        } catch {
            print("DEBUG: Other error: \(error)")
            return .failure(error)
        }
    }

    // Keep the old second-frontmost function in case you want it later
    func resizeSecondFrontmost(width: CGFloat, height: CGFloat, x: CGFloat?, y: CGFloat?) -> Result<ResultInfo, Error> {
        guard AXIsProcessTrusted() else { return .failure(ResizerError.accessibilityNotTrusted) }
        do {
            let pid = try getSecondFrontmostAppPID()
            let window = try findWindow(for: pid, index: nil, titleSubstring: nil)

            var moved = false
            var finalX: CGFloat = 0
            var finalY: CGFloat = 0

            if let xv = x, let yv = y {
                try setWindowPositionAndSize(window: window, x: xv, y: yv, width: width, height: height)
                moved = true
                finalX = xv; finalY = yv
            } else {
                let pos = try getWindowPosition(window)
                try setWindowSize(window: window, width: width, height: height)
                finalX = pos.x; finalY = pos.y
            }

            return .success(ResultInfo(pid: pid, width: width, height: height, moved: moved, x: finalX, y: finalY))
        } catch let e as ResizerError {
            return .failure(e)
        } catch {
            return .failure(error)
        }
    }

    // MARK: Low-level helpers (adapted from earlier CLI)

    func getFrontmostAppPID() throws -> pid_t {
        let ourPid = getpid()
        print("DEBUG: Our PID is \(ourPid)")
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoCF = CGWindowListCopyWindowInfo(options, kCGNullWindowID) else { throw ResizerError.noSuitableWindow }
        let nsArr = infoCF as NSArray

        for item in nsArr {
            guard let dict = item as? NSDictionary else { continue }
            var pid: pid_t = 0
            if let p = dict[kCGWindowOwnerPID as String] as? Int { pid = pid_t(p) }
            else if let pnum = dict[kCGWindowOwnerPID as String] as? NSNumber { pid = pid_t(truncating: pnum) }
            else { continue }
            if pid == 0 { continue }
            if pid == ourPid {
                print("DEBUG: Skipping our own PID \(pid)")
                continue
            }
            let ownerName = dict[kCGWindowOwnerName as String] as? String ?? "unknown"
            print("DEBUG: Checking window: PID=\(pid), owner=\(ownerName)")
            if let ownerName = dict[kCGWindowOwnerName as String] as? String {
                let lowered = ownerName.lowercased()
                if lowered.contains("window server") || lowered.contains("dock") || lowered.contains("loginwindow") {
                    print("DEBUG: Skipping system window: \(ownerName)")
                    continue
                }
            }
            if let layerNum = dict[kCGWindowLayer as String] as? Int {
                if layerNum != 0 {
                    print("DEBUG: Skipping non-zero layer window (layer=\(layerNum))")
                    continue
                }
            }
            // Return the first valid non-self window
            print("DEBUG: Selected PID \(pid) with owner \(ownerName)")
            return pid
        }
        print("DEBUG: No suitable window found in CGWindowList")
        throw ResizerError.noSuitableWindow
    }

    func getSecondFrontmostAppPID() throws -> pid_t {
        let ourPid = getpid()
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoCF = CGWindowListCopyWindowInfo(options, kCGNullWindowID) else { throw ResizerError.noSuitableWindow }
        let nsArr = infoCF as NSArray

        var frontMostPid: pid_t? = nil
        var candidatePid: pid_t? = nil
        for item in nsArr {
            guard let dict = item as? NSDictionary else { continue }
            var pid: pid_t = 0
            if let p = dict[kCGWindowOwnerPID as String] as? Int { pid = pid_t(p) }
            else if let pnum = dict[kCGWindowOwnerPID as String] as? NSNumber { pid = pid_t(truncating: pnum) }
            else { continue }
            if pid == 0 { continue }
            if pid == ourPid { continue }
            if let ownerName = dict[kCGWindowOwnerName as String] as? String {
                let lowered = ownerName.lowercased()
                if lowered.contains("window server") || lowered.contains("dock") || lowered.contains("loginwindow") { continue }
            }
            if let layerNum = dict[kCGWindowLayer as String] as? Int { if layerNum != 0 { continue } }
            if frontMostPid == nil { frontMostPid = pid; continue }
            else { if pid != frontMostPid { candidatePid = pid; break } else { continue } }
        }
        if let cpid = candidatePid { return cpid }
        if let fpid = frontMostPid { return fpid }
        throw ResizerError.noSuitableWindow
    }

    func findPID(matching nameOrBundle: String) -> pid_t? {
        let apps = NSWorkspace.shared.runningApplications
        for app in apps {
            if let bundleID = app.bundleIdentifier, bundleID == nameOrBundle { return app.processIdentifier }
        }
        for app in apps { if let appName = app.localizedName, appName == nameOrBundle { return app.processIdentifier } }
        return nil
    }

    func windowsForPID(_ pid: pid_t) throws -> [AXUIElement] {
        let appRef = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value)
        if err != .success || value == nil {
            print("DEBUG: windowsForPID failed for PID \(pid), AXError: \(err.rawValue)")
            throw ResizerError.axError("Cannot get windows for PID \(pid), AXError: \(err.rawValue)")
        }
        let cfArr = value! as! CFArray
        let nsArr = cfArr as NSArray
        print("DEBUG: Found \(nsArr.count) windows for PID \(pid)")
        var result: [AXUIElement] = []
        for i in 0 ..< nsArr.count {
            let raw = nsArr[i] as AnyObject
            let ax = unsafeBitCast(raw, to: AXUIElement.self)
            result.append(ax)
        }
        return result
    }

    func titleOfWindow(_ window: AXUIElement) -> String? {
        var val: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &val)
        if err != .success || val == nil { return nil }
        return (val as? String)
    }

    func findWindow(for pid: pid_t, index: Int?, titleSubstring: String?) throws -> AXUIElement {
        let wins = try windowsForPID(pid)
        if let idx = index { if idx < 0 || idx >= wins.count { throw ResizerError.noSuitableWindow } ; return wins[idx] }
        if let substr = titleSubstring?.lowercased() {
            for w in wins { if let t = titleOfWindow(w)?.lowercased(), t.contains(substr) { return w } }
            throw ResizerError.noSuitableWindow
        }
        let appRef = AXUIElementCreateApplication(pid)
        var frontWindow: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &frontWindow)
        if err == .success, frontWindow != nil { let fw = frontWindow! as! AXUIElement ; return fw }
        if wins.count > 0 { return wins[0] }
        throw ResizerError.noSuitableWindow
    }

    func getWindowPosition(_ window: AXUIElement) throws -> CGPoint {
        var val: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &val)
        if err != .success || val == nil { throw ResizerError.axError("Failed to read window position (AX error \(err.rawValue))") }
        let axVal = val! as! AXValue
        var point = CGPoint.zero
        if !AXValueGetValue(axVal, .cgPoint, &point) { throw ResizerError.axError("Failed to convert position AXValue to CGPoint") }
        return point
    }

    // Helper: check if an attribute is settable on an AX element
    func isAttributeSettable(_ element: AXUIElement, attribute: CFString) -> (settable: Bool, error: AXError) {
        var settable: DarwinBoolean = false
        let err = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return (settable.boolValue, err)
    }

    // Replace your existing setWindowSize(...) with this version
    func setWindowSize(window: AXUIElement, width: CGFloat, height: CGFloat) throws {
        // First check if the attribute is settable, which tells us early why writes fail on some windows.
        let (settable, checkErr) = isAttributeSettable(window, attribute: kAXSizeAttribute as CFString)
        if checkErr != .success {
            let msg = "AX check failed for kAXSizeAttribute (AXError \(checkErr.rawValue))"
            throw ResizerError.axError(msg)
        }
        if !settable {
            throw ResizerError.axError("kAXSizeAttribute is not settable on this window (cannot resize via AX).")
        }

        var s = CGSize(width: width, height: height)
        guard let sizeVal = AXValueCreate(.cgSize, &s) else {
            throw ResizerError.axError("Failed to create AXValue for size")
        }
        let err = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        if err != .success {
            // Provide diagnostic detail including the AXError code
            throw ResizerError.axError("AXUIElementSetAttributeValue(kAXSizeAttribute) failed with AXError \(err.rawValue)")
        }
    }

    // Replace your existing setWindowPositionAndSize(...) with this version
    func setWindowPositionAndSize(window: AXUIElement, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) throws {
        // Check position settable
        let posCheck = isAttributeSettable(window, attribute: kAXPositionAttribute as CFString)
        if posCheck.error != .success {
            throw ResizerError.axError("AX check failed for kAXPositionAttribute (AXError \(posCheck.error.rawValue))")
        }
        if !posCheck.settable {
            throw ResizerError.axError("kAXPositionAttribute is not settable on this window (cannot move via AX).")
        }

        // Check size settable
        let sizeCheck = isAttributeSettable(window, attribute: kAXSizeAttribute as CFString)
        if sizeCheck.error != .success {
            throw ResizerError.axError("AX check failed for kAXSizeAttribute (AXError \(sizeCheck.error.rawValue))")
        }
        if !sizeCheck.settable {
            throw ResizerError.axError("kAXSizeAttribute is not settable on this window (cannot resize via AX).")
        }

        var p = CGPoint(x: x, y: y)
        guard let posVal = AXValueCreate(.cgPoint, &p) else { throw ResizerError.axError("Failed to create AXValue for position") }
        var s = CGSize(width: width, height: height)
        guard let sizeVal = AXValueCreate(.cgSize, &s) else { throw ResizerError.axError("Failed to create AXValue for size") }

        var err = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        if err != .success {
            throw ResizerError.axError("AXUIElementSetAttributeValue(kAXPositionAttribute) failed with AXError \(err.rawValue)")
        }
        err = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        if err != .success {
            throw ResizerError.axError("AXUIElementSetAttributeValue(kAXSizeAttribute) failed with AXError \(err.rawValue)")
        }
    }

    
    // Put this inside WindowResizer (near other helpers)
    func inspectFrontmost() -> String {
        var out = ""
        // frontmost app pid
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return "No frontmost app found"
        }
        let pid = frontApp.processIdentifier
        let appName = frontApp.localizedName ?? "PID:\(pid)"
        out += "Frontmost app: \(appName) (pid:\(pid))\n"

        // list CGWindow z-order (front -> back)
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let infoCF = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) {
            let arr = infoCF as NSArray
            out += "Top-level CGWindows (front->back):\n"
            var count = 0
            for case let dict as NSDictionary in arr {
                if count >= 30 { break }
                let owner = (dict[kCGWindowOwnerName as String] as? String) ?? "(unknown)"
                let ownerPID: Int = (dict[kCGWindowOwnerPID as String] as? Int) ?? -1
                let title = (dict[kCGWindowName as String] as? String) ?? "(no title)"
                let layer = (dict[kCGWindowLayer as String] as? Int) ?? 0
                out += "  [\(count)] owner=\(owner) pid=\(ownerPID) layer=\(layer) title='\(title)'\n"
                count += 1
            }
        } else {
            out += "Failed to get CGWindowList\n"
        }

        // try to list AX windows for the frontmost pid
        do {
            let wins = try windowsForPID(pid_t(pid))
            out += "AX windows for pid \(pid): count=\(wins.count)\n"
            for (i,w) in wins.enumerated() {
                let t = titleOfWindow(w) ?? "(no title)"
                var posDesc = "(unknown)"
                if let pos = try? getWindowPosition(w) {
                    posDesc = "(\(Int(pos.x)),\(Int(pos.y)))"
                }
                var sizeDesc = "(unknown)"
                var val: CFTypeRef?
                if AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &val) == .success,
                   let cfVal = val,
                   CFGetTypeID(cfVal) == AXValueGetTypeID() {
                    let axVal: AXValue = unsafeBitCast(cfVal, to: AXValue.self)
                    var s = CGSize.zero
                    if AXValueGetValue(axVal, .cgSize, &s) {
                        sizeDesc = "\(Int(s.width))x\(Int(s.height))"
                    }
                }
                out += "  AX[\(i)] title='\(t)' pos=\(posDesc) size=\(sizeDesc)\n"
            }
        } catch {
            out += "AX list failed: \(error)\n"
        }

        return out
    }
}

