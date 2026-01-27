import SwiftUI

struct ManagementView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        AppNavigationView {
            VStack {
                Text(lang.t("management"))
                    .font(.largeTitle)
                    .bold()
                    .padding()

                Spacer()
            }
            .navigationTitle(lang.t("management"))
        }
    }
}
