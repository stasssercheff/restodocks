//
//  CompanyLoginView.swift
//  Restodocks
//

import SwiftUI

struct CompanyLoginView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager
    @EnvironmentObject var appState: AppState

    @State private var companyName = ""
    @State private var companyPin = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showRegistration = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Логотип
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .shadow(color: AppTheme.shadow, radius: 6, y: 3)

            // Заголовок
            Text(getWelcomeBackText())
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
                .multilineTextAlignment(.center)

            // Описание
            Text(getLoginDescriptionText())
                .font(.system(size: 16))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Поля входа
            VStack(spacing: 16) {
                TextField(getCompanyNamePlaceholder(), text: $companyName)
                    .padding()
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )

                SecureField(getPinPlaceholder(), text: $companyPin)
                    .keyboardType(.default)
                    .textInputAutocapitalization(.never)
                    .onChange(of: companyPin) { _, newValue in
                        companyPin = newValue.uppercased()
                    }
                    .padding()
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(showError ? AppTheme.error : AppTheme.border, lineWidth: 1)
                    )

                if showError {
                    Text(errorMessage)
                        .foregroundColor(AppTheme.error)
                        .font(.system(size: 14))
                }
            }
            .padding(.horizontal)

            // Кнопки
            VStack(spacing: 12) {
                PrimaryButton(title: getLoginButtonText(),
                            isDisabled: companyName.isEmpty || companyPin.isEmpty) {
                    loginToCompany()
                }

                SecondaryButton(title: getRegisterCompanyText()) {
                    showRegistration = true
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .background(AppTheme.background)
        .sheet(isPresented: $showRegistration) {
            NavigationStack {
                RegistrationChoiceView()
            }
        }
    }

    private func loginToCompany() {
        showError = false

        // Ищем компанию по названию
        if let company = accounts.findCompanyByName(companyName) {
            // Компания найдена, проверяем PIN (без учета регистра и лишних символов)
            let cleanExistingPin = company.pinCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
            let cleanInputPin = companyPin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if cleanExistingPin == cleanInputPin {
                // PIN верный, устанавливаем компанию
                accounts.establishment = company
                appState.isCompanySelected = true
                appState.companyPinCode = companyPin
                // Теперь пользователь перейдет к регистрации сотрудника
            } else {
                showErrorMessage(getInvalidPinText())
            }
        } else {
            showErrorMessage(getCompanyNotFoundText())
        }
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    // Локализованные тексты
    private func getWelcomeBackText() -> String {
        switch lang.currentLang {
        case "ru": return "Добро пожаловать обратно!"
        case "en": return "Welcome back!"
        case "es": return "¡Bienvenido de vuelta!"
        case "de": return "Willkommen zurück!"
        case "fr": return "Bienvenue!"
        default: return "Welcome back!"
        }
    }

    private func getLoginDescriptionText() -> String {
        switch lang.currentLang {
        case "ru": return "Введите данные вашей компании для входа"
        case "en": return "Enter your company details to sign in"
        case "es": return "Ingrese los datos de su empresa para iniciar sesión"
        case "de": return "Geben Sie Ihre Unternehmensdaten ein, um sich anzumelden"
        case "fr": return "Entrez les détails de votre entreprise pour vous connecter"
        default: return "Enter your company details to sign in"
        }
    }

    private func getCompanyNamePlaceholder() -> String {
        switch lang.currentLang {
        case "ru": return "Название компании"
        case "en": return "Company name"
        case "es": return "Nombre de empresa"
        case "de": return "Firmenname"
        case "fr": return "Nom de l'entreprise"
        default: return "Company name"
        }
    }

    private func getPinPlaceholder() -> String {
        switch lang.currentLang {
        case "ru": return "PIN код компании (8 символов)"
        case "en": return "Company PIN code (8 characters)"
        case "es": return "Código PIN de empresa (8 caracteres)"
        case "de": return "Firmen-PIN-Code (8 Zeichen)"
        case "fr": return "Code PIN entreprise (8 caractères)"
        default: return "Company PIN code (8 characters)"
        }
    }

    private func getLoginButtonText() -> String {
        switch lang.currentLang {
        case "ru": return "Войти"
        case "en": return "Sign In"
        case "es": return "Iniciar sesión"
        case "de": return "Anmelden"
        case "fr": return "Se connecter"
        default: return "Sign In"
        }
    }

    private func getRegisterCompanyText() -> String {
        switch lang.currentLang {
        case "ru": return "Зарегистрировать компанию"
        case "en": return "Register Company"
        case "es": return "Registrar empresa"
        case "de": return "Unternehmen registrieren"
        case "fr": return "Enregistrer entreprise"
        default: return "Register Company"
        }
    }

    private func getInvalidPinText() -> String {
        switch lang.currentLang {
        case "ru": return "Неверный PIN код компании"
        case "en": return "Invalid company PIN code"
        case "es": return "Código PIN de empresa inválido"
        case "de": return "Ungültiger Firmen-PIN-Code"
        case "fr": return "Code PIN entreprise invalide"
        default: return "Invalid company PIN code"
        }
    }

    private func getCompanyNotFoundText() -> String {
        switch lang.currentLang {
        case "ru": return "Компания с таким названием не найдена"
        case "en": return "Company with this name not found"
        case "es": return "Empresa con este nombre no encontrada"
        case "de": return "Unternehmen mit diesem Namen nicht gefunden"
        case "fr": return "Entreprise avec ce nom introuvable"
        default: return "Company with this name not found"
        }
    }
}