// HomeView.swift
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var pro: ProAccess
    @EnvironmentObject var accounts: AccountManager
    @EnvironmentObject var appState: AppState

    private var currentEmployee: Employee? {
        accounts.currentEmployee ?? appState.currentEmployee
    }

    /// Шеф-повар или су-шеф — показываем отдельные кнопки ТТК
    private var isChefOrSousChef: Bool {
        guard let emp = currentEmployee else { return false }
        return emp.rolesArray.contains("executive_chef") || emp.rolesArray.contains("sous_chef")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // ТТК и Просмотр ТТК — для шеф/су-шеф
                if isChefOrSousChef {
                    NavigationLink {
                        TTKView()
                    } label: {
                        HomeButton(title: lang.t("ttk"))
                    }

                    NavigationLink {
                        DepartmentTTKView(department: "kitchen")
                    } label: {
                        HomeButton(title: lang.t("view_ttk"))
                    }
                }

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

                // Products — скрыто
                // NavigationLink {
                //     ProductsRootView()
                // } label: {
                //     HomeButton(title: lang.t("products"))
                // }

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
