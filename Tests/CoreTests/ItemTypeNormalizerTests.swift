import Foundation
import XCTest

#if canImport(Core)
import Core
#endif

final class ItemTypeNormalizerTests: XCTestCase {

    func testCanonicalTypeMapsKnownPluralToKnownSingular() {
        let type = ItemTypeNormalizer.canonicalType(
            from: " books ",
            knownTypes: ["Todo", "Book", "Movie"]
        )
        XCTAssertEqual(type, "book")
    }

    func testCanonicalTypeKeepsKnownSingular() {
        let type = ItemTypeNormalizer.canonicalType(
            from: "Book",
            knownTypes: ["book", "movie"]
        )
        XCTAssertEqual(type, "book")
    }

    func testCanonicalTypeKeepsUnknownPluralWhenNoKnownSingularMatch() {
        let type = ItemTypeNormalizer.canonicalType(
            from: "news",
            knownTypes: ["book", "movie"]
        )
        XCTAssertEqual(type, "news")
    }

    func testCanonicalTypeHandlesIesPluralForm() {
        let type = ItemTypeNormalizer.canonicalType(
            from: "movies",
            knownTypes: ["movie", "book"]
        )
        XCTAssertEqual(type, "movie")
    }
}
