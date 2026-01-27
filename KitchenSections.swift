import SwiftUI

struct HotKitchenView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("hot_kitchen"))
            .font(.largeTitle)
            .padding()
            .navigationTitle(lang.t("hot_kitchen"))
    }
}

struct ColdKitchenView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("cold_kitchen"))
            .font(.largeTitle)
            .padding()
            .navigationTitle(lang.t("cold_kitchen"))
    }
}

struct GrillView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("grill"))
            .font(.largeTitle)
            .padding()
            .navigationTitle(lang.t("grill"))
    }
}

struct PizzaView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("pizza"))
            .font(.largeTitle)
            .padding()
            .navigationTitle(lang.t("pizza"))
    }
}

struct SushiBarView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("sushi_bar"))
            .font(.largeTitle)
            .padding()
            .navigationTitle(lang.t("sushi_bar"))
    }
}

struct PrepView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("prep"))
            .font(.largeTitle)
            .padding()
            .navigationTitle(lang.t("prep"))
    }
}

struct BakeryView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("bakery"))
            .font(.largeTitle)
            .padding()
            .navigationTitle(lang.t("bakery"))
    }
}

struct PastryView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("pastry"))
            .font(.largeTitle)
            .padding()
            .navigationTitle(lang.t("pastry"))
    }
}
