import SwiftUI
import AppKit
import MacToolsKit

// The app's look: soft neutrals, ink as the accent (black on light, white on dark), pills and rounded cards.
// Adapted from the newi tools Dispatch app; every control here replaces a stock one.

enum Look {
    static func dyn(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static let canvas = dyn(NSColor(white: 0.962, alpha: 1), NSColor(white: 0.085, alpha: 1))
    static let panel = dyn(NSColor(white: 0.995, alpha: 1), NSColor(white: 0.12, alpha: 1))
    static let card = dyn(.white, NSColor(white: 0.145, alpha: 1))
    // Increase Contrast: borders go from barely there to clearly visible.
    static let line = Color(nsColor: NSColor(name: nil) { a in
        let dark = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let strong = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return NSColor(white: dark ? 1 : 0, alpha: strong ? 0.4 : dark ? 0.08 : 0.075)
    })
    static let pill = dyn(NSColor(white: 0.945, alpha: 1), NSColor(white: 0.2, alpha: 1))
    static let field = dyn(NSColor(white: 0.955, alpha: 1), NSColor(white: 0.185, alpha: 1))
    static let ink = dyn(NSColor(white: 0.1, alpha: 1), NSColor(white: 0.95, alpha: 1))
    static let onInk = dyn(.white, NSColor(white: 0.08, alpha: 1))
    static let hover = dyn(NSColor(white: 0.968, alpha: 1), NSColor(white: 0.18, alpha: 1))
    static let chosen = dyn(NSColor(white: 0.925, alpha: 1), NSColor(white: 0.23, alpha: 1))
    static let track = dyn(NSColor(white: 0.88, alpha: 1), NSColor(white: 0.28, alpha: 1))
    static let muted = dyn(NSColor(white: 0.42, alpha: 1), NSColor(white: 0.62, alpha: 1))
    static let faint = dyn(NSColor(white: 0.6, alpha: 1), NSColor(white: 0.45, alpha: 1))
    static let focus = ink.opacity(0.55)
    static let gemini = Color(hex: 0x4285f4)
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

/// The app icon from the bundle (AppIcon.icns), for the sidebar and onboarding.
enum AppIcon {
    static let image: NSImage = Bundle.main.image(forResource: "AppIcon") ?? NSApplication.shared.applicationIconImage
}

// MARK: Containers

struct Card<Content: View>: View {
    var title: String? = nil
    var detail: String? = nil
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || detail != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let title { Text(title).font(.ui(15, .semibold)).accessibilityAddTraits(.isHeader) }
                    if let detail { Text(detail).font(.ui(12.5)).foregroundStyle(Look.muted).fixedSize(horizontal: false, vertical: true) }
                }
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Look.card))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Look.line))
        .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
    }
}

/// A small heading over a group of cards.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased()).font(.ui(11.5, .semibold)).foregroundStyle(Look.muted).kerning(0.6)
            .padding(.leading, 4).accessibilityAddTraits(.isHeader)
    }
}

/// A calm placeholder for a list or chart with nothing in it yet.
struct EmptyState: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var height: CGFloat = 160
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.ui(20, .medium)).foregroundStyle(Look.faint)
                .frame(width: 44, height: 44).background(Circle().fill(Look.pill))
            Text(title).font(.ui(13.5, .medium))
            if let detail { Text(detail).font(.ui(12.5)).foregroundStyle(Look.muted).multilineTextAlignment(.center).frame(maxWidth: 360) }
        }
        .frame(maxWidth: .infinity, minHeight: height)
    }
}

/// A row of a settings-style card: name and detail on the left, the control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    var last = false
    @ViewBuilder let control: Control
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.ui(13.5, .medium))
                    if let detail { Text(detail).font(.ui(12)).foregroundStyle(Look.muted).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 12)
                control
            }
            .padding(.vertical, 11)
            if !last { Rectangle().fill(Look.line).frame(height: 1) }
        }
    }
}

// MARK: Buttons

enum ButtonKind { case primary, secondary, danger, quiet }

/// Capsule buttons: ink for the main action, soft for the rest, red text for destructive ones.
struct DButton: ButtonStyle {
    var kind = ButtonKind.secondary
    var small = false
    func makeBody(configuration: Configuration) -> some View { Chrome(configuration: configuration, kind: kind, small: small) }

    private struct Chrome: View {
        let configuration: Configuration
        let kind: ButtonKind
        let small: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false
        var body: some View {
            configuration.label
                .font(.ui(small ? 12.5 : 13, kind == .primary ? .semibold : .medium))
                .labelStyle(TightLabel())
                .lineLimit(1)
                .foregroundStyle(fg)
                .padding(.horizontal, small ? 12 : 15).frame(minHeight: small ? 28 : 32)
                .background(Capsule().fill(bg))
                .overlay(Capsule().strokeBorder(kind == .secondary || kind == .danger ? Look.line : .clear))
                .contentShape(Capsule())
                .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
                .onHover { hover = $0 && enabled }
                .animation(.easeOut(duration: 0.12), value: hover)
        }
        private var fg: Color {
            switch kind { case .primary: Look.onInk; case .danger: Color.mtBad; default: Look.ink }
        }
        private var bg: Color {
            switch kind {
            case .primary: hover ? Look.ink.opacity(0.85) : Look.ink
            case .secondary: hover ? Look.chosen : Look.pill
            case .danger: hover ? Color.mtBad.opacity(0.14) : Color.mtBad.opacity(0.08)
            case .quiet: hover ? Look.hover : .clear
            }
        }
    }
}

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.font(.ui(12, .semibold)); configuration.title }
    }
}

/// A square icon button with a hover fill.
struct IconButton: View {
    let symbol: String
    let label: String
    var tint: Color = Look.muted
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.ui(12.5, .medium)).foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Look.chosen : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hover = $0 && enabled }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: Text input

/// A text field: soft fill, rounded, ink focus ring, placeholder in a lighter grey.
struct DField: View {
    let placeholder: String
    @Binding var text: String
    var symbol: String? = nil
    var mono = false
    var secure = false
    var width: CGFloat? = nil
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            if let symbol { Image(systemName: symbol).font(.ui(12, .medium)).foregroundStyle(Look.faint).accessibilityHidden(true) }
            ZStack(alignment: .leading) {
                if text.isEmpty { Text(placeholder).foregroundStyle(Look.faint).lineLimit(1).allowsHitTesting(false).accessibilityHidden(true) }
                Group {
                    if secure { SecureField("", text: $text) } else { TextField("", text: $text) }
                }
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(onSubmit)
                .accessibilityLabel(placeholder)
            }
            if symbol == "magnifyingglass" && !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Look.faint) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .font(mono ? .system(size: 12.5, design: .monospaced) : .ui(13))
        .padding(.horizontal, 11).frame(height: 32)
        .frame(width: width)
        .fieldChrome(focused)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

/// A multi-line field in the same style.
struct DEditor: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 80
    @FocusState private var focused: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty { Text(placeholder).foregroundStyle(Look.faint).padding(.horizontal, 5).padding(.top, 1).allowsHitTesting(false) }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .accessibilityLabel(placeholder)
        }
        .font(.ui(13)).lineSpacing(2)
        .padding(.horizontal, 7).padding(.vertical, 8)
        .frame(minHeight: minHeight)
        .fieldChrome(focused, radius: 11)
    }
}

extension View {
    func fieldChrome(_ focused: Bool, radius: CGFloat = 9) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius).fill(focused ? Look.card : Look.field))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(focused ? Look.focus : Look.line, lineWidth: focused ? 1.5 : 1))
            .background(RoundedRectangle(cornerRadius: radius + 3).stroke(Look.ink.opacity(focused ? 0.1 : 0), lineWidth: 6).padding(-1.5))
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

/// A number with − and + on either side; the middle can be typed in.
struct DStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var label = "Value"
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 0) {
            nudge("minus", -step).disabled(value <= range.lowerBound)
            TextField("", text: $text)
                .textFieldStyle(.plain).multilineTextAlignment(.center).font(.ui(13, .medium)).monospacedDigit()
                .focused($focused).frame(width: 64)
                .onSubmit(commit)
                .onChange(of: focused) { if !focused { commit() } }
                .accessibilityLabel(label)
            nudge("plus", step).disabled(value >= range.upperBound)
        }
        .frame(height: 32)
        .fieldChrome(focused)
        .onAppear { text = "\(value)" }
        .onChange(of: value) { text = "\(value)" }
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { d in value = clamp(value + (d == .increment ? step : -step)) }
    }
    private func nudge(_ symbol: String, _ by: Int) -> some View {
        Button { value = clamp(value + by) } label: {
            Image(systemName: symbol).font(.ui(11, .bold)).foregroundStyle(Look.muted).frame(width: 30, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(by > 0 ? "Increase" : "Decrease")
    }
    private func commit() { value = clamp(Int(text.filter(\.isNumber)) ?? value); text = "\(value)" }
    private func clamp(_ v: Int) -> Int { min(range.upperBound, max(range.lowerBound, v)) }
}

// MARK: Choosing

enum MenuIcon: Equatable { case symbol(String), dot(Color), none }

struct MenuOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var icon: MenuIcon = .none
    var separatorBefore = false
    var id: Value { value }
}

struct MenuIconView: View {
    let icon: MenuIcon
    var size: CGFloat = 16
    var body: some View {
        switch icon {
        case .none: EmptyView()
        case let .dot(color): Circle().fill(color).frame(width: 8, height: 8).frame(width: size, height: size)
        case let .symbol(name): Image(systemName: name).font(.ui(size * 0.75, .medium)).foregroundStyle(Look.muted).frame(width: size, height: size)
        }
    }
}

/// The dropdown: a pill showing the choice with a chevron; the list opens as a small card with a check.
struct DMenu<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [MenuOption<Value>]
    var width: CGFloat? = nil
    var mono = false
    @State private var open = false
    @State private var hovered: Value?
    @State private var hover = false

    var body: some View {
        let current = options.first { $0.value == selection }
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                if let current { MenuIconView(icon: current.icon, size: 14) }
                Text(current?.title ?? "Choose").font(mono ? .system(size: 12.5, design: .monospaced) : .ui(13, .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.ui(9, .bold)).foregroundStyle(Look.muted)
            }
            .padding(.horizontal, 12).frame(height: 32)
            .frame(width: width)
            .fixedSize(horizontal: width == nil, vertical: false)
            .background(Capsule().fill(hover || open ? Look.chosen : Look.pill))
            .overlay(Capsule().strokeBorder(open ? Look.focus : Look.line, lineWidth: open ? 1.5 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(current?.title ?? "")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(options) { o in
                        if o.separatorBefore { Rectangle().fill(Look.line).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 6) }
                        Button { selection = o.value; open = false } label: {
                            HStack(spacing: 10) {
                                MenuIconView(icon: o.icon)
                                Text(o.title).font(mono ? .system(size: 13, design: .monospaced) : .ui(13.5, o.value == selection ? .semibold : .regular))
                                Spacer(minLength: 16)
                                if o.value == selection { Image(systemName: "checkmark").font(.ui(11.5, .bold)) }
                            }
                            .padding(.horizontal, 10).frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 8).fill(hovered == o.value ? Look.hover : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovered = $0 ? o.value : (hovered == o.value ? nil : hovered) }
                        .accessibilityAddTraits(o.value == selection ? .isSelected : [])
                    }
                }
                .padding(6)
            }
            .frame(minWidth: max(220, width ?? 0), maxHeight: min(420, CGFloat(options.count) * 34 + 30))
        }
    }
}

/// Segmented choice: a soft track with the chosen segment raised as a small card.
struct DSegmented<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [(Value, String)]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                let on = value == selection
                Button { withAnimation(.easeOut(duration: 0.15)) { selection = value } } label: {
                    Text(title).font(.ui(12.5, on ? .semibold : .medium))
                        .foregroundStyle(on ? Look.ink : Look.muted)
                        .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 26)
                        .background(Capsule().fill(on ? Look.card : .clear).shadow(color: .black.opacity(on ? 0.1 : 0), radius: 2, y: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Look.pill))
        .overlay(Capsule().strokeBorder(Look.line))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// The switch: ink when on. The label is read by VoiceOver; the row around it shows the words.
struct DSwitch: View {
    let label: String
    @Binding var on: Bool
    var body: some View {
        Capsule().fill(on ? Look.ink : Look.track)
            .frame(width: 34, height: 20)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(on ? Look.onInk : Color.white).shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .frame(width: 16, height: 16).padding(2)
            }
            .animation(.easeOut(duration: 0.15), value: on)
            .contentShape(Capsule())
            .onTapGesture { on.toggle() }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(on ? "On" : "Off")
            .accessibilityAction { on.toggle() }
    }
}

/// A slider: thin track, ink fill, a round knob.
struct DSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var label = "Value"
    var valueText: String = ""
    var body: some View {
        GeometryReader { g in
            let knob: CGFloat = 18
            let f = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .leading) {
                Capsule().fill(Look.track).frame(height: 4)
                Capsule().fill(Look.ink).frame(width: max(4, knob / 2 + f * (g.size.width - knob)), height: 4)
                Circle().fill(Look.card)
                    .overlay(Circle().strokeBorder(Look.line))
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(x: f * (g.size.width - knob))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                let t = Double(min(1, max(0, (d.location.x - knob / 2) / (g.size.width - knob))))
                let raw = range.lowerBound + t * (range.upperBound - range.lowerBound)
                value = min(range.upperBound, max(range.lowerBound, (raw / step).rounded() * step))
            })
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { d in
            value = min(range.upperBound, max(range.lowerBound, value + (d == .increment ? step : -step)))
        }
    }
}

// MARK: Status

/// A thin progress bar.
struct DProgress: View {
    let value: Double
    var tint: Color = Look.ink
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Look.track)
                Capsule().fill(tint).frame(width: max(6, g.size.width * CGFloat(min(1, max(0, value)))))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

/// The "working" mark: a dot that pulses (steady under Reduce Motion).
struct Pulse: View {
    var color = Look.ink
    var size: CGFloat = 7
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle().fill(color).frame(width: size, height: size).opacity(dim ? 0.25 : 1)
            .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true } } }
            .accessibilityLabel("Working")
    }
}

/// A small rounded count or tag.
struct Tag: View {
    let text: String
    var mono = false
    var tint: Color? = nil
    var body: some View {
        Text(text)
            .font(mono ? .system(size: 11.5, weight: .medium, design: .monospaced) : .ui(11.5, .medium))
            .monospacedDigit().lineLimit(1)
            .foregroundStyle(tint ?? Look.muted)
            .padding(.horizontal, 8).frame(minHeight: 20)
            .background(Capsule().fill(tint.map { $0.opacity(0.12) } ?? Look.pill))
            .fixedSize()
    }
}

/// Ready / not ready, always with a symbol and words.
struct StatusPill: View {
    let ok: Bool
    let text: String
    var body: some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .labelStyle(TightLabel())
            .font(.ui(12, .medium)).foregroundStyle(ok ? Color.mtGood : Color.mtWarn)
            .padding(.horizontal, 10).frame(minHeight: 24)
            .background(Capsule().fill((ok ? Color.mtGood : Color.mtWarn).opacity(0.1)))
            .fixedSize()
    }
}

/// A notice line on a soft tinted background.
struct Notice: View {
    let text: String
    var symbol = "exclamationmark.triangle.fill"
    var tint = Color.mtWarn
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: symbol).font(.ui(12, .semibold)).foregroundStyle(tint)
            Text(text).font(.ui(13)).foregroundStyle(Look.ink).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.22)))
    }
}

/// A custom disclosure: a chevron and a title that open what is under it.
struct DDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.ui(10, .bold)).rotationEffect(.degrees(open ? 90 : 0))
                    Text(title).font(.ui(12.5, .medium))
                }
                .foregroundStyle(Look.muted).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            if open { content }
        }
    }
}

/// Monospaced text on an inset well, for commands and logs.
struct CodeWell: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, design: .monospaced)).foregroundStyle(Look.ink)
            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Look.field))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Look.line))
    }
}
