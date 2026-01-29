//
//  KitchenProductsView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 12/22/25.
//


import SwiftUI

struct KitchenProductsView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var pro: ProAccess

    var body: some View {
        List {

            // Suppliers
            NavigationLink {
                SuppliersView()
            } label: {
                Text(lang.t("suppliers"))
            }

            // Product list with prices (and calories/macros – pro)
            NavigationLink {
                ProductCatalogView()
            } label: {
                if pro.isPro {
                    Text("\(lang.t("product_list_prices")) (\(lang.t("with_calories_macros")))")
                } else {
                    Text(lang.t("product_list_prices"))
                }
            }

            // Order checklist (with sending function via email – pro)
            if pro.isPro {
                NavigationLink {
                    OrderChecklistView()
                } label: {
                    Text(lang.t("order_checklist"))
                }
            } else {
                NavigationLink {
                    ProUnlockView()
                } label: {
                    HStack {
                        Text(lang.t("order_checklist"))
                        Spacer()
                        Text("PRO")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

        }
        .navigationTitle("\(lang.t("kitchen_title")) - \(lang.t("products"))")
    }
}