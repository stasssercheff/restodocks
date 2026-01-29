//
//  TTKView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 12/22/25.
//


import SwiftUI

struct TTKView: View {
    @ObservedObject var lang = LocalizationManager.shared
    @EnvironmentObject var pro: ProAccess

    var body: some View {
        List {
            
            // ===== ОБЩИЕ ЦЕХА =====
            Section(header: Text(lang.t("standard_sections"))) {
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
            }
            
            // ===== PRO ЦЕХА =====
            Section(header: Text(lang.t("pro_sections"))) {
                if pro.isPro {
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
                    
                    NavigationLink {
                        BarTTKView()
                    } label: {
                        Text(lang.t("bar"))
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
                }
            }
        }
        .navigationTitle(lang.t("ttk"))
    }
}