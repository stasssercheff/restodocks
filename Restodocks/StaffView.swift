import SwiftUI

struct StaffView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        AppNavigationView {
            VStack {
                Text(lang.t("staff"))
                    .font(.largeTitle)
                    .bold()
                    .padding()

                Spacer()
            }
            .navigationTitle(lang.t("staff"))
        }
    }
}
