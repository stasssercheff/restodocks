//
//  KitchenRootView.swift
//  Restodocks
//

import SwiftUI

struct KitchenRootView: View {

    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var pro: ProAccess

    var body: some View {
        List {

            // ===== MAIN KITCHEN (View Only) =====
            Section(header: Text(lang.t("kitchen_main"))) {
                NavigationLink {
                    KitchenScheduleView() // Entire kitchen schedule (view only)
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                        Text(lang.t("schedule"))
                        Text("(\(lang.t("view_only")))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                NavigationLink {
                    KitchenMenuView() // All menu (view only)
                } label: {
                    HStack {
                        Image(systemName: "book")
                        Text(lang.t("menu"))
                        Text("(\(lang.t("view_only")))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // ===== KITCHEN SECTIONS =====
            Section(header: Text(lang.t("kitchen_sections"))) {
                // Hot Kitchen (Hot Section)
            NavigationLink {
                KitchenSectionView(section: .hotKitchen)
            } label: {
                Text(lang.t("hot_kitchen"))
            }

                // Cold Kitchen (Cold Section)
            NavigationLink {
                KitchenSectionView(section: .coldKitchen)
            } label: {
                Text(lang.t("cold_kitchen"))
            }

                // Prep Section
                NavigationLink {
                    KitchenSectionView(section: .prep)
                } label: {
                    Text(lang.t("prep"))
                }

                // Pastry
                NavigationLink {
                    KitchenSectionView(section: .pastry)
                } label: {
                    Text(lang.t("pastry"))
                }

                // PRO SECTIONS
                if pro.isPro {
                    // Grill
                    NavigationLink {
                        KitchenSectionView(section: .grill)
                    } label: {
                        Text(lang.t("grill"))
                    }

                    // Pizza
                    NavigationLink {
                        KitchenSectionView(section: .pizza)
                    } label: {
                    Text(lang.t("pizza"))
                }

                    // Sushi Bar
                NavigationLink {
                    KitchenSectionView(section: .sushiBar)
                } label: {
                    Text(lang.t("sushi_bar"))
                }

                    // Bakery
                NavigationLink {
                    KitchenSectionView(section: .bakery)
                } label: {
                    Text(lang.t("bakery"))
                }
            } else {
                    // PRO Locked
                NavigationLink {
                    ProUnlockView()
                } label: {
                    Text("\(lang.t("grill")) (PRO)")
                }

                NavigationLink {
                    ProUnlockView()
                } label: {
                    Text("\(lang.t("pizza")) (PRO)")
                }

                NavigationLink {
                    ProUnlockView()
                } label: {
                    Text("\(lang.t("sushi_bar")) (PRO)")
                }

                NavigationLink {
                    ProUnlockView()
                } label: {
                    Text("\(lang.t("bakery")) (PRO)")
                }
            }
            }
        }
        .navigationTitle(lang.t("kitchen_title"))
    }
}
