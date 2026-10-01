import SwiftUI
import SumiCore

struct ContentView: View {
    @ObservedObject var workspace: Workspace
    @State private var splitFraction: CGFloat = 0.5

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border.opacity(0.55)).frame(height: 1)
            HStack(spacing: 0) {
                if let sidePanel = workspace.sidePanel { sidebar(sidePanel).frame(width: 224); divider }
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let editorWidth = workspace.layout == .writing ? width : (workspace.layout == .preview ? 0 : max(280, min(width - 280, width * splitFraction)))
                    HStack(spacing: 0) {
                        manuscript.frame(width: editorWidth).clipped()
                            .opacity(workspace.layout == .preview ? 0 : 1)
                            .accessibilityHidden(workspace.layout == .preview)
                        Rectangle().fill(Theme.border).frame(width: workspace.layout == .split ? 1 : 0)
                            .overlay(Color.clear.frame(width: 9).contentShape(Rectangle()).gesture(DragGesture(coordinateSpace: .named("writingArea")).onChanged { value in splitFraction = min(0.75, max(0.25, value.location.x / width)) }))
                        preview.frame(width: max(0, width - editorWidth - (workspace.layout == .split ? 1 : 0))).clipped()
                            .opacity(workspace.layout == .writing ? 0 : 1)
                            .accessibilityHidden(workspace.layout == .writing)
                    }.coordinateSpace(name: "writingArea")
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let message = workspace.message { messageBar(message) }
            if workspace.paletteOpen {
                Rectangle().fill(Theme.accent.opacity(0.4)).frame(height: 1)
                CommandPalette(workspace: workspace)
            }
            Rectangle().fill(Theme.border.opacity(0.55)).frame(height: 1)
            footer
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }

    private var divider: some View { Rectangle().fill(Theme.border.opacity(0.55)).frame(width: 1) }

    private var header: some View {
        HStack(spacing: 12) {
            Text("S U M I").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.accent).padding(.leading, 86)
            Rectangle().fill(Theme.border).frame(width: 1, height: 14).padding(.horizontal, 5)
            Text(workspace.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            if workspace.text != workspace.savedText, workspace.fileURL != nil { Circle().fill(Theme.accent).frame(width: 5, height: 5).accessibilityLabel("尚未保存") }
            Spacer(minLength: 20)
            QuietButton(icon: "list", help: "文稿大纲", active: workspace.sidePanel == .outline) { workspace.sidePanel = workspace.sidePanel == .outline ? nil : .outline }
            Rectangle().fill(Theme.border).frame(width: 1, height: 14)
            QuietButton(icon: "pencil-simple", help: "专注写作", active: workspace.layout == .writing) { workspace.layout = .writing }
            QuietButton(icon: "columns", help: "并排预览", active: workspace.layout == .split) { workspace.layout = .split }
            QuietButton(icon: "eye", help: "阅读成稿", active: workspace.layout == .preview) { workspace.layout = .preview }
            Rectangle().fill(Theme.border).frame(width: 1, height: 14)
            QuietButton(icon: "arrow-square-out", help: "导出 PDF") { workspace.exportPDF() }.disabled(workspace.exporting)
        }.padding(.trailing, 20).frame(height: 54)
    }

    private var manuscript: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MANUSCRIPT").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2.5).foregroundStyle(Theme.muted)
                Spacer()
                Text("TYPST").font(.system(size: 9, weight: .regular, design: .monospaced)).tracking(1.8).foregroundStyle(Theme.muted)
            }.padding(.horizontal, 36).padding(.top, 25).padding(.bottom, 12)
            ManuscriptView(workspace: workspace).clipped()
        }.background(Theme.editor)
    }

    private var preview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PREVIEW").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2.5).foregroundStyle(Theme.muted)
                if let main = workspace.mainFileURL {
                    Button(main.lastPathComponent) { workspace.open(main) }.buttonStyle(.plain).font(.system(size: 10)).help("返回主文稿")
                }
                Spacer()
                Button("−") { workspace.previewZoom = max(0.5, workspace.previewZoom - 0.1) }.buttonStyle(.plain).help("缩小预览")
                Text("\(Int((workspace.previewZoom * 100).rounded()))%").font(.system(size: 10, design: .monospaced)).frame(width: 38)
                Button("+") { workspace.previewZoom = min(2, workspace.previewZoom + 0.1) }.buttonStyle(.plain).help("放大预览")
            }.foregroundStyle(Theme.secondary).padding(.horizontal, 24).frame(height: 48)
            if let url = workspace.previewURL {
                PreviewView(url: url, zoom: workspace.previewZoom) { workspace.showMessage($0, persistent: true) }
            } else {
                VStack(spacing: 16) {
                    PhosphorIcon(name: "file-text", size: 32).foregroundStyle(Theme.accent.opacity(0.8))
                    Text("文字正在成为页面").font(.system(size: 16, weight: .medium))
                    Text(workspace.serviceStatus).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    if !workspace.serviceReady {
                        Button("重新连接") { workspace.startService() }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Theme.panel)
    }

    private func sidebar(_ panel: SidePanel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(panel == .outline ? "文章脉络" : "文稿检查").font(.system(size: 12, weight: .semibold))
                Spacer()
                QuietButton(icon: "x", help: "关闭侧栏") { workspace.sidePanel = nil }
            }.padding(.horizontal, 18).padding(.top, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if panel == .outline {
                        if workspace.outline.isEmpty { Text("用 = 添加第一个标题").font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(18) }
                        ForEach(workspace.outline) { item in
                            Button { workspace.jump(to: item.offset) } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Text(String(repeating: "·", count: min(item.level, 3))).foregroundStyle(Theme.muted)
                                    Text(item.title).lineLimit(2).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }.font(.system(size: 12)).foregroundStyle(item.level == 1 ? Theme.text : Theme.secondary)
                                    .padding(.vertical, 9).padding(.leading, CGFloat(18 + (item.level - 1) * 10)).padding(.trailing, 14)
                            }.buttonStyle(.plain)
                        }
                    } else {
                        if workspace.diagnostics.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                PhosphorIcon(name: "check").foregroundStyle(Theme.green)
                                Text(workspace.serviceReady ? "目前没有发现问题" : "等待排版服务").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            }.padding(18)
                        }
                        ForEach(workspace.diagnostics) { diagnostic in
                            Button { workspace.showDiagnostic(diagnostic) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(diagnostic.url.lastPathComponent) · \(diagnostic.position.line + 1)").font(.system(size: 10, design: .monospaced)).foregroundStyle(diagnostic.severity == 1 ? Theme.red : Theme.accent)
                                    Text(diagnostic.message).font(.system(size: 12)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }.background(Theme.background)
    }

    private func messageBar(_ message: String) -> some View {
        HStack(spacing: 10) {
            PhosphorIcon(name: "warning-circle", size: 15).foregroundStyle(Theme.accent)
            Text(message).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(3)
            Spacer()
            QuietButton(icon: "x", help: "关闭提示") { workspace.message = nil }
        }.padding(.horizontal, 20).padding(.vertical, 3).background(Theme.panel)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button { workspace.togglePalette() } label: {
                HStack(spacing: 8) {
                    PhosphorIcon(name: "command", size: 14)
                    Text("发现命令").font(.system(size: 11))
                    Text("⌘ \(workspace.commandKey.uppercased())").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                }.foregroundStyle(workspace.paletteOpen ? Theme.accent : Theme.secondary)
            }.buttonStyle(.plain).accessibilityLabel("发现命令 ⌘\(workspace.commandKey.uppercased())")
            Spacer()
            Text(workspace.saveStatus).font(.system(size: 10)).foregroundStyle(Theme.muted)
            Rectangle().fill(Theme.border).frame(width: 1, height: 10)
            Button { workspace.sidePanel = .diagnostics } label: {
                HStack(spacing: 6) {
                    Circle().fill(workspace.diagnostics.contains { $0.severity == 1 } ? Theme.red : (workspace.serviceReady ? Theme.green : Theme.muted)).frame(width: 4, height: 4)
                    Text(workspace.serviceStatus).font(.system(size: 10))
                }
            }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
            Rectangle().fill(Theme.border).frame(width: 1, height: 10)
            Text("\(workspace.wordCount) 字").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
            Text("\(workspace.position.line + 1):\(workspace.position.character + 1)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted).frame(minWidth: 35, alignment: .trailing)
        }.padding(.horizontal, 24).frame(height: 34)
    }
}

struct CommandPalette: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if workspace.paletteGroup != nil || workspace.searchMode || workspace.activeCommand != nil {
                    QuietButton(icon: "arrow-left", help: "返回上一级") { workspace.backPalette() }
                } else { PhosphorIcon(name: "command", size: 16).foregroundStyle(Theme.accent).frame(width: 30, height: 30) }
                Text(breadcrumb).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("ESC 返回").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                QuietButton(icon: "x", help: "关闭命令面板") { workspace.closePalette() }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
            if let command = workspace.activeCommand { parameterForm(command) }
            else if workspace.searchMode { search }
            else if workspace.paletteGroup != nil { commands }
            else { groups }
            if workspace.activeCommand == nil, let error = workspace.commandError {
                Text(error).font(.system(size: 11)).foregroundStyle(Theme.red).padding(.horizontal, 30).padding(.top, 12)
            }
        }
        .padding(.bottom, 18)
        .background(Theme.panel)
    }

    private var breadcrumb: String {
        if let command = workspace.activeCommand { return "命令  /  \(command.title)" }
        if workspace.searchMode { return "搜索命令" }
        if let group = CommandGroup.all.first(where: { $0.id == workspace.paletteGroup }) { return "命令  /  \(group.title)" }
        return "此刻，你想做什么？"
    }

    private var groups: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(CommandGroup.all) { group in
                Button { workspace.enterGroup(group.id) } label: {
                    HStack(spacing: 12) {
                        PhosphorIcon(name: group.icon).foregroundStyle(Theme.secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                            Text(group.subtitle).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Keycap(value: group.key)
                    }.padding(12).contentShape(Rectangle())
                }.buttonStyle(PaletteButtonStyle())
            }
            Button { workspace.searchMode = true } label: {
                HStack(spacing: 12) {
                    PhosphorIcon(name: "magnifying-glass").foregroundStyle(Theme.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("搜索全部命令").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                        Text("试试「公式」或「export」").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Keycap(value: "/")
                }.padding(12).contentShape(Rectangle())
            }.buttonStyle(PaletteButtonStyle())
        }.padding(.horizontal, 24)
    }

    private var search: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                PhosphorIcon(name: "magnifying-glass", size: 16).foregroundStyle(Theme.accent)
                PaletteTextField(text: $workspace.query, label: "搜索命令", placeholder: "用中文或英文寻找一个命令…")
                    .frame(height: 20)
                    .onChange(of: workspace.query) { _, _ in workspace.selectedCommandIndex = 0 }
            }.padding(12).background(Theme.background, in: RoundedRectangle(cornerRadius: 5)).padding(.horizontal, 24)
            commands
        }
    }

    private var commands: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if workspace.filteredCommands.isEmpty {
                        Text("没有找到匹配的命令，换一个关键词试试。").font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(20)
                    }
                    ForEach(workspace.filteredCommands) { command in
                        let index = workspace.filteredCommands.firstIndex { $0.id == command.id } ?? 0
                        Button { workspace.selectCommand(command) } label: {
                            HStack(spacing: 14) {
                                Keycap(value: command.key)
                                Text(command.title).font(.system(size: 12, weight: .medium)).frame(width: 116, alignment: .leading)
                                Text(command.detail).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                                Spacer(minLength: 0)
                                PhosphorIcon(name: "caret-right", size: 12).foregroundStyle(Theme.muted)
                            }.padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
                                .background(index == workspace.selectedCommandIndex ? Theme.border.opacity(0.55) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                        }.buttonStyle(.plain).id(command.id)
                    }
                }.padding(.horizontal, 24)
            }.frame(height: min(CGFloat(max(1, workspace.filteredCommands.count)) * 43, 222))
                .onChange(of: workspace.selectedCommandIndex) { _, index in
                    if workspace.filteredCommands.indices.contains(index) { proxy.scrollTo(workspace.filteredCommands[index].id, anchor: .center) }
                }
        }
    }

    private func parameterForm(_ command: WritingCommand) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(command.detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            HStack(alignment: .top, spacing: 16) {
                ForEach(command.fields) { field in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(field.title).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        PaletteTextField(text: Binding(get: { workspace.fieldValues[field.id] ?? field.initial }, set: { workspace.fieldValues[field.id] = $0 }), label: field.title, autoFocus: field.id == command.fields.first?.id, onSubmit: { workspace.execute(command) })
                            .frame(height: 18).padding(10)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                    }
                }
                VStack {
                    Text(" ").font(.system(size: 10))
                    Button { workspace.execute(command) } label: {
                        HStack(spacing: 12) { Text(command.group == "page" ? "应用设置" : "插入文稿"); Text("↵").opacity(0.6) }
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.background)
                            .padding(.horizontal, 18).padding(.vertical, 10).background(Theme.accent, in: RoundedRectangle(cornerRadius: 4))
                    }.buttonStyle(.plain).disabled(workspace.applyingCommand)
                }
            }
            if let error = workspace.commandError { Text(error).font(.system(size: 11)).foregroundStyle(Theme.red) }
            else { Text("生成原生 Typst 代码 · 插入后可直接修改 · ⌘Z 撤销").font(.system(size: 10)).foregroundStyle(Theme.muted) }
        }.padding(.horizontal, 30).padding(.bottom, 7)
    }
}

struct PaletteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Theme.border : Theme.background.opacity(0.3), in: RoundedRectangle(cornerRadius: 5))
    }
}
