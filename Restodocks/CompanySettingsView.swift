//
//  CompanySettingsView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/21/26.
//


//
//  CompanySettingsView.swift
//  Restodocks
//

import SwiftUI

struct CompanySettingsView: View {

    @EnvironmentObject var accounts: AccountManager
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {

        Form {

            if let company = accounts.establishment {

                Section(header: Text(lang.t("company_section"))) {
                    HStack {
                        Text(lang.t("name_label"))
                        Spacer()
                        Text(company.name ?? "—")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text(lang.t("company_pin"))) {
                    HStack {
                        Text("PIN")
                        Spacer()
                        Text(company.pinCode ?? "—")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Text(lang.t("used_for_registration"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            } else {
                Text(lang.t("company_not_found"))
                    .foregroundColor(.red)
            }
        }
        .navigationTitle(lang.t("company_title"))
    }
}