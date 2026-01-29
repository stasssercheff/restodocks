//
//  PersonalCabinetView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/20/26.
//


import SwiftUI

struct PersonalCabinetView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("personal_cabinet"))
            .font(.largeTitle)
    }
}