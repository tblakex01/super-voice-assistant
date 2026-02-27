import Foundation
import XCTest
@testable import SharedModels

final class WhisperModelManagerTests: XCTestCase {
    private let manager = WhisperModelManager()
    private let fileManager = FileManager.default

    func testGetModelPathAppendsModelNameToBasePath() {
        let modelName = "unit-test-model"

        let basePath = manager.getModelsBasePath()
        let modelPath = manager.getModelPath(for: modelName)

        XCTAssertEqual(modelPath, basePath.appendingPathComponent(modelName))
    }

    func testModelExistsOnDiskReflectsFilesystemState() throws {
        let modelName = uniqueModelName()
        let modelPath = manager.getModelPath(for: modelName)
        defer { try? fileManager.removeItem(at: modelPath) }

        XCTAssertFalse(manager.modelExistsOnDisk(modelName))

        try fileManager.createDirectory(at: modelPath, withIntermediateDirectories: true)
        XCTAssertTrue(manager.modelExistsOnDisk(modelName))
    }

    func testMarkModelAsDownloadedPersistsMetadataAndModelAppearsDownloaded() throws {
        let modelName = uniqueModelName()
        let modelPath = manager.getModelPath(for: modelName)
        defer { try? fileManager.removeItem(at: modelPath) }

        try fileManager.createDirectory(at: modelPath, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modelPath.appendingPathComponent("config.json"))
        try Data([0x01, 0x02, 0x03]).write(to: modelPath.appendingPathComponent("model.mil"))

        manager.markModelAsDownloaded(modelName)

        XCTAssertTrue(manager.isModelDownloaded(modelName))
        XCTAssertTrue(manager.getDownloadedModels().contains(modelName))
        XCTAssertTrue(manager.validateModelIntegrity(modelName))

        let metadata = manager.getModelMetadata(modelName)
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.modelName, modelName)
        XCTAssertTrue((metadata?.isComplete) ?? false)
        XCTAssertGreaterThanOrEqual(metadata?.fileCount ?? 0, 2)
        XCTAssertGreaterThan(metadata?.totalSize ?? 0, 0)
    }

    func testRemoveDownloadMetadataMarksModelAsNotDownloaded() throws {
        let modelName = uniqueModelName()
        let modelPath = manager.getModelPath(for: modelName)
        defer { try? fileManager.removeItem(at: modelPath) }

        try fileManager.createDirectory(at: modelPath, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modelPath.appendingPathComponent("config.json"))

        manager.markModelAsDownloaded(modelName)
        XCTAssertTrue(manager.isModelDownloaded(modelName))

        manager.removeDownloadMetadata(for: modelName)
        XCTAssertFalse(manager.isModelDownloaded(modelName))
    }

    func testValidateModelIntegrityIsFalseWhenModelDirectoryMissing() {
        XCTAssertFalse(manager.validateModelIntegrity(uniqueModelName()))
    }

    private func uniqueModelName() -> String {
        "unit-test-\(UUID().uuidString)"
    }
}
