import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CaltoKit

struct ExtractionRequestBuilderTests {
    private let prompt = ExtractionPrompt(system: "RULES", user: "Dinner tomorrow at 19:00")
    private let image = ImageAttachment(data: Data([1, 2, 3]), contentType: .png, pixelWidth: 1, pixelHeight: 1)

    private func body(_ request: URLRequest) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: try #require(request.httpBody))
    }

    @Test("Anthropic: /v1/messages, image blocks before text, JSON schema output")
    func anthropic() throws {
        let config = ProviderConfiguration(provider: .anthropic, model: "claude-opus-5", apiKey: "sk-ant")
        let request = try ExtractionRequestBuilder.request(config, prompt: prompt, images: [image], mode: .structured)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let json = try body(request)
        #expect(json["model"] == "claude-opus-5")
        #expect(json["system"] == "RULES")
        let content = try #require(json["messages"]?[0]?["content"]?.arrayValue)
        #expect(content[0]["type"] == "image")
        #expect(content[0]["source"]?["media_type"] == "image/png")
        #expect(content[0]["source"]?["data"] == .string(Data([1, 2, 3]).base64EncodedString()))
        #expect(content[1]["text"] == "Dinner tomorrow at 19:00")
        #expect(json["output_config"]?["format"]?["type"] == "json_schema")
        #expect(json["output_config"]?["format"]?["schema"] == ExtractionSchema.jsonSchema)
    }

    @Test("Anthropic JSON-only mode has no output_config")
    func anthropicJSONOnly() throws {
        let config = ProviderConfiguration(provider: .anthropic, model: "claude-opus-5", apiKey: "sk-ant")
        let json = try body(ExtractionRequestBuilder.request(config, prompt: prompt, images: [], mode: .jsonOnly))
        #expect(json["output_config"] == nil)
    }

    @Test("OpenAI: chat completions, strict json_schema, data-URL images")
    func openAI() throws {
        let config = ProviderConfiguration(provider: .openAI, model: "gpt-x", apiKey: "sk")
        let request = try ExtractionRequestBuilder.request(config, prompt: prompt, images: [image], mode: .structured)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk")
        let json = try body(request)
        #expect(json["messages"]?[0]?["role"] == "system")
        let parts = try #require(json["messages"]?[1]?["content"]?.arrayValue)
        #expect(parts[0]["text"] == "Dinner tomorrow at 19:00")
        #expect(parts[1]["image_url"]?["url"]?.stringValue?.hasPrefix("data:image/png;base64,") == true)
        #expect(json["response_format"]?["type"] == "json_schema")
        #expect(json["response_format"]?["json_schema"]?["strict"] == true)
    }

    @Test("OpenAI-compatible without images sends plain string content and json_object in JSON-only mode")
    func compatible() throws {
        let config = ProviderConfiguration(provider: .openAICompatible, model: "qwen3:8b", apiKey: nil, baseURL: URL(string: "http://localhost:11434/v1"))
        let request = try ExtractionRequestBuilder.request(config, prompt: prompt, images: [], mode: .jsonOnly)
        #expect(request.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let json = try body(request)
        #expect(json["messages"]?[1]?["content"] == "Dinner tomorrow at 19:00")
        #expect(json["response_format"] == ["type": "json_object"])
    }

    @Test("Gemini: generateContent URL, key header, inlineData, responseJsonSchema")
    func gemini() throws {
        let config = ProviderConfiguration(provider: .gemini, model: "gemini-flash-lite-latest", apiKey: "AIza")
        let request = try ExtractionRequestBuilder.request(config, prompt: prompt, images: [image], mode: .structured)
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "AIza")
        let json = try body(request)
        #expect(json["systemInstruction"]?["parts"]?[0]?["text"] == "RULES")
        let parts = try #require(json["contents"]?[0]?["parts"]?.arrayValue)
        #expect(parts[0]["text"] == "Dinner tomorrow at 19:00")
        #expect(parts[1]["inlineData"]?["mimeType"] == "image/png")
        #expect(json["generationConfig"]?["responseMimeType"] == "application/json")
        #expect(json["generationConfig"]?["responseJsonSchema"] == ExtractionSchema.jsonSchema)
    }

    @Test("Gemini tolerates a models/ prefix in the model name")
    func geminiPrefix() throws {
        let config = ProviderConfiguration(provider: .gemini, model: "models/gemini-x", apiKey: "AIza")
        let request = try ExtractionRequestBuilder.request(config, prompt: prompt, images: [], mode: .jsonOnly)
        #expect(request.url?.absoluteString.hasSuffix("/models/gemini-x:generateContent") == true)
        #expect(try body(request)["generationConfig"]?["responseJsonSchema"] == nil)
    }

    @Test("Missing key or model are reported before any request")
    func preconditions() {
        #expect(throws: ProviderError.missingAPIKey) {
            try ExtractionRequestBuilder.request(ProviderConfiguration(provider: .gemini, model: "g", apiKey: ""), prompt: prompt, images: [], mode: .structured)
        }
        #expect(throws: ProviderError.badRequest(nil)) {
            try ExtractionRequestBuilder.request(ProviderConfiguration(provider: .openAI, model: " ", apiKey: "sk"), prompt: prompt, images: [], mode: .structured)
        }
    }
}

struct ExtractionResponseParserTests {
    private func data(_ string: String) -> Data { Data(string.utf8) }

    @Test("Anthropic text block")
    func anthropic() throws {
        let body = data(#"{"content":[{"type":"text","text":"{\"events\":[]}"}],"stop_reason":"end_turn"}"#)
        #expect(try ExtractionResponseParser.outputText(from: body, provider: .anthropic) == #"{"events":[]}"#)
    }

    @Test("Anthropic refusal and truncation")
    func anthropicStops() {
        #expect(throws: ProviderError.refused(nil)) {
            try ExtractionResponseParser.outputText(from: data(#"{"content":[],"stop_reason":"refusal"}"#), provider: .anthropic)
        }
        #expect(throws: ProviderError.truncated) {
            try ExtractionResponseParser.outputText(from: data(#"{"content":[{"type":"text","text":"{"}],"stop_reason":"max_tokens"}"#), provider: .anthropic)
        }
    }

    @Test("OpenAI message content, refusal and length")
    func openAI() throws {
        let ok = data(#"{"choices":[{"message":{"role":"assistant","content":"{\"events\":[]}","refusal":null},"finish_reason":"stop"}]}"#)
        #expect(try ExtractionResponseParser.outputText(from: ok, provider: .openAI) == #"{"events":[]}"#)
        #expect(throws: ProviderError.refused("I can't help")) {
            try ExtractionResponseParser.outputText(from: data(#"{"choices":[{"message":{"content":null,"refusal":"I can't help"},"finish_reason":"stop"}]}"#), provider: .openAI)
        }
        #expect(throws: ProviderError.truncated) {
            try ExtractionResponseParser.outputText(from: data(#"{"choices":[{"message":{"content":"{"},"finish_reason":"length"}]}"#), provider: .openAICompatible)
        }
    }

    @Test("Gemini parts (skipping thoughts), blocked prompts, safety stops")
    func gemini() throws {
        let ok = data(#"{"candidates":[{"content":{"parts":[{"text":"thinking…","thought":true},{"text":"{\"events\":"},{"text":"[]}"}]},"finishReason":"STOP"}]}"#)
        #expect(try ExtractionResponseParser.outputText(from: ok, provider: .gemini) == #"{"events":[]}"#)
        #expect(throws: ProviderError.refused("SAFETY")) {
            try ExtractionResponseParser.outputText(from: data(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#), provider: .gemini)
        }
        #expect(throws: ProviderError.truncated) {
            try ExtractionResponseParser.outputText(from: data(#"{"candidates":[{"content":{"parts":[{"text":"{"}]},"finishReason":"MAX_TOKENS"}]}"#), provider: .gemini)
        }
    }

    @Test("Events from clean JSON, code fences, prose around JSON and bare arrays")
    func tolerantDecoding() throws {
        let event = #"{"title":"Кино","start":"2026-09-26T19:30","end":null,"all_day":false,"time_zone":null,"location":"Октябрь","url":null,"notes":null,"reminder_minutes_before":null,"recurrence":null,"ambiguities":[]}"#
        let variants = [
            #"{"events":[\#(event)]}"#,
            "```json\n{\"events\":[\(event)]}\n```",
            "Here you go:\n{\"events\":[\(event)]}\nHope this helps!",
            "[\(event)]",
        ]
        for variant in variants {
            let events = try ExtractionResponseParser.events(fromOutput: variant)
            #expect(events.count == 1)
            #expect(events.first?.title == "Кино")
            #expect(events.first?.location == "Октябрь")
        }
    }

    @Test("Minimal events from JSON-only mode decode with defaults")
    func lenient() throws {
        let events = try ExtractionResponseParser.events(fromOutput: #"{"events":[{"title":"Dentist","start":"2026-10-02T09:00"}]}"#)
        #expect(events == [WireEvent(title: "Dentist", start: "2026-10-02T09:00")])
    }

    @Test("Not JSON at all is malformed output")
    func malformed() {
        #expect(throws: ProviderError.malformedOutput) {
            try ExtractionResponseParser.events(fromOutput: "Sorry, I couldn't find any events.")
        }
    }

    @Test("A 400 about images becomes imagesNotSupported only when images were sent")
    func imageErrors() {
        let body = data(#"{"error":{"message":"This model does not support image input."}}"#)
        #expect(throws: ProviderError.imagesNotSupported) {
            try ExtractionResponseParser.validate(status: 400, body: body, provider: .openAICompatible, sentImages: true)
        }
        #expect(throws: ProviderError.badRequest("This model does not support image input.")) {
            try ExtractionResponseParser.validate(status: 400, body: body, provider: .openAICompatible, sentImages: false)
        }
    }

    @Test("Schema rejections are recognized for the JSON-only retry")
    func schemaRejection() {
        #expect(ExtractionResponseParser.isSchemaRejection(.badRequest("Invalid schema for response_format 'calendar_events'")))
        #expect(ExtractionResponseParser.isSchemaRejection(.badRequest("Unknown name \"responseJsonSchema\" at 'generation_config'")))
        #expect(!ExtractionResponseParser.isSchemaRejection(.badRequest("model not found")))
        #expect(!ExtractionResponseParser.isSchemaRejection(.rateLimited))
    }
}

struct PromptBuilderTests {
    private let request = try! ExtractionRequest(
        content: InputContent(text: "Добавь на завтра в 13 встречку, напомни за 15 и за 30 минут"),
        customInstructions: "Рабочие встречи — в календарь «Работа».",
        referenceDate: Date(timeIntervalSince1970: 1_790_335_800), // 2026-09-25 14:30 UTC+3
        timeZone: TimeZone(identifier: "Europe/Moscow")!,
        locale: Locale(identifier: "ru_RU")
    )

    @Test("The context line carries date, weekday, zone, offset and locale")
    func context() {
        let context = PromptBuilder.context(for: request)
        #expect(context.contains("2026-09-25 14:30, Friday"))
        #expect(context.contains("Europe/Moscow (UTC+03:00)"))
        #expect(context.contains("ru_RU"))
        #expect(context.contains(#"language "ru""#))
    }

    @Test("User message holds custom instructions, the input (with its instructions) and OCR text")
    func sections() {
        let prompt = PromptBuilder.build(for: request, recognizedText: ["Концерт 12 октября 20:00", " "], imageCount: 0)
        #expect(prompt.user.contains("Рабочие встречи — в календарь «Работа»."))
        #expect(prompt.user.contains("User's input:\n\"\"\"\nДобавь на завтра в 13 встречку, напомни за 15 и за 30 минут\n\"\"\""))
        #expect(prompt.user.contains("Text recognized on image 1:"))
        #expect(prompt.user.contains("(no text found)"))
        #expect(!prompt.system.contains("JSON Schema"))
    }

    @Test("Rules explain instructions inside the input and several reminders")
    func rules() {
        let prompt = PromptBuilder.build(for: request)
        #expect(prompt.system.contains("mix event details with instructions"))
        #expect(prompt.system.contains("[15, 30]"))
        #expect(prompt.system.contains("default reminder"))
    }

    @Test("JSON-only mode spells out the schema in the system prompt")
    func schemaInPrompt() {
        let prompt = PromptBuilder.build(for: request, imageCount: 2, includeSchema: true)
        #expect(prompt.system.contains(ExtractionSchema.jsonSchema.jsonString))
        #expect(prompt.user.contains("2 images are attached."))
    }
}

struct ExtractionSchemaTests {
    @Test("Strict schema: every property of an event is required and nothing else is allowed")
    func strict() throws {
        let event = try #require(ExtractionSchema.jsonSchema["properties"]?["events"]?["items"])
        #expect(event["additionalProperties"] == false)
        let required = Set((event["required"]?.arrayValue ?? []).compactMap(\.stringValue))
        guard case .object(let properties)? = event["properties"] else {
            Issue.record("event properties missing")
            return
        }
        #expect(required == Set(properties.keys))
        #expect(required.contains("reminder_minutes_before"))
    }

    @Test("A WireEvent round-trips through the snake_case JSON the schema describes")
    func roundTrip() throws {
        let event = WireEvent(title: "T", start: "2026-01-01", allDay: true, reminderMinutesBefore: [30], recurrence: WireRecurrence(frequency: "yearly"))
        let data = try JSONEncoder().encode(ExtractionResponse(events: [event]))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(json["events"]?[0]?["all_day"] == true)
        #expect(json["events"]?[0]?["reminder_minutes_before"] == [30])
        #expect(try JSONDecoder().decode(ExtractionResponse.self, from: data).events == [event])
    }
}

struct MockExtractorTests {
    @Test("Mock answers are valid, resolvable JSON: one event per line on consecutive days")
    func mock() throws {
        let zone = TimeZone(identifier: "Europe/Moscow")!
        let request = try ExtractionRequest(
            content: InputContent(text: "Standup\n\nReview"),
            referenceDate: Date(timeIntervalSince1970: 1_790_335_800),
            timeZone: zone
        )
        let events = try ExtractionResponseParser.events(fromOutput: MockExtractor.output(for: request))
        #expect(events.map(\.title) == ["Standup", "Review"])
        #expect(events.map(\.start) == ["2026-09-26T10:00", "2026-09-27T10:00"])
        let drafts = EventResolver.resolve(events, context: ResolutionContext(timeZone: zone, referenceDate: request.referenceDate))
        #expect(drafts.allSatisfy { $0.issues.isEmpty })
    }
}
