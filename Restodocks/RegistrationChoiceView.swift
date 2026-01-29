import SwiftUI

struct RegistrationChoiceView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        VStack(spacing: 24) {

            Spacer()

            NavigationLink {
                CreateEstablishmentView()
            } label: {
                Text(lang.t("register_company"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            NavigationLink {
                EmployeeRegistrationView()
            } label: {
                Text(lang.t("register_employee"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            NavigationLink {
                EmployeeLoginView()
            } label: {
                Text(lang.t("employee_login"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            Spacer()
        }
        .padding()
        .navigationTitle(lang.t("welcome"))
    }
}
