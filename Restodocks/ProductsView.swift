
import SwiftUI

struct InventoryView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("inventory"))
            .font(.largeTitle)
            .padding()
            .navigationTitle(lang.t("inventory"))
    }
}//
//  ProductsView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 12/19/25.
//


import SwiftUI

struct ProductsView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("products"))
            .font(.largeTitle)
            .padding()
            .navigationTitle(lang.t("products"))
    }
}
