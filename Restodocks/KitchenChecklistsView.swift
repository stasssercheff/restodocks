//
//  KitchenChecklistsView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/20/26.
//


import SwiftUI

struct KitchenChecklistsView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("kitchen_checklists"))
            .navigationTitle(lang.t("checklists_title"))
    }
}