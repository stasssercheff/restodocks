//
//  CompanyRegistrationView.swift
//  Restodocks
//

import SwiftUI
import UIKit

struct CompanyRegistrationView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager
    @EnvironmentObject var appState: AppState

    @State private var companyName = ""
    @State private var ownerName = ""
    @State private var ownerEmail = ""
    @State private var ownerPassword = ""
    @State private var ownerRole = "owner"

    @State private var currentStep = 0 // 0: company name, 1: owner details
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var generatedPin = ""

    var availableRoles: [(String, String)] {
        [
            ("owner", "Владелец"),
            ("director", "Директор"),
            ("manager", "Управляющий"),
            ("executive_chef", "Шеф повар"),
            ("brigadier", "Бригадир"),
            ("sous_chef", "Су-шеф"),
            ("cook", "Повар"),
            ("bartender", "Бармен"),
            ("waiter", "Официант")
        ]
    }

    var body: some View {
        VStack {
            if currentStep == 0 {
                // Шаг 1: Название компании
                companyNameStep
            } else {
                // Шаг 2: Данные владельца
                ownerDetailsStep
            }
        }
        .navigationBarBackButtonHidden(false)
        .navigationTitle(getNavigationTitle())
    }

    private var companyNameStep: some View {
        VStack(spacing: 24) {
            Spacer()

            // Заголовок
            VStack(spacing: 16) {
                Image(systemName: "building.2")
                    .font(.system(size: 60))
                    .foregroundColor(AppTheme.primary)

                Text(getCompanyStepTitle())
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(getCompanyStepSubtitle())
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Поле ввода
            VStack(spacing: 16) {
                TextField(getCompanyNamePlaceholder(), text: $companyName)
                    .padding()
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )

                if !generatedPin.isEmpty {
                    VStack(spacing: 8) {
                        Text(getGeneratedPinLabel())
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)

                        HStack {
                            Text(generatedPin)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(AppTheme.primary)

                            Button {
                                UIPasteboard.general.string = generatedPin
                                // Добавляем уведомление о копировании
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .foregroundColor(AppTheme.primary)
                                    .font(.system(size: 16))
                            }
                        }
                        .padding()
                        .background(AppTheme.secondaryBackground)
                        .cornerRadius(12)
                    }
                }

                if showError {
                    Text(errorMessage)
                        .foregroundColor(AppTheme.error)
                        .font(.system(size: 14))
                }
            }
            .padding(.horizontal)

            Spacer()

            // Кнопка
            PrimaryButton(title: getNextButtonTitle(),
                        isDisabled: companyName.isEmpty) {
                if generatedPin.isEmpty {
                    generatedPin = appState.generatePinCode()
                } else {
                    currentStep = 1
                    showError = false
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .padding(.vertical, 20)
    }

    private var ownerDetailsStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Заголовок
                VStack(spacing: 16) {
                    Image(systemName: "person.badge.key")
                        .font(.system(size: 60))
                        .foregroundColor(AppTheme.primary)

                    Text(getOwnerStepTitle())
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(getOwnerStepSubtitle())
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Информация о компании
                VStack(alignment: .leading, spacing: 8) {
                    Text(getCompanyInfoTitle())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)

                    VStack(spacing: 8) {
                        Text("\(getCompanyNameLabel()): \(companyName)")
                        Text("\(getPinLabel()): \(generatedPin)")
                    }
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding()
                    .background(AppTheme.secondaryBackground)
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                // Поля владельца
                VStack(spacing: 16) {
                    TextField(getOwnerNamePlaceholder(), text: $ownerName)
                        .padding()
                        .background(AppTheme.cardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )

                    TextField(getOwnerEmailPlaceholder(), text: $ownerEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(AppTheme.cardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )

                    SecureField(getOwnerPasswordPlaceholder(), text: $ownerPassword)
                        .padding()
                        .background(AppTheme.cardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Владелец (автоматически) + дополнительная роль:")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)

                        Picker("Дополнительная роль", selection: $ownerRole) {
                            Text("Без дополнительной роли").tag("owner")
                            ForEach(availableRoles.filter { $0.0 != "owner" }, id: \.0) { role in
                                Text(role.1).tag(role.0)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding()
                        .background(AppTheme.cardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                    }

                    if showError {
                        Text(errorMessage)
                            .foregroundColor(AppTheme.error)
                            .font(.system(size: 14))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Кнопки
                VStack(spacing: 12) {
                    PrimaryButton(title: getCreateCompanyButtonTitle(),
                                isDisabled: !isOwnerFormValid || isLoading) {
                        createCompanyAndOwner()
                    }

                    Button {
                        currentStep = 0
                    } label: {
                        Text(getBackButtonTitle())
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppTheme.primary)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .padding(.vertical, 20)
        }
    }

    private var isOwnerFormValid: Bool {
        !ownerName.isEmpty && !ownerEmail.isEmpty && !ownerPassword.isEmpty
    }

    private func createCompanyAndOwner() {
        isLoading = true
        showError = false

        Task { @MainActor in
            do {
                let pin = try await accounts.createCompanyAndOwner(
                    companyName: companyName,
                    fullName: ownerName,
                    email: ownerEmail,
                    password: ownerPassword,
                    ownerRole: ownerRole
                )
                generatedPin = pin
                appState.isCompanySelected = true
                appState.companyPinCode = pin
                print("👑 Company and owner created: \(ownerName)")
            } catch {
                showErrorMessage(error.localizedDescription)
            }
            isLoading = false
        }
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    // Localized text methods
    private func getNavigationTitle() -> String {
        switch lang.currentLang {
        case "ru": return "Регистрация компании"
        case "en": return "Company Registration"
        case "es": return "Registro de empresa"
        case "de": return "Unternehmensregistrierung"
        case "fr": return "Inscription entreprise"
        default: return "Company Registration"
        }
    }

    private func getCompanyStepTitle() -> String {
        switch lang.currentLang {
        case "ru": return "Создание компании"
        case "en": return "Create Company"
        case "es": return "Crear empresa"
        case "de": return "Unternehmen erstellen"
        case "fr": return "Créer entreprise"
        default: return "Create Company"
        }
    }

    private func getCompanyStepSubtitle() -> String {
        switch lang.currentLang {
        case "ru": return "Введите название вашей компании"
        case "en": return "Enter your company name"
        case "es": return "Ingrese el nombre de su empresa"
        case "de": return "Geben Sie Ihren Firmennamen ein"
        case "fr": return "Entrez le nom de votre entreprise"
        default: return "Enter your company name"
        }
    }

    private func getOwnerStepTitle() -> String {
        switch lang.currentLang {
        case "ru": return "Регистрация владельца"
        case "en": return "Owner Registration"
        case "es": return "Registro del propietario"
        case "de": return "Besitzerregistrierung"
        case "fr": return "Inscription propriétaire"
        default: return "Owner Registration"
        }
    }

    private func getOwnerStepSubtitle() -> String {
        switch lang.currentLang {
        case "ru": return "Создайте учетную запись владельца"
        case "en": return "Create owner account"
        case "es": return "Crear cuenta de propietario"
        case "de": return "Besitzerkonto erstellen"
        case "fr": return "Créer un compte propriétaire"
        default: return "Create owner account"
        }
    }

    private func getCompanyInfoTitle() -> String {
        switch lang.currentLang {
        case "ru": return "Информация о компании"
        case "en": return "Company Information"
        case "es": return "Información de la empresa"
        case "de": return "Unternehmensinformationen"
        case "fr": return "Informations sur l'entreprise"
        default: return "Company Information"
        }
    }

    private func getCompanyNameLabel() -> String {
        switch lang.currentLang {
        case "ru": return "Название"
        case "en": return "Name"
        case "es": return "Nombre"
        case "de": return "Name"
        case "fr": return "Nom"
        default: return "Name"
        }
    }

    private func getPinLabel() -> String {
        switch lang.currentLang {
        case "ru": return "PIN код"
        case "en": return "PIN code"
        case "es": return "Código PIN"
        case "de": return "PIN-Code"
        case "fr": return "Code PIN"
        default: return "PIN code"
        }
    }

    // ... остальные методы локализации
    private func getCompanyNamePlaceholder() -> String {
        switch lang.currentLang {
        case "ru": return "Название компании"
        case "en": return "Company name"
        default: return "Company name"
        }
    }

    private func getGeneratedPinLabel() -> String {
        switch lang.currentLang {
        case "ru": return "Сгенерированный PIN код (8 символов):"
        case "en": return "Generated PIN code (8 characters):"
        case "es": return "Código PIN generado (8 caracteres):"
        case "de": return "Generierter PIN-Code (8 Zeichen):"
        case "fr": return "Code PIN généré (8 caractères):"
        default: return "Generated PIN code (8 characters):"
        }
    }

    private func getNextButtonTitle() -> String {
        if generatedPin.isEmpty {
            switch lang.currentLang {
            case "ru": return "Сгенерировать PIN"
            case "en": return "Generate PIN"
            default: return "Generate PIN"
            }
        } else {
            switch lang.currentLang {
            case "ru": return "Далее"
            case "en": return "Next"
            default: return "Next"
            }
        }
    }

    private func getOwnerNamePlaceholder() -> String {
        switch lang.currentLang {
        case "ru": return "Имя владельца"
        case "en": return "Owner name"
        default: return "Owner name"
        }
    }

    private func getOwnerEmailPlaceholder() -> String {
        switch lang.currentLang {
        case "ru": return "Email владельца"
        case "en": return "Owner email"
        default: return "Owner email"
        }
    }

    private func getOwnerPasswordPlaceholder() -> String {
        switch lang.currentLang {
        case "ru": return "Пароль"
        case "en": return "Password"
        default: return "Password"
        }
    }

    private func getOwnerRolePlaceholder() -> String {
        switch lang.currentLang {
        case "ru": return "Должность владельца"
        case "en": return "Owner position"
        default: return "Owner position"
        }
    }

    private func getCreateCompanyButtonTitle() -> String {
        switch lang.currentLang {
        case "ru": return "Создать компанию"
        case "en": return "Create Company"
        default: return "Create Company"
        }
    }

    private func getBackButtonTitle() -> String {
        switch lang.currentLang {
        case "ru": return "Назад"
        case "en": return "Back"
        default: return "Back"
        }
    }

    private func getCompanyExistsError() -> String {
        switch lang.currentLang {
        case "ru": return "Компания с таким названием уже существует"
        case "en": return "Company with this name already exists"
        default: return "Company with this name already exists"
        }
    }

    private func getCreationError() -> String {
        switch lang.currentLang {
        case "ru": return "Ошибка создания компании"
        case "en": return "Error creating company"
        default: return "Error creating company"
        }
    }
}