import XCTest
@testable import ConnectFourKit

final class ConnectFourKitTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(ConnectFourKitInfo.name, "ConnectFourKit")
    }
}
