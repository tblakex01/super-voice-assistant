import XCTest
@testable import SharedModels

final class GeminiAudioCollectorErrorTests: XCTestCase {
    func testInvalidURLErrorDescription() {
        XCTAssertEqual(
            GeminiAudioCollectorError.invalidURL.errorDescription,
            "Invalid WebSocket URL"
        )
    }

    func testCollectionErrorDescriptionIncludesUnderlyingMessage() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "network unavailable" }
        }

        let description = GeminiAudioCollectorError.collectionError(TestError()).errorDescription

        XCTAssertEqual(description, "Audio collection error: network unavailable")
    }
}
