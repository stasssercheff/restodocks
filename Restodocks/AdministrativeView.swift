//
//  AdministrativeView.swift
//  Restodocks
//

import SwiftUI

struct AdministrativeView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        List {
            NavigationLink {
                PayrollView()
            } label: {
                HStack {
                    Image(systemName: "banknote")
                    Text(lang.t("payroll"))
                }
            }
        }
        .navigationTitle(lang.t("administrative"))
    }
}
