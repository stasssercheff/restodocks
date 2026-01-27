import SwiftUI

struct PastryView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("pastry"))
            .navigationTitle(lang.t("pastry"))
    }
}