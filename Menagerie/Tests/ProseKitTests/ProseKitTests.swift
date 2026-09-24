import XCTest
@testable import ProseKit

final class ProseKitTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(ProseKitInfo.name, "ProseKit")
    }
}
