import SwiftUI
import TermCore
import UIKit

/// The command palette: every slash command, searchable, with its choices one tap away.
struct CommandMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// The command whose choices are showing; `nil` on the command list.
    @State private var opened: SlashCommand?
    @State private var sessionToDelete: UUID?

    /// Commands that put up a sheet of their own, which has to wait for this one to close.
    private static let presenting: Set<String> = ["config", "export"]

    var body: some View {
        let palette = model.palette

        VStack(spacing: 0) {
            header(palette)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let opened {
                        choicePage(opened, palette)
                    } else {
                        commandPage(palette)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .glassSheet()
        .preferredColorScheme(model.theme.isDark ? .dark : .light)
        .confirmationDialog("Delete this session?", isPresented: deleteDialogShown, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = sessionToDelete { model.deleteSession(id) }
                sessionToDelete = nil
            }
        }
    }

    private var deleteDialogShown: Binding<Bool> {
        Binding(get: { sessionToDelete != nil }, set: { shown in if !shown { sessionToDelete = nil } })
    }

    // MARK: Header

    private func header(_ palette: Palette) -> some View {
        HStack(spacing: 8) {
            if opened != nil {
                Button {
                    opened = nil
                    query = ""
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .frame(width: 44, height: 44)
                        .background(palette.text.opacity(0.08), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            HStack(spacing: 6) {
                Text(opened.map { "/\($0.name)" } ?? "/").font(palette.bold).foregroundStyle(palette.accent)
                TextField("", text: $query,
                          prompt: Text(opened == nil ? "search commands" : "filter").foregroundStyle(palette.dim))
                    .font(palette.font)
                    .foregroundStyle(palette.text)
                    .tint(palette.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(runFirstMatch)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(palette.dim)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(palette.text.opacity(0.08), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.top, 26)
        .padding(.bottom, 8)
    }

    // MARK: Command list

    @ViewBuilder
    private func commandPage(_ palette: Palette) -> some View {
        let sections = Commands.grouped(Commands.search(query))
        let hits = query.isEmpty ? [] : choiceHits

        ForEach(sections) { section in
            MenuHeading(text: section.group.title, palette: palette)
            ForEach(section.commands, id: \.name) { command in
                CommandRow(command: command, value: model.currentValue(for: command.name), palette: palette) {
                    open(command)
                }
            }
        }
        if !hits.isEmpty {
            MenuHeading(text: "switch to", palette: palette)
            ForEach(hits) { hit in
                ChoiceRow(choice: hit.choice, prefix: "/\(hit.command.name)", palette: palette) {
                    pick(hit.choice)
                }
            }
        }
        if sections.isEmpty, hits.isEmpty {
            MenuNote(text: "nothing matches \(query)", palette: palette)
        } else if query.isEmpty {
            MenuNote(text: "typing / in the prompt lists the same commands", palette: palette)
        }
    }

    private struct ChoiceHit: Identifiable {
        let command: SlashCommand
        let choice: MenuChoice
        var id: String { command.name + " " + choice.id }
    }

    /// Models, hosts, themes and so on that match the search, so "light" or a model name can be picked directly.
    private var choiceHits: [ChoiceHit] {
        Commands.all.filter { $0.argument == .choices }.flatMap { command -> [ChoiceHit] in
            model.choices(for: command.name)
                .filter { !$0.isCurrent && Commands.matches($0.title + " " + ($0.detail ?? ""), query: query) }
                .map { ChoiceHit(command: command, choice: $0) }
        }
    }

    // MARK: Choices of one command

    private struct ChoiceSection: Identifiable {
        let id: String
        var title: String?
        var choices: [MenuChoice]
    }

    private func sections(of choices: [MenuChoice]) -> [ChoiceSection] {
        var sections: [ChoiceSection] = []
        for choice in choices {
            if let last = sections.indices.last, sections[last].title == choice.section {
                sections[last].choices.append(choice)
            } else {
                sections.append(ChoiceSection(id: "\(sections.count)", title: choice.section, choices: [choice]))
            }
        }
        return sections
    }

    @ViewBuilder
    private func choicePage(_ command: SlashCommand, _ palette: Palette) -> some View {
        let all = model.choices(for: command.name)
        let shown = all.filter { Commands.matches($0.title + " " + ($0.detail ?? ""), query: query) }

        ForEach(sections(of: shown)) { section in
            MenuHeading(text: section.title ?? command.help, palette: palette)
            ForEach(section.choices) { choice in
                ChoiceRow(choice: choice, palette: palette,
                          onDelete: choice.deletableSession.map { id in { sessionToDelete = id } }) {
                    pick(choice)
                }
            }
        }
        if shown.isEmpty {
            MenuNote(text: all.isEmpty ? emptyNote(for: command) : "nothing matches \(query)", palette: palette)
        }

        if let extra = extraAction(for: command) {
            MenuHeading(text: "more", palette: palette)
            CommandRow(command: extra, palette: palette) {
                open(extra)
            }
        }
    }

    private func emptyNote(for command: SlashCommand) -> String {
        switch command.name {
        case "model", "profile": return "no API profile yet"
        case "sessions": return "no saved sessions yet"
        default: return "nothing to choose from"
        }
    }

    /// Where to go when the wanted choice is not in the list.
    private func extraAction(for command: SlashCommand) -> SlashCommand? {
        switch command.name {
        case "model", "profile": return Commands.named(model.profiles.isEmpty ? "setup" : "config")
        case "host": return Commands.named("config")
        case "sessions": return Commands.named("new")
        default: return nil
        }
    }

    // MARK: Actions

    private func open(_ command: SlashCommand) {
        UISelectionFeedbackGenerator().selectionChanged()
        switch command.argument {
        case .choices:
            query = ""
            opened = command
        case .text:
            let model = model
            model.afterMenuCloses { model.beginTyping(command) }
            dismiss()
        case .none:
            if Self.presenting.contains(command.name) {
                let model = model
                model.afterMenuCloses { model.runFromMenu(command) }
            } else {
                model.runFromMenu(command)
            }
            dismiss()
        }
    }

    private func pick(_ choice: MenuChoice) {
        UISelectionFeedbackGenerator().selectionChanged()
        model.pick(choice)
        dismiss()
    }

    /// Return in the search field takes the first row.
    private func runFirstMatch() {
        if let opened {
            let first = model.choices(for: opened.name)
                .first { Commands.matches($0.title + " " + ($0.detail ?? ""), query: query) }
            if let first { pick(first) }
        } else if let command = Commands.search(query).first {
            open(command)
        } else if let hit = choiceHits.first {
            pick(hit.choice)
        }
    }
}

// MARK: Rows

/// A slash command. Two lines in the menu, one line (`compact`) in the list above the input.
struct CommandRow: View {
    let command: SlashCommand
    var value: String? = nil
    let palette: Palette
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if compact {
                    Text("/\(command.name)").foregroundStyle(palette.accent).fixedSize()
                    Text(command.help).foregroundStyle(palette.dim).lineLimit(1)
                    Spacer(minLength: 0)
                } else {
                    Image(systemName: command.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(palette.dim)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("/\(command.name)").font(palette.font).foregroundStyle(palette.accent)
                        Text(command.help).foregroundStyle(palette.dim).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if let value {
                        Text(value).foregroundStyle(palette.text.opacity(0.75))
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: 130, alignment: .trailing)
                            // Only as wide as the value needs (up to 130), so a short value leaves room for the help line.
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    if command.argument == .choices {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.dim)
                    }
                }
            }
            .font(palette.small)
            .padding(.horizontal, 12)
            .frame(minHeight: compact ? 36 : 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One choice of a command: a model, a host, a theme, a saved session.
struct ChoiceRow: View {
    let choice: MenuChoice
    /// The command the choice belongs to, shown when rows of several commands are mixed.
    var prefix: String? = nil
    let palette: Palette
    var compact = false
    var onDelete: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Text(choice.isCurrent ? "●" : "○").foregroundStyle(choice.isCurrent ? palette.accent : palette.dim)
                    if let theme = choice.theme {
                        ThemeSwatch(theme: theme)
                    }
                    if compact {
                        Text(choice.title).foregroundStyle(palette.text).lineLimit(1).truncationMode(.middle)
                        if let detail = choice.detail {
                            Text(detail).foregroundStyle(palette.dim).lineLimit(1)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(palette.font).foregroundStyle(palette.text)
                                .lineLimit(1).truncationMode(.middle)
                            if let detail = choice.detail {
                                Text(detail).foregroundStyle(palette.dim).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .frame(minHeight: compact ? 36 : 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(choice.isCurrent ? .isSelected : [])

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.dim)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete session")
            }
        }
        .font(palette.small)
        .padding(.trailing, onDelete == nil ? 12 : 0)
    }

    private var title: String {
        prefix.map { "\($0) \(choice.title)" } ?? choice.title
    }
}

/// A thumbnail of a theme: its prompt colour on its background.
private struct ThemeSwatch: View {
    let theme: Theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Text("❯_")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(Color(hex: theme.accent))
            .frame(width: 34, height: 24)
            .background(Color(hex: theme.background), in: shape)
            .overlay(shape.stroke(Color(hex: theme.dim).opacity(0.6), lineWidth: 0.5))
    }
}

private struct MenuHeading: View {
    let text: String
    let palette: Palette

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .kerning(1.2)
            .foregroundStyle(palette.dim)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

private struct MenuNote: View {
    let text: String
    let palette: Palette

    var body: some View {
        Text(text)
            .font(palette.small)
            .foregroundStyle(palette.dim)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
    }
}
