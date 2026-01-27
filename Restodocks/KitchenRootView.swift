// KitchenRootView.swift
import SwiftUI

struct KitchenRootView: View {
    @ObservedObject var lang = LocalizationManager.shared
    @EnvironmentObject var pro: ProAccess

    var body: some View {
        List {
            NavigationLink(destination: HotKitchenView()) {
                Text(lang.t("hot_kitchen"))
            }
            NavigationLink(destination: ColdKitchenView()) {
                Text(lang.t("cold_kitchen"))
            }

            if pro.isPro {
                NavigationLink(destination: GrillView()) { Text(lang.t("grill")) }
                NavigationLink(destination: PizzaView()) { Text(lang.t("pizza")) }
                NavigationLink(destination: SushiBarView()) { Text(lang.t("sushi_bar")) }
                NavigationLink(destination: BakeryView()) { Text(lang.t("bakery")) }
            } else {
                // если не Pro — ведём на экран разблокировки (ProUnlockView)
                NavigationLink(destination: ProUnlockView()) { Text("\(lang.t("grill")) (PRO)") }
                NavigationLink(destination: ProUnlockView()) { Text("\(lang.t("pizza")) (PRO)") }
                NavigationLink(destination: ProUnlockView()) { Text("\(lang.t("sushi_bar")) (PRO)") }
                NavigationLink(destination: ProUnlockView()) { Text("\(lang.t("bakery")) (PRO)") }
            }

            NavigationLink(destination: PrepView()) { Text(lang.t("prep")) }
            NavigationLink(destination: PastryView()) { Text(lang.t("pastry")) }
        }
        .navigationTitle(lang.t("kitchen_title"))
    }
}
