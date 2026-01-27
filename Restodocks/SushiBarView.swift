import SwiftUI

struct SushiBarView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("sushi_bar"))
            .navigationTitle(lang.t("sushi_bar"))
    }
}