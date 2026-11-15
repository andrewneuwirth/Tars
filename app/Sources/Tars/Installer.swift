import CryptoKit
import Foundation

/// The pinned downloads in Resources/training-manifest.json.
struct Manifest: Decodable {
    struct Von: Decodable { var commit: String; var url: String; var files: [String: String] }
    struct Model: Decodable { var name: String; var repo: String; var revision: String }
    var python: String
    var von: Von
    var base: Model
    var tars: Model
    var modelFiles: [String]

    static let shared: Manifest = {
        let url = Bundled.resources?.appendingPathComponent("training-manifest.json")
        guard let url, let d = try? Data(contentsOf: url), let m = try? JSONDecoder().decode(Manifest.self, from: d) else {
            fatalError("training-manifest.json is missing from the app")
        }
        return m
    }()
}

/// What ships inside the app: the training code, the dependency lock, uv. A plain `swift build` (no bundle) uses the
/// checkout it was built in and uv from the PATH.
enum Bundled {
    static var inBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    /// Contents/Resources in the app; app/Resources in a checkout.
    static var resources: URL? {
        if inBundle { return Bundle.main.resourceURL }
        return checkout?.appendingPathComponent("app/Resources")
    }
    /// The training code: Contents/Resources/training in the app; the checkout itself otherwise.
    static var training: URL? { inBundle ? Bundle.main.resourceURL?.appendingPathComponent("training") : checkout }
    static var lock: URL? { resources?.appendingPathComponent("requirements.lock") }
    static var uv: String? {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/uv").path
        if FileManager.default.isExecutableFile(atPath: helper) { return helper }
        return ["/opt/homebrew/bin/uv", "/usr/local/bin/uv", NSHomeDirectory() + "/.local/bin/uv"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static var checkout: URL? {
        var u = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        for _ in 0..<6 {
            u.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: u.appendingPathComponent("pipeline/run.sh").path) { return u }
        }
        return nil
    }
}

/// One-time setup of everything training needs, under Application Support/Tars:
///   env/python  a pinned CPython (uv's managed builds)   env/venv  torch, transformers… from requirements.lock (hashes required)
///   von/        Von's source at a pinned commit, every Python file checked by sha256
///   models/von-1.2  the base checkpoint from Von's Hugging Face repo at a pinned revision, checked against the repo's hashes
/// Each part is skipped when already done, so Retry continues where it stopped. Afterwards training works offline.
@MainActor @Observable
final class Installer {
    enum State: Equatable { case idle, running, failed(String), done }
    var state: State = .idle
    var step = ""
    var detail = ""
    var fraction = 0.0
    private var task: Task<Void, Never>?
    private var process: Process?

    nonisolated static var ready: Bool { FileManager.default.fileExists(atPath: Files.env.appendingPathComponent("ready").path) }
    /// What the setup downloads, for the button. Measured on a clean install (see app/README.md).
    nonisolated static let downloadSize = "about 3.4 GB"

    func start() {
        guard state != .running else { return }
        state = .running
        fraction = 0
        task = Task {
            do {
                try await run()
                state = .done
                step = "Training is set up"
                detail = ""
                fraction = 1
            } catch is CancellationError {
                state = .failed("Cancelled. Retry continues where it stopped.")
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Downloads the published Tars weights (Manifest.tars) into models/tars.
    func startTars() {
        guard state != .running else { return }
        state = .running
        fraction = 0
        task = Task {
            do {
                try await downloadModel(Manifest.shared.tars, to: Files.tarsModel) { done, total in self.fraction = Double(done) / Double(max(total, 1)) }
                state = .done
            } catch is CancellationError { state = .failed("Cancelled.") } catch { state = .failed(error.localizedDescription) }
        }
    }

    func cancel() {
        task?.cancel()
        process?.terminate()
    }

    private func run() async throws {
        let m = Manifest.shared, fm = FileManager.default
        try fm.createDirectory(at: Files.env, withIntermediateDirectories: true)
        guard let uv = Bundled.uv, let lock = Bundled.lock else { throw AIFailure("uv or requirements.lock is missing from the app") }

        // 1. Python and the packages (~0.5 GB of downloads).
        let venv = Files.env.appendingPathComponent("venv")
        let env = ["UV_PYTHON_INSTALL_DIR": Files.env.appendingPathComponent("python").path, "UV_CACHE_DIR": Files.env.appendingPathComponent("cache").path,
                   "UV_PYTHON_PREFERENCE": "only-managed", "UV_NO_CONFIG": "1", "UV_LINK_MODE": "copy", "UV_PYTHON_DOWNLOADS": "automatic"]
        let depsMark = Files.env.appendingPathComponent("deps-" + (try Hash.sha256(lock)).prefix(16))
        if !fm.fileExists(atPath: depsMark.path) {
            step = "Installing Python \(m.python)"
            fraction = 0.02
            if !fm.isExecutableFile(atPath: venv.appendingPathComponent("bin/python").path) {
                try await exec(uv, ["venv", "--python", m.python, venv.path], env)
            }
            step = "Installing PyTorch and the training packages"
            fraction = 0.05
            try await exec(uv, ["pip", "install", "--python", venv.appendingPathComponent("bin/python").path, "--require-hashes", "-r", lock.path], env)
            try? fm.removeItem(at: Files.env.appendingPathComponent("cache"))   // the venv has its own copies (UV_LINK_MODE=copy)
            fm.createFile(atPath: depsMark.path, contents: nil)
        }
        fraction = 0.2
        try Task.checkCancellation()

        // 2. Von's source (model class, collator, loss, replay generator), at the pinned commit.
        let vonMark = Files.von.appendingPathComponent(".tars-\(m.von.commit.prefix(12))")
        if !fm.fileExists(atPath: vonMark.path) {
            step = "Downloading Von's source"
            let tgz = Files.env.appendingPathComponent("von.tar.gz"), tmp = Files.env.appendingPathComponent("von-tmp")
            try await Downloader.fetch(URL(string: m.von.url)!, to: tgz) { _, _ in }
            try? fm.removeItem(at: tmp)
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            try await exec("/usr/bin/tar", ["xzf", tgz.path, "-C", tmp.path, "--strip-components", "1"], [:])
            try Self.verifyVon(at: tmp, m.von.files)
            try? fm.removeItem(at: Files.von)
            try fm.moveItem(at: tmp, to: Files.von)
            try? fm.removeItem(at: tgz)
            fm.createFile(atPath: vonMark.path, contents: nil)
        }
        fraction = 0.22
        try Task.checkCancellation()

        // 3. The base checkpoint (~3.2 GB).
        try await downloadModel(m.base, to: Files.baseModel) { done, total in
            self.fraction = 0.22 + 0.78 * Double(done) / Double(max(total, 1))
        }
        fm.createFile(atPath: Files.env.appendingPathComponent("ready").path, contents: nil)
    }

    /// A model folder from Hugging Face: every file checked against the repo's own hashes (sha256 for LFS files, the git
    /// blob sha1 for small ones). Files already present and correct are kept.
    func downloadModel(_ model: Manifest.Model, to dir: URL, progress: @escaping (Int64, Int64) -> Void) async throws {
        let entries = try await HF.tree(model.repo, model.revision)
        let wanted = Manifest.shared.modelFiles.compactMap { f in entries.first { $0.path == f } }
        guard wanted.contains(where: { $0.path == "option_marker.pt" }) else { throw AIFailure("\(model.repo) has no option_marker.pt") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let total = wanted.reduce(Int64(0)) { $0 + $1.size }
        var done: Int64 = 0
        for e in wanted {
            let dest = dir.appendingPathComponent(e.path)
            let fmt = ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)
            if (try? HF.verify(dest, e)) == true { done += e.size; progress(done, total); continue }
            step = "Downloading \(model.name): \(e.path) (\(fmt))"
            let part = dir.appendingPathComponent(e.path + ".part")
            let before = done
            try await Downloader.fetch(HF.url(model.repo, model.revision, e.path), to: part) { got, _ in
                Task { @MainActor in
                    self.detail = "\(ByteCountFormatter.string(fromByteCount: before + got, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
                    progress(before + got, total)
                }
            }
            step = "Checking \(e.path)"
            guard try HF.verify(part, e) else { try? FileManager.default.removeItem(at: part); throw AIFailure("\(e.path) didn't match its checksum; Retry downloads it again") }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: part, to: dest)
            done += e.size
            progress(done, total)
        }
    }

    static func verifyVon(at dir: URL, _ files: [String: String]) throws {
        for (path, want) in files {
            guard try Hash.sha256(dir.appendingPathComponent(path)) == want else { throw AIFailure("Von's \(path) isn't the pinned version") }
        }
    }

    /// A tool with its output shown as the detail line; throws with the output's tail when it fails or is cancelled.
    private func exec(_ tool: String, _ args: [String], _ extra: [String: String]) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.merging(extra) { $1 }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        var tail = ""
        pipe.fileHandleForReading.readabilityHandler = { h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            guard !s.isEmpty else { return }
            Task { @MainActor in
                tail = String((tail + s).suffix(2000))
                if let last = s.split(whereSeparator: \.isNewline).last { self.detail = String(last.prefix(140)) }
            }
        }
        process = p
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                p.terminationHandler = { _ in c.resume() }
                do { try p.run() } catch { p.terminationHandler = nil; c.resume(throwing: error) }
            }
        } onCancel: { p.terminate() }
        pipe.fileHandleForReading.readabilityHandler = nil
        process = nil
        try Task.checkCancellation()
        guard p.terminationStatus == 0 else {
            try await Task.sleep(for: .milliseconds(100))   // let the last output land
            throw AIFailure("\((tool as NSString).lastPathComponent) failed: \(tail.suffix(400))")
        }
    }
}

/// Hugging Face's public API: a repo's files at a revision, with the hashes git and LFS keep for them.
enum HF {
    struct Entry: Decodable, Equatable {
        struct LFS: Decodable, Equatable { var oid: String; var size: Int64 }
        var type: String
        var path: String
        var size: Int64
        var oid: String
        var lfs: LFS?
    }
    static func url(_ repo: String, _ rev: String, _ path: String) -> URL { URL(string: "https://huggingface.co/\(repo)/resolve/\(rev)/\(path)")! }

    static func tree(_ repo: String, _ rev: String) async throws -> [Entry] {
        let u = URL(string: "https://huggingface.co/api/models/\(repo)/tree/\(rev)")!
        let (d, r) = try await URLSession.shared.data(from: u)
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw AIFailure("\(repo) isn't available on Hugging Face (HTTP \((r as? HTTPURLResponse)?.statusCode ?? 0))") }
        return try JSONDecoder().decode([Entry].self, from: d)
    }

    static func verify(_ file: URL, _ e: Entry) throws -> Bool {
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? -1
        if let lfs = e.lfs { return try size == lfs.size && Hash.sha256(file) == lfs.oid }
        return try size == e.size && Hash.gitBlobSHA1(file) == e.oid
    }
}

enum Hash {
    static func sha256(_ url: URL) throws -> String {
        var h = SHA256()
        try stream(url) { h.update(data: $0) }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }
    /// What `git hash-object` prints: sha1 over "blob <size>\0" and the content.
    static func gitBlobSHA1(_ url: URL) throws -> String {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        var h = Insecure.SHA1()
        h.update(data: Data("blob \(size)\0".utf8))
        try stream(url) { h.update(data: $0) }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func stream(_ url: URL, _ f: (Data) -> Void) throws {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        while let d = try h.read(upToCount: 8 << 20), !d.isEmpty { f(d) }
    }
}

/// A download to a file with progress, cancellable.
final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private let dest: URL
    private let progress: (Int64, Int64) -> Void

    private init(dest: URL, progress: @escaping (Int64, Int64) -> Void) { self.dest = dest; self.progress = progress }

    static func fetch(_ url: URL, to dest: URL, progress: @escaping (Int64, Int64) -> Void) async throws {
        let d = Downloader(dest: dest, progress: progress)
        let session = URLSession(configuration: .default, delegate: d, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                d.continuation = c
                task.resume()
            }
        } onCancel: { task.cancel() }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }
    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { continuation?.resume(throwing: AIFailure("Download failed (HTTP \(code)): \(downloadTask.originalRequest?.url?.absoluteString ?? "")")); continuation = nil; return }
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.moveItem(at: location, to: dest); continuation?.resume() } catch { continuation?.resume(throwing: error) }
        continuation = nil
    }
    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
        continuation = nil
    }
}
