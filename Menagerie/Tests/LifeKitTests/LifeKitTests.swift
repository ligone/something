import XCTest
@testable import LifeKit

final class LifeKitTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(LifeKitInfo.name, "LifeKit")
    }
}
