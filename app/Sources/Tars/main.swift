import SwiftUI

if CommandLine.arguments.contains("--self-check") {
    MainActor.assumeIsolated { SelfCheck.run() }
}
// `Tars --mcp`: the MCP server for Claude Code, Codex or any MCP client, on stdin/stdout (MCP.swift).
if CommandLine.arguments.contains("--mcp") {
    MCP.serve()
}
// `Tars --preview <dir>`: screenshots with demo data, rendered offscreen (Preview.swift).
if let i = CommandLine.arguments.firstIndex(of: "--preview") {
    let folder = CommandLine.arguments.dropFirst(i + 1).first ?? FileManager.default.currentDirectoryPath
    MainActor.assumeIsolated { Preview.run(into: folder) }
    exit(0)
}
TarsApp.main()

struct TarsApp: App {
    @State private var app = AppModel(demo: CommandLine.arguments.contains("--demo"))

    var body: some Scene {
        Window("Tars", id: "main") {
            RootView(app: app)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1200, height: 820)
    }
}
