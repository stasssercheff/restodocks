//
//  ExecutiveChefView.swift
//  Restodocks
//

import SwiftUI

struct ExecutiveChefView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var pro: ProAccess

    var body: some View {
        List {
            // Kitchen schedule (with editing capability)
            NavigationLink {
                ScheduleView() // TODO: Add editing capability for Executive Chef
            } label: {
                HStack {
                    Image(systemName: "calendar.badge.exclamationmark")
                    Text(lang.t("kitchen_schedule_editable"))
                }
            }

            // Recipe Cards section
            Section(header: Text(lang.t("recipe_cards"))) {
                NavigationLink {
                    KitchenRootView() // All kitchen sections for recipe cards
                } label: {
                    Text(lang.t("kitchen_title"))
                }
                
                NavigationLink {
                    HotKitchenTTKView()
                } label: {
                    Text(lang.t("hot_kitchen"))
                }
                
                NavigationLink {
                    ColdKitchenTTKView()
                } label: {
                    Text(lang.t("cold_kitchen"))
                }
                
                if pro.isPro {
                    NavigationLink {
                        PizzaTTKView()
                    } label: {
                        Text(lang.t("grill"))
                    }
                    
                    NavigationLink {
                        PizzaTTKView()
                    } label: {
                        Text(lang.t("pizza"))
                    }
                    
                    NavigationLink {
                        SushiBarTTKView()
                    } label: {
                        Text(lang.t("sushi_bar"))
                    }
                }
                
                NavigationLink {
                    KitchenSectionView(section: .prep)
                } label: {
                    Text(lang.t("prep"))
                }
                
                NavigationLink {
                    KitchenSectionView(section: .pastry)
                } label: {
                    Text(lang.t("pastry"))
                }
                
                if pro.isPro {
                    NavigationLink {
                        KitchenSectionView(section: .bakery)
                    } label: {
                        Text(lang.t("bakery"))
                    }
                }
            }
        }
        .navigationTitle(lang.t("executive_chef"))
    }
}
