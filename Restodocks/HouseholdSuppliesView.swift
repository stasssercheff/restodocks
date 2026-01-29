//
//  HouseholdSuppliesView.swift
//  Restodocks
//

import SwiftUI

struct HouseholdSuppliesView: View {
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
            
            // Product list with prices
            NavigationLink {
                ProductCatalogView()
            } label: {
                Text(lang.t("product_list_prices"))
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
        .navigationTitle(lang.t("household_supplies"))
    }
}
