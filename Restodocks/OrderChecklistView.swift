//
//  OrderChecklistView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 12/23/25.
//


import SwiftUI

struct OrderChecklistView: View {
    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {
        Text(lang.t("order_checklist"))
            .font(.largeTitle)
            .navigationTitle(lang.t("order_checklist"))
    }
}