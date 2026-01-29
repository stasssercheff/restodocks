import SwiftUI

struct ColdKitchenView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("cold_kitchen"))
            .navigationTitle(lang.t("cold_kitchen"))
    }
}
