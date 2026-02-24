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
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var isEmailNotConfirmed = false
    @State private var isResendingConfirmation = false

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

                    if showError {
                        Text(errorMessage)
                            .foregroundColor(AppTheme.error)
                            .font(.system(size: 14))
                            .multilineTextAlignment(.center)
                    }

                    if isEmailNotConfirmed {
                        SecondaryButton(title: getResendConfirmationTitle(),
                                      isDisabled: isResendingConfirmation) {
                            resendConfirmation()
                        }
                        .padding(.top, 8)
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
        !email.isEmpty && !password.isEmpty
    }

    private func login() {
        isLoading = true
        showError = false
        isEmailNotConfirmed = false

        Task { @MainActor in
            do {
                try await accounts.signIn(email: email, password: password)
            } catch {
                if let nsError = error as NSError?, nsError.code == 401 {
                    // Email not confirmed error
                    isEmailNotConfirmed = true
                    showErrorMessage(getEmailNotConfirmedText())
                } else {
                    showErrorMessage(getInvalidCredentialsText())
                }
            }
            isLoading = false
        }
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func resendConfirmation() {
        isResendingConfirmation = true
        showError = false

        Task { @MainActor in
            do {
                try await accounts.resendConfirmationEmail(email: email)
                showErrorMessage(getConfirmationSentText())
            } catch {
                showErrorMessage(getResendErrorText())
            }
            isResendingConfirmation = false
        }
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

    private func getEmailNotConfirmedText() -> String {
        switch lang.currentLang {
        case "ru": return "Email не подтвержден. Проверьте почту и перейдите по ссылке подтверждения."
        case "en": return "Email not confirmed. Please check your email and click the confirmation link."
        case "es": return "Email no confirmado. Revisa tu correo y haz clic en el enlace de confirmación."
        case "de": return "E-Mail nicht bestätigt. Bitte überprüfen Sie Ihre E-Mail und klicken Sie auf den Bestätigungslink."
        case "fr": return "Email non confirmé. Vérifiez votre email et cliquez sur le lien de confirmation."
        default: return "Email not confirmed. Please check your email and click the confirmation link."
        }
    }

    private func getResendConfirmationTitle() -> String {
        switch lang.currentLang {
        case "ru": return "Отправить подтверждение повторно"
        case "en": return "Resend confirmation"
        case "es": return "Reenviar confirmación"
        case "de": return "Bestätigung erneut senden"
        case "fr": return "Renvoyer la confirmation"
        default: return "Resend confirmation"
        }
    }

    private func getConfirmationSentText() -> String {
        switch lang.currentLang {
        case "ru": return "Письмо с подтверждением отправлено"
        case "en": return "Confirmation email sent"
        case "es": return "Correo de confirmación enviado"
        case "de": return "Bestätigungs-E-Mail gesendet"
        case "fr": return "Email de confirmation envoyé"
        default: return "Confirmation email sent"
        }
    }

    private func getResendErrorText() -> String {
        switch lang.currentLang {
        case "ru": return "Ошибка при отправке письма"
        case "en": return "Error sending email"
        case "es": return "Error al enviar el correo"
        case "de": return "Fehler beim Senden der E-Mail"
        case "fr": return "Erreur lors de l'envoi de l'email"
        default: return "Error sending email"
        }
    }
}