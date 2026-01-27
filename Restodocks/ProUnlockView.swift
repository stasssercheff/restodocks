import SwiftUI

struct ProUnlockView: View {
    @EnvironmentObject var pro: ProAccess
    @EnvironmentObject var lang: LocalizationManager

    @State private var code: String = ""
    @State private var wrongCode: Bool = false

    var body: some View {
        AppNavigationView {
            VStack(spacing: 20) {

                Text(lang.t("pro_features"))
                    .font(.largeTitle)
                    .padding(.top)

                Text(lang.t("pro_enter_or_buy"))
                    .multilineTextAlignment(.center)
                    .padding()

                TextField(lang.t("enter_code"), text: $code)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                if wrongCode {
                    Text(lang.t("wrong_code"))
                        .foregroundColor(.red)
                }

                Button {
                    if pro.activateWithCode(code) {
                        wrongCode = false
                    } else {
                        wrongCode = true
                    }
                } label: {
                    Text(lang.t("activate"))
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle(lang.t("pro_features"))
        }
    }
}
