//
//  HotKitchenMenuView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/6/26.
//


import SwiftUI

struct HotKitchenMenuView: View {
    @EnvironmentObject var lang: LocalizationManager
    
    var body: some View {
        List {
            Text(lang.t("hot_kitchen"))
                .font(.headline)
            Text(lang.t("hot_kitchen_menu"))
                .foregroundColor(.secondary)
        }
        .navigationTitle(lang.t("menu"))
    }
}