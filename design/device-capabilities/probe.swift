import Foundation
import FoundationModels

struct CapabilityCase: Decodable {
    struct Field: Decodable {
        let name: String
        let kind: String
        let description: String
        let choices: [String]?
    }

    let id: String
    let category: String
    let language: String
    let instructions: String
    let input: String
    let fields: [Field]
    let useCase: String?
    let image: String?
}

struct CapabilityObservation: Encodable {
    let id: String
    let category: String
    let language: String
    let responseJSON: String?
    let error: String?
    let seconds: Double
    let promptTokens: Int?
    let instructionTokens: Int?
    let schemaTokens: Int?
    let toolCalls: [RecordedToolCall]
}

struct RecordedToolCall: Codable, Sendable {
    let name: String
    let argument: String
}

actor ToolRecorder {
    private var entries: [RecordedToolCall] = []

    func record(_ name: String, _ argument: String) {
        entries.append(.init(name: name, argument: argument))
    }

    func calls() -> [RecordedToolCall] {
        entries
    }
}

@available(macOS 26, *)
struct FindDocumentTool: Tool {
    let name = "findDocument"
    let description = "Search the synthetic document archive by topic. Return a document ID or unknown. Read-only."
    let recorder: ToolRecorder

    @Generable struct Arguments {
        @Guide(description: "The topic to search, such as carbon, Rust, or typography.")
        var query: String
    }

    func call(arguments: Arguments) async -> String {
        await recorder.record(name, arguments.query)
        let text = arguments.query.lowercased()
        if text.contains("carbon") || text
            .contains("碳")
        {
            return "Document ID: doc-carbon; title: Carbon capture notes."
        }
        if text.contains("rust") {
            return "Document ID: doc-rust; title: Rust ownership notes."
        }
        if text.contains("typograph") || text
            .contains("排版")
        {
            return "Document ID: doc-type; title: Typography notes."
        }
        return "No matching document. Answer unknown."
    }
}

@available(macOS 26, *)
struct CountWordsTool: Tool {
    let name = "countWords"
    let description = "Count whitespace-separated words in the exact text supplied. Read-only."
    let recorder: ToolRecorder

    @Generable struct Arguments {
        @Guide(description: "Only the exact text whose words should be counted, without surrounding instructions.")
        var text: String
    }

    func call(arguments: Arguments) async -> String {
        await recorder.record(name, arguments.text)
        return String(arguments.text.split(whereSeparator: \.isWhitespace).count)
    }
}

@main enum DeviceCapabilityProbe {
    static func main() async throws {
        guard #available(macOS 27, *) else {
            print("This research probe records macOS 27 capabilities; it is not an app deployment requirement.")
            return
        }
        try await run()
    }

    @available(macOS 27, *)
    private static func run() async throws {
        guard CommandLine.arguments.count == 3 else {
            print("Usage: device-capability-probe cases.json output-directory")
            return
        }
        let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let cases = try JSONDecoder().decode([CapabilityCase].self, from: Data(contentsOf: inputURL))
        let general = SystemLanguageModel.default
        let tagging = SystemLanguageModel(useCase: .contentTagging)
        guard general.isAvailable else {
            throw ProbeError.modelUnavailable
        }
        let metadata: [String: Any] = [
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "contextSize": general.contextSize,
            "taggingContextSize": tagging.contextSize,
            "taggingAvailability": String(describing: tagging.availability),
            "supportedLanguages": general.supportedLanguages.map(\.minimalIdentifier).sorted(),
            "vision": general.capabilities.contains(.vision),
            "guidedGeneration": general.capabilities.contains(.guidedGeneration),
            "toolCalling": general.capabilities.contains(.toolCalling),
            "reasoning": general.capabilities.contains(.reasoning),
        ]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("metadata.json"), options: .atomic)
        var observations: [CapabilityObservation] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for (index, item) in cases.enumerated() {
            let model = item.useCase == "tagging" ? tagging : general
            let recorder = ToolRecorder()
            let tools: [any Tool] = item.category == "toolCalling"
                ? [FindDocumentTool(recorder: recorder), CountWordsTool(recorder: recorder)] : []
            let instructions = Instructions(item.instructions)
            let session = LanguageModelSession(model: model, tools: tools, instructions: instructions)
            let fields = item.fields.map { field -> DynamicGenerationSchema.Property in
                let schema: DynamicGenerationSchema = switch field.kind {
                case "enum": .init(name: field.name + "Choice", anyOf: field.choices ?? [])
                case "strings": .init(arrayOf: .init(type: String.self), maximumElements: 4)
                case "bool": .init(type: Bool.self)
                default: .init(type: String.self)
                }
                return .init(name: field.name, description: field.description, schema: schema)
            }
            let schema = try GenerationSchema(root: .init(name: "Result", properties: fields), dependencies: [])
            let imageRoot = ProcessInfo.processInfo.environment["LEFTBLANK_CAPABILITY_IMAGE_ROOT"] ?? inputURL
                .deletingLastPathComponent().path
            let prompt = if let image = item.image {
                Prompt {
                    item.input
                    Attachment(imageURL: URL(fileURLWithPath: imageRoot).appendingPathComponent(image))
                }
            } else {
                Prompt(item.input)
            }
            let start = Date()
            var responseJSON: String?
            var errorMessage: String?
            let promptTokens = try? await model.tokenCount(for: prompt)
            let instructionTokens = try? await model.tokenCount(for: instructions)
            let schemaTokens = try? await model.tokenCount(for: schema)
            do {
                let response = try await session.respond(
                    to: prompt, schema: schema,
                    options: GenerationOptions(temperature: 0, maximumResponseTokens: 512),
                )
                responseJSON = response.content.jsonString
            } catch {
                errorMessage = String(describing: error)
            }
            await observations.append(.init(
                id: item.id, category: item.category, language: item.language,
                responseJSON: responseJSON, error: errorMessage,
                seconds: Date().timeIntervalSince(start), promptTokens: promptTokens,
                instructionTokens: instructionTokens, schemaTokens: schemaTokens,
                toolCalls: recorder.calls(),
            ))
            try encoder.encode(observations).write(
                to: output.appendingPathComponent("observations.json"),
                options: .atomic,
            )
            print("CAPABILITY \(index + 1)/\(cases.count) \(item.id): \(errorMessage ?? "ok")")
            fflush(stdout)
        }
    }
}

private enum ProbeError: Error {
    case modelUnavailable
}
