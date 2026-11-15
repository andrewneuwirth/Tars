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
// `Tars --setup`: the one-time training setup without the window, printing progress (TARS_HOME picks another folder).
if CommandLine.arguments.contains("--setup") {
    MainActor.assumeIsolated { Headless.setup() }
    RunLoop.main.run()
}
// `Tars --quick-train <labels.jsonl>`: a few training steps on the example catalog and these labels, then the verdict.
if let i = CommandLine.arguments.firstIndex(of: "--quick-train"), i + 1 < CommandLine.arguments.count {
    let labels = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated { Headless.quickTrain(labels) }
    RunLoop.main.run()
}
TarsApp.main()

@MainActor
enum Headless {
    static func setup() {
        let inst = Installer()
        inst.start()
        var last = ""
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                let line = "\(Int(inst.fraction * 100))%  \(inst.step)  \(inst.detail)"
                if line != last { print(line); last = line; fflush(stdout) }
                switch inst.state {
                case .done: print("setup ok: \(Files.root.path)"); exit(0)
                case .failed(let why): print("setup failed: \(why)"); exit(1)
                default: break
                }
            }
        }
    }

    static func quickTrain(_ labels: String) {
        guard Setup.problems().isEmpty else { print(Setup.problems().joined(separator: "\n")); exit(1) }
        if Files.loadCatalog() == nil, let ex = Bundled.training?.appendingPathComponent("catalogs/example.json") {
            try? FileManager.default.copyItem(at: ex, to: Files.catalog)
        }
        let t = Trainer()
        t.quick = true
        t.start(labels: URL(fileURLWithPath: labels))
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard !t.running, let status = t.exitStatus else { return }
                print(t.logTail.suffix(1500))
                print("exit \(status), verdict \(t.report?.verdict ?? "none"), runs \(t.runs.count), candidate \(t.hasCandidate)")
                exit(status)
            }
        }
    }
}

struct TarsApp: App {
    @State private var app = AppModel(demo: CommandLine.arguments.contains("--demo"))

    var body: some Scene {
        Window("Tars", id: "main") {
            RootView(app: app)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 820)
    }
}
