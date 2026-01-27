//
//  KitchenProductsView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 12/22/25.
//


import SwiftUI

struct KitchenProductsView: View {

    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {
        List {

            NavigationLink {
                SuppliersView()
            } label: {
                Text(lang.t("suppliers"))
            }

            NavigationLink {
                ProductCatalogView()
            } label: {
                Text(lang.t("product_catalog"))
            }

            NavigationLink {
                OrderChecklistView()
            } label: {
                Text(lang.t("order_checklist"))
            }

        }
        .navigationTitle(lang.t("kitchen"))
    }
}