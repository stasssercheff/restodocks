import SwiftUI

struct HotKitchenView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("hot_kitchen"))
            .navigationTitle(lang.t("hot_kitchen"))
    }
}
