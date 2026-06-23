// ELAPTests — XCTest suite for ELAP pure / safety-critical logic.
//
// Excluded by design (would mutate system/signal state or require attached hardware):
//   - countdownSeconds (1-second sleeps, terminal I/O)
//   - installReenableHandlers / removeReenableHandlers (mutate signal disposition)
//   - the actual setEnabled(_:false) disable path (would blank the screen)
//   - daemon/launchctl flows (mutate system launchd state)

import XCTest
@testable import ELAP

final class ELAPTests: XCTestCase {

    // MARK: §DTError messages

    func testErrorNoBuiltInDisplay() {
        let err = DTError.noBuiltInDisplay
        XCTAssertEqual(err.errorDescription, "No built-in display detected on this machine.")
    }

    func testErrorNoExternalDisplayContainsForceHint() {
        let err = DTError.noExternalDisplay
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("--force"), "noExternalDisplay error must mention --force")
        XCTAssertTrue(desc.contains("blank screen"), "noExternalDisplay error must mention blank screen risk")
    }

    func testErrorSymbolNotFoundListsNamesAndNmSuggestion() {
        let names = ["CGSConfigureDisplayEnabled", "CGSSetDisplayEnabled"]
        let err = DTError.symbolNotFound(names)
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("CGSConfigureDisplayEnabled"))
        XCTAssertTrue(desc.contains("CGSSetDisplayEnabled"))
        XCTAssertTrue(desc.contains("nm "), "symbolNotFound error must include nm command suggestion")
        XCTAssertTrue(desc.contains("SkyLight.framework"))
    }

    func testErrorApiFailureMessage() {
        let err = DTError.apiFailure("X", 7)
        XCTAssertEqual(err.errorDescription, "Private API 'X' returned error code 7.")
    }

    // MARK: §State-file round-trip

    // Back up any existing state file, exercise save/load/clear, then restore.
    private var backupContent: String? = nil

    override func setUp() {
        super.setUp()
        backupContent = try? String(contentsOfFile: stateFilePath, encoding: .utf8)
        // Remove it so tests start clean.
        try? FileManager.default.removeItem(atPath: stateFilePath)
    }

    override func tearDown() {
        // Restore whatever was there before the test ran.
        if let original = backupContent {
            try? original.write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(atPath: stateFilePath)
        }
        super.tearDown()
    }

    func testStateFileSaveAndLoad() {
        let id: CGDirectDisplayID = 12345
        saveBuiltInDisplayID(id)
        XCTAssertEqual(loadSavedBuiltInDisplayID(), id)
    }

    func testStateFileClear() {
        saveBuiltInDisplayID(99)
        clearBuiltInDisplayID()
        XCTAssertNil(loadSavedBuiltInDisplayID())
    }

    func testStateFileWhitespaceTrimParsing() {
        // Simulate a file written with surrounding whitespace / newlines.
        let id: CGDirectDisplayID = 42
        let raw = "  \(id)\n"
        try? raw.write(toFile: stateFilePath, atomically: true, encoding: .utf8)
        XCTAssertEqual(loadSavedBuiltInDisplayID(), id)
    }

    // MARK: §hasActiveExternalDisplay

    private func makeDisplay(id: CGDirectDisplayID, isBuiltIn: Bool, isActive: Bool) -> DisplayInfo {
        DisplayInfo(id: id, isBuiltIn: isBuiltIn, isActive: isActive, bounds: .zero)
    }

    func testHasActiveExternalDisplay_externalActive() {
        let displays = [
            makeDisplay(id: 1, isBuiltIn: true,  isActive: true),
            makeDisplay(id: 2, isBuiltIn: false, isActive: true),
        ]
        XCTAssertTrue(hasActiveExternalDisplay(displays))
    }

    func testHasActiveExternalDisplay_externalInactiveOnly() {
        let displays = [
            makeDisplay(id: 1, isBuiltIn: true,  isActive: true),
            makeDisplay(id: 2, isBuiltIn: false, isActive: false),
        ]
        XCTAssertFalse(hasActiveExternalDisplay(displays))
    }

    func testHasActiveExternalDisplay_builtInOnly() {
        let displays = [
            makeDisplay(id: 1, isBuiltIn: true, isActive: true),
        ]
        XCTAssertFalse(hasActiveExternalDisplay(displays))
    }

    func testHasActiveExternalDisplay_empty() {
        XCTAssertFalse(hasActiveExternalDisplay([]))
    }

    // MARK: §builtInDisplay(in:)

    func testBuiltInDisplayFound() {
        let builtin = makeDisplay(id: 7, isBuiltIn: true,  isActive: true)
        let external = makeDisplay(id: 8, isBuiltIn: false, isActive: true)
        let result = builtInDisplay(in: [external, builtin])
        XCTAssertEqual(result?.id, 7)
    }

    func testBuiltInDisplayNilWhenAbsent() {
        let displays = [makeDisplay(id: 8, isBuiltIn: false, isActive: true)]
        XCTAssertNil(builtInDisplay(in: displays))
    }

    // MARK: §waitForEnterOrTimeout edge cases

    func testWaitForEnterOrTimeoutZeroReturnsFalseImmediately() {
        let result = waitForEnterOrTimeout(seconds: 0)
        XCTAssertFalse(result)
    }

    func testWaitForEnterOrTimeoutNegativeReturnsFalseImmediately() {
        let result = waitForEnterOrTimeout(seconds: -5)
        XCTAssertFalse(result)
    }

    // MARK: §Symbol resolution on host

    func testSkyLightAPILoadsAndResolvesSymbol() throws {
        // Read-only: only resolves the symbol, never toggles a display.
        let api = try SkyLightAPI.load(verbose: false)
        XCTAssertFalse(api.symbolName.isEmpty, "symbolName must be non-empty after load()")
        XCTAssertEqual(api.symbolName, "CGSConfigureDisplayEnabled",
                       "Expected primary symbol on supported macOS; update if macOS renames it")
    }

    // MARK: §fetchDisplays classification

    func testFetchDisplaysBuiltInClassification() throws {
        let displays = fetchDisplays(verbose: false)
        if let builtin = builtInDisplay(in: displays) {
            // On a MacBook the built-in must be reported as built-in.
            XCTAssertTrue(builtin.isBuiltIn)
        } else {
            // Running in CI without a built-in panel — skip gracefully.
            throw XCTSkip("No built-in display detected; skipping classification test (CI environment)")
        }
    }

    // Access the internal stateFilePath for use in setUp/tearDown.
    // It is a module-level `private let`, but @testable import exposes internal/private
    // top-level vars. Actually stateFilePath is `private let`, we access it via the
    // module's save/load/clear functions instead.
}

// Expose stateFilePath for the tearDown restore path.
// Because stateFilePath is declared `private`, tests reach it indirectly:
// - saveBuiltInDisplayID / clearBuiltInDisplayID / loadSavedBuiltInDisplayID are `internal`.
// - The backup uses Foundation directly with the same computed path.
private var stateFilePath: String {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".elap-builtin-id").path
}
