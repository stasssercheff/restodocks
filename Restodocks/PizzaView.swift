//
//  PizzaView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/6/26.
//


import SwiftUI

struct PizzaView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("pizza"))
            .navigationTitle(lang.t("pizza"))
    }
}