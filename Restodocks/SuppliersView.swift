//
//  SuppliersView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 12/23/25.
//


import SwiftUI

struct SuppliersView: View {
    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {
        Text(lang.t("suppliers"))
            .font(.largeTitle)
            .navigationTitle(lang.t("suppliers"))
    }
}