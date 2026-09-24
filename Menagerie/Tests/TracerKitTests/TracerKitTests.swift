import XCTest
@testable import TracerKit

final class TracerKitTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(TracerKitInfo.name, "TracerKit")
    }
}
