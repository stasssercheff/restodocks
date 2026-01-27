import SwiftUI

struct BarView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("bar"))
            .font(.largeTitle)
            .padding()
            .navigationTitle(lang.t("bar"))
    }
}
