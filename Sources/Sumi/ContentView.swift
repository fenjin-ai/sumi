import SwiftUI
import SumiCore

struct ContentView: View {
    @ObservedObject var workspace: Workspace
    @State private var splitFraction: CGFloat = 0.5

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if workspace.sidePanel == .diagnostics { diagnosticSidebar.frame(width: 224); divider }
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let editorWidth = workspace.layout == .writing ? width : (workspace.layout == .preview ? 0 : max(280, min(width - 280, width * splitFraction)))
                    HStack(spacing: 0) {
                        manuscript.frame(width: editorWidth).clipped()
                            .overlay(alignment: .topLeading) {
                                if workspace.layout != .preview {
                                    FloatingOutline(workspace: workspace, availableMargin: max(36, (editorWidth - 740) / 2))
                                        .padding(.leading, 14).padding(.top, 64)
                                }
                            }
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
        .sheet(isPresented: $workspace.universeOpen) {
            UniverseBrowser(cacheURL: workspace.stateDirectory.appendingPathComponent("universe-index.json"), onImport: workspace.importPackage)
        }
    }

    private var divider: some View { Rectangle().fill(Theme.border.opacity(0.55)).frame(width: 1) }

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
                Button(workspace.previewDark ? "深色" : "原色") { workspace.previewDark.toggle() }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(workspace.previewDark ? Theme.accent : Theme.secondary)
                    .learningHelp("成稿阅读配色", shortcut: "⌘\(workspace.commandKey.uppercased()) → v n", detail: "只调整阅读配色，不影响导出的 PDF。")
                Button("−") { workspace.previewZoom = max(0.5, workspace.previewZoom - 0.1) }.buttonStyle(.plain).learningHelp("缩小预览")
                Text("\(Int((workspace.previewZoom * 100).rounded()))%").font(.system(size: 10, design: .monospaced)).frame(width: 38)
                Button("+") { workspace.previewZoom = min(2, workspace.previewZoom + 0.1) }.buttonStyle(.plain).learningHelp("放大预览")
            }.foregroundStyle(Theme.secondary).padding(.horizontal, 24).frame(height: 48)
            if let url = workspace.previewURL {
                if workspace.previewStale {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.accent).frame(width: 4, height: 4)
                        Text(workspace.hasSuccessfulPreview ? "显示上次成功的成稿 · 等待当前修改完成排版" : "等待文稿首次成功排版")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        Spacer()
                        if workspace.diagnostics.contains(where: { $0.severity == 1 }) {
                            Button("检查源码") { workspace.sidePanel = .diagnostics }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.accent)
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 10)
                }
                PreviewView(url: url, zoom: workspace.previewZoom, dark: workspace.previewDark) { workspace.showMessage($0, persistent: true) }
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

    private var diagnosticSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("文稿检查").font(.system(size: 12, weight: .semibold))
                Spacer()
                QuietButton(icon: "x", help: "关闭侧栏") { workspace.sidePanel = nil }
            }.padding(.horizontal, 18).padding(.top, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
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
            }.buttonStyle(.plain).accessibilityLabel("发现命令 ⌘\(workspace.commandKey.uppercased())").learningHelp("发现命令", shortcut: "⌘\(workspace.commandKey.uppercased())", detail: "按字母逐层发现，按 / 搜索所有命令。")
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
