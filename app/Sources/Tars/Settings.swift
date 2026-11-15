import SwiftUI
import MacToolsKit

struct SettingsView: View {
    @Bindable var app: AppModel
    @State private var useOwn = Setup.useOwn
    @State private var repo = Setup.ownRepo
    @State private var python = Setup.ownPython
    @State private var von = Setup.ownVon
    @State private var editing: AIProvider?
    @State private var tick = 0   // re-reads statuses after a key is saved

    var body: some View {
        Page(title: "Settings", subtitle: "Training setup, and the AI providers that write labels.") {
            SectionHeader(title: "Training")
            SetupCard(installer: app.installer)
            Card(title: "Start from \(Manifest.shared.tars.name)") { TarsWeightsRow(app: app) }
            SectionHeader(title: "AI providers").padding(.top, 6)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(AIProvider.allCases.enumerated()), id: \.element) { i, p in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                MenuIconView(icon: p.icon)
                                Text(p.title).font(.ui(13.5, .medium))
                                Spacer()
                                let st = p.status
                                StatusPill(ok: st == .ready, text: st.title)
                                Button(editing == p ? "Done" : "Set Up") { withAnimation(.easeOut(duration: 0.15)) { editing = editing == p ? nil : p } }
                                    .buttonStyle(DButton(kind: editing == p ? .primary : .secondary, small: true))
                            }
                            if editing == p { ProviderSetup(provider: p) { tick += 1 } }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        if i < AIProvider.allCases.count - 1 { Rectangle().fill(Look.line).frame(height: 1).padding(.leading, 18) }
                    }
                }
                .id(tick)
            }
            SectionHeader(title: "Advanced").padding(.top, 6)
            Card {
                SettingRow(title: "Use my own environment", detail: "A Tars checkout, Python and Von I manage myself.", last: !useOwn) {
                    DSwitch(label: "Use my own environment", on: $useOwn)
                        .onChange(of: useOwn) { Setup.useOwn = useOwn }
                }
                if useOwn {
                    PathRow(title: "Tars folder", detail: "The checkout with pipeline/run.sh", path: $repo, directory: true) { Setup.ownRepo = $0 }
                    PathRow(title: "Python", detail: "A Python 3.12+ with torch, transformers and Von installed", path: $python, directory: false) { Setup.ownPython = $0 }
                    PathRow(title: "Von folder", detail: "github.com/wfzyx/von with checkpoints/von-1.2", path: $von, directory: true) { Setup.ownVon = $0 }
                    Problems(items: Setup.problems())
                }
                HStack(spacing: 6) {
                    Image(systemName: "folder").font(.ui(11.5)).foregroundStyle(Look.muted)
                    Text("Your data: \((Files.root.path as NSString).abbreviatingWithTildeInPath)").font(.ui(12)).foregroundStyle(Look.muted).textSelection(.enabled)
                }
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(13, .medium))
                Text(detail).font(.ui(11.5)).foregroundStyle(Look.muted).fixedSize(horizontal: false, vertical: true)
            }.frame(width: 240, alignment: .leading)
            DField(placeholder: directory ? "Folder path" : "File path", text: $path, mono: true) { save(path) }
                .onChange(of: path) { save(path) }
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = directory; panel.canChooseFiles = !directory; panel.showsHiddenFiles = true
                if panel.runModal() == .OK, let u = panel.url { path = u.path; save(path) }
            }
            .buttonStyle(DButton(small: true))
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
                    DField(placeholder: "Base URL (Ollama: http://localhost:11434/v1)", text: $base, mono: true)
                        .onChange(of: base) { AISettings.baseURL = base; changed() }
                }
                DField(placeholder: "Model (\(provider.defaultModel))", text: $model)
                    .onChange(of: model) { AISettings.setModel(model, for: provider) }
                HStack(spacing: 8) {
                    DField(placeholder: Keychain.get(provider.rawValue) == nil ? "Paste your API key" : "Replace key", text: $key, symbol: "key", secure: true)
                    Button("Save") { Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.rawValue); key = ""; changed() }
                        .buttonStyle(DButton(kind: .primary, small: true))
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    if Keychain.get(provider.rawValue) != nil { Button("Remove", role: .destructive) { Keychain.delete(provider.rawValue); changed() }.buttonStyle(DButton(kind: .danger, small: true)) }
                }
                Text("Kept in your Keychain, never in settings files.").font(.ui(12)).foregroundStyle(Look.muted)
            } else if let path = AI.tool(provider) {
                Text(provider == .claude ? "Runs on your Claude plan. Sign in once by running claude in Terminal."
                     : provider == .chatgpt ? "Runs on your ChatGPT plan. Sign in once with codex login in Terminal."
                     : "Sign in once by running gemini in Terminal.").font(.ui(12)).foregroundStyle(Look.muted)
                Text(path).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Look.muted)
            } else {
                Text(provider == .claude ? "Install Claude Code (claude.com/code), then run claude once to sign in."
                     : provider == .chatgpt ? "In Terminal: brew install codex, then codex login."
                     : "In Terminal: brew install gemini-cli, then run gemini once to sign in.").font(.ui(12)).foregroundStyle(Look.muted)
            }
            HStack(spacing: 10) {
                Button { test() } label: { Label(testing ? "Testing…" : "Test", systemImage: "bolt") }.buttonStyle(DButton(small: true)).disabled(testing)
                if testing { Pulse() }
                if let result { Text(result.text).font(.ui(12)).foregroundStyle(result.ok ? Color.mtGood : Color.mtBad).lineLimit(3).textSelection(.enabled) }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Look.field))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Look.line))
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

/// The one-time training setup, with progress, cancel and retry.
struct SetupCard: View {
    @Bindable var installer: Installer
    var body: some View {
        Card(title: "Training setup") {
            if Installer.ready && installer.state != .running {
                HStack(spacing: 10) {
                    StatusPill(ok: true, text: "Ready")
                    Text("Training runs on this Mac and works offline.").font(.ui(13))
                }
                Text("Python \(Manifest.shared.python), PyTorch and Von 1.2 are in \((Files.root.path as NSString).abbreviatingWithTildeInPath).").font(.ui(12)).foregroundStyle(Look.muted)
            } else {
                Text("Setting up training downloads \(Installer.downloadSize) once: Python, PyTorch, Von's code and the Von 1.2 base model. After that, training works offline.")
                    .font(.ui(13)).foregroundStyle(Look.muted).fixedSize(horizontal: false, vertical: true)
                switch installer.state {
                case .running:
                    InstallProgress(step: installer.step, detail: installer.detail, fraction: installer.fraction)
                    Button("Cancel") { installer.cancel() }.buttonStyle(DButton(small: true))
                case .failed(let why):
                    Notice(text: why, symbol: "xmark.octagon.fill", tint: .mtBad)
                    Button { installer.start() } label: { Label("Retry", systemImage: "arrow.clockwise") }.buttonStyle(DButton(kind: .primary))
                default:
                    Button { installer.start() } label: { Label("Set Up Training", systemImage: "arrow.down.circle") }.buttonStyle(DButton(kind: .primary))
                }
            }
        }
    }
}

struct InstallProgress: View {
    let step: String
    let detail: String
    let fraction: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(step).font(.ui(12.5, .medium)).lineLimit(1)
                Spacer()
                Text("\(Int(fraction * 100))%").font(.ui(12)).foregroundStyle(Look.muted).monospacedDigit()
            }
            DProgress(value: fraction)
            if !detail.isEmpty { Text(detail).font(.ui(11.5)).foregroundStyle(Look.muted).lineLimit(1) }
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Look.field))
    }
}

/// Download the published Tars model to fine-tune from it instead of the plain base model.
struct TarsWeightsRow: View {
    @Bindable var app: AppModel
    @State private var startFrom = Setup.startFromTars
    var body: some View {
        let have = FileManager.default.fileExists(atPath: Files.tarsModel.appendingPathComponent("option_marker.pt").path)
        let w = app.tarsWeights
        Text("\(Manifest.shared.tars.name) already knows how to split commands and route them. Starting from it can need fewer labels than starting from Von 1.2. About 3.2 GB, from huggingface.co/\(Manifest.shared.tars.repo).")
            .font(.ui(12.5)).foregroundStyle(Look.muted).fixedSize(horizontal: false, vertical: true)
        if have {
            SettingRow(title: "Start training from \(Manifest.shared.tars.name)", last: true) {
                DSwitch(label: "Start training from \(Manifest.shared.tars.name)", on: $startFrom)
                    .onChange(of: startFrom) { Setup.startFromTars = startFrom }
            }
        } else if w.state == .running {
            InstallProgress(step: w.step, detail: w.detail, fraction: w.fraction)
            Button("Cancel") { w.cancel() }.buttonStyle(DButton(small: true))
        } else {
            if case .failed(let why) = w.state { Notice(text: why, symbol: "xmark.octagon.fill", tint: .mtBad) }
            Button { w.startTars() } label: { Label("Download \(Manifest.shared.tars.name)", systemImage: "arrow.down.circle") }.buttonStyle(DButton()).disabled(app.demo)
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
             text: "Tars fine-tunes the base model on your labels with your Mac's GPU, then scores it against the base model on sentences it never saw. Everything it needs comes with the app; the first time, it downloads Python, PyTorch and the base model once."),
    ]

    var body: some View {
        let p = pages[page]
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Group {
                    if page == 0 {
                        Image(nsImage: AppIcon.image).resizable().interpolation(.high).frame(width: 76, height: 76)
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 16).fill(Look.ink).frame(width: 60, height: 60)
                            .overlay(Image(systemName: p.symbol).font(.ui(24, .semibold)).foregroundStyle(Look.onInk))
                    }
                }
                .frame(height: 78)
                .accessibilityHidden(true)
                Text(p.title).font(.ui(22, .semibold)).multilineTextAlignment(.center)
                Text(p.text).font(.ui(13.5)).lineSpacing(2).multilineTextAlignment(.center).foregroundStyle(Look.muted)
                    .frame(maxWidth: 460).fixedSize(horizontal: false, vertical: true)
                if page == 1 {
                    Button { app.loadExample(); page += 1 } label: { Label("Start from the Example Catalog", systemImage: "square.grid.2x2") }
                        .buttonStyle(DButton()).disabled(!app.catalog.skills.isEmpty).padding(.top, 4)
                }
                if page == pages.count - 1 && !Installer.ready {
                    if app.installer.state == .running {
                        InstallProgress(step: app.installer.step, detail: "", fraction: app.installer.fraction).frame(maxWidth: 380)
                    } else {
                        VStack(spacing: 6) {
                            Button { app.installer.start() } label: { Label("Set Up Training Now (\(Installer.downloadSize))", systemImage: "arrow.down.circle") }
                                .buttonStyle(DButton())
                            Text("You can also do this later from the Train page.").font(.ui(12)).foregroundStyle(Look.muted)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 36).padding(.top, 34)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule().fill(i == page ? Look.ink : Look.track).frame(width: i == page ? 18 : 7, height: 7)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: page)
                .accessibilityElement().accessibilityLabel("Page \(page + 1) of \(pages.count)")
                Spacer()
                if page > 0 { Button("Back") { page -= 1 }.buttonStyle(DButton()) }
                Button(page == pages.count - 1 ? "Get Started" : "Continue") { page == pages.count - 1 ? finish() : (page += 1) }
                    .buttonStyle(DButton(kind: .primary)).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(Look.canvas)
            .overlay(alignment: .top) { Rectangle().fill(Look.line).frame(height: 1) }
        }
        .frame(width: 600, height: 420)
        .background(Look.panel)
        .tint(Look.ink)
    }
}
