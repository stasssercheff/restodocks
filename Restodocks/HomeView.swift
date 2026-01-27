// HomeView.swift
import SwiftUI

struct HomeView: View {

    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {
        List {

            NavigationLink {
                KitchenRootView()
            } label: {
                HomeButton(title: lang.t("kitchen_title"))
            }

            NavigationLink {
                BarView()
            } label: {
                HomeButton(title: lang.t("bar"))
            }

            NavigationLink {
                HallView()
            } label: {
                HomeButton(title: lang.t("hall"))
            }

            NavigationLink {
                ManagementView()
            } label: {
                HomeButton(title: lang.t("management"))
            }

            NavigationLink {
                ProductsRootView()
            } label: {
                HomeButton(title: lang.t("products"))
            }

            NavigationLink {
                StaffView()
            } label: {
                HomeButton(title: lang.t("staff"))
            }
        }
        .navigationTitle(lang.t("app_name"))
    }
}
