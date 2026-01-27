import SwiftUI

struct BakeryView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("bakery"))
            .navigationTitle(lang.t("bakery"))
    }
}