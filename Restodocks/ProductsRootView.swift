//
//  ProductsRootView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 12/22/25.
//


import SwiftUI

struct ProductsRootView: View {

    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {
        List {
            NavigationLink {
                KitchenProductsView()
            } label: {
                Text(lang.t("kitchen"))
            }
        }
        .navigationTitle(lang.t("products"))
    }
}