import XCTest
@testable import SynthKit

final class SynthKitTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(SynthKitInfo.name, "SynthKit")
    }
}
