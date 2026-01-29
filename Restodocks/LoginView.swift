//
//  LoginView.swift
//  Restodocks
//

import SwiftUI

struct LoginView: View {

    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {

        VStack(spacing: 24) {

            Text(lang.t("login"))
                .font(.largeTitle)
                .bold()

            NavigationLink {
                EmployeeLoginView()
            } label: {
                Text(lang.t("employee_login"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            NavigationLink {
                CreateOwnerView()
            } label: {
                Text(lang.t("create_owner"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
        .navigationTitle(lang.t("login"))
    }
}
