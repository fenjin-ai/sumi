import Foundation
import Testing
@testable import LeftBlankCore

@Test func bundledLanguagesResolveWithoutChangingSystemSettings() throws {
    #expect(AppLanguage.resolve(.system, preferredLanguages: ["en-GB"]) == .english)
    #expect(AppLanguage.resolve(.system, preferredLanguages: ["zh-Hans-CN"]) == .simplifiedChinese)
    #expect(AppLanguage.resolve(.system, preferredLanguages: ["fr-FR"]) == .english)
    #expect(AppLanguage.resolve(.english, preferredLanguages: ["zh-Hans"]) == .english)
    #expect(L10n.text("Table", language: .english) == "Table")
    #expect(L10n.text("Table", language: .simplifiedChinese) == "表格")
    #expect(L10n.text("An untranslated future label", language: .simplifiedChinese) == "An untranslated future label")
    #expect(WelcomeDocument.source(language: .english).contains("= Ink for your thoughts"))
    #expect(WelcomeDocument.source(language: .simplifiedChinese).contains("= 留白"))
    #expect(L10n.text("LeftBlank", language: .english) == "LeftBlank")
    #expect(L10n.text("LeftBlank", language: .simplifiedChinese) == "留白")
    #expect(L10n.text("Ink for your thoughts", language: .simplifiedChinese) == "此中有真意，欲辨已忘言")
    let english = try TypstInsertion.make("table", values: ["columns": "2", "rows": "1"], language: .english)
    let chinese = try TypstInsertion.make("table", values: ["columns": "2", "rows": "1"], language: .simplifiedChinese)
    #expect(english.selections.count == chinese.selections.count)
    #expect((english.text as NSString).substring(with: english.selections[0]) == "Heading 1")
    #expect((chinese.text as NSString).substring(with: chinese.selections[0]) == "标题 1")
    for language in [AppLanguage.english, .simplifiedChinese] {
        let literal = "My title 中文😀"
        #expect(try TypstInsertion.make("heading", selection: literal, language: language).text == "= " + literal)
        #expect(try TypstInsertion.make("contents", language: language).text.contains("#outline(title:"))
    }
}
