import XCTest
@testable import SharedModels

final class SmartSentenceSplitterTests: XCTestCase {
    func testSplitIntoSentencesReturnsEmptyArrayForEmptyInput() {
        XCTAssertEqual(SmartSentenceSplitter.splitIntoSentences("   \n\t"), [])
    }

    func testSplitIntoSentencesKeepsShortTextAsSingleSentence() {
        let text = "  Hello world from unit tests.  "
        XCTAssertEqual(SmartSentenceSplitter.splitIntoSentences(text), ["Hello world from unit tests."])
    }

    func testSplitIntoSentencesRespectsCommonAbbreviations() {
        let text = "Dr. Smith gave a talk yesterday. It was clear and useful for everyone."

        let sentences = SmartSentenceSplitter.splitIntoSentences(text, minWordsPerSentence: 4)

        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[0], "Dr. Smith gave a talk yesterday.")
        XCTAssertEqual(sentences[1], "It was clear and useful for everyone.")
    }

    func testSplitIntoSentencesCombinesShortSentencesWhenNeeded() {
        let text = "One two. Three four. Five six seven eight nine ten eleven twelve."

        let sentences = SmartSentenceSplitter.splitIntoSentences(text, minWordsPerSentence: 5)

        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[0], "One two. Three four.")
        XCTAssertEqual(sentences[1], "Five six seven eight nine ten eleven twelve.")
    }

    func testAnalyzeTextReturnsSentenceWordCounts() {
        let text = "First sentence has five words. Second sentence has exactly six words."

        let analysis = SmartSentenceSplitter.analyzeText(text)

        XCTAssertEqual(analysis.sentences.count, analysis.wordCounts.count)
        XCTAssertEqual(analysis.wordCounts, [5, 6])
    }
}
