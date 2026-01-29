//
//  AdministrativeView.swift
//  Restodocks
//

import SwiftUI

struct AdministrativeView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        List {
            Text(lang.t("administrative_section"))
                .foregroundColor(.secondary)
        }
        .navigationTitle(lang.t("administrative"))
    }
}
