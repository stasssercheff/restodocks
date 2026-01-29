//
//  QuickActionView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/20/26.
//


import SwiftUI

struct QuickActionView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("quick_action"))
            .font(.largeTitle)
    }
}