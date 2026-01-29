//
//  KitchenMenuView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/6/26.
//


import SwiftUI

struct KitchenMenuView: View {
    @ObservedObject var lang = LocalizationManager.shared
    @EnvironmentObject var pro: ProAccess

    var body: some View {
        List {
            
            // ===== ОБЩИЕ ЦЕХА =====
            Section(header: Text(lang.t("standard_sections"))) {
                NavigationLink {
                    HotKitchenMenuView()
                } label: {
                    Text(lang.t("hot_kitchen"))
                }
                
                NavigationLink {
                    ColdKitchenMenuView()
                } label: {
                    Text(lang.t("cold_kitchen"))
                }
            }
            
            // ===== PRO ЦЕХА =====
            Section(header: Text(lang.t("pro_sections"))) {
                if pro.isPro {
                    NavigationLink {
                        PizzaMenuView()
                    } label: {
                        Text(lang.t("pizza"))
                    }
                    
                    NavigationLink {
                        SushiBarMenuView()
                    } label: {
                        Text(lang.t("sushi_bar"))
                    }
                    
                    NavigationLink {
                        BarMenuView()
                    } label: {
                        Text(lang.t("bar"))
                    }
                    
                    NavigationLink {
                        PastryKitchenView()
                    } label: {
                        Text(lang.t("bakery"))
                    }
                } else {
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
                        Text("\(lang.t("bar")) (PRO)")
                    }
                    
                    NavigationLink {
                        ProUnlockView()
                    } label: {
                        Text("\(lang.t("bakery")) (PRO)")
                    }
                }
            }
        }
        .navigationTitle(lang.t("menu"))
    }
}