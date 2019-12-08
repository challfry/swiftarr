#if !canImport(ObjectiveC)
import XCTest

extension AppTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__AppTests = [
        ("testNothing", testNothing),
    ]
}

extension BarrelTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__BarrelTests = [
        ("testAlertWordsModify", testAlertWordsModify),
        ("testBarrelCreate", testBarrelCreate),
        ("testBarrelModify", testBarrelModify),
        ("testDefaultBarrels", testDefaultBarrels),
        ("testMuteWordsModify", testMuteWordsModify),
        ("testUserBarrel", testUserBarrel),
        ("testUserBarrelDelete", testUserBarrelDelete),
        ("testUserBarrelRename", testUserBarrelRename),
        ("testUserBlock", testUserBlock),
        ("testUserFilters", testUserFilters),
        ("testUserMute", testUserMute),
        ("testUserUnblock", testUserUnblock),
        ("testUserUnmute", testUserUnmute),
    ]
}

extension ClientTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__ClientTests = [
        ("testClientMigration", testClientMigration),
        ("testUserHeaders", testUserHeaders),
        ("testUsersearch", testUsersearch),
        ("testUserUpdates", testUserUpdates),
    ]
}

extension EventTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__EventTests = [
        ("testEventsAll", testEventsAll),
        ("testEventsMatch", testEventsMatch),
        ("testEventsMigration", testEventsMigration),
        ("testEventsNow", testEventsNow),
        ("testEventsToday", testEventsToday),
        ("testEventsUpdate", testEventsUpdate),
    ]
}

extension UserTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__UserTests = [
        ("testAuthLogin", testAuthLogin),
        ("testAuthLogout", testAuthLogout),
        ("testAuthRecovery", testAuthRecovery),
        ("testRegistrationCodesMigration", testRegistrationCodesMigration),
        ("testUserAccessLevelsAreOrdered", testUserAccessLevelsAreOrdered),
        ("testUserAdd", testUserAdd),
        ("testUserCreate", testUserCreate),
        ("testUserImage", testUserImage),
        ("testUserNotes", testUserNotes),
        ("testUserPassword", testUserPassword),
        ("testUserProfile", testUserProfile),
        ("testUserUsername", testUserUsername),
        ("testUserVerify", testUserVerify),
        ("testUserWhoami", testUserWhoami),
    ]
}

extension UsersTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__UsersTests = [
        ("testMatchAllNames", testMatchAllNames),
        ("testMatchUsername", testMatchUsername),
        ("testUserReport", testUserReport),
        ("testUsersFind", testUsersFind),
        ("testUsersHeader", testUsersHeader),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(AppTests.__allTests__AppTests),
        testCase(BarrelTests.__allTests__BarrelTests),
        testCase(ClientTests.__allTests__ClientTests),
        testCase(EventTests.__allTests__EventTests),
        testCase(UserTests.__allTests__UserTests),
        testCase(UsersTests.__allTests__UsersTests),
    ]
}
#endif
