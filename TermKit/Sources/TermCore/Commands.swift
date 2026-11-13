import Foundation

/// Sections of the command menu, in display order.
public enum CommandGroup: String, CaseIterable, Sendable {
    case session, model, agent, app

    public var title: String {
        switch self {
        case .session: return "session"
        case .model: return "model & api"
        case .agent: return "agent"
        case .app: return "app"
        }
    }
}

public struct SlashCommand: Equatable, Sendable {
    /// What follows the command name.
    public enum Argument: Equatable, Sendable {
        /// Nothing: the command runs as soon as it is picked.
        case none
        /// One of a known set (models, hosts, themes…), which menus can list.
        case choices
        /// Free text the user has to type.
        case text
    }

    public var name: String
    public var usage: String
    public var help: String
    public var group: CommandGroup
    /// SF Symbol shown next to the command in the menu.
    public var symbol: String
    public var argument: Argument

    public init(name: String, usage: String, help: String, group: CommandGroup = .app,
                symbol: String = "terminal", argument: Argument = .none) {
        self.name = name
        self.usage = usage
        self.help = help
        self.group = group
        self.symbol = symbol
        self.argument = argument
    }
}

public enum ParsedInput: Equatable, Sendable {
    case empty
    case prompt(String)
    /// `!cmd`: run directly on the active SSH host, bypassing the model.
    case shell(String)
    case command(name: String, args: String)
}

/// One section of the command menu.
public struct CommandSection: Identifiable, Equatable, Sendable {
    public var group: CommandGroup
    public var commands: [SlashCommand]
    public var id: CommandGroup { group }
}

/// A command whose argument is being typed, e.g. `/model gp`.
public struct ArgumentContext: Equatable, Sendable {
    public var command: SlashCommand
    public var partial: String
}

public enum Commands {
    public static let all: [SlashCommand] = [
        .init(name: "help", usage: "/help", help: "list commands", group: .app, symbol: "questionmark.circle"),
        .init(name: "setup", usage: "/setup", help: "add an API profile step by step", group: .model, symbol: "wand.and.stars"),
        .init(name: "config", usage: "/config", help: "open settings", group: .app, symbol: "gearshape"),
        .init(name: "model", usage: "/model [id]", help: "show or switch model", group: .model, symbol: "cpu", argument: .choices),
        .init(name: "profile", usage: "/profile [name]", help: "show or switch API profile", group: .model, symbol: "key", argument: .choices),
        .init(name: "host", usage: "/host [name|off]", help: "show or switch SSH host", group: .agent, symbol: "server.rack", argument: .choices),
        .init(name: "approve", usage: "/approve [ask|auto]", help: "tool approval mode", group: .agent, symbol: "hand.raised", argument: .choices),
        .init(name: "theme", usage: "/theme [id]", help: "show or switch theme", group: .app, symbol: "paintpalette", argument: .choices),
        .init(name: "system", usage: "/system [text|reset]", help: "show or set the system prompt", group: .agent, symbol: "text.quote", argument: .text),
        .init(name: "new", usage: "/new", help: "start a new session", group: .session, symbol: "plus"),
        .init(name: "sessions", usage: "/sessions [n]", help: "list or resume sessions", group: .session, symbol: "clock.arrow.circlepath", argument: .choices),
        .init(name: "retry", usage: "/retry", help: "resend the last prompt", group: .session, symbol: "arrow.clockwise"),
        .init(name: "copy", usage: "/copy", help: "copy the last answer", group: .session, symbol: "doc.on.doc"),
        .init(name: "export", usage: "/export", help: "share the session as Markdown", group: .session, symbol: "square.and.arrow.up"),
        .init(name: "clear", usage: "/clear", help: "clear the screen", group: .session, symbol: "eraser"),
    ]

    public static func named(_ name: String) -> SlashCommand? {
        all.first { $0.name == name }
    }

    public static func parse(_ raw: String) -> ParsedInput {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .empty }
        if text.hasPrefix("!") {
            let command = text.dropFirst().trimmingCharacters(in: .whitespaces)
            return command.isEmpty ? .empty : .shell(command)
        }
        if text.hasPrefix("/") {
            let body = text.dropFirst()
            let name = body.prefix { !$0.isWhitespace }.lowercased()
            // A leading slash that is not a known command (e.g. a file path) is an ordinary prompt.
            guard all.contains(where: { $0.name == name }) else { return .prompt(text) }
            let args = body.dropFirst(name.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return .command(name: name, args: args)
        }
        return .prompt(text)
    }

    /// Commands matching a partially typed `/name` (no arguments yet).
    public static func suggestions(for input: String) -> [SlashCommand] {
        guard input.hasPrefix("/"), !input.contains(where: { $0.isWhitespace }) else { return [] }
        let partial = input.dropFirst().lowercased()
        return all.filter { $0.name.hasPrefix(partial) && $0.name != partial }
    }

    /// The command and partial argument when the input is `/name <partial>` for a command with listable choices.
    public static func argumentContext(for input: String) -> ArgumentContext? {
        guard input.hasPrefix("/"), !input.contains(where: { $0.isNewline }) else { return nil }
        let body = input.dropFirst()
        let name = body.prefix { !$0.isWhitespace }
        // Only once the name is finished: `/model` alone still completes command names.
        guard name.count < body.count, let command = named(name.lowercased()), command.argument == .choices else { return nil }
        return ArgumentContext(command: command, partial: body.dropFirst(name.count).trimmingCharacters(in: .whitespaces))
    }

    /// Menu search: commands whose name starts with the query first, then those whose description
    /// has a word starting with each word of it (so "se" finds "open settings" but not "resend").
    public static func search(_ query: String) -> [SlashCommand] {
        var needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while needle.hasPrefix("/") { needle.removeFirst() }
        let wanted = needle.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard !wanted.isEmpty else { return all }
        let leading = all.filter { $0.name.hasPrefix(needle) }
        let rest = all.filter { command in
            guard !command.name.hasPrefix(needle) else { return false }
            let words = (command.name + " " + command.help).lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            return wanted.allSatisfy { part in words.contains { $0.hasPrefix(part) } }
        }
        return leading + rest
    }

    /// Commands bucketed by group, keeping both the group order and the order within `commands`.
    public static func grouped(_ commands: [SlashCommand]) -> [CommandSection] {
        CommandGroup.allCases.compactMap { group in
            let members = commands.filter { $0.group == group }
            return members.isEmpty ? nil : CommandSection(group: group, commands: members)
        }
    }

    /// Case-insensitive match where every word of `query` has to appear somewhere in `text`.
    public static func matches(_ text: String, query: String) -> Bool {
        let haystack = text.lowercased()
        return query.lowercased().split(whereSeparator: \.isWhitespace).allSatisfy { haystack.contains($0) }
    }
}
