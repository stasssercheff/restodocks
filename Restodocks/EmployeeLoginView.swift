//
//  EmployeeLoginView.swift
//  Restodocks
//

import SwiftUI

struct EmployeeLoginView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager
    @EnvironmentObject var appState: AppState

    @State private var email = ""
    @State private var password = ""
    @State private var companyPin = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 60))
                        .foregroundColor(AppTheme.primary)

                    Text(getLoginTitle())
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)

                    Text(getLoginSubtitle())
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Login form
                VStack(spacing: 16) {
                    TextField(getEmailPlaceholder(), text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(AppTheme.cardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )

                    SecureField(getPasswordPlaceholder(), text: $password)
                        .padding()
                        .background(AppTheme.cardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )

                    TextField(getCompanyPinPlaceholder(), text: $companyPin)
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
                                .stroke(AppTheme.border, lineWidth: 1)
                        )

                    if showError {
                        Text(errorMessage)
                            .foregroundColor(AppTheme.error)
                            .font(.system(size: 14))
                            .multilineTextAlignment(.center)
                    }

                    PrimaryButton(title: getLoginButtonTitle(),
                                isDisabled: !isFormValid || isLoading) {
                        login()
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.vertical, 20)
        }
        .navigationBarBackButtonHidden(false)
        .navigationTitle(getLoginNavTitle())
    }

    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && !companyPin.isEmpty
    }

    private func login() {
        isLoading = true
        showError = false

        // Find company by PIN
        if let company = accounts.findCompanyByPinCode(companyPin) {
            // Find employee by email and password in this company
            if let employee = accounts.findEmployeeByEmailAndPassword(email, password, inCompany: company) {
                accounts.currentEmployee = employee
                accounts.establishment = company
                appState.currentEmployee = employee
                appState.isLoggedIn = true
                appState.isCompanySelected = true
                // Navigation will happen automatically
            } else {
                showErrorMessage(getInvalidCredentialsText())
            }
        } else {
            showErrorMessage(getCompanyNotFoundText())
        }

        isLoading = false
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    // Localized text methods
    private func getLoginTitle() -> String {
        switch lang.currentLang {
        case "ru": return "Вход в систему"
        case "en": return "Sign In"
        case "es": return "Iniciar sesión"
        case "de": return "Anmelden"
        case "fr": return "Se connecter"
        default: return "Sign In"
        }
    }

    private func getLoginSubtitle() -> String {
        switch lang.currentLang {
        case "ru": return "Введите данные для входа в компанию"
        case "en": return "Enter your credentials to sign in"
        case "es": return "Ingrese sus credenciales para iniciar sesión"
        case "de": return "Geben Sie Ihre Anmeldedaten ein"
        case "fr": return "Entrez vos identifiants pour vous connecter"
        default: return "Enter your credentials to sign in"
        }
    }

    private func getEmailPlaceholder() -> String {
        switch lang.currentLang {
        case "ru": return "Email"
        case "en": return "Email"
        case "es": return "Correo electrónico"
        case "de": return "E-Mail"
        case "fr": return "Email"
        default: return "Email"
        }
    }

    private func getPasswordPlaceholder() -> String {
        switch lang.currentLang {
        case "ru": return "Пароль"
        case "en": return "Password"
        case "es": return "Contraseña"
        case "de": return "Passwort"
        case "fr": return "Mot de passe"
        default: return "Password"
        }
    }

    private func getCompanyPinPlaceholder() -> String {
        switch lang.currentLang {
        case "ru": return "PIN код компании (8 символов)"
        case "en": return "Company PIN code (8 characters)"
        case "es": return "Código PIN de empresa (8 caracteres)"
        case "de": return "Firmen-PIN-Code (8 Zeichen)"
        case "fr": return "Code PIN entreprise (8 caractères)"
        default: return "Company PIN code (8 characters)"
        }
    }

    private func getLoginButtonTitle() -> String {
        switch lang.currentLang {
        case "ru": return "Войти"
        case "en": return "Sign In"
        case "es": return "Iniciar sesión"
        case "de": return "Anmelden"
        case "fr": return "Se connecter"
        default: return "Sign In"
        }
    }

    private func getLoginNavTitle() -> String {
        switch lang.currentLang {
        case "ru": return "Вход"
        case "en": return "Login"
        case "es": return "Acceso"
        case "de": return "Login"
        case "fr": return "Connexion"
        default: return "Login"
        }
    }

    private func getInvalidCredentialsText() -> String {
        switch lang.currentLang {
        case "ru": return "Неверный email или пароль"
        case "en": return "Invalid email or password"
        case "es": return "Email o contraseña inválidos"
        case "de": return "Ungültige E-Mail oder Passwort"
        case "fr": return "Email ou mot de passe invalide"
        default: return "Invalid email or password"
        }
    }

    private func getCompanyNotFoundText() -> String {
        switch lang.currentLang {
        case "ru": return "Компания с таким PIN кодом не найдена"
        case "en": return "Company with this PIN code not found"
        case "es": return "Empresa con este código PIN no encontrada"
        case "de": return "Unternehmen mit diesem PIN-Code nicht gefunden"
        case "fr": return "Entreprise avec ce code PIN introuvable"
        default: return "Company with this PIN code not found"
        }
    }
}