//
//  HomeContainerView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/20/26.
//


import SwiftUI

struct HomeContainerView: View {

    @EnvironmentObject var accounts: AccountManager

    var body: some View {

        // позже тут будет логика по подразделению
        // сейчас — базовый Home

        HomeView()
    }
}