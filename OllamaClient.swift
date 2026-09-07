import Foundation

/// Minimal client for the Ollama HTTP API (native /api/chat + /api/tags).
final class OllamaClient {

    enum OllamaError: LocalizedError {
        case badURL
        case server(String)

        var errorDescription: String? {
            switch self {
            case .badURL:
                return "Invalid server URL."
            case .server(let message):
                return message
            }
        }
    }

    /// Normalizes user input like "192.168.1.192:11434" into a proper base URL.
    static func baseURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
            s = "http://" + s
        }
        if !s.hasSuffix("/") { s += "/" }
        return URL(string: s)
    }

    /// GET /api/tags -> sorted list of model names available on the server.
    func listModels(server: String) async throws -> [String] {
        guard let base = Self.baseURL(server) else { throw OllamaError.badURL }
        var request = URLRequest(url: base.appendingPathComponent("api/tags"))
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OllamaError.server("Server returned an error.")
        }

        struct Tags: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]?
        }
        let tags = try JSONDecoder().decode(Tags.self, from: data)
        return (tags.models ?? []).map { $0.name }.sorted()
    }

    /// POST /api/chat with stream:true. Yields content chunks as they arrive (NDJSON).
    func streamChat(server: String,
                    model: String,
                    messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let base = Self.baseURL(server) else {
                continuation.finish(throwing: OllamaError.badURL)
                return
            }

            var request = URLRequest(url: base.appendingPathComponent("api/chat"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 600 // long generations on local GPUs

            let body: [String: Any] = [
                "model": model,
                "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
                "stream": true
            ]
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                continuation.finish(throwing: error)
                return
            }

            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode) else {
                        throw OllamaError.server("Server returned an error. Is Ollama running and reachable at \(server)?")
                    }
                    // Ollama streams one JSON object per line (NDJSON)
                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let message = obj["message"] as? [String: Any],
                              let content = message["content"] as? String else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
