import AppKit
import SwiftUI

/// `Tars --preview <dir>`: PNGs of every screen with demo data, light and dark, for the website. The windows are laid out
/// offscreen and never ordered on screen; nothing on disk is read or written except the pictures.
@MainActor
enum Preview {
    static func run(into folder: String) {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        NSApplication.shared.setActivationPolicy(.prohibited)
        let app = AppModel(demo: true)
        let size = NSSize(width: 1200, height: 820)
        var shots: [(String, AnyView, NSSize)] = Section.allCases.enumerated().map { i, s in
            ("\(i + 1)-\(s.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))", AnyView(RootView(app: app, section: s, showOnboarding: false, plainSidebar: true)), size)
        }
        for step in 0..<4 { shots.append(("0-onboarding-\(step + 1)", AnyView(OnboardingView(app: app, step: step) {}), NSSize(width: 600, height: 400))) }
        var written = 0
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for (name, view, size) in shots {
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                let host = NSHostingView(rootView: view.environment(\.colorScheme, appearance == .darkAqua ? .dark : .light))
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))   // let the split view, tables and charts settle
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                let file = URL(fileURLWithPath: folder).appendingPathComponent(name + (appearance == .darkAqua ? "-dark" : "") + ".png")
                if (try? rep.representation(using: .png, properties: [:])?.write(to: file)) != nil { written += 1 }
            }
        }
        print("wrote \(written) pictures to \(folder)")
    }
}
