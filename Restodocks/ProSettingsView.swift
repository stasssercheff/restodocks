//
//  ProSettingsView.swift
//  Restodocks
//
//  Настройки PRO: статус и ввод промокода в одном экране.
//

import SwiftUI

struct ProSettingsView: View {
    @EnvironmentObject var pro: ProAccess
    @EnvironmentObject var lang: LocalizationManager

    @State private var code: String = ""
    @State private var wrongCode: Bool = false

    var body: some View {
        List {
            // Статус PRO
            Section {
                HStack {
                    Image(systemName: pro.isPro ? "crown.fill" : "crown")
                        .foregroundColor(pro.isPro ? AppTheme.accent : .secondary)
                    Text(pro.isPro ? lang.t("pro_active") : lang.t("pro_not_active"))
                        .foregroundColor(pro.isPro ? .primary : .secondary)
                }
            }

            // Ввод промокода (всегда доступен — для активации или повторной активации)
            Section(header: Text(lang.t("promo_code"))) {
                TextField(lang.t("enter_code"), text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                if wrongCode {
                    Text(lang.t("wrong_code"))
                        .foregroundColor(AppTheme.error)
                        .font(.caption)
                }

                Button(lang.t("activate")) {
                    if pro.activateWithCode(code) {
                        wrongCode = false
                        code = ""
                    } else {
                        wrongCode = true
                    }
                }
                .disabled(code.isEmpty)
            }
        }
        .navigationTitle("PRO")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    popCurrentNavigationToRoot()
                } label: {
                    Image(systemName: "house.fill")
                }
                .accessibilityLabel(lang.t("home"))
            }
        }
    }
}
