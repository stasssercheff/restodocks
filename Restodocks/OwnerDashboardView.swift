import SwiftUI

struct OwnerDashboardView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        List {
            // === КУХНЯ ===
            Section(header: Text("🍳 Кухня")) {
                NavigationLink {
                    KitchenScheduleView() // Показывает все отделы кухни
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                        Text("График кухни")
                    }
                }

                NavigationLink {
                    KitchenRootView()
                } label: {
                    HStack {
                        Image(systemName: "book")
                        Text("Номенклатура кухни")
                    }
                }

                NavigationLink {
                    KitchenRootView()
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("ТТК кухни")
                    }
                }
            }

            // === БАР ===
            Section(header: Text("🍸 Бар")) {
                NavigationLink {
                    ScheduleView(department: "bar")
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                        Text("График бара")
                    }
                }

                NavigationLink {
                    BarProductsView()
                } label: {
                    HStack {
                        Image(systemName: "book")
                        Text("Номенклатура бара")
                    }
                }

                NavigationLink {
                    BarTTKView()
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("ТТК бара")
                    }
                }
            }

            // === ЗАЛ ===
            Section(header: Text("🍽️ Зал")) {
                NavigationLink {
                    ScheduleView(department: "dining_room")
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                        Text("График зала")
                    }
                }

                NavigationLink {
                    HouseholdSuppliesView()
                } label: {
                    HStack {
                        Image(systemName: "book")
                        Text("Номенклатура зала")
                    }
                }

                NavigationLink {
                    HouseholdSuppliesView()
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("ТТК зала")
                    }
                }
            }
        }
        .navigationTitle("Панель собственника")
    }
}