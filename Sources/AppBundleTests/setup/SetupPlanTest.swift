import Common
import XCTest

final class SetupPlanTest: XCTestCase {
    private let settings = [
        SetupSetting(domain: "d1", key: "a", value: true, note: ""),
        SetupSetting(domain: "d2", key: "b", value: false, note: ""),
    ]

    func testWritesOnlyWhatDiffersAndRecordsPrevious() {
        let current: [String: Bool] = ["d1.a": true] // b unset
        let plan = initPlan(current: { current["\($0).\($1)"] }, existingBackup: nil, settings: settings)
        assertEquals(plan.actions, [.write(domain: "d2", key: "b", value: false)])
        assertEquals(plan.backup, SetupBackup(entries: [
            .init(domain: "d1", key: "a", previous: true),
            .init(domain: "d2", key: "b", previous: nil),
        ]))
    }

    func testSecondInitKeepsOriginalBackup() {
        let original = SetupBackup(entries: [.init(domain: "d1", key: "a", previous: false), .init(domain: "d2", key: "b", previous: nil)])
        let plan = initPlan(current: { _, _ in nil }, existingBackup: original, settings: settings)
        assertEquals(plan.backup, original) // second run: values now are HyprDarwin's; the backup keeps the first ones
    }

    func testSettingAddedLaterIsAppendedToBackup() {
        let old = SetupBackup(entries: [.init(domain: "d1", key: "a", previous: false)])
        let plan = initPlan(current: { d, _ in d == "d2" ? true : nil }, existingBackup: old, settings: settings)
        assertEquals(plan.backup.entries.last, .init(domain: "d2", key: "b", previous: true))
        assertEquals(plan.backup.entries.count, 2)
    }

    func testUndoDeletesWhatWasUnset() {
        let backup = SetupBackup(entries: [.init(domain: "d1", key: "a", previous: false), .init(domain: "d2", key: "b", previous: nil)])
        assertEquals(undoPlan(backup), [.write(domain: "d1", key: "a", value: false), .delete(domain: "d2", key: "b")])
    }

    func testShippedSettingsMatchHyprspaceInit() {
        assertEquals(setupSettings.map { "\($0.domain) \($0.key) \($0.value)" }, [
            "com.apple.spaces spans-displays true",
            "com.apple.dock expose-group-apps true",
            "NSGlobalDomain NSAutomaticWindowAnimationsEnabled false",
            "NSGlobalDomain _HIHideMenuBar true",
        ])
    }

    func testConfigDirHonorsXdg() {
        assertEquals(hyprDarwinConfigDir(env: ["XDG_CONFIG_HOME": "/x"], home: URL(filePath: "/h")).path, "/x/hyprland-darwin")
        assertEquals(hyprDarwinConfigDir(env: [:], home: URL(filePath: "/h")).path, "/h/.config/hyprland-darwin")
    }
}
