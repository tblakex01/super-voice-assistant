import XCTest
@testable import SharedModels

final class ModelDataTests: XCTestCase {
    func testAvailableModelsIncludesCoreModels() {
        let models = ModelData.availableModels
        let modelNames = Set(models.map(\.name))

        XCTAssertTrue(modelNames.contains("distil-large-v3"))
        XCTAssertTrue(modelNames.contains("large-v3-turbo"))
        XCTAssertTrue(modelNames.contains("large-v3"))
    }

    func testAvailableModelsHaveUniqueIdentityFields() {
        let models = ModelData.availableModels

        let names = models.map(\.name)
        let whisperKitModelNames = models.map(\.whisperKitModelName)

        XCTAssertEqual(Set(names).count, names.count, "Model names must be unique")
        XCTAssertEqual(Set(whisperKitModelNames).count, whisperKitModelNames.count, "WhisperKit model names must be unique")
    }

    func testAvailableModelsContainRequiredMetadata() {
        for model in ModelData.availableModels {
            XCTAssertFalse(model.name.isEmpty)
            XCTAssertFalse(model.displayName.isEmpty)
            XCTAssertFalse(model.whisperKitModelName.isEmpty)
            XCTAssertFalse(model.size.isEmpty)
            XCTAssertFalse(model.speed.isEmpty)
            XCTAssertFalse(model.accuracy.isEmpty)
            XCTAssertFalse(model.accuracyNote.isEmpty)
            XCTAssertFalse(model.languages.isEmpty)
            XCTAssertFalse(model.description.isEmpty)
            XCTAssertFalse(model.sourceURL.isEmpty)

            guard let url = URL(string: model.sourceURL) else {
                XCTFail("Invalid source URL for model \(model.name)")
                continue
            }

            XCTAssertEqual(url.scheme, "https", "Source URL must use HTTPS for model \(model.name)")
            XCTAssertEqual(url.host, "huggingface.co", "Source URL should point to Hugging Face for model \(model.name)")
        }
    }

    func testDebugTinyModelIfPresentHasExplicitDevOnlyMarker() {
        let models = ModelData.availableModels

        guard let tiny = models.first(where: { $0.name == "tiny-test" }) else {
            return
        }

        XCTAssertTrue(tiny.description.contains("DEV ONLY"))
        XCTAssertEqual(tiny.languages, "99 languages")
    }
}
