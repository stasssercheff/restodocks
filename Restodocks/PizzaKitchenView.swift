//
//  PizzaKitchenView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/6/26.
//


import SwiftUI

struct PizzaKitchenView: View {
    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {
        List {
            NavigationLink { PizzaMenuView() } label: { Text(lang.t("menu")) }
            NavigationLink { PizzaTTKView() } label: { Text(lang.t("ttk")) }
            NavigationLink { PizzaScheduleView() } label: { Text(lang.t("schedule")) }
        }
        .navigationTitle(lang.t("pizza"))
    }
}