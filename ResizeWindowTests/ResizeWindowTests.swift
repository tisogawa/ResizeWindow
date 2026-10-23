import CoreGraphics
import XCTest
@testable import ResizeWindow

final class WindowGeometryTests: XCTestCase {
    func testParsesSizeAndIgnoresCoordinatesWhenNotMoving() {
        let result = WindowGeometry.parse(width: " 1440 ", height: "900", move: false, x: "", y: "nope")
        XCTAssertEqual(result, .success(WindowGeometry.Request(width: 1440, height: 900, origin: nil)))
    }

    func testRejectsEmptyWidth() {
        let result = WindowGeometry.parse(width: " ", height: "900", move: false, x: "", y: "")
        XCTAssertEqual(result, .failure(.invalidWidth))
    }

    func testRejectsNonNumericHeight() {
        let result = WindowGeometry.parse(width: "1440", height: "abc", move: false, x: "", y: "")
        XCTAssertEqual(result, .failure(.invalidHeight))
    }

    func testRejectsZeroAndNegativeSize() {
        XCTAssertEqual(WindowGeometry.parse(width: "0", height: "900", move: false, x: "", y: ""), .failure(.invalidWidth))
        XCTAssertEqual(WindowGeometry.parse(width: "-10", height: "900", move: false, x: "", y: ""), .failure(.invalidWidth))
        XCTAssertEqual(WindowGeometry.parse(width: "1440", height: "0", move: false, x: "", y: ""), .failure(.invalidHeight))
    }

    func testRejectsNonFiniteSize() {
        XCTAssertEqual(WindowGeometry.parse(width: "inf", height: "900", move: false, x: "", y: ""), .failure(.invalidWidth))
        XCTAssertEqual(WindowGeometry.parse(width: "1440", height: "nan", move: false, x: "", y: ""), .failure(.invalidHeight))
    }

    func testMoveRequiresBothCoordinates() {
        XCTAssertEqual(
            WindowGeometry.parse(width: "800", height: "600", move: true, x: "", y: ""),
            .failure(.missingCoordinates)
        )
        XCTAssertEqual(
            WindowGeometry.parse(width: "800", height: "600", move: true, x: "10", y: " "),
            .failure(.missingCoordinates)
        )
    }

    func testMoveRejectsNonNumericCoordinates() {
        XCTAssertEqual(
            WindowGeometry.parse(width: "800", height: "600", move: true, x: "left", y: "10"),
            .failure(.invalidX)
        )
        XCTAssertEqual(
            WindowGeometry.parse(width: "800", height: "600", move: true, x: "10", y: "top"),
            .failure(.invalidY)
        )
    }

    func testMoveAllowsNegativeCoordinates() {
        let result = WindowGeometry.parse(width: "800", height: "600", move: true, x: "-40", y: "25")
        XCTAssertEqual(result, .success(WindowGeometry.Request(width: 800, height: 600, origin: CGPoint(x: -40, y: 25))))
    }
}

final class WindowTargetSelectorTests: XCTestCase {
    func testPrefersFrontmostAppWhenItHasAnEligibleWindow() {
        let windows = [
            WindowCandidate(pid: 10, ownerName: "Overlay", layer: 0),
            WindowCandidate(pid: 20, ownerName: "Terminal", layer: 0),
        ]
        let selected = WindowTargetSelector.select(frontmostPID: 20, windows: windows, ownPID: 1)
        XCTAssertEqual(selected?.pid, 20)
    }

    func testSkipsOwnFrontmostAppAndUsesZOrder() {
        let windows = [
            WindowCandidate(pid: 1, ownerName: "ResizeWindow", layer: 0),
            WindowCandidate(pid: 30, ownerName: "Safari", layer: 0),
        ]
        let selected = WindowTargetSelector.select(frontmostPID: 1, windows: windows, ownPID: 1)
        XCTAssertEqual(selected?.pid, 30)
    }

    func testSkipsSystemWindowsAndNonZeroLayers() {
        let windows = [
            WindowCandidate(pid: 2, ownerName: "Window Server", layer: 0),
            WindowCandidate(pid: 3, ownerName: "Dock", layer: 0),
            WindowCandidate(pid: 4, ownerName: "loginwindow", layer: 0),
            WindowCandidate(pid: 5, ownerName: "Screenshot", layer: 8),
            WindowCandidate(pid: 0, ownerName: "Unknown", layer: 0),
            WindowCandidate(pid: 40, ownerName: "Notes", layer: 0),
        ]
        let selected = WindowTargetSelector.select(frontmostPID: nil, windows: windows, ownPID: 1)
        XCTAssertEqual(selected?.pid, 40)
    }

    func testFrontmostWithOnlyHigherLayersFallsThrough() {
        let windows = [
            WindowCandidate(pid: 7, ownerName: "Panel", layer: 3),
            WindowCandidate(pid: 8, ownerName: "Mail", layer: 0),
        ]
        let selected = WindowTargetSelector.select(frontmostPID: 7, windows: windows, ownPID: 1)
        XCTAssertEqual(selected?.pid, 8)
    }

    func testMissingLayerStaysEligible() {
        let windows = [WindowCandidate(pid: 9, ownerName: "Finder", layer: nil)]
        let selected = WindowTargetSelector.select(frontmostPID: nil, windows: windows, ownPID: 1)
        XCTAssertEqual(selected?.pid, 9)
    }

    func testReturnsNilWhenNothingIsEligible() {
        let windows = [WindowCandidate(pid: 1, ownerName: "ResizeWindow", layer: 0)]
        XCTAssertNil(WindowTargetSelector.select(frontmostPID: 1, windows: windows, ownPID: 1))
    }

    func testNonZeroNSNumberLayerIsExcluded() {
        let dict: NSDictionary = [
            kCGWindowOwnerPID as String: NSNumber(value: 42),
            kCGWindowOwnerName as String: "Overlay",
            kCGWindowLayer as String: NSNumber(value: 8),
        ]
        let windows = WindowTargetSelector.candidates(from: [dict])
        XCTAssertEqual(windows.first?.layer, 8)
        XCTAssertNil(WindowTargetSelector.select(frontmostPID: 42, windows: windows, ownPID: 1))
    }

    func testMissingLayerInWindowListStaysEligible() {
        let dict: NSDictionary = [
            kCGWindowOwnerPID as String: NSNumber(value: 42),
            kCGWindowOwnerName as String: "Terminal",
        ]
        let windows = WindowTargetSelector.candidates(from: [dict])
        XCTAssertEqual(windows.first?.layer, nil)
        XCTAssertEqual(WindowTargetSelector.select(frontmostPID: nil, windows: windows, ownPID: 1)?.pid, 42)
    }
}

final class ResultInfoTests: XCTestCase {
    func testReportsMeasuredSizeWhenItDiffersFromTheRequest() {
        let info = ResultInfo(
            pid: 12,
            appName: "Terminal",
            measuredSize: CGSize(width: 800, height: 600),
            measuredPosition: CGPoint(x: 10, y: 40),
            requestedWidth: 100,
            requestedHeight: 100,
            requestedOrigin: nil,
            positionApplied: true,
            positionError: nil
        )
        XCTAssertEqual(
            info.statusText,
            "Done — Terminal (pid:12) size:800x600 (requested 100x100) position:(10, 40)"
        )
    }

    func testReportsSizeAppliedWhenPositionFails() {
        let info = ResultInfo(
            pid: 12,
            appName: "Terminal",
            measuredSize: CGSize(width: 1440, height: 900),
            measuredPosition: CGPoint(x: 10, y: 40),
            requestedWidth: 1440,
            requestedHeight: 900,
            requestedOrigin: CGPoint(x: 0, y: 0),
            positionApplied: false,
            positionError: "AX error: not settable"
        )
        XCTAssertTrue(info.statusText.contains("size:1440x900"))
        XCTAssertTrue(info.statusText.contains("Size applied, position unchanged"))
        XCTAssertFalse(info.statusText.contains("position:(0, 0)"))
    }

    func testDoesNotClaimRequestedSizeWhenReadbackFails() {
        let info = ResultInfo(
            pid: 12,
            appName: "Terminal",
            measuredSize: nil,
            measuredPosition: nil,
            requestedWidth: 1440,
            requestedHeight: 900,
            requestedOrigin: nil,
            positionApplied: true,
            positionError: nil
        )
        XCTAssertFalse(info.statusText.contains("1440"))
        XCTAssertTrue(info.statusText.contains("actual size could not be read"))
    }
}
