import SwiftUI
import SumiCore

@MainActor
final class AppLocalization: ObservableObject {
    static let shared = AppLocalization()
    @Published private(set) var language = L10n.language
    @Published private(set) var generation = 0
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .sumiLanguageChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.language != L10n.language else { return }
                self?.language = L10n.language
                self?.generation += 1
            }
        }
    }

    func select(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        generation += 1
        L10n.setLanguage(language)
    }
}

/// Embed in the app's Settings form alongside writing, library and agent preferences.
struct LanguageSettingsSection: View {
    @ObservedObject private var localization = AppLocalization.shared

    var body: some View {
        Section {
            Picker(L10n.text("App Language"), selection: Binding(get: { localization.language }, set: localization.select)) {
                ForEach(AppLanguage.allCases) { language in Text(language.displayName).tag(language) }
            }.accessibilityIdentifier("settings.language")
            Text(L10n.text("Changes apply immediately. Your writing stays in its original language."))
                .font(.footnote).foregroundStyle(Theme.secondary)
        } header: { Text(L10n.text("Language")) }
    }
}
