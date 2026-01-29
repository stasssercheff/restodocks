//
//  BakeryView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/6/26.
//


import SwiftUI

struct BakeryView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("bakery"))
            .navigationTitle(lang.t("bakery"))
    }
}