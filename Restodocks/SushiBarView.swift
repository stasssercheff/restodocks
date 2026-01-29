//
//  SushiBarView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/6/26.
//

import SwiftUI

struct SushiBarView: View {
    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {
        List {
            NavigationLink {
                SushiBarMenuView()
            } label: {
                Text(lang.t("menu"))
            }

            NavigationLink {
                SushiBarTTKView()
            } label: {
                Text(lang.t("ttk"))
            }

            NavigationLink {
                SushiBarScheduleView()
            } label: {
                Text(lang.t("schedule"))
            }
        }
        .navigationTitle(lang.t("sushi_bar"))
    }
}
