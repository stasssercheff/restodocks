import SwiftUI

struct GrillView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("grill"))
            .navigationTitle(lang.t("grill"))
    }
}