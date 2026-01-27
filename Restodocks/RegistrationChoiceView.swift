import SwiftUI

struct RegistrationChoiceView: View {

    @ObservedObject var lang = LocalizationManager.shared
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 24) {

            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 80)
                .padding(.top, 40)

            Text(lang.t("app_name"))
                .font(.largeTitle)
                .bold()

            NavigationLink {
                LoginView()
            } label: {
                PrimaryButton(title: lang.t("login"))
            }
            .padding(.horizontal)

            NavigationLink {
                CreateEstablishmentView()
            } label: {
                PrimaryButton(title: lang.t("register_company"))
            }
            .padding(.horizontal)

            NavigationLink {
                EmployeeRegistrationView()
            } label: {
                SecondaryButton(title: lang.t("register_employee"))
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.horizontal)
        .navigationTitle(lang.t("welcome"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
