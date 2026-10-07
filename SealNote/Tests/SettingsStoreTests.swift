import XCTest
@testable import SealNote

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeStore() -> SettingsStore {
        SettingsStore(defaults: defaults)
    }

    func testDefaultFontSizeIs14() {
        let store = makeStore()
        XCTAssertEqual(store.editorFontSize, 14)
    }

    func testAllowedFontSizesCanBeSet() {
        let store = makeStore()
        for size in [12.0, 13.0, 14.0, 16.0, 18.0] {
            store.editorFontSize = size
            XCTAssertEqual(store.editorFontSize, size)
        }
    }

    func testIllegalFontSizeIsClamped() {
        let store = makeStore()
        store.editorFontSize = 100
        XCTAssertEqual(store.editorFontSize, 18)
        store.editorFontSize = 0
        XCTAssertEqual(store.editorFontSize, 12)
    }

    func testResetForTestingRestoresFontSize() {
        let store = makeStore()
        store.editorFontSize = 18
        XCTAssertEqual(store.editorFontSize, 18)
        store.editorLineHeightMultiple = 1.6
        store.resetForTesting()
        XCTAssertEqual(store.editorFontSize, 14)
        XCTAssertEqual(store.editorLineHeightMultiple, 1.5, accuracy: 0.0001)
        XCTAssertFalse(store.limitEditorMaximumWidth)
    }

    func testPersistedFontSizeIsLoaded() {
        defaults.set(15.0, forKey: "SNMacEditorFontSize")
        let store = makeStore()
        XCTAssertEqual(store.editorFontSize, 15)
    }

    func testDefaultLineHeightMultipleIs150() {
        let store = makeStore()
        XCTAssertEqual(store.editorLineHeightMultiple, 1.5, accuracy: 0.0001)
    }

    func testLineHeightMultipleCanBeSetInRange() {
        let store = makeStore()
        for multiple in [1.2, 1.25, 2.0] {
            store.editorLineHeightMultiple = multiple
            XCTAssertEqual(store.editorLineHeightMultiple, multiple, accuracy: 0.0001)
        }
    }

    func testLineHeightMultipleIsClamped() {
        let store = makeStore()
        store.editorLineHeightMultiple = 1.0
        XCTAssertEqual(store.editorLineHeightMultiple, 1.2, accuracy: 0.0001)
        store.editorLineHeightMultiple = 2.5
        XCTAssertEqual(store.editorLineHeightMultiple, 2.0, accuracy: 0.0001)
    }

    func testPersistedLineHeightMultipleIsLoaded() {
        defaults.set(1.5, forKey: "SNMacEditorLineHeightMultiple")
        let store = makeStore()
        XCTAssertEqual(store.editorLineHeightMultiple, 1.5, accuracy: 0.0001)
    }

    func testEditorMaximumWidthLimitDefaultsOffAndPersists() {
        let store = makeStore()
        XCTAssertFalse(store.limitEditorMaximumWidth)

        store.limitEditorMaximumWidth = true

        XCTAssertTrue(makeStore().limitEditorMaximumWidth)
    }

    func testNewMacSettingsDefaults() {
        let store = makeStore()
        XCTAssertTrue(store.autoDeleteEmptyNotes)
        XCTAssertFalse(store.autoRenameNotesOnSave)
        XCTAssertTrue(store.excludeHexColorsFromTags)
        XCTAssertEqual(store.appTheme, .pink)
        XCTAssertEqual(store.macRecentNotesLimit, 5)
    }

    func testMacThemePersists() {
        let store = makeStore()
        store.appTheme = .cyan
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.appTheme, .cyan)
    }

    func testEditingPrivacyAndDataPreferencesPersist() {
        let store = makeStore()
        store.preferredNoteMode = .encrypted
        store.hideContentOnBackground = false
        store.autoDeleteEmptyNotes = false
        store.autoRenameNotesOnSave = true
        store.excludeHexColorsFromTags = false
        store.maintenanceLoggingEnabled = true

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.preferredNoteMode, .encrypted)
        XCTAssertFalse(reloaded.hideContentOnBackground)
        XCTAssertFalse(reloaded.autoDeleteEmptyNotes)
        XCTAssertTrue(reloaded.autoRenameNotesOnSave)
        XCTAssertFalse(reloaded.excludeHexColorsFromTags)
        XCTAssertTrue(reloaded.maintenanceLoggingEnabled)
    }

    func testPrivacyAndVaultDefaults() {
        let store = makeStore()
        XCTAssertEqual(store.preferredNoteMode, .plain)
        XCTAssertTrue(store.hideContentOnBackground)
        XCTAssertFalse(store.lockSessionOnBackground)
        XCTAssertFalse(store.needsKeyExportPending)
        XCTAssertNil(store.pinnedStorageRoot)
    }

    func testEditorPreferencesAndVaultStatePersist() {
        let store = makeStore()
        store.editorFontSize = 16
        store.editorLineHeightMultiple = 1.8
        store.lockSessionOnBackground = true
        store.needsKeyExportPending = true
        store.pinnedStorageRoot = "icloud"

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.editorFontSize, 16)
        XCTAssertEqual(reloaded.editorLineHeightMultiple, 1.8, accuracy: 0.0001)
        XCTAssertTrue(reloaded.lockSessionOnBackground)
        XCTAssertTrue(reloaded.needsKeyExportPending)
        XCTAssertEqual(reloaded.pinnedStorageRoot, "icloud")
        reloaded.pinnedStorageRoot = nil
        XCTAssertNil(makeStore().pinnedStorageRoot)
    }

    func testStoredValuesAreValidatedOnLoad() {
        defaults.set("unknown", forKey: "SNPreferredNoteMode")
        defaults.set("unknown", forKey: SettingsStore.macThemeDefaultsKey)
        defaults.set(100.0, forKey: "SNMacEditorFontSize")
        defaults.set(3.0, forKey: "SNMacEditorLineHeightMultiple")
        defaults.set(7, forKey: "SNMacRecentNotesLimit")

        let store = makeStore()
        XCTAssertEqual(store.preferredNoteMode, .plain)
        XCTAssertEqual(store.appTheme, .pink)
        XCTAssertEqual(store.editorFontSize, 18)
        XCTAssertEqual(store.editorLineHeightMultiple, 2.0, accuracy: 0.0001)
        XCTAssertEqual(store.macRecentNotesLimit, 5)
    }

    func testEveryRecentNotesLimitOptionPersists() {
        let store = makeStore()
        for limit in [5, 10, 15] {
            store.macRecentNotesLimit = limit
            XCTAssertEqual(makeStore().macRecentNotesLimit, limit)
        }
    }

    #if os(iOS)
    func testIOSAppIconPreferencePersists() {
        let store = makeStore()
        store.iOSAppIconName = IOSAppIconChoice.cyan.iconName

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.iOSAppIconName, IOSAppIconChoice.cyan.iconName)
        XCTAssertEqual(IOSAppIconChoice.choice(for: reloaded.iOSAppIconName), .cyan)
    }

    func testIPadDoubleColumnLayoutDefaultsOnAndPersists() {
        let store = makeStore()
        XCTAssertTrue(store.iPadDoubleColumnLayoutEnabled)

        store.iPadDoubleColumnLayoutEnabled = false

        let reloaded = makeStore()
        XCTAssertFalse(reloaded.iPadDoubleColumnLayoutEnabled)
        reloaded.resetForTesting()
        XCTAssertTrue(reloaded.iPadDoubleColumnLayoutEnabled)
    }
    #endif

    func testRecentNotesLimitIsClamped() {
        let store = makeStore()
        store.macRecentNotesLimit = 1
        XCTAssertEqual(store.macRecentNotesLimit, 5)
        store.macRecentNotesLimit = 99
        XCTAssertEqual(store.macRecentNotesLimit, 15)
    }

    func testRecentNotesLimitPersists() {
        let store = makeStore()
        store.macRecentNotesLimit = 10
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.macRecentNotesLimit, 10)
    }

    #if os(macOS)
    func testMacIntroPreferencePersists() {
        let store = makeStore()
        store.hideMacIntroOnLaunch = true

        let reloaded = makeStore()
        XCTAssertTrue(reloaded.hideMacIntroOnLaunch)
    }

    func testResetForTestingRestoresMacIntroPreference() {
        let store = makeStore()
        store.hideMacIntroOnLaunch = true
        store.resetForTesting()
        XCTAssertFalse(store.hideMacIntroOnLaunch)
    }
    #endif

}
