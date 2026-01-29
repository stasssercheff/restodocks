import SwiftUI

struct CreateEstablishmentView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager
    @State private var name = ""
    @State private var showPinCode = false
    @State private var generatedPinCode = ""

    var body: some View {
        VStack {
            if showPinCode {
                // Экран с PIN кодом
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(AppTheme.success)

                    Text(lang.t("company_created"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)

                    VStack(spacing: 16) {
                        Text("PIN код компании:")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)

                        Text(generatedPinCode)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(AppTheme.primary)
                            .padding()
                            .background(AppTheme.cardBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppTheme.primary, lineWidth: 2)
                            )
                    }

                    Text("Сохраните этот PIN код! Он потребуется для регистрации сотрудников.")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Spacer()

                    PrimaryButton(title: lang.t("continue")) {
                        showPinCode = false
                        // Приложение автоматически перейдет к следующему шагу
                    }
                    .padding(.horizontal)
                }
                .padding()
            } else {
                // Форма создания компании
                Form {
                    Section(lang.t("company")) {
                        TextField(lang.t("company_name"), text: $name)
                    }

                    Section {
                        PrimaryButton(title: lang.t("create_company"), isDisabled: name.isEmpty) {
                            let pinCode = accounts.createEstablishment(name: name)
                            generatedPinCode = pinCode
                            showPinCode = true
                        }
                    }
                }
                .navigationTitle(lang.t("register_company"))
            }
        }
    }
}
