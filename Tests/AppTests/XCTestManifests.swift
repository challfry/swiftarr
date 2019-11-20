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
        ("testUsersFind", testUsersFind),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(AppTests.__allTests__AppTests),
        testCase(UserTests.__allTests__UserTests),
        testCase(UsersTests.__allTests__UsersTests),
    ]
}
#endif
