import SwiftUI
import SumiCore

struct FloatingOutline: View {
    @ObservedObject var workspace: Workspace
    let availableMargin: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var dismissTask: Task<Void, Never>?
    private var expanded: Bool { hovering || workspace.sidePanel == .outline }
    private var current: Int? { workspace.outline.last { $0.offset <= workspace.selection.location }?.id }

    var body: some View {
        if !workspace.outline.isEmpty || workspace.sidePanel == .outline {
            VStack(alignment: .leading, spacing: 0) {
                if expanded {
                    Text("文章脉络").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                        .padding(.leading, 17).padding(.top, 12).padding(.bottom, 10)
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                if workspace.outline.isEmpty {
                                    Text("用 = 写下第一个标题").font(.system(size: 11)).foregroundStyle(Theme.muted).padding(14)
                                }
                                ForEach(workspace.outline) { item in
                                    Button { workspace.jump(to: item.offset) } label: {
                                        HStack(spacing: 8) {
                                            Capsule().fill(item.id == current ? Theme.accent.opacity(0.8) : Color.clear).frame(width: 2, height: 11)
                                            Text(item.title).font(.system(size: 11, weight: item.id == current ? .medium : .regular))
                                                .lineLimit(2).multilineTextAlignment(.leading)
                                            Spacer(minLength: 0)
                                        }.foregroundStyle(item.id == current ? Theme.text : Theme.secondary)
                                            .padding(.leading, CGFloat(12 + min(item.level - 1, 3) * 8)).padding(.trailing, 12).padding(.vertical, 9)
                                            .contentShape(Rectangle())

                                    }.buttonStyle(.plain).id(item.id)
                                }
                            }.padding(5)
                        }.frame(height: min(350, max(52, CGFloat(workspace.outline.count) * 42 + 10)))
                            .onAppear { if let current { proxy.scrollTo(current) } }
                    }
                } else {
                    Button { workspace.sidePanel = .outline } label: {
                        VStack(alignment: .leading, spacing: 11) {
                            ForEach(Array(workspace.outline.prefix(14))) { item in
                                Capsule().fill(item.id == current ? Theme.accent.opacity(0.8) : Theme.muted.opacity(0.45))
                                    .frame(width: item.level == 1 ? 16 : 9, height: 2)
                            }
                        }.padding(.horizontal, 7).padding(.vertical, 15).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("展开文章脉络")
                }
            }
            .frame(width: expanded ? min(224, max(180, availableMargin - 28)) : 30, alignment: .leading)
            .background {
                if expanded {
                    // Opaque beside the text on narrow windows, blending into the
                    // existing margin on wide ones. No card, border or drop shadow.
                    LinearGradient(stops: [.init(color: Theme.editor, location: 0), .init(color: Theme.editor, location: 0.88), .init(color: Theme.editor.opacity(0), location: 1)], startPoint: .leading, endPoint: .trailing)
                }
            }
            .onHover { inside in
                dismissTask?.cancel()
                if inside { hovering = true }
                else {
                    dismissTask = Task {
                        do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                        hovering = false
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: expanded)
            .onDisappear { dismissTask?.cancel() }
        }
    }
}
