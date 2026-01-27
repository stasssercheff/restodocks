//
//  CompanySettingsView.swift
//  Restodocks
//

import SwiftUI

struct CompanySettingsView: View {

    @EnvironmentObject var accounts: AccountManager

    var body: some View {

        Form {

            if let company = accounts.establishment {

                Section(header: Text("Компания")) {
                    HStack {
                        Text("Название")
                        Spacer()
                        Text(company.name ?? "—")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("PIN-код компании")) {
                    HStack {
                        Text("PIN")
                        Spacer()
                        Text(company.pinCode ?? "—")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Text("Используется при регистрации сотрудников")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            } else {
                Text("Компания не найдена")
                    .foregroundColor(.red)
            }
        }
        .navigationTitle("Компания")
    }
}