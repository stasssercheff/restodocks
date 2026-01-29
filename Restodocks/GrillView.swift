//
//  GrillView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/6/26.
//


import SwiftUI

struct GrillView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("grill"))
            .navigationTitle(lang.t("grill"))
    }
}