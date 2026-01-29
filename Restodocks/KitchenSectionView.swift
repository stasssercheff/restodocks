//
//  KitchenSectionView.swift
//  Restodocks
//

import SwiftUI

struct KitchenSectionView: View {

    let section: KitchenSection
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        List {
            
            // Menu (by section) - view only
            NavigationLink {
                menuView(for: section)
            } label: {
                HStack {
                    Image(systemName: "book.fill")
                        .foregroundColor(.blue)
                    Text(lang.t("menu"))
                    Text("(\(lang.t("view_only")))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Recipe Cards (by section) - view with recalculation by key product
            NavigationLink {
                ttkView(for: section)
            } label: {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.orange)
                    Text(lang.t("recipe_cards"))
                    Text("(\(lang.t("with_recalculation")))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Schedule (by section) - view only
            NavigationLink {
                scheduleView(for: section)
            } label: {
                HStack {
                    Image(systemName: "calendar.fill")
                        .foregroundColor(.green)
                    Text(lang.t("schedule"))
                    Text("(\(lang.t("view_only")))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(lang.t(titleKey))
    }
    
    @ViewBuilder
    private func menuView(for section: KitchenSection) -> some View {
        switch section {
        case .hotKitchen:
            HotKitchenMenuView()
        case .coldKitchen:
            ColdKitchenMenuView()
        case .pizza:
            PizzaMenuView()
        case .sushiBar:
            SushiBarMenuView()
        case .bakery:
            PastryKitchenView()
        case .grill:
            GrillView()
        default:
            Text(lang.t("menu"))
                .navigationTitle(lang.t("menu"))
        }
    }
    
    @ViewBuilder
    private func scheduleView(for section: KitchenSection) -> some View {
        // All sections now use the unified KitchenScheduleView
        KitchenScheduleView()
    }
    
    @ViewBuilder
    private func ttkView(for section: KitchenSection) -> some View {
        switch section {
        case .hotKitchen:
            HotKitchenTTKView()
        case .coldKitchen:
            ColdKitchenTTKView()
        case .pizza:
            PizzaTTKView()
        case .sushiBar:
            SushiBarTTKView()
        case .bakery:
            BarTTKView()
        case .grill:
            GrillView()
        default:
            Text(lang.t("ttk"))
                .navigationTitle(lang.t("ttk"))
        }
    }

    private var titleKey: String {
        switch section {
        case .hotKitchen:
            return "hot_kitchen"
        case .coldKitchen:
            return "cold_kitchen"
        case .prep:
            return "prep"
        case .pastry:
            return "pastry"
        case .grill:
            return "grill"
        case .pizza:
            return "pizza"
        case .sushiBar:
            return "sushi_bar"
        case .bakery:
            return "bakery"
        case .cleaning:
            return "cleaning"
        case .kitchenManagement:
            return "kitchen_management"
        }
    }
}
