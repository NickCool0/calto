import Foundation
import Testing
@testable import CaltoKit

struct ModelCatalogRequestTests {
    @Test("Anthropic: /v1/models with x-api-key and anthropic-version")
    func anthropic() throws {
        let request = try ModelCatalog.request(for: .anthropic, apiKey: " sk-ant-test \n")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/models?limit=1000")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("OpenAI: bearer token")
    func openAI() throws {
        let request = try ModelCatalog.request(for: .openAI, apiKey: "sk-test")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    }

    @Test("Gemini: key in x-goog-api-key, never in the URL")
    func gemini() throws {
        let request = try ModelCatalog.request(for: .gemini, apiKey: "AIza-test")
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "AIza-test")
        #expect(request.url?.query()?.contains("AIza") == false)
    }

    @Test("OpenAI-compatible: custom base URL, key optional", arguments: [
        ("http://localhost:11434/v1", "http://localhost:11434/v1/models"),
        ("http://localhost:1234/v1/", "http://localhost:1234/v1/models"),
        ("https://openrouter.ai/api/v1", "https://openrouter.ai/api/v1/models"),
    ])
    func compatible(base: String, expected: String) throws {
        let request = try ModelCatalog.request(for: .openAICompatible, apiKey: "", baseURL: URL(string: base))
        #expect(request.url?.absoluteString == expected)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("OpenAI-compatible falls back to the Ollama default")
    func compatibleDefault() throws {
        let request = try ModelCatalog.request(for: .openAICompatible, apiKey: "key", baseURL: nil)
        #expect(request.url?.absoluteString == "http://localhost:11434/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
    }

    @Test("The base URL is ignored for providers with a fixed endpoint")
    func fixedEndpoint() throws {
        let request = try ModelCatalog.request(for: .openAI, apiKey: "sk", baseURL: URL(string: "https://evil.example/v1"))
        #expect(request.url?.host() == "api.openai.com")
    }

    @Test("Missing key for a provider that needs one", arguments: [LLMProvider.anthropic, .openAI, .gemini])
    func missingKey(provider: LLMProvider) {
        #expect(throws: ProviderError.missingAPIKey) {
            try ModelCatalog.request(for: provider, apiKey: "   ")
        }
    }

    @Test("Base URL must be http(s) with a host", arguments: ["ftp://localhost/v1", "localhost:11434", "file:///tmp"])
    func invalidBaseURL(base: String) {
        #expect(throws: ProviderError.invalidBaseURL) {
            try ModelCatalog.request(for: .openAICompatible, apiKey: nil, baseURL: URL(string: base))
        }
    }

    @Test("Apple's on-device model has no catalog")
    func apple() {
        #expect(throws: ProviderError.unsupported) {
            try ModelCatalog.request(for: .appleOnDevice, apiKey: nil)
        }
    }
}

struct ModelCatalogParsingTests {
    private func json(_ string: String) -> Data { Data(string.utf8) }

    @Test("Anthropic list keeps API order and display names")
    func anthropic() throws {
        let body = json("""
        {"data":[{"type":"model","id":"claude-opus-5","display_name":"Claude Opus 5","created_at":"2026-05-01T00:00:00Z"},
                 {"type":"model","id":"claude-haiku-4-5","display_name":"Claude Haiku 4.5"}],
         "has_more":false,"first_id":"claude-opus-5","last_id":"claude-haiku-4-5"}
        """)
        let models = try ModelCatalog.parse(body, provider: .anthropic)
        #expect(models == [
            ModelInfo(id: "claude-opus-5", displayName: "Claude Opus 5"),
            ModelInfo(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5"),
        ])
    }

    @Test("OpenAI list drops non-chat models and sorts newest first")
    func openAI() throws {
        let body = json("""
        {"object":"list","data":[
          {"id":"text-embedding-3-large","object":"model","created":1705953180,"owned_by":"system"},
          {"id":"gpt-old","object":"model","created":1600000000,"owned_by":"openai"},
          {"id":"whisper-1","object":"model","created":1677532384,"owned_by":"openai-internal"},
          {"id":"gpt-new","object":"model","created":1750000000,"owned_by":"openai"},
          {"id":"tts-1-hd","object":"model","created":1699046015,"owned_by":"system"}
        ]}
        """)
        #expect(try ModelCatalog.parse(body, provider: .openAI).map(\.id) == ["gpt-new", "gpt-old"])
    }

    @Test("Ollama's OpenAI-compatible list (no names, same created)")
    func ollama() throws {
        let body = json("""
        {"object":"list","data":[
          {"id":"qwen3:8b","object":"model","created":1758000000,"owned_by":"library"},
          {"id":"llama3.2-vision:latest","object":"model","created":1758000000,"owned_by":"library"},
          {"id":"nomic-embed-text:latest","object":"model","created":1758000000,"owned_by":"library"}
        ]}
        """)
        #expect(try ModelCatalog.parse(body, provider: .openAICompatible).map(\.id) == ["llama3.2-vision:latest", "qwen3:8b"])
    }

    @Test("OpenRouter's names become display names")
    func openRouter() throws {
        let body = json(#"{"data":[{"id":"anthropic/claude-opus-5","name":"Anthropic: Claude Opus 5","created":1750000000}]}"#)
        #expect(try ModelCatalog.parse(body, provider: .openAICompatible) == [
            ModelInfo(id: "anthropic/claude-opus-5", displayName: "Anthropic: Claude Opus 5"),
        ])
    }

    @Test("Gemini keeps generateContent models and strips the models/ prefix")
    func gemini() throws {
        let body = json("""
        {"models":[
          {"name":"models/gemini-pro-x","displayName":"Gemini Pro X","supportedGenerationMethods":["generateContent","countTokens"]},
          {"name":"models/text-embedding-004","displayName":"Text Embedding 004","supportedGenerationMethods":["embedContent"]},
          {"name":"models/gemini-flash-x","displayName":"Gemini Flash X","supportedGenerationMethods":["generateContent"]}
        ],"nextPageToken":""}
        """)
        #expect(try ModelCatalog.parse(body, provider: .gemini) == [
            ModelInfo(id: "gemini-pro-x", displayName: "Gemini Pro X"),
            ModelInfo(id: "gemini-flash-x", displayName: "Gemini Flash X"),
        ])
    }

    @Test("Garbage or HTML is an invalid response", arguments: LLMProvider.allCases.filter { $0 != .appleOnDevice })
    func invalid(provider: LLMProvider) {
        #expect(throws: ProviderError.invalidResponse) {
            try ModelCatalog.parse(Data("<html>Bad gateway</html>".utf8), provider: provider)
        }
    }
}

struct ModelCatalogErrorTests {
    @Test("HTTP statuses map to actionable errors", arguments: [
        (401, ProviderError.invalidAPIKey),
        (403, .forbidden),
        (404, .notFound),
        (429, .rateLimited),
        (500, .serverError(status: 500)),
        (529, .serverError(status: 529)),
        (418, .unexpectedStatus(418)),
    ])
    func statuses(status: Int, expected: ProviderError) {
        #expect(throws: expected) {
            try ModelCatalog.validate(status: status, body: Data(), provider: .anthropic)
        }
    }

    @Test("2xx passes")
    func success() throws {
        try ModelCatalog.validate(status: 200, body: Data(), provider: .openAI)
    }

    @Test("Gemini's 400 for a bad key is an invalid key, other 400s are not")
    func geminiBadKey() {
        let body = Data(#"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"reason":"API_KEY_INVALID"}]}}"#.utf8)
        #expect(throws: ProviderError.invalidAPIKey) {
            try ModelCatalog.validate(status: 400, body: body, provider: .gemini)
        }
        #expect(throws: ProviderError.unexpectedStatus(400)) {
            try ModelCatalog.validate(status: 400, body: Data(#"{"error":"bad"}"#.utf8), provider: .gemini)
        }
    }

    @Test("URL errors map to offline, timeout, connection and TLS problems")
    func urlErrors() {
        let url = URL(string: "http://localhost:11434/v1/models")
        #expect(ModelCatalog.error(from: URLError(.notConnectedToInternet), url: url) == .offline)
        #expect(ModelCatalog.error(from: URLError(.timedOut), url: url) == .timedOut)
        #expect(ModelCatalog.error(from: URLError(.cannotConnectToHost), url: url) == .cannotConnect(host: "localhost"))
        #expect(ModelCatalog.error(from: URLError(.appTransportSecurityRequiresSecureConnection), url: url) == .insecureConnection)
    }
}

struct LLMProviderTests {
    @Test("Keys: required for cloud providers, optional for compatible, none for Apple")
    func keys() {
        #expect(LLMProvider.allCases.filter(\.requiresAPIKey) == [.anthropic, .openAI, .gemini])
        #expect(LLMProvider.openAICompatible.acceptsAPIKey)
        #expect(!LLMProvider.appleOnDevice.acceptsAPIKey)
    }

    @Test("Every provider except Apple's has an endpoint")
    func endpoints() {
        for provider in LLMProvider.allCases {
            #expect((provider.defaultBaseURL == nil) == (provider == .appleOnDevice))
        }
    }
}

struct CustomInstructionsTests {
    @Test("Custom instructions from Settings travel with every request, trimmed")
    func included() throws {
        let request = try ExtractionRequest(
            content: InputContent(text: "Dinner Friday 19:00"),
            instruction: "",
            customInstructions: "  Work events go to the Work calendar.\n"
        )
        #expect(request.customInstructions == "Work events go to the Work calendar.")
    }

    @Test("Blank custom instructions are omitted")
    func blank() throws {
        let request = try ExtractionRequest(content: InputContent(text: "Dinner"), instruction: "", customInstructions: " \n ")
        #expect(request.customInstructions == nil)
    }
}
