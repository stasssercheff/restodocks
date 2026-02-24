import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var pro: ProAccess
    @EnvironmentObject var accounts: AccountManager
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var currentEmployee: Employee? {
        accounts.currentEmployee ?? appState.currentEmployee
    }

    var body: some View {
        NavigationStack {
            List {

                // Переключатель: собственник ↔ должность (только если собственник с должностью)
                if let emp = currentEmployee, emp.isOwnerWithPosition, let position = emp.jobPosition {
                    Section(header: Text(lang.t("view_mode"))) {
                        Picker(lang.t("interface"), selection: Binding(
                            get: { appState.ownerViewMode },
                            set: { appState.ownerViewMode = $0 }
                        )) {
                            Text(lang.t("owner")).tag("owner")
                            Text(getPositionDisplayName(position)).tag("position")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section(header: Text("График")) {
                    Toggle("Показывать время в сменах", isOn: Binding(
                        get: { appState.showTimeInShifts },
                        set: { appState.showTimeInShifts = $0 }
                    ))
                }

                Section(header: Text(lang.t("language"))) {
                    languageRow(title: lang.t("russian"), code: "ru")
                    languageRow(title: "English", code: "en")
                    languageRow(title: "Español", code: "es")
                    languageRow(title: "Deutsch", code: "de")
                    languageRow(title: "Français", code: "fr")
                }

                Section(header: Text("PRO")) {
                    NavigationLink {
                        ProSettingsView()
                    } label: {
                        HStack {
                            Text("PRO")
                            Spacer()
                            Text(pro.isPro ? lang.t("pro_active") : lang.t("pro_not_active"))
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

    private func getPositionDisplayName(_ position: String) -> String {
        switch position {
        case "executive_chef": return lang.t("executive_chef")
        case "sous_chef": return lang.t("sous_chef")
        case "manager": return lang.t("manager")
        case "director": return lang.t("director")
        case "dining_manager": return lang.t("dining_manager")
        case "bar_manager": return "Бар-менеджер"
        default: return position.capitalized
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
