import XCTest
@testable import MazeKit

final class MazeKitTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(MazeKitInfo.name, "MazeKit")
    }
}
