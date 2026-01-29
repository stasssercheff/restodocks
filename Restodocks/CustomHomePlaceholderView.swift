//
//  CustomHomePlaceholderView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/20/26.
//


import SwiftUI

struct CustomHomePlaceholderView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "star")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text(lang.t("custom_button_placeholder"))
                .foregroundColor(.secondary)
        }
        .navigationTitle(lang.t("favorites_title"))
    }
}