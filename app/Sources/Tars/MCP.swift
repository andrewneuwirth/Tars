import Foundation

/// `Tars --mcp`: an MCP server on stdin/stdout (JSON-RPC 2.0, one message per line; logs go to stderr only) so Claude Code,
/// Codex or any MCP client can write labels for your catalog. It reads and appends the same files the app uses.
///   claude mcp add tars -- /Applications/Tars.app/Contents/MacOS/Tars --mcp
enum MCP {
    static let versions = ["2025-06-18", "2024-11-05"]

    static func serve() {
        log("tars mcp: catalog \(Files.catalog.path)")
        while let line = readLine() {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let reply: [String: Any]?
            if let req = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] { reply = handle(req) }
            else { reply = error(NSNull(), -32700, "Parse error") }
            if let reply, let data = try? JSONSerialization.data(withJSONObject: reply) { FileHandle.standardOutput.write(data + Data("\n".utf8)) }
        }
        exit(0)
    }

    static func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

    private static func error(_ id: Any, _ code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    /// One message in, its answer out (nil for notifications). `catalogURL`/`labelsURL` let the self-check use temp files.
    static func handle(_ req: [String: Any], catalogURL: URL = Files.catalog, labelsURL: URL = Files.labels, progressURL: URL = Files.progress) -> [String: Any]? {
        let id = req["id"]
        guard let method = req["method"] as? String else { return id.map { error($0, -32600, "Invalid request") } }
        let params = req["params"] as? [String: Any] ?? [:]
        let result: [String: Any]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            result = ["protocolVersion": versions.contains(asked) ? asked : versions[0],
                      "capabilities": ["tools": [String: Any]()],
                      "serverInfo": ["name": "tars", "version": "0.1"],
                      "instructions": "Write training labels for the user's Tars model. Call get_label_schema first, then submit_labels in batches of 20 to 50; get_progress shows which skills still need labels."]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": tools]
        case "tools/call":
            guard let name = params["name"] as? String, tools.contains(where: { $0["name"] as? String == name }) else {
                return id.map { error($0, -32602, "Unknown tool") }
            }
            let (text, failed) = call(name, params["arguments"] as? [String: Any] ?? [:], catalogURL, labelsURL, progressURL)
            result = ["content": [["type": "text", "text": text]], "isError": failed]
        default:
            return id.map { error($0, -32601, "Method not found: \(method)") }
        }
        return id.map { ["jsonrpc": "2.0", "id": $0, "result": result] }
    }

    private static func tool(_ name: String, _ title: String, _ description: String, _ props: [String: Any] = [:], required: [String] = [], readOnly: Bool = true) -> [String: Any] {
        ["name": name, "title": title, "description": description, "inputSchema": ["type": "object", "properties": props, "required": required],
         "annotations": ["title": title, "readOnlyHint": readOnly, "destructiveHint": false, "idempotentHint": readOnly, "openWorldHint": false]]
    }

    static var tools: [[String: Any]] {
        let step: [String: Any] = ["type": "object", "properties": ["text": ["type": "string", "description": "Exact substring of said"],
                                                                    "skill": ["type": "string", "description": "A skill key from get_catalog, or none"]],
                                   "required": ["text", "skill"]]
        let label: [String: Any] = ["type": "object", "properties": [
            "said": ["type": "string"], "steps": ["type": "array", "items": step, "minItems": 1],
            "set": ["type": "string", "enum": ["train", "test", "real"], "description": "Optional. About 10% go to test automatically."]],
                                    "required": ["said", "steps"]]
        return [
            tool("get_catalog", "Get catalog", "The user's assistant: families, skills (key, family, name, examples) and context."),
            tool("get_label_schema", "Get label schema", "How to write labels: the format, the rules a label must pass, and what makes good training data."),
            tool("submit_labels", "Submit labels", "Adds labeled sentences. Each is checked (known skills, step texts found in order in said, not a duplicate); the answer lists what was rejected and why.",
                 ["labels": ["type": "array", "items": label]], required: ["labels"], readOnly: false),
            tool("get_progress", "Get progress", "How many labels there are, the target, labels per skill (thinnest first), and the training stage."),
        ]
    }

    private static func call(_ name: String, _ args: [String: Any], _ catalogURL: URL, _ labelsURL: URL, _ progressURL: URL) -> (String, Bool) {
        guard let catalog = Files.loadCatalog(catalogURL) else { return ("No catalog yet. Open the Tars app and add your skills first.", true) }
        switch name {
        case "get_catalog":
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return ((try? e.encode(catalog)).map { String(decoding: $0, as: UTF8.self) } ?? "{}", false)
        case "get_label_schema":
            return (LabelPrompt.schema(catalog), false)
        case "submit_labels":
            guard let raw = args["labels"] as? [[String: Any]] else { return ("labels must be an array of objects", true) }
            let intake = Intake.check(raw, catalog: catalog, existing: Files.loadLabels(labelsURL), source: "mcp")
            Files.append(intake.accepted, to: labelsURL)
            var text = "Accepted \(intake.accepted.count) of \(raw.count)."
            if !intake.rejected.isEmpty { text += "\nRejected:\n" + intake.rejected.prefix(30).joined(separator: "\n") }
            return (text, intake.accepted.isEmpty && !raw.isEmpty)
        case "get_progress":
            let labels = Files.loadLabels(labelsURL)
            let counts = labels.reduce(into: [String: Int]()) { d, l in for s in l.steps { d[s.skill, default: 0] += 1 } }
            let perSkill = catalog.skills.map { ($0.key, counts[$0.key] ?? 0) }.sorted { $0.1 < $1.1 }
            let stage = Progress.decode(Progress.self, from: progressURL)?.stage ?? "idle"
            let body: [String: Any] = ["labels": labels.count, "target": Setup.target, "test_labels": labels.filter { $0.set == "test" }.count,
                                       "none_steps": counts["none"] ?? 0, "per_skill": perSkill.map { ["skill": $0.0, "labels": $0.1] }, "training_stage": stage]
            return ((try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}", false)
        default:
            return ("Unknown tool", true)
        }
    }
}
