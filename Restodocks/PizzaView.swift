import SwiftUI

struct PizzaView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("pizza"))
            .navigationTitle(lang.t("pizza"))
    }
}