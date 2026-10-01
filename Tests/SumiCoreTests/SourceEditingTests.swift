import Foundation
import Testing
@testable import SumiCore

@Test func sourceDecorationRespectsCodeMathAndIncompleteInput() {
    let source = """
    = 中文😀标题
    *bold* and _italic_ and `literal *stars*`.
    $ x * y _ z $
    ```typ
    = not a heading
    *not bold*
    ```
    // *comment*
    /* outer /* _nested_ */ *comment* */
    #let example = [
      *code content*
    ]
    plain_word and \\*escaped*.
    """
    let decorated = SourcePresentation.decorations(in: source)
    #expect(decorated.map(\.kind) == [.heading(1), .strong, .emphasis, .code])
    #expect(decorated.map { (source as NSString).substring(with: $0.range) } == ["= 中文😀标题", "*bold*", "_italic_", "`literal *stars*`"])
    for unfinished in ["```\n*unfinished*", "$ unfinished *bold*", "/* *comment*", "#let x = [\n*unfinished*"] {
        #expect(SourcePresentation.decorations(in: unfinished).isEmpty)
    }
    #expect(SourcePresentation.decorations(in: "Text \\$ *real* after").contains { $0.kind == .strong })
    #expect(SourcePresentation.decorations(in: "Text ``literal ` code`` after").isEmpty)
    #expect(SourcePresentation.decorations(in: "* unfinished ").isEmpty)
    let active = SourcePresentation.activeParagraph(in: source, selection: NSRange(location: 4, length: 0))
    #expect((source as NSString).substring(with: active) == "= 中文😀标题\n")
    #expect(SourcePresentation.activeParagraph(in: "", selection: NSRange(location: 80, length: 1)) == NSRange(location: 0, length: 0))
}

@Test func lineEditingPreservesSelectionBoundariesAndUnicode() throws {
    let source = "中文😀\n  second\nthird\n"
    let selected = NSRange(location: 0, length: "中文😀\n  second\n".utf16.count)
    let indent = TextEditing.lines(.indent, text: source, selection: selected)
    let indented = try TextEditing.applying([indent], to: source)
    #expect(indented == "  中文😀\n    second\nthird\n")
    let outdent = TextEditing.lines(.outdent, text: indented, selection: NSRange(location: 0, length: indent.text.utf16.count))
    #expect(try TextEditing.applying([outdent], to: indented) == source)
    let comment = TextEditing.lines(.comment, text: source, selection: selected)
    #expect(comment.text == "// 中文😀\n  // second\n")
    let commented = try TextEditing.applying([comment], to: source)
    let uncomment = TextEditing.lines(.comment, text: commented, selection: NSRange(location: 0, length: comment.text.utf16.count))
    #expect(try TextEditing.applying([uncomment], to: commented) == source)
    #expect(TextEditing.lines(.outdent, text: "\tx", selection: NSRange(location: 0, length: 0)).text == "x")
    #expect(TextEditing.lines(.outdent, text: " x", selection: NSRange(location: 0, length: 0)).text == "x")
    #expect(TextEditing.lines(.comment, text: "// a\n  \n//b", selection: NSRange(location: 0, length: 12)).text == "a\n  \nb")
    #expect(TextEditing.lines(.indent, text: "", selection: NSRange(location: 200, length: 0)).text == "  ")
    #expect(try TextEditing.applying([.init(range: NSRange(location: 0, length: 1), text: "A"), .init(range: NSRange(location: 2, length: 1), text: "C")], to: "abc") == "AbC")
    #expect(throws: CommandError.self) { try TextEditing.applying([.init(range: NSRange(location: 99, length: 1), text: "x")], to: "abc") }
    #expect(throws: CommandError.self) { try TextEditing.applying([.init(range: NSRange(location: 0, length: 3), text: "x"), .init(range: NSRange(location: 2, length: 1), text: "y")], to: "abc") }
}
