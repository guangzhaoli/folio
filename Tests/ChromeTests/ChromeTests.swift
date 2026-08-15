import XCTest
@testable import Folio

final class ChromeTests: XCTestCase {
    func testOutlinePlacementRoundTrip() {
        let previous = UserDefaults.standard.string(forKey: OutlinePlacement.defaultsKey)
        defer { UserDefaults.standard.set(previous, forKey: OutlinePlacement.defaultsKey) }

        OutlinePlacement.top.persist()
        XCTAssertEqual(OutlinePlacement.stored, .top)
        OutlinePlacement.trailing.persist()
        XCTAssertEqual(OutlinePlacement.stored, .trailing)
        OutlinePlacement.belowLibrary.persist()
        XCTAssertEqual(OutlinePlacement.stored, .belowLibrary)
    }

    func testOutlinePlacementTitles() {
        XCTAssertEqual(OutlinePlacement.belowLibrary.title, "Below Library")
        XCTAssertEqual(OutlinePlacement.top.title, "Top")
        XCTAssertEqual(OutlinePlacement.trailing.title, "Right")
    }
}