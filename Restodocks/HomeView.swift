// HomeView.swift
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var pro: ProAccess

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Kitchen
                NavigationLink {
                    KitchenRootView()
                } label: {
                    HomeButton(title: lang.t("kitchen_title"))
                }

                // Bar
                NavigationLink {
                    BarView()
                } label: {
                    HomeButton(title: lang.t("bar"))
                }

                // Dining Room
                NavigationLink {
                    HallView()
                } label: {
                    HomeButton(title: lang.t("dining_room"))
                }

                // Management
                NavigationLink {
                    ManagementView()
                } label: {
                    HomeButton(title: lang.t("management"))
                }

                // Products
                NavigationLink {
                    ProductsRootView()
                } label: {
                    HomeButton(title: lang.t("products"))
                }

                // Employees
                NavigationLink {
                    StaffView()
                } label: {
                HomeButton(title: lang.t("staff"))
            }

            // Inventory (pro)
            if pro.isPro {
                NavigationLink {
                    Text(lang.t("inventory"))
                        .navigationTitle(lang.t("inventory"))
                } label: {
                    HomeButton(title: lang.t("inventory"), isPro: true)
                }
            } else {
                NavigationLink {
                    ProUnlockView()
                } label: {
                    HomeButton(title: lang.t("inventory"), isPro: true)
                }
            }

            // Administrative (pro)
            if pro.isPro {
                NavigationLink {
                    AdministrativeView()
                } label: {
                    HomeButton(title: lang.t("administrative"), isPro: true)
                }
            } else {
                NavigationLink {
                    ProUnlockView()
                } label: {
                    HomeButton(title: lang.t("administrative"), isPro: true)
                }
            }

                // Settings
                NavigationLink {
                    SettingsView()
                } label: {
                    HomeButton(title: lang.t("settings"))
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(lang.t("app_name"))
    }
}
