import SwiftUI

struct DepartmentTTKView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var pro: ProAccess

    let department: String

    var body: some View {
        List {
            switch department {
            case "kitchen":
                kitchenTTKSection
            case "bar":
                barTTKSection
            case "dining_room":
                diningRoomTTKSection
            default:
                Text("Подразделение не найдено")
            }
        }
        .navigationTitle(departmentTitle)
    }

    private var departmentTitle: String {
        switch department {
        case "kitchen": return "ТТК кухни"
        case "bar": return "ТТК бара"
        case "dining_room": return "ТТК зала"
        default: return "Просмотр ТТК"
        }
    }

    private var kitchenTTKSection: some View {
        Section(header: Text("Технологические карты кухни")) {
            NavigationLink {
                HotKitchenTTKView()
            } label: {
                Text(lang.t("hot_kitchen"))
            }

            NavigationLink {
                ColdKitchenTTKView()
            } label: {
                Text(lang.t("cold_kitchen"))
            }

            NavigationLink {
                KitchenSectionView(section: .prep)
            } label: {
                Text(lang.t("prep"))
            }

            NavigationLink {
                KitchenSectionView(section: .pastry)
            } label: {
                Text(lang.t("pastry"))
            }

            if pro.isPro {
                NavigationLink {
                    KitchenSectionView(section: .grill)
                } label: {
                    Text(lang.t("grill"))
                }

                NavigationLink {
                    KitchenSectionView(section: .pizza)
                } label: {
                    Text(lang.t("pizza"))
                }

                NavigationLink {
                    KitchenSectionView(section: .sushiBar)
                } label: {
                    Text(lang.t("sushi_bar"))
                }

                NavigationLink {
                    KitchenSectionView(section: .bakery)
                } label: {
                    Text(lang.t("bakery"))
                }
            }
        }
    }

    private var barTTKSection: some View {
        Section(header: Text("Технологические карты бара")) {
            NavigationLink {
                BarTTKView()
            } label: {
                Text("Коктейли и напитки")
            }
        }
    }

    private var diningRoomTTKSection: some View {
        Section(header: Text("Технологические карты зала")) {
            NavigationLink {
                HouseholdSuppliesView()
            } label: {
                Text("Сервис и обслуживание")
            }
        }
    }
}