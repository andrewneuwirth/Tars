import SwiftUI
import MacToolsKit

struct SettingsView: View {
    @State private var repo = Setup.repo
    @State private var python = Setup.python
    @State private var von = Setup.von
    @State private var editing: AIProvider?
    @State private var tick = 0   // re-reads statuses after a key is saved

    var body: some View {
        Page(title: "Settings", subtitle: "Where the Python pipeline lives, and the AI providers that write labels.") {
            Card(title: "Training setup") {
                PathRow(title: "Tars folder", detail: "The checkout with pipeline/run.sh", path: $repo, directory: true) { Setup.repo = $0 }
                PathRow(title: "Python", detail: "A Python 3.12+ with torch, transformers and Von installed", path: $python, directory: false) { Setup.python = $0 }
                PathRow(title: "Von folder", detail: "github.com/wfzyx/von with checkpoints/von-1.2", path: $von, directory: true) { Setup.von = $0 }
                Problems(items: Setup.problems())
                Text("Your data: \(Files.root.path)").font(.caption).foregroundStyle(Color.mtInkMuted).textSelection(.enabled)
            }
            Card(title: "AI providers") {
                ForEach(AIProvider.allCases) { p in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(p.title)
                            Spacer()
                            let st = p.status
                            Label(st.title, systemImage: st == .ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .foregroundStyle(st == .ready ? Color.mtGood : Color.mtWarn).font(.callout)
                            Button(editing == p ? "Done" : "Set Up") { editing = editing == p ? nil : p }
                        }
                        if editing == p { ProviderSetup(provider: p) { tick += 1 } }
                        Divider()
                    }
                }
                .id(tick)
            }
        }
    }
}

struct PathRow: View {
    let title: String
    let detail: String
    @Binding var path: String
    let directory: Bool
    let save: (String) -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(Color.mtInkMuted)
            }.frame(width: 260, alignment: .leading)
            TextField("", text: $path).textFieldStyle(.roundedBorder).onSubmit { save(path) }.onChange(of: path) { save(path) }
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = directory; panel.canChooseFiles = !directory; panel.showsHiddenFiles = true
                if panel.runModal() == .OK, let u = panel.url { path = u.path; save(path) }
            }
        }
    }
}

/// One provider's setup: model and key (Keychain) for API providers, install hints for the command line tools, then Test.
struct ProviderSetup: View {
    let provider: AIProvider
    let changed: () -> Void
    @State private var key = ""
    @State private var model = ""
    @State private var base = AISettings.baseURL
    @State private var testing = false
    @State private var result: (ok: Bool, text: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if provider.usesAPI {
                if provider == .compatible {
                    TextField("Base URL (Ollama: http://localhost:11434/v1)", text: $base).textFieldStyle(.roundedBorder)
                        .onChange(of: base) { AISettings.baseURL = base; changed() }
                }
                TextField("Model (\(provider.defaultModel))", text: $model).textFieldStyle(.roundedBorder)
                    .onChange(of: model) { AISettings.setModel(model, for: provider) }
                HStack {
                    SecureField(Keychain.get(provider.rawValue) == nil ? "Paste your API key" : "Replace key", text: $key).textFieldStyle(.roundedBorder)
                    Button("Save") { Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.rawValue); key = ""; changed() }
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    if Keychain.get(provider.rawValue) != nil { Button("Remove", role: .destructive) { Keychain.delete(provider.rawValue); changed() } }
                }
                Text("Kept in your Keychain, never in settings files.").font(.caption).foregroundStyle(Color.mtInkMuted)
            } else if let path = AI.tool(provider) {
                Text(provider == .claude ? "Runs on your Claude plan. Sign in once by running claude in Terminal."
                     : provider == .chatgpt ? "Runs on your ChatGPT plan. Sign in once with codex login in Terminal."
                     : "Sign in once by running gemini in Terminal.").font(.caption).foregroundStyle(Color.mtInkMuted)
                Text(path).font(.caption.monospaced()).foregroundStyle(Color.mtInkMuted)
            } else {
                Text(provider == .claude ? "Install Claude Code (claude.com/code), then run claude once to sign in."
                     : provider == .chatgpt ? "In Terminal: brew install codex, then codex login."
                     : "In Terminal: brew install gemini-cli, then run gemini once to sign in.").font(.caption).foregroundStyle(Color.mtInkMuted)
            }
            HStack {
                Button(testing ? "Testing…" : "Test") { test() }.disabled(testing)
                if let result { Text(result.text).font(.caption).foregroundStyle(result.ok ? Color.mtGood : Color.mtBad).lineLimit(3).textSelection(.enabled) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: MT.Radius.row).fill(Color.mtFillInset))
        .onAppear { model = (UserDefaults.standard.dictionary(forKey: "aiModels") as? [String: String])?[provider.rawValue] ?? "" }
    }

    private func test() {
        testing = true
        result = nil
        let p = provider
        Task {
            do { result = (true, "Reply: " + (try await AI.ask(p, "Reply with just the word OK.")).prefix(200)) }
            catch { result = (false, error.localizedDescription) }
            testing = false
        }
    }
}

// MARK: Onboarding

struct OnboardingView: View {
    @Bindable var app: AppModel
    let finish: () -> Void
    @State private var page = 0

    init(app: AppModel, step: Int = 0, finish: @escaping () -> Void) {
        self.app = app; self.finish = finish
        _page = State(initialValue: step)
    }

    private struct Info { let symbol: String; let title: String; let text: String }
    private let pages = [
        Info(symbol: "point.3.filled.connected.trianglepath.dotted", title: "Train your own decision maker",
             text: "Tars is a small model that runs on your Mac and decides what to do with a command: where one request ends and the next begins, which part of your assistant handles it, and which skill to run. You teach it your own tools."),
        Info(symbol: "square.grid.2x2", title: "1. Describe your tools",
             text: "List the families (music, calendar, windows…) and the skills inside each, with a few examples of how people ask for them."),
        Info(symbol: "sparkles", title: "2. Make labels",
             text: "Labels are example commands with the right answer. Your own AI provider writes them (a Claude, ChatGPT or Gemini subscription, an API key, or a local model), or any agent connected over MCP. You review them before training."),
        Info(symbol: "chart.xyaxis.line", title: "3. Train and compare",
             text: "Tars fine-tunes the base model on your labels with your Mac's GPU, then scores it against the base model on sentences it never saw. Export it when it's better."),
    ]

    var body: some View {
        let p = pages[page]
        VStack(spacing: MT.Space.s18) {
            Image(systemName: p.symbol).font(.system(size: 44, weight: .semibold)).foregroundStyle(Color.accentColor).frame(height: 60)
            Text(p.title).font(.system(size: 22, weight: .semibold))
            Text(p.text).multilineTextAlignment(.center).foregroundStyle(Color.mtInkMuted).frame(maxWidth: 440).fixedSize(horizontal: false, vertical: true)
            if page == 1 {
                Button("Start from the Example Catalog") { app.loadExample(); page += 1 }.disabled(!app.catalog.skills.isEmpty)
            }
            Spacer(minLength: 0)
            HStack {
                HStack(spacing: 6) { ForEach(pages.indices, id: \.self) { i in Circle().fill(i == page ? Color.accentColor : Color.mtRingTrack).frame(width: 7, height: 7) } }
                Spacer()
                if page > 0 { Button("Back") { page -= 1 } }
                Button(page == pages.count - 1 ? "Get Started" : "Continue") { page == pages.count - 1 ? finish() : (page += 1) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(MT.Space.s26 + 6)
        .frame(width: 600, height: 400)
        .background(Color.mtSurface)
    }
}
