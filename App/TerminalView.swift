import SwiftUI
import TermCore
import UIKit

struct TerminalView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var inputFocused: Bool

    var body: some View {
        @Bindable var model = model
        let palette = model.palette

        // The transcript fills the screen and scrolls underneath the two glass bars.
        TranscriptView()
            .safeAreaInset(edge: .top, spacing: 0) {
                StatusBar()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BottomBar(inputFocused: $inputFocused)
            }
            .background(Backdrop(palette: palette).ignoresSafeArea())
            .preferredColorScheme(model.theme.isDark ? .dark : .light)
            .onChange(of: model.focusTick) {
                inputFocused = true
            }
            .sheet(isPresented: $model.showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $model.showMenu, onDismiss: { model.menuDidClose() }) {
                CommandMenu()
            }
            .sheet(item: $model.shareItem) { item in
                ShareSheet(text: item.text)
            }
    }
}

/// The theme's background with two faint pools of the accent colour, so the glass has something to bend.
private struct Backdrop: View {
    let palette: Palette

    var body: some View {
        ZStack {
            palette.background
            RadialGradient(colors: [palette.accent.opacity(0.16), palette.accent.opacity(0)],
                           center: .topLeading, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [palette.accent.opacity(0.10), palette.accent.opacity(0)],
                           center: .bottomTrailing, startRadius: 0, endRadius: 380)
        }
    }
}

/// Fades the transcript out behind a bar so glass controls stay readable over text.
private struct Scrim: View {
    let palette: Palette
    let edge: VerticalEdge

    var body: some View {
        LinearGradient(
            colors: [palette.background.opacity(0.94), palette.background.opacity(0.6), palette.background.opacity(0)],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top)
            .ignoresSafeArea(.container, edges: edge == .top ? .top : .bottom)
            .allowsHitTesting(false)
    }
}

// MARK: Status bar

private struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let palette = model.palette
        GlassGroup {
            HStack(spacing: 8) {
                Menu {
                    ForEach(model.profiles) { profile in
                        Section(profile.name) {
                            ForEach(profile.models, id: \.self) { id in
                                Button {
                                    model.select(model: id, in: profile.id)
                                } label: {
                                    if profile.id == model.activeProfile?.id, id == model.activeModel {
                                        Label(id, systemImage: "checkmark")
                                    } else {
                                        Text(id)
                                    }
                                }
                            }
                        }
                    }
                    Button("Settings…") { model.showSettings = true }
                } label: {
                    HStack(spacing: 6) {
                        Text("●").foregroundStyle(model.isRunning ? palette.accent : palette.success)
                        Text(profileLabel).foregroundStyle(palette.text).lineLimit(1).truncationMode(.middle)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .contentShape(Capsule())
                }
                .glass(Capsule(), interactive: true)

                Spacer(minLength: 0)

                Menu {
                    ForEach(model.hosts) { host in
                        Button {
                            model.selectHost(host.id)
                        } label: {
                            if host.id == model.activeHost?.id {
                                Label("\(host.name)  \(host.address)", systemImage: "checkmark")
                            } else {
                                Text("\(host.name)  \(host.address)")
                            }
                        }
                    }
                    Button("No SSH host") { model.selectHost(nil) }
                } label: {
                    Text(model.activeHost.map { "⇄ \($0.name)" } ?? "⇄ off")
                        .foregroundStyle(model.activeHost == nil ? palette.dim : palette.accent)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .contentShape(Capsule())
                }
                .glass(Capsule(), interactive: true)
                .layoutPriority(1)

                // Like shift+tab in a desktop CLI: one tap flips between asking and auto-approving.
                Button {
                    model.toggleApproval()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: model.autoApproving ? "forward.fill" : "hand.raised")
                            .font(.system(size: 11, weight: .semibold))
                        Text(model.autoApproving ? "auto" : "ask")
                    }
                    .foregroundStyle(model.autoApproving ? palette.error : palette.dim)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .glass(Capsule(), interactive: true)
                .accessibilityLabel(model.autoApproving ? "Tool approval: automatic" : "Tool approval: ask first")
            }
        }
        .font(palette.small)
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background { Scrim(palette: palette, edge: .top) }
    }

    private var profileLabel: String {
        guard let profile = model.activeProfile else { return "no profile · /setup" }
        return "\(profile.name) · \(model.activeModel ?? "no model")"
    }
}

// MARK: Transcript

private struct TranscriptView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let palette = model.palette
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.session.transcript) { item in
                            ItemView(item: item, palette: palette)
                        }
                        if model.isRunning, model.pendingApproval == nil {
                            Text("▍").font(palette.font).foregroundStyle(palette.accent)
                        } else if let usage = model.usageLine {
                            Text(usage).font(palette.small).foregroundStyle(palette.dim)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    // A short transcript starts at the top, like a fresh terminal, rather than hugging the input.
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                    .shadow(color: model.theme.glow ? palette.text.opacity(0.55) : .clear, radius: 3)
                }
                // Stay pinned to the newest output while it streams, unless the user scrolls up.
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.scrollTick) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}

private struct ItemView: View {
    let item: TranscriptItem
    let palette: Palette

    var body: some View {
        switch item.kind {
        case .user:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("❯").foregroundStyle(palette.accent)
                Text(item.text).foregroundStyle(palette.text).textSelection(.enabled)
            }
            .font(palette.bold)
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(Markdown.segments(item.text).enumerated()), id: \.offset) { _, segment in
                    if segment.isCode {
                        CodeBlock(code: segment.text, palette: palette)
                    } else {
                        Text(segment.text).font(palette.font).foregroundStyle(palette.text).textSelection(.enabled)
                    }
                }
            }
        case .tool:
            ToolBlock(item: item, palette: palette)
        case .info:
            Text(item.text).font(palette.font).foregroundStyle(palette.dim).textSelection(.enabled)
        case .error:
            Text(item.text).font(palette.font).foregroundStyle(palette.error).textSelection(.enabled)
        }
    }
}

private struct CodeBlock: View {
    let code: String
    let palette: Palette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code).font(palette.font).foregroundStyle(palette.text).textSelection(.enabled)
                .padding(.vertical, 8)
                .padding(.leading, 10)
                .padding(.trailing, 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.code, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                UIPasteboard.general.string = code
            } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 12)).foregroundStyle(palette.dim).padding(8)
            }
            .accessibilityLabel("Copy code")
        }
    }
}

private struct ToolBlock: View {
    let item: TranscriptItem
    let palette: Palette

    private var glyph: (String, Color) {
        switch item.status {
        case .running: return ("…", palette.accent)
        case .ok: return ("✓", palette.success)
        case .failed: return ("✗", palette.error)
        case .denied: return ("⊘", palette.dim)
        case nil: return ("·", palette.dim)
        }
    }

    /// Long output is shown from the end, where the result usually is.
    private var tail: String {
        let lines = item.text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 40 else { return item.text }
        return "… \(lines.count - 40) earlier lines\n" + lines.suffix(40).joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(glyph.0).foregroundStyle(glyph.1)
                Text(item.title ?? "tool").foregroundStyle(palette.text.opacity(0.85)).textSelection(.enabled)
            }
            .font(palette.small)
            if !item.text.isEmpty {
                Text(tail).font(palette.small).foregroundStyle(palette.dim).textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.code, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: Input area

private struct BottomBar: View {
    @Environment(AppModel.self) private var model
    var inputFocused: FocusState<Bool>.Binding

    var body: some View {
        @Bindable var model = model
        let palette = model.palette

        VStack(spacing: 8) {
            if let approval = model.pendingApproval {
                ApprovalBar(approval: approval, palette: palette)
            } else {
                Completions(palette: palette)
            }

            GlassGroup {
                HStack(alignment: .bottom, spacing: 8) {
                    RoundButton(symbol: "line.3.horizontal", label: "Commands", color: palette.text) {
                        inputFocused.wrappedValue = false
                        model.showMenu = true
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.setup == nil ? "❯" : "?").font(palette.bold).foregroundStyle(palette.accent)
                        Group {
                            if model.inputIsSecret {
                                SecureField("", text: $model.input, prompt: Text(model.placeholder).foregroundStyle(palette.dim))
                            } else {
                                TextField("", text: $model.input, prompt: Text(model.placeholder).foregroundStyle(palette.dim), axis: .vertical)
                                    .lineLimit(1...6)
                            }
                        }
                        .font(palette.font)
                        .foregroundStyle(palette.text)
                        .tint(palette.accent)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .focused(inputFocused)
                        .onSubmit(send)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    // The whole pill focuses the field, not only the line of text inside it.
                    .contentShape(Rectangle())
                    .onTapGesture { inputFocused.wrappedValue = true }
                    .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    if showsStop {
                        RoundButton(symbol: "stop.fill", label: "Stop", color: .white, tint: palette.error) {
                            model.cancel()
                        }
                    } else {
                        RoundButton(symbol: "arrow.up", label: "Send",
                                    color: canSend ? palette.background : palette.dim,
                                    tint: canSend ? palette.accent : nil, action: send)
                    }
                }
            }

            KeyRow(palette: palette, hideKeyboard: { inputFocused.wrappedValue = false })
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background { Scrim(palette: palette, edge: .bottom) }
    }

    private var canSend: Bool {
        !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// While a run is in progress the send button stops it, unless something has been typed to send.
    private var showsStop: Bool {
        model.isRunning && model.pendingApproval == nil && !canSend
    }

    private func send() {
        model.submit()
        // Submitting drops focus; keep the keyboard up like a terminal would.
        DispatchQueue.main.async { inputFocused.wrappedValue = true }
    }
}

/// A 44-point circular glass button holding one symbol.
private struct RoundButton: View {
    let symbol: String
    let label: String
    let color: Color
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glass(Circle(), tint: tint, interactive: true)
        .accessibilityLabel(label)
    }
}

/// Terminal keys the on-screen keyboard lacks, on one strip of glass.
private struct KeyRow: View {
    @Environment(AppModel.self) private var model
    let palette: Palette
    let hideKeyboard: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                key("esc") { model.escape() }
                key("/") { model.input += "/" }
                key("!") { model.input += "!" }
                key("↑") { model.historyUp() }
                key("↓") { model.historyDown() }
                key("tab") { model.completeSuggestion() }
                key("^C", tint: model.isRunning ? palette.error : nil) { model.cancel() }
                key("paste") {
                    if let text = UIPasteboard.general.string { model.input += text }
                }
                key("⌄", action: hideKeyboard)
            }
            .padding(.horizontal, 6)
        }
        .clipShape(Capsule())
        .glass(Capsule())
    }

    private func key(_ label: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(palette.small)
                .foregroundStyle(tint ?? palette.text)
                .padding(.horizontal, 10)
                .frame(minWidth: 40, minHeight: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The list above the input: matching commands while a `/name` is typed, then that command's choices.
private struct Completions: View {
    @Environment(AppModel.self) private var model
    let palette: Palette

    var body: some View {
        let commands = model.suggestions
        let choices = commands.isEmpty ? model.argumentChoices : []
        if !commands.isEmpty || !choices.isEmpty {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            // Sized to its rows until it reaches the height limit, then it scrolls.
            ViewThatFits(in: .vertical) {
                rows(commands, choices)
                ScrollView {
                    rows(commands, choices)
                }
            }
            .frame(maxHeight: 232)
            .clipShape(shape)
            .glass(shape)
        }
    }

    private func rows(_ commands: [SlashCommand], _ choices: [MenuChoice]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(commands, id: \.name) { command in
                CommandRow(command: command, palette: palette, compact: true) {
                    model.pickSuggestion(command)
                }
            }
            ForEach(choices) { choice in
                ChoiceRow(choice: choice, palette: palette, compact: true) {
                    model.pick(choice)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ApprovalBar: View {
    @Environment(AppModel.self) private var model
    let approval: PendingApproval
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("run this?").font(palette.small).foregroundStyle(palette.accent)
            Text(approval.summary).font(palette.small).foregroundStyle(palette.text).lineLimit(6)
            HStack(spacing: 8) {
                choice("[y] yes", palette.success) { model.resolveApproval(.allow) }
                choice("[n] no", palette.error) { model.resolveApproval(.deny) }
                choice("[a] always", palette.dim) { model.allowAlways() }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func choice(_ label: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(palette.small).foregroundStyle(color)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(color.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
