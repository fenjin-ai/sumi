import Foundation
@testable import LeftBlankApp
import LeftBlankCore
import Testing

/// Opt-in effect evaluation. Quality misses are recorded as data, not disguised as regression-test failures.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["LEFTBLANK_EVALUATION"] == "1"))
struct IntelligenceEvaluationTests {
    @Test func measureFixedRequestsAndReferencePages() async throws {
        #expect(LocalIntelligence.status == .available)
        let root = try URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["LEFTBLANK_EVALUATION_ROOT"]))
        let decoder = JSONDecoder()
        let requests = try decoder.decode(
            [EvaluationRequest].self,
            from: Data(contentsOf: root.appendingPathComponent("requests.json")),
        )
        #expect(requests.count == 100)
        #expect(requests.filter { $0.language == "zh" }.count == 50)
        var results: [EvaluationResponse] = []
        for (index, request) in requests.enumerated() {
            var route = "model"
            var ruleSuggestion: TypesettingSuggestion?
            var ruleError: String?
            do {
                ruleSuggestion = try TypesettingIntelligence.suggest(request.request)
                if ruleSuggestion != nil {
                    route = "rules"
                }
                if TypesettingIntelligence.requiresNumberedCode(request.request) {
                    route = "rules-refusal"
                }
            } catch {
                route = "rules-rejection"
                ruleError = String(describing: error)
            }
            let start = Date()
            var suggestion: TypesettingSuggestion?
            var errorMessage: String?
            var isValidationError = false
            do {
                suggestion = try await LocalIntelligence.suggest(request.request)
            } catch {
                errorMessage = String(describing: error)
                isValidationError = error is CommandError
                if let local = error as? LocalIntelligenceError {
                    switch local {
                    case .invalidSuggestion, .requestLength: isValidationError = true
                    case .generationFailed: break
                    }
                }
            }
            results.append(.init(
                id: request.id, category: request.category, language: request.language,
                request: request.request, expected: request.expected, route: route,
                ruleSuggestion: ruleSuggestion, ruleError: ruleError,
                suggestion: suggestion, error: errorMessage,
                seconds: Date().timeIntervalSince(start),
                correct: request.expected.matches(
                    suggestion,
                    error: errorMessage,
                    isValidationError: isValidationError,
                ),
            ))
            try write(results, to: root.appendingPathComponent("request-results.json"))
            if (index + 1).isMultiple(of: 10) {
                print("EVALUATION requests \(index + 1)/100; correct \(results.filter(\.correct).count)")
            }
        }
        let pages = try decoder.decode(
            [EvaluationPage].self,
            from: Data(contentsOf: root.appendingPathComponent("pages.json")),
        )
        var imports: [EvaluationImport] = []
        for page in pages {
            let start = Date()
            let result = try await ReferencePageImporter.importPage(from: root.appendingPathComponent(page.file))
            try result.source.write(
                to: root.appendingPathComponent("\(page.id)-reconstructed.typ"),
                atomically: true,
                encoding: .utf8,
            )
            imports.append(.init(
                id: page.id, file: page.file, expectedText: page.expectedText,
                extractedText: result.extractedText, seconds: Date().timeIntervalSince(start),
                mode: String(describing: result.extractionMode),
                headingCount: result.source.components(separatedBy: "#heading(").count - 1,
                tableCount: result.source.components(separatedBy: "#table(").count - 1,
                listCount: result.source.components(separatedBy: "#list(").count - 1,
            ))
            print("EVALUATION page \(page.id): \(result.extractionMode)")
        }
        try write(imports, to: root.appendingPathComponent("page-results.json"))
    }

    private func write(_ value: some Encodable, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

private struct EvaluationRequest: Codable {
    let id: String
    let category: String
    let language: String
    let request: String
    let expected: EvaluationExpectation
}

private struct EvaluationExpectation: Codable {
    let disposition: String
    let commandID: String?
    let values: [String: String]?

    func matches(_ actual: TypesettingSuggestion?, error: String?, isValidationError: Bool) -> Bool {
        if disposition == "reject" {
            return actual == nil && (error == nil || isValidationError)
        }
        if disposition == "none" {
            return actual == nil && error == nil
        }
        guard error == nil, let actual, actual.commandID == commandID, let command = actual.command else {
            return false
        }
        let defaults = Dictionary(uniqueKeysWithValues: command.fields.map { ($0.id, $0.initial) })
        let expectedValues = defaults.merging(values ?? [:]) { _, supplied in supplied }
        let actualValues = defaults.merging(actual.values) { _, supplied in supplied }
        return actualValues == expectedValues
    }
}

private struct EvaluationResponse: Codable {
    let id: String
    let category: String
    let language: String
    let request: String
    let expected: EvaluationExpectation
    let route: String
    let ruleSuggestion: TypesettingSuggestion?
    let ruleError: String?
    let suggestion: TypesettingSuggestion?
    let error: String?
    let seconds: Double
    let correct: Bool
}

private struct EvaluationPage: Codable {
    let id: String
    let file: String
    let expectedText: String
}

private struct EvaluationImport: Codable {
    let id: String
    let file: String
    let expectedText: String
    let extractedText: String
    let seconds: Double
    let mode: String
    let headingCount: Int
    let tableCount: Int
    let listCount: Int
}
