import SwiftUI

struct PrepView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("prep"))
            .navigationTitle(lang.t("prep"))
    }
}
