import XCTest
@testable import CalculusKit

final class CalculusKitTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(CalculusKitInfo.name, "CalculusKit")
    }
}
