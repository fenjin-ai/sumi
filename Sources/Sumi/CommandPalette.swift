import SwiftUI
import SumiCore

/// A fixed-height command desk: selection never moves the manuscript or controls.
struct CommandPalette: View {
    @ObservedObject var workspace: Workspace
    private var root: Bool { workspace.paletteGroup == nil && !workspace.searchMode && workspace.activeCommand == nil }

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: 48)
            HStack(alignment: .top, spacing: 0) {
                if root { groupGrid(CommandGroup.roots) }
                else {
                    Group {
                        if let command = workspace.activeCommand { parameterForm(command) }
                        else if !workspace.paletteGroups.isEmpty { groupGrid(workspace.paletteGroups) }
                        else { commands }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    Rectangle().fill(Theme.border.opacity(0.7)).frame(width: 1)
                    commandGuide.frame(width: 254).padding(.horizontal, 20)
                }
            }.frame(maxWidth: 1120, maxHeight: .infinity).padding(.horizontal, 24)
            footer.frame(height: 40)
        }.frame(height: 320).frame(maxWidth: .infinity).background(Theme.panel)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if root {
                PhosphorIcon(name: "command", size: 16).foregroundStyle(Theme.accent).frame(width: 30)
            } else { QuietButton(icon: "arrow-left", help: "返回上一级", shortcut: "Esc") { workspace.backPalette() } }
            if workspace.searchMode && workspace.activeCommand == nil {
                PaletteTextField(text: $workspace.query, label: "搜索命令", placeholder: "用中文或英文寻找一个命令…")
                    .frame(height: 22).onChange(of: workspace.query) { _, _ in workspace.selectedCommandIndex = 0 }
            } else { Text(breadcrumb).font(.system(size: 12, weight: .medium)) }
            Spacer(minLength: 8)
            if !workspace.searchMode && workspace.activeCommand == nil {
                Button { workspace.searchMode = true; workspace.selectedCommandIndex = 0 } label: {
                    HStack(spacing: 8) { PhosphorIcon(name: "magnifying-glass", size: 14); Text("搜索命令").font(.system(size: 11)); Keycap(value: "/") }
                }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
            }
            QuietButton(icon: "x", help: "关闭命令面板", shortcut: "⌘\(workspace.commandKey.uppercased())") { workspace.closePalette() }
        }.padding(.horizontal, 24)
    }

    private var breadcrumb: String {
        if let command = workspace.activeCommand { return "命令  /  \(command.title)" }
        if let group = CommandGroup.all.first(where: { $0.id == workspace.paletteGroup }) { return "命令  /  \(group.title)" }
        return "此刻，你想做什么？"
    }

    private func groupGrid(_ groups: [SumiCore.CommandGroup]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: root ? 3 : 1), spacing: 10) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                Button { workspace.enterGroup(group.id) } label: {
                    HStack(spacing: 13) {
                        PhosphorIcon(name: group.icon, size: 22).foregroundStyle(index == workspace.selectedCommandIndex ? Theme.accent : Theme.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                            Text(group.subtitle).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Keycap(value: group.key)
                    }.padding(.horizontal, 14).frame(height: 66).contentShape(Rectangle())
                }.buttonStyle(PaletteButtonStyle())
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(index == workspace.selectedCommandIndex ? Theme.accent.opacity(0.5) : Theme.border.opacity(0.4)))
            }
        }
    }

    private var commands: some View {
        let commands = workspace.filteredCommands
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if commands.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("没有找到匹配的命令").font(.system(size: 12))
                            Text("试试“表格”“分式”或英文名称。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                        CommandRow(command: command, selected: index == workspace.selectedCommandIndex, searching: workspace.searchMode) {
                            workspace.selectCommand(command)
                        }.id(command.id)
                    }
                }.padding(.trailing, 16)
            }
            .onChange(of: workspace.selectedCommandIndex) { _, _ in
                if let command = workspace.highlightedCommand { proxy.scrollTo(command.id) }
            }
            .onChange(of: workspace.query) { _, _ in if let command = commands.first { proxy.scrollTo(command.id, anchor: .top) } }
        }
    }

    private var commandGuide: some View {
        let command = workspace.activeCommand ?? workspace.highlightedCommand
        return VStack(alignment: .leading, spacing: 12) {
            if let command {
                HStack(spacing: 9) {
                    PhosphorIcon(name: command.icon, size: 19).foregroundStyle(Theme.accent)
                    Text(command.title).font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                Text(command.detail).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(3)
                if !command.shortcuts.isEmpty {
                    HStack(spacing: 6) {
                        Text("快捷键").font(.system(size: 10)).foregroundStyle(Theme.muted)
                        ForEach(command.shortcuts, id: \.label) { shortcut in Keycap(value: shortcut.label) }
                    }
                }
                HStack(spacing: 5) {
                    Keycap(value: "⌘\(workspace.commandKey.uppercased())")
                    Text("→").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    ForEach(Array(command.keyPath.split(separator: " ").enumerated()), id: \.offset) { _, key in Keycap(value: String(key)) }
                }
                if command.isInsertion {
                    let example = (workspace.activeCommand != nil ? try? TypstInsertion.make(command.id, values: workspace.fieldValues).text : command.example) ?? command.example ?? ""
                    Text(example).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary).lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Theme.background, in: RoundedRectangle(cornerRadius: 5))
                    if let url = command.documentationURL { Link("Typst 语法文档 ↗", destination: url).font(.system(size: 10)).foregroundStyle(Theme.accent) }
                }
            } else {
                PhosphorIcon(name: workspace.paletteGroups.isEmpty ? "magnifying-glass" : "sigma", size: 24).foregroundStyle(Theme.accent)
                Text(workspace.paletteGroups.isEmpty ? "从一个词开始" : "逐层发现数学表达").font(.system(size: 12, weight: .medium))
                Text("按字母进入分类，↑ ↓ 选择，↵ 执行。快捷键始终显示在这里，无需事先记住。")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(4)
            }
            Spacer(minLength: 0)
        }.padding(.top, 9).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
    }

    private func parameterForm(_ command: WritingCommand) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                    ForEach(command.fields) { field in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(field.title).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            PaletteTextField(text: Binding(get: { workspace.fieldValues[field.id] ?? field.initial }, set: { workspace.fieldValues[field.id] = $0 }), label: field.title, autoFocus: field.id == command.fields.first?.id, onSubmit: { workspace.execute(command) })
                                .frame(height: 18).padding(10).background(Theme.background, in: RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                        }
                    }
                }
                Button { workspace.execute(command) } label: {
                    HStack(spacing: 18) { Text(command.placement == .preamble ? "应用设置" : "插入文稿"); Text("↵").opacity(0.65) }
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.background).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).disabled(workspace.applyingCommand)
            }.padding(.top, 10).padding(.trailing, 24)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let error = workspace.commandError {
                PhosphorIcon(name: "warning-circle", size: 13).foregroundStyle(Theme.red)
                Text(error).font(.system(size: 10)).foregroundStyle(Theme.red).lineLimit(2)
            } else {
                Text(workspace.activeCommand == nil ? "按字母发现 · ↑ ↓ 选择 · ↵ 确认" : "原生 Typst 源码 · 插入后可修改 · ⌘Z 撤销")
                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Text(root ? "\(WritingCommand.all.count) 个命令" : "Esc 返回").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
        }.padding(.horizontal, 30)
    }
}

private struct CommandRow: View {
    let command: WritingCommand
    let selected: Bool
    let searching: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                PhosphorIcon(name: command.icon, size: 17).foregroundStyle(selected ? Theme.accent : Theme.secondary)
                Text(command.title).font(.system(size: 12, weight: selected ? .medium : .regular)).lineLimit(1)
                Spacer(minLength: 2)
                if let shortcut = command.shortcuts.first {
                    Text(shortcut.label).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                }
                Keycap(value: searching ? command.keyPath : command.key)
            }.padding(.horizontal, 12).frame(height: 38).contentShape(Rectangle())
                .background(selected ? Theme.border.opacity(0.75) : (hovered ? Theme.border.opacity(0.35) : Color.clear), in: RoundedRectangle(cornerRadius: 5))
                .overlay(alignment: .leading) { if selected { Capsule().fill(Theme.accent).frame(width: 2, height: 16) } }
        }.buttonStyle(.plain).onHover { hovered = $0 }
    }
}

struct PaletteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Theme.border : Theme.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }
}
