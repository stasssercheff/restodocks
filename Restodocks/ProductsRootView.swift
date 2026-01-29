//
//  ProductsRootView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 12/22/25.
//


import SwiftUI

struct ProductsRootView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var pro: ProAccess
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            // Номенклатура (стартовая база + свои). Источник для ТТК и инвентаризации.
            Section(header: Text(lang.t("nomenclature"))) {
                NavigationLink {
                    ProductCatalogView(department: "kitchen", titleOverride: "nomenclature")
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text(lang.t("nomenclature"))
                    }
                }
            }

            // Kitchen Products
            Section(header: Text(lang.t("kitchen_title"))) {
                NavigationLink {
                    KitchenProductsView()
                } label: {
                    Text(lang.t("kitchen"))
                }
            }
            
            // Bar Products
            Section(header: Text(lang.t("bar"))) {
                NavigationLink {
                    BarProductsView()
                } label: {
                    Text(lang.t("bar"))
                }
            }
            
            // Household Supplies
            Section(header: Text(lang.t("household_supplies"))) {
                NavigationLink {
                    HouseholdSuppliesView()
                } label: {
                    Text(lang.t("household_supplies"))
                }
            }

            // Tech Cards (только для шеф-повара и выше)
            if appState.canManageSchedule {
                Section(header: Text(lang.t("tech_cards"))) {
                    NavigationLink {
                        TechCardEditorView()
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.fill")
                            Text(lang.t("create_tech_card"))
                        }
                    }
                }
            }
        }
        .navigationTitle(lang.t("products"))
    }
}