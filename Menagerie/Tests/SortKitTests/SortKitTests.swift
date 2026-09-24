import XCTest
@testable import SortKit

final class SortKitTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(SortKitInfo.name, "SortKit")
    }
}
