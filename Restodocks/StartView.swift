import SwiftUI

struct StartView: View {

    @EnvironmentObject var lang: LocalizationManager

    let onRegisterCompany: () -> Void
    let onRegisterEmployee: () -> Void
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 28) {

            // Верхняя панель: аватар
            HStack {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 32))
                Spacer()
            }

            Spacer()

            Text(lang.t("welcome"))
                .font(.largeTitle)
                .bold()

            VStack(spacing: 16) {

                Button {
                    onRegisterCompany()
                } label: {
                    Text(lang.t("register_company"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onRegisterEmployee()
                } label: {
                    Text(lang.t("register_employee"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onLogin()
                } label: {
                    Text(lang.t("login"))
                        .frame(maxWidth: .infinity)
                }
            }

            Spacer()
        }
        .padding()
        .navigationTitle(lang.t("start"))
    }
}
