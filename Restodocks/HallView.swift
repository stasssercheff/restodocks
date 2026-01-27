import SwiftUI

struct HallView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        AppNavigationView {
            VStack {
                Text(lang.t("hall"))
                    .font(.largeTitle)
                    .bold()
                    .padding()

                Spacer()
            }
            .navigationTitle(lang.t("hall"))
        }
    }
}
