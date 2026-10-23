// ResizeWindowApp.swift
// Menu bar app that resizes the frontmost window through the Accessibility API.

import AppKit
import ApplicationServices
import CoreGraphics
import os
import SwiftUI

nonisolated private let resizeLog = Logger(subsystem: "com.isogawa.ResizeWindow", category: "WindowResizer")

extension Notification.Name {
    static let resizeWindowPopoverDidShow = Notification.Name("resizeWindowPopoverDidShow")
}

@main
struct ResizeWindowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hostingController = NSHostingController(rootView: ResizeContentView())
        hostingController.sizingOptions = [.preferredContentSize]

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = hostingController

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
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        NotificationCenter.default.post(name: .resizeWindowPopoverDidShow, object: nil)
    }
}

struct ResizeContentView: View {
    @State private var widthText: String = "1440"
    @State private var heightText: String = "900"
    @State private var xText: String = ""
    @State private var yText: String = ""
    @State private var useXY: Bool = false
    @State private var message: String = ""
    @State private var targetSummary: String = "Target: …"
    @State private var isWorking: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(targetSummary)
                .font(.headline)

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
                Button("Resize") { performResize() }
                    .disabled(isWorking)
                Button("Check Frontmost Window") { inspectFrontmost() }
                    .disabled(isWorking)
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
                Text("X and Y are points from the top-left of the primary display. Negative values reach other displays.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            ScrollView {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 100)

            HStack {
                Button("Open Accessibility Settings") { openAccessibilitySettings() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 360)
        .fixedSize(horizontal: true, vertical: true)
        .onAppear {
            if !AXIsProcessTrusted() {
                message = "Accessibility permission is required. Click the button below to open System Settings → Privacy & Security → Accessibility and enable this app."
            }
            refreshTarget()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resizeWindowPopoverDidShow)) { _ in
            refreshTarget()
        }
    }

    private func openAccessibilitySettings() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate), NSWorkspace.shared.open(url) else { continue }
            return
        }
    }

    private func performResize() {
        switch WindowGeometry.parse(width: widthText, height: heightText, move: useXY, x: xText, y: yText) {
        case .failure(let error):
            message = error.description
            return
        case .success(let request):
            isWorking = true
            message = "Working..."
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            Task {
                let outcome = await Task.detached {
                    WindowResizer.shared.resize(request, frontmostPID: frontmostPID)
                }.value
                message = outcome.statusText
                isWorking = false
                refreshTarget()
            }
        }
    }

    private func inspectFrontmost() {
        isWorking = true
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task {
            let diag = await Task.detached {
                let text = WindowResizer.shared.inspectFrontmost(frontmostPID: frontmostPID)
                WindowResizer.shared.appendInspectLog(text)
                return text
            }.value
            message = diag
            isWorking = false
            refreshTarget()
        }
    }

    private func refreshTarget() {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task {
            let summary = await Task.detached {
                WindowResizer.shared.targetSummary(frontmostPID: frontmostPID)
            }.value
            targetSummary = summary
        }
    }
}

nonisolated enum WindowGeometry {
    struct Request: Equatable, Sendable {
        var width: CGFloat
        var height: CGFloat
        var origin: CGPoint?
    }

    enum ParseError: Error, Equatable, Sendable, CustomStringConvertible {
        case invalidWidth
        case invalidHeight
        case invalidX
        case invalidY
        case missingCoordinates

        var description: String {
            switch self {
            case .invalidWidth:
                return "Width must be a number greater than 0."
            case .invalidHeight:
                return "Height must be a number greater than 0."
            case .invalidX:
                return "X must be a number."
            case .invalidY:
                return "Y must be a number."
            case .missingCoordinates:
                return "Enter both X and Y to move the window."
            }
        }
    }

    static func parse(width: String, height: String, move: Bool, x: String, y: String) -> Result<Request, ParseError> {
        let widthText = width.trimmingCharacters(in: .whitespacesAndNewlines)
        let heightText = height.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let widthValue = Double(widthText), widthValue.isFinite, widthValue > 0 else {
            return .failure(.invalidWidth)
        }
        guard let heightValue = Double(heightText), heightValue.isFinite, heightValue > 0 else {
            return .failure(.invalidHeight)
        }
        guard move else {
            return .success(Request(width: CGFloat(widthValue), height: CGFloat(heightValue), origin: nil))
        }

        let xText = x.trimmingCharacters(in: .whitespacesAndNewlines)
        let yText = y.trimmingCharacters(in: .whitespacesAndNewlines)
        if xText.isEmpty || yText.isEmpty {
            return .failure(.missingCoordinates)
        }
        guard let xValue = Double(xText), xValue.isFinite else {
            return .failure(.invalidX)
        }
        guard let yValue = Double(yText), yValue.isFinite else {
            return .failure(.invalidY)
        }
        return .success(Request(
            width: CGFloat(widthValue),
            height: CGFloat(heightValue),
            origin: CGPoint(x: xValue, y: yValue)
        ))
    }
}

nonisolated struct WindowCandidate: Equatable, Sendable {
    var pid: pid_t
    var ownerName: String
    var layer: Int?
}

nonisolated enum WindowTargetSelector {
    static func select(frontmostPID: pid_t?, windows: [WindowCandidate], ownPID: pid_t) -> WindowCandidate? {
        if let frontmostPID,
           let match = windows.first(where: { $0.pid == frontmostPID && isEligible($0, ownPID: ownPID) }) {
            return match
        }
        return windows.first(where: { isEligible($0, ownPID: ownPID) })
    }

    static func isEligible(_ window: WindowCandidate, ownPID: pid_t) -> Bool {
        if window.pid == 0 || window.pid == ownPID { return false }
        let lowered = window.ownerName.lowercased()
        if lowered.contains("window server") || lowered.contains("dock") || lowered.contains("loginwindow") {
            return false
        }
        if let layer = window.layer, layer != 0 { return false }
        return true
    }

    static func candidates(from info: NSArray) -> [WindowCandidate] {
        var result: [WindowCandidate] = []
        for case let dict as NSDictionary in info {
            guard let pid = pidValue(dict[kCGWindowOwnerPID as String]) else { continue }
            let owner = dict[kCGWindowOwnerName as String] as? String ?? ""
            let layer = integerValue(dict[kCGWindowLayer as String])
            result.append(WindowCandidate(pid: pid, ownerName: owner, layer: layer))
        }
        return result
    }

    static func pidValue(_ raw: Any?) -> pid_t? {
        if let value = raw as? Int { return pid_t(value) }
        if let number = raw as? NSNumber { return pid_t(truncating: number) }
        return nil
    }

    static func integerValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let number = raw as? NSNumber { return number.intValue }
        return nil
    }
}

nonisolated struct ResultInfo: Equatable, Sendable {
    var pid: pid_t
    var appName: String
    var measuredSize: CGSize?
    var measuredPosition: CGPoint?
    var requestedWidth: CGFloat
    var requestedHeight: CGFloat
    var requestedOrigin: CGPoint?
    var positionApplied: Bool
    var positionError: String?

    var statusText: String {
        var text = "Done — \(appName) (pid:\(pid))"
        if let measuredSize {
            text += " size:\(Int(measuredSize.width))x\(Int(measuredSize.height))"
            if differs(measuredSize.width, requestedWidth) || differs(measuredSize.height, requestedHeight) {
                text += " (requested \(Int(requestedWidth))x\(Int(requestedHeight)))"
            }
        } else {
            text += ". Size was written, but the actual size could not be read"
        }

        if let requestedOrigin {
            if positionApplied {
                if let measuredPosition {
                    text += " position:(\(Int(measuredPosition.x)), \(Int(measuredPosition.y)))"
                    if differs(measuredPosition.x, requestedOrigin.x) || differs(measuredPosition.y, requestedOrigin.y) {
                        text += " (requested position (\(Int(requestedOrigin.x)), \(Int(requestedOrigin.y))))"
                    }
                } else {
                    text += ". Position was written, but the actual position could not be read"
                }
            } else {
                let detail = positionError ?? "position could not be changed"
                text += ". Size applied, position unchanged (\(detail))"
            }
        } else if let measuredPosition {
            text += " position:(\(Int(measuredPosition.x)), \(Int(measuredPosition.y)))"
        }
        return text
    }

    private func differs(_ actual: CGFloat, _ requested: CGFloat) -> Bool {
        abs(actual - requested) > 1
    }
}

nonisolated enum ResizeOutcome: Sendable {
    case success(ResultInfo)
    case failure(WindowResizer.ResizerError)

    var statusText: String {
        switch self {
        case .success(let info):
            return info.statusText
        case .failure(let error):
            return "Error: \(error.description)"
        }
    }
}

nonisolated final class WindowResizer: Sendable {
    static let shared = WindowResizer()
    private static let axTimeout: Float = 2

    enum ResizerError: Error, CustomStringConvertible, Sendable {
        case accessibilityNotTrusted
        case noSuitableWindow
        case axError(String)

        var description: String {
            switch self {
            case .accessibilityNotTrusted: return "Accessibility permission is not granted"
            case .noSuitableWindow: return "No suitable window found"
            case .axError(let message): return "AX error: \(message)"
            }
        }
    }

    private init() {}

    func resize(_ request: WindowGeometry.Request, frontmostPID: pid_t?) -> ResizeOutcome {
        guard AXIsProcessTrusted() else { return .failure(.accessibilityNotTrusted) }
        guard let target = selectedTarget(frontmostPID: frontmostPID) else {
            return .failure(.noSuitableWindow)
        }

        do {
            let window = try findWindow(for: target.pid)
            try setWindowSize(window: window, width: request.width, height: request.height)

            var positionApplied = request.origin == nil
            var positionError: String?
            if let origin = request.origin {
                do {
                    try setWindowPosition(window: window, x: origin.x, y: origin.y)
                    positionApplied = true
                } catch let error as ResizerError {
                    positionApplied = false
                    positionError = error.description
                } catch {
                    positionApplied = false
                    positionError = error.localizedDescription
                }
            }

            let info = ResultInfo(
                pid: target.pid,
                appName: displayName(for: target),
                measuredSize: readSize(window),
                measuredPosition: readPosition(window),
                requestedWidth: request.width,
                requestedHeight: request.height,
                requestedOrigin: request.origin,
                positionApplied: positionApplied,
                positionError: positionError
            )
            resizeLog.debug("Resized pid \(target.pid, privacy: .public): \(info.statusText, privacy: .public)")
            return .success(info)
        } catch let error as ResizerError {
            return .failure(contextualize(error, target: target))
        } catch {
            return .failure(.axError("\(displayName(for: target)) (pid:\(target.pid)): \(error.localizedDescription)"))
        }
    }

    func targetSummary(frontmostPID: pid_t?) -> String {
        guard let target = selectedTarget(frontmostPID: frontmostPID) else {
            return "Target: No suitable window"
        }
        return "Target: \(displayName(for: target)) (pid:\(target.pid))"
    }

    func inspectFrontmost(frontmostPID: pid_t?) -> String {
        if !AXIsProcessTrusted() {
            return "Accessibility permission is not granted.\n\nOpen Accessibility Settings, enable ResizeWindow, then try again."
        }

        var out = ""
        if let target = selectedTarget(frontmostPID: frontmostPID) {
            out += "\(targetSummary(frontmostPID: frontmostPID))\n"
            if let window = try? findWindow(for: target.pid), let size = readSize(window) {
                out += "Focused size: \(Int(size.width)) x \(Int(size.height))\n"
            }
        } else {
            out += "No frontmost app found\n"
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) {
            let windows = info as NSArray
            out += "Top-level CGWindows (front->back):\n"
            var count = 0
            for case let dict as NSDictionary in windows {
                if count >= 30 { break }
                let owner = (dict[kCGWindowOwnerName as String] as? String) ?? "(unknown)"
                let ownerPID = WindowTargetSelector.pidValue(dict[kCGWindowOwnerPID as String]) ?? -1
                let title = (dict[kCGWindowName as String] as? String) ?? "(no title)"
                let layer = WindowTargetSelector.integerValue(dict[kCGWindowLayer as String]).map(String.init) ?? "missing"
                out += "  [\(count)] owner=\(owner) pid=\(ownerPID) layer=\(layer) title='\(title)'\n"
                count += 1
            }
        } else {
            out += "Failed to get CGWindowList\n"
        }

        if let target = selectedTarget(frontmostPID: frontmostPID) {
            do {
                let wins = try windowsForPID(target.pid)
                out += "AX windows for pid \(target.pid): count=\(wins.count)\n"
                for (index, window) in wins.enumerated() {
                    let title = titleOfWindow(window) ?? "(no title)"
                    let position = readPosition(window).map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "(unknown)"
                    let size = readSize(window).map { "\(Int($0.width))x\(Int($0.height))" } ?? "(unknown)"
                    out += "  AX[\(index)] title='\(title)' pos=\(position) size=\(size)\n"
                }
            } catch {
                out += "AX list failed: \(error)\n"
            }
        }
        return out
    }

    func appendInspectLog(_ text: String) {
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ResizeWindowApp.log")
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let number = try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber,
               number.int64Value > 1_000_000 {
                try FileManager.default.removeItem(at: logURL)
            }
            let stamp = ISO8601DateFormatter().string(from: Date())
            guard let data = "[\(stamp)] INSPECT\n\(text)\n".data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: logURL)
            }
        } catch {
            resizeLog.error("Failed to write inspect log: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func selectedTarget(frontmostPID: pid_t?) -> WindowCandidate? {
        WindowTargetSelector.select(
            frontmostPID: frontmostPID,
            windows: currentCandidates(),
            ownPID: getpid()
        )
    }

    private func currentCandidates() -> [WindowCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) else {
            resizeLog.debug("CGWindowListCopyWindowInfo returned nil")
            return []
        }
        return WindowTargetSelector.candidates(from: info as NSArray)
    }

    private func displayName(for target: WindowCandidate) -> String {
        if !target.ownerName.isEmpty { return target.ownerName }
        return "pid \(target.pid)"
    }

    private func contextualize(_ error: ResizerError, target: WindowCandidate) -> ResizerError {
        switch error {
        case .axError(let message):
            return .axError("\(displayName(for: target)) (pid:\(target.pid)): \(message)")
        case .accessibilityNotTrusted, .noSuitableWindow:
            return error
        }
    }

    private func applicationElement(for pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.axTimeout)
        return app
    }

    private func windowsForPID(_ pid: pid_t) throws -> [AXUIElement] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(applicationElement(for: pid), kAXWindowsAttribute as CFString, &value)
        guard error == .success, let value else {
            throw ResizerError.axError("Cannot get windows for PID \(pid), AXError: \(error.rawValue)")
        }
        return try axElements(from: value)
    }

    private func axElements(from value: CFTypeRef) throws -> [AXUIElement] {
        guard CFGetTypeID(value) == CFArrayGetTypeID() else {
            throw ResizerError.axError("kAXWindowsAttribute was not an array")
        }
        let array = unsafeDowncast(value, to: CFArray.self)
        let count = CFArrayGetCount(array)
        var result: [AXUIElement] = []
        result.reserveCapacity(count)
        for index in 0 ..< count {
            guard let pointer = CFArrayGetValueAtIndex(array, index) else {
                throw ResizerError.axError("Window list contained a null value")
            }
            let item = Unmanaged<CFTypeRef>.fromOpaque(UnsafeMutableRawPointer(mutating: pointer)).takeUnretainedValue()
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else {
                throw ResizerError.axError("Window list contained a value that is not an AXUIElement")
            }
            result.append(unsafeDowncast(item, to: AXUIElement.self))
        }
        return result
    }

    private func axElement(from value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func titleOfWindow(_ window: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
        guard error == .success, let value else { return nil }
        return value as? String
    }

    private func findWindow(for pid: pid_t) throws -> AXUIElement {
        let windows = try windowsForPID(pid)
        let app = applicationElement(for: pid)
        var focused: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused)
        if error == .success, let focused, let element = axElement(from: focused) {
            return element
        }
        if let first = windows.first { return first }
        throw ResizerError.noSuitableWindow
    }

    private func readSize(_ window: AXUIElement) -> CGSize? {
        guard let axValue = copyAXValue(window, attribute: kAXSizeAttribute as CFString) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private func readPosition(_ window: AXUIElement) -> CGPoint? {
        guard let axValue = copyAXValue(window, attribute: kAXPositionAttribute as CFString) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func copyAXValue(_ element: AXUIElement, attribute: CFString) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }

    private func isAttributeSettable(_ element: AXUIElement, attribute: CFString) -> (settable: Bool, error: AXError) {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return (settable.boolValue, error)
    }

    private func setWindowSize(window: AXUIElement, width: CGFloat, height: CGFloat) throws {
        let check = isAttributeSettable(window, attribute: kAXSizeAttribute as CFString)
        if check.error != .success {
            throw ResizerError.axError("AX check failed for kAXSizeAttribute (AXError \(check.error.rawValue))")
        }
        if !check.settable {
            throw ResizerError.axError("kAXSizeAttribute is not settable on this window")
        }

        var size = CGSize(width: width, height: height)
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw ResizerError.axError("Failed to create AXValue for size")
        }
        let error = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        if error != .success {
            throw ResizerError.axError("AXUIElementSetAttributeValue(kAXSizeAttribute) failed with AXError \(error.rawValue)")
        }
    }

    private func setWindowPosition(window: AXUIElement, x: CGFloat, y: CGFloat) throws {
        let check = isAttributeSettable(window, attribute: kAXPositionAttribute as CFString)
        if check.error != .success {
            throw ResizerError.axError("AX check failed for kAXPositionAttribute (AXError \(check.error.rawValue))")
        }
        if !check.settable {
            throw ResizerError.axError("kAXPositionAttribute is not settable on this window")
        }

        var point = CGPoint(x: x, y: y)
        guard let positionValue = AXValueCreate(.cgPoint, &point) else {
            throw ResizerError.axError("Failed to create AXValue for position")
        }
        let error = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        if error != .success {
            throw ResizerError.axError("AXUIElementSetAttributeValue(kAXPositionAttribute) failed with AXError \(error.rawValue)")
        }
    }
}
