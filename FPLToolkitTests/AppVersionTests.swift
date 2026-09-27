import Testing
@testable import FPLToolkit

struct AppVersionTests {
    @Test(arguments: [
        ("1.0.0", "1.0.1", true),
        ("1.0.9", "1.0.10", true),
        ("1.2", "1.10", true),
        ("1.0", "1.0.0", false),
        ("2.0.0", "1.9.9", false),
        ("1.0.0", "1.0.0", false),
    ])
    func olderThan(current: String, minimum: String, older: Bool) {
        #expect((AppVersion(current) < AppVersion(minimum)) == older)
    }
}
