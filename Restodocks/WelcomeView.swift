//
//  WelcomeView.swift
//  Restodocks
//

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var appState: AppState

    @State private var selectedLanguage = "en"
    @State private var showLanguagePicker = false

    let languages = [
        ("en", "English", "🇺🇸"),
        ("ru", "Русский", "🇷🇺"),
        ("es", "Español", "🇪🇸"),
        ("de", "Deutsch", "🇩🇪"),
        ("fr", "Français", "🇫🇷")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // Logo
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .shadow(color: AppTheme.shadow, radius: 8, y: 4)

                    // Title
                    Text(getWelcomeTitle())
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .lineLimit(2)

                    // Language selector
                    VStack(spacing: 12) {
                        Button {
                            showLanguagePicker.toggle()
                        } label: {
                            HStack {
                                Text(getCurrentLanguageName())
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)

                                Spacer()

                                Image(systemName: showLanguagePicker ? "chevron.up" : "chevron.down")
                                    .foregroundColor(AppTheme.primary)
                            }
                            .padding()
                            .background(AppTheme.cardBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            )
                        }

                        if showLanguagePicker {
                            VStack(spacing: 8) {
                                ForEach(languages, id: \.0) { language in
                                    Button {
                                        selectedLanguage = language.0
                                        lang.setLang(language.0)
                                        showLanguagePicker = false
                                    } label: {
                                        HStack {
                                            Text(language.2)
                                                .font(.system(size: 20))
                                            Text(language.1)
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(selectedLanguage == language.0 ? AppTheme.primary : AppTheme.textPrimary)
                                            Spacer()
                                            if selectedLanguage == language.0 {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(AppTheme.primary)
                                            }
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                    }
                                }
                            }
                            .padding()
                            .background(AppTheme.cardBackground)
                            .cornerRadius(12)
                            .shadow(color: AppTheme.shadow, radius: 4, y: 2)
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal)

                    // Action buttons
                    VStack(spacing: 16) {
                        NavigationLink {
                            EmployeeLoginView()
                        } label: {
                            WelcomeButton(title: getLoginButtonTitle(), icon: "person.circle")
                        }

                        NavigationLink {
                            EmployeeRegistrationView()
                        } label: {
                            WelcomeButton(title: getRegisterEmployeeButtonTitle(), icon: "person.badge.plus")
                        }

                        NavigationLink {
                            CompanyRegistrationView()
                        } label: {
                            WelcomeButton(title: getRegisterCompanyButtonTitle(), icon: "building.2")
                        }
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.vertical, 20)
            }
            .onAppear {
                // Set default language
                if !lang.isLanguageSelected {
                    selectedLanguage = "en"
                    lang.setLang("en")
                } else {
                    selectedLanguage = lang.currentLang
                }
            }
        }
    }

    private func getWelcomeTitle() -> String {
        switch selectedLanguage {
        case "ru": return "Добро пожаловать\nв Restodocks"
        case "en": return "Welcome\nto Restodocks"
        case "es": return "Bienvenido\na Restodocks"
        case "de": return "Willkommen\nbei Restodocks"
        case "fr": return "Bienvenue\nchez Restodocks"
        default: return "Welcome\nto Restodocks"
        }
    }

    private func getCurrentLanguageName() -> String {
        let current = languages.first { $0.0 == selectedLanguage }
        return current?.1 ?? "English"
    }

    private func getLoginButtonTitle() -> String {
        switch selectedLanguage {
        case "ru": return "Вход"
        case "en": return "Login"
        case "es": return "Iniciar sesión"
        case "de": return "Anmelden"
        case "fr": return "Se connecter"
        default: return "Login"
        }
    }

    private func getRegisterEmployeeButtonTitle() -> String {
        switch selectedLanguage {
        case "ru": return "Регистрация сотрудника"
        case "en": return "Employee Registration"
        case "es": return "Registro de empleado"
        case "de": return "Mitarbeiterregistrierung"
        case "fr": return "Inscription employé"
        default: return "Employee Registration"
        }
    }

    private func getRegisterCompanyButtonTitle() -> String {
        switch selectedLanguage {
        case "ru": return "Регистрация компании"
        case "en": return "Company Registration"
        case "es": return "Registro de empresa"
        case "de": return "Unternehmensregistrierung"
        case "fr": return "Inscription entreprise"
        default: return "Company Registration"
        }
    }
}

struct WelcomeButton: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(AppTheme.primary)
                .frame(width: 40, height: 40)
                .background(AppTheme.primary.opacity(0.1))
                .cornerRadius(12)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(AppTheme.textSecondary)
                .font(.system(size: 16, weight: .medium))
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppTheme.shadow, radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}