import Foundation
import Security

// Your own AI provider writes labels. Adapted from Dispatch (newi tools): a subscription's command line tool
// (Claude Code `claude -p`, ChatGPT through `codex exec`, `gemini -p`) or an API key (Anthropic, OpenAI, Google, or any
// OpenAI-compatible server such as Ollama or LM Studio). Keys live in the Keychain, service "app.newitools.Tars",
// account = provider; never in settings files.

enum AIProvider: String, CaseIterable, Identifiable {
    case claude, chatgpt, gemini, anthropic, openai, google, compatible
    var id: String { rawValue }
    var title: String {
        switch self {
        case .claude: "Claude subscription (Claude Code)"
        case .chatgpt: "ChatGPT subscription (Codex)"
        case .gemini: "Gemini CLI"
        case .anthropic: "Anthropic API key"
        case .openai: "OpenAI API key"
        case .google: "Google Gemini API key"
        case .compatible: "OpenAI-compatible (Ollama, LM Studio)"
        }
    }
    var short: String {
        switch self {
        case .chatgpt, .openai: "ChatGPT"
        case .claude, .anthropic: "Claude"
        case .gemini, .google: "Gemini"
        case .compatible: "Your model"
        }
    }
    var usesAPI: Bool { [.openai, .anthropic, .google, .compatible].contains(self) }
    var defaultModel: String {
        switch self {
        case .openai: "gpt-5-mini"
        case .anthropic: "claude-opus-5-5"
        case .google: "gemini-2.5-flash"
        case .compatible: "llama3.2"
        default: ""
        }
    }
}

enum ProviderStatus: Equatable {
    case ready, needsKey, needsURL, notInstalled
    var title: String {
        switch self { case .ready: "Ready"; case .needsKey: "Needs key"; case .needsURL: "Needs URL"; case .notInstalled: "Not installed" }
    }
}

extension AIProvider {
    /// Pure: subscriptions need their tool, API providers a saved key, a compatible endpoint an http(s) URL (key optional).
    func status(hasKey: Bool, installed: Bool, baseURL: String) -> ProviderStatus {
        switch self {
        case .chatgpt, .claude, .gemini: return installed ? .ready : .notInstalled
        case .openai, .anthropic, .google: return hasKey ? .ready : .needsKey
        case .compatible:
            let u = URL(string: baseURL.trimmingCharacters(in: .whitespaces))
            return ["http", "https"].contains(u?.scheme?.lowercased() ?? "") && u?.host?.isEmpty == false ? .ready : .needsURL
        }
    }
    var status: ProviderStatus {
        status(hasKey: Keychain.get(rawValue) != nil, installed: AI.tool(self) != nil, baseURL: AISettings.baseURL)
    }
}

enum AISettings {
    static var provider: AIProvider {
        get { AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "") ?? .claude }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "aiProvider") }
    }
    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: "aiBaseURL") ?? "http://localhost:11434/v1" }
        set { UserDefaults.standard.set(newValue, forKey: "aiBaseURL") }
    }
    static func model(_ p: AIProvider) -> String {
        let m = (UserDefaults.standard.dictionary(forKey: "aiModels") as? [String: String])?[p.rawValue] ?? ""
        return m.isEmpty ? p.defaultModel : m
    }
    static func setModel(_ m: String, for p: AIProvider) {
        var d = UserDefaults.standard.dictionary(forKey: "aiModels") as? [String: String] ?? [:]
        d[p.rawValue] = m
        UserDefaults.standard.set(d, forKey: "aiModels")
    }
}

enum Keychain {
    static let service = "app.newitools.Tars"
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func set(_ value: String, for account: String) {
        SecItemDelete(query(account) as CFDictionary)
        var add = query(account)
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
    static func get(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(_ account: String) { SecItemDelete(query(account) as CFDictionary) }
}

struct AIFailure: LocalizedError {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}

enum AI {
    private static func find(_ name: String) -> String? {
        [NSHomeDirectory() + "/.local/bin/\(name)", "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func tool(_ p: AIProvider) -> String? {
        switch p { case .chatgpt: find("codex"); case .claude: find("claude"); case .gemini: find("gemini"); default: nil }
    }

    /// The provider's answer, or an error saying exactly what went wrong.
    static func ask(_ p: AIProvider, _ prompt: String) async throws -> String {
        switch p {
        case .chatgpt:
            guard let codex = tool(.chatgpt) else { throw AIFailure("Codex isn't installed (brew install codex, then codex login)") }
            // The prompt goes on stdin ("-"), never argv: anything on the Mac can read argv with ps.
            return try await exec(codex, input: prompt) { ["exec", "--skip-git-repo-check", "--ephemeral", "-s", "read-only", "-c", "notify=[]", "-o", $0.path, "-"] }
        case .claude:
            guard let claude = tool(.claude) else { throw AIFailure("Claude Code isn't installed (claude.com/code), or run claude once to sign in") }
            // Text in, text out: no tools, no MCP servers, nothing saved to the session list.
            return try await exec(claude, input: prompt) { _ in ["-p", "--tools", "", "--strict-mcp-config", "--no-session-persistence"] }
        case .gemini:
            guard let gemini = tool(.gemini) else { throw AIFailure("Gemini CLI isn't installed (brew install gemini-cli)") }
            return try await exec(gemini, input: prompt) { _ in ["-p", "Answer the request given on stdin."] }
        case .openai, .anthropic, .google, .compatible:
            let key = Keychain.get(p.rawValue)
            guard p == .compatible || !(key ?? "").isEmpty else { throw AIFailure("Add your \(p.short) API key first") }
            guard let r = request(p, prompt: prompt, key: key, model: AISettings.model(p), base: AISettings.baseURL) else {
                throw AIFailure("That base URL isn't valid")
            }
            let (data, resp): (Data, URLResponse)
            do { (data, resp) = try await URLSession.shared.data(for: r) } catch { throw AIFailure(error.localizedDescription) }
            let (text, err) = reply(p, data)
            if let text, (resp as? HTTPURLResponse)?.statusCode == 200 { return text }
            throw AIFailure(err ?? "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
        }
    }

    /// The API request for one prompt. The key goes in a header only.
    static func request(_ p: AIProvider, prompt: String, key: String?, model: String, base: String) -> URLRequest? {
        let body: [String: Any]
        let url: URL?
        var headers = ["Content-Type": "application/json"]
        switch p {
        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/messages")
            headers["x-api-key"] = key
            headers["anthropic-version"] = "2023-06-01"
            body = ["model": model, "max_tokens": 16_000, "messages": [["role": "user", "content": prompt]]]
        case .google:
            url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")
            headers["x-goog-api-key"] = key
            body = ["contents": [["parts": [["text": prompt]]]]]
        case .openai, .compatible:
            let root = p == .openai ? "https://api.openai.com/v1" : base.trimmingCharacters(in: CharacterSet.whitespaces.union(["/"]))
            url = URL(string: root + "/chat/completions")
            if let key, !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }
            body = ["model": model, "messages": [["role": "user", "content": prompt]]]
        default: return nil
        }
        guard let url, url.scheme?.hasPrefix("http") == true else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 300)
        r.httpMethod = "POST"
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return r
    }

    /// The answer's text, or the provider's own error message.
    static func reply(_ p: AIProvider, _ data: Data) -> (text: String?, error: String?) {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let e = j["error"] { return (nil, (e as? [String: Any])?["message"] as? String ?? e as? String ?? "\(e)") }
        func texts(_ parts: Any?) -> String? {
            let t = (parts as? [[String: Any]] ?? []).filter { ($0["type"] as? String ?? "text") == "text" }.compactMap { $0["text"] as? String }.joined()
            return t.isEmpty ? nil : t
        }
        switch p {
        case .anthropic:
            if j["stop_reason"] as? String == "refusal" { return (nil, "Claude declined this request") }
            return (texts(j["content"]), "No text in Claude's answer")
        case .google:
            let content = ((j["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"]
            return (texts(content), "No text in Gemini's answer")
        default:
            let msg = (j["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
            return (msg?["content"] as? String, "No text in the answer")
        }
    }

    /// A command line tool in a scratch folder, nothing saved; its answer is the file it wrote (Codex's -o) or its output.
    /// Output goes to files, not pipes, so a long answer can't fill a pipe and hang it.
    static func exec(_ tool: String, input: String, timeout: Double = 300, _ args: @escaping @Sendable (URL) -> [String]) async throws -> String {
        try await Task.detached {
            let fm = FileManager.default
            let dir = fm.temporaryDirectory.appendingPathComponent("tars-ai-\(UUID().uuidString)")
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: dir) }
            let answer = dir.appendingPathComponent("answer.txt"), out = dir.appendingPathComponent("out.txt"), err = dir.appendingPathComponent("err.txt")
            fm.createFile(atPath: out.path, contents: nil)
            fm.createFile(atPath: err.path, contents: nil)
            let prompt = dir.appendingPathComponent("prompt.txt")
            fm.createFile(atPath: prompt.path, contents: Data(input.utf8), attributes: [.posixPermissions: 0o600])
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.currentDirectoryURL = dir
            p.arguments = args(answer)
            p.standardInput = (try? FileHandle(forReadingFrom: prompt)) ?? FileHandle.nullDevice
            p.standardOutput = try? FileHandle(forWritingTo: out)
            p.standardError = try? FileHandle(forWritingTo: err)
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            p.environment = env
            do { try p.run() } catch { throw AIFailure("Couldn't start \(tool): \(error.localizedDescription)") }
            let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            p.waitUntilExit()
            killer.cancel()
            let timedOut = p.terminationReason == .uncaughtSignal && p.terminationStatus == SIGTERM
            func read(_ u: URL) -> String { ((try? String(contentsOf: u, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            let text = read(answer).isEmpty ? read(out) : read(answer)
            if p.terminationStatus == 0, !text.isEmpty { return text }
            if timedOut { throw AIFailure("No answer within \(Int(timeout / 60)) minutes") }
            let why = read(err).isEmpty ? text : read(err)
            throw AIFailure(why.isEmpty ? "\((tool as NSString).lastPathComponent) exited with status \(p.terminationStatus)" : String(why.suffix(400)))
        }.value
    }
}
