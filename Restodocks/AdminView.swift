import SwiftUI

struct AdminView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        Text(lang.t("administration"))
            .font(.largeTitle)
            .padding()
            .navigationTitle(lang.t("administration"))
    }
}
