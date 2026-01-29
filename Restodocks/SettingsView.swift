import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var lang: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {

                Section(header: Text(lang.t("language"))) {
                    languageRow(title: lang.t("russian"), code: "ru")
                    languageRow(title: "English", code: "en")
                    languageRow(title: "Español", code: "es")
                    languageRow(title: "Deutsch", code: "de")
                    languageRow(title: "Français", code: "fr")
                }

                Section {
                    NavigationLink {
                        Text("PRO")
                    } label: {
                        HStack {
                            Text("PRO")
                            Spacer()
                            Text(lang.t("pro_active"))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(lang.t("settings"))
            .toolbar {

                // ✅ КНОПКА ЗАКРЫТИЯ
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(lang.t("close")) {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func languageRow(title: String, code: String) -> some View {
        Button {
            lang.setLang(code)
        } label: {
            HStack {
                Text(title)
                Spacer()
                if lang.currentLang == code {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}
