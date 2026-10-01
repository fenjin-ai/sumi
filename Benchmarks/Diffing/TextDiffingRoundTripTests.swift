import Testing
@testable import TextDiffing

@Test func generatedEditsRoundTrip() {
    var state: UInt64 = 42
    func text() -> String {
        var text = ""
        for _ in 0..<18 {
            state = state &* 6364136223846793005 &+ 1
            text.append(Array("abc #$\n")[Int(state >> 32) % 7])
        }
        return text
    }
    for _ in 0..<500 {
        let old = text(), new = text()
        let tokenizer = CharacterStringTokenizer()
        let parts = tokenizer.tokenize(new).diffSegments(comparingWith: tokenizer.tokenize(old))
        let recoveredOld = parts.filter { $0.type != .inserted }.map(\.element).joined()
        let recoveredNew = parts.filter { $0.type != .removed }.map(\.element).joined()
        guard recoveredOld == old, recoveredNew == new else {
            Issue.record("before=\(String(reflecting:old)) after=\(String(reflecting:new)) recoveredBefore=\(String(reflecting:recoveredOld)) recoveredAfter=\(String(reflecting:recoveredNew))")
            return
        }
    }
}
