//
//  OnboardingView.swift
//  Restodocks
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager
    @EnvironmentObject var appState: AppState

    // Language selection
    @State private var selectedLanguage = "en"

    // Company login
    @State private var companyName = ""
    @State private var companyPin = ""
    @State private var loginError = ""

    // Company registration
    @State private var newCompanyName = ""
    @State private var newCompanyGeneratedPin = ""
    @State private var registrationError = ""

    // Employee registration
    @State private var employeeName = ""
    @State private var employeeEmail = ""
    @State private var employeePassword = ""
    @State private var employeeDepartment = "kitchen"
    @State private var employeeRole = "cook"

    @State private var currentStep = 0 // 0: language, 1: login/register, 2: employee
    @State private var showCompanyRegistration = false
    @State private var isLoading = false

    let languages = [
        ("en", "English", "🇺🇸"),
        ("ru", "Русский", "🇷🇺"),
        ("es", "Español", "🇪🇸"),
        ("de", "Deutsch", "🇩🇪"),
        ("fr", "Français", "🇫🇷")
    ]

    var availableRoles: [(String, String)] {
        switch employeeDepartment {
        case "kitchen":
            return [
                ("sous_chef", "Су-шеф"),
                ("brigadier", "Бригадир"),
                ("cook", "Повар"),
                ("prep_cook", "Заготовщик"),
                ("grill_cook", "Повар гриль"),
                ("sushi_chef", "Сушист"),
                ("pizza_chef", "Пиццер"),
                ("pastry_chef", "Шеф кондитер"),
                ("confectioner", "Кондитер")
            ]
        case "bar":
            return [
                ("bar_manager", "Бар менеджер"),
                ("senior_bartender", "Старший бармен"),
                ("bartender", "Бармен")
            ]
        case "dining_room":
            return [
                ("dining_manager", "Менеджер зала"),
                ("cashier", "Кассир"),
                ("waiter", "Официант"),
                ("runner", "Раннер")
            ]
        case "management":
            return [
                ("director", "Директор"),
                ("manager", "Управляющий"),
                ("executive_chef", "Шеф повар"),
                ("owner", "Владелец")
            ]
        default:
            return [("employee", "Сотрудник")]
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .shadow(color: AppTheme.shadow, radius: 4, y: 2)

                    Text(getWelcomeText())
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                // Step 1: Language Selection
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: currentStep >= 0 ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(currentStep >= 0 ? AppTheme.success : AppTheme.textSecondary)
                        Text(getLanguageStepText())
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                    }

                    VStack(spacing: 12) {
                        ForEach(languages, id: \.0) { language in
                            LanguageRow(
                                code: language.0,
                                name: language.1,
                                flag: language.2,
                                isSelected: selectedLanguage == language.0
                            ) {
                                selectedLanguage = language.0
                                lang.setLang(language.0)
                            }
                        }
                    }
                }
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.border, lineWidth: 1)
                )

                // Step 2: Company Access
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: currentStep >= 1 ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(currentStep >= 1 ? AppTheme.success : AppTheme.textSecondary)
                        Text(getCompanyStepText())
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                    }

                    if !showCompanyRegistration {
                        // Login to existing company
                        VStack(spacing: 16) {
                            TextField(getCompanyNamePlaceholder(), text: $companyName)
                                .padding()
                                .background(AppTheme.secondaryBackground)
                                .cornerRadius(12)

                            SecureField(getPinPlaceholder(), text: $companyPin)
                                .keyboardType(.numberPad)
                                .padding()
                                .background(AppTheme.secondaryBackground)
                                .cornerRadius(12)

                            if !loginError.isEmpty {
                                Text(loginError)
                                    .foregroundColor(AppTheme.error)
                                    .font(.system(size: 14))
                            }

                            HStack(spacing: 12) {
                                SecondaryButton(title: getLoginButtonText()) {
                                    loginToCompany()
                                }
                                .disabled(companyName.isEmpty || companyPin.isEmpty)

                                SecondaryButton(title: getRegisterNewCompanyText()) {
                                    showCompanyRegistration = true
                                }
                            }
                        }
                    } else {
                        // Register new company
                        VStack(spacing: 16) {
                            TextField(getNewCompanyNamePlaceholder(), text: $newCompanyName)
                                .padding()
                                .background(AppTheme.secondaryBackground)
                                .cornerRadius(12)

                            if !newCompanyGeneratedPin.isEmpty {
                                VStack(spacing: 8) {
                                    Text(getGeneratedPinText())
                                        .font(.system(size: 14))
                                        .foregroundColor(AppTheme.textSecondary)

                                    Text(newCompanyGeneratedPin)
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(AppTheme.primary)
                                        .padding()
                                        .background(AppTheme.secondaryBackground)
                                        .cornerRadius(12)
                                }
                            }

                            if !registrationError.isEmpty {
                                Text(registrationError)
                                    .foregroundColor(AppTheme.error)
                                    .font(.system(size: 14))
                            }

                            HStack(spacing: 12) {
                                if newCompanyGeneratedPin.isEmpty {
                                    SecondaryButton(title: getGeneratePinText()) {
                                        newCompanyGeneratedPin = appState.generatePinCode()
                                    }
                                } else {
                                    SecondaryButton(title: getCreateCompanyText()) {
                                        createNewCompany()
                                    }
                                    .disabled(newCompanyName.isEmpty)
                                }

                                SecondaryButton(title: getBackToLoginText()) {
                                    showCompanyRegistration = false
                                    newCompanyName = ""
                                    newCompanyGeneratedPin = ""
                                    registrationError = ""
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.border, lineWidth: 1)
                )

                // Step 3: Employee Registration
                if appState.isCompanySelected || appState.isCompanyCreated {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: currentStep >= 2 ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(currentStep >= 2 ? AppTheme.success : AppTheme.textSecondary)
                            Text(getEmployeeStepText())
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                        }

                        VStack(spacing: 16) {
                            TextField(getEmployeeNamePlaceholder(), text: $employeeName)
                                .padding()
                                .background(AppTheme.secondaryBackground)
                                .cornerRadius(12)

                            TextField(getEmployeeEmailPlaceholder(), text: $employeeEmail)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .padding()
                                .background(AppTheme.secondaryBackground)
                                .cornerRadius(12)

                            SecureField(getEmployeePasswordPlaceholder(), text: $employeePassword)
                                .padding()
                                .background(AppTheme.secondaryBackground)
                                .cornerRadius(12)

                            Picker(getDepartmentPlaceholder(), selection: $employeeDepartment) {
                                Text("Кухня").tag("kitchen")
                                Text("Бар").tag("bar")
                                Text("Зал").tag("dining_room")
                                Text("Управление").tag("management")
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: employeeDepartment) {
                                employeeRole = availableRoles.first?.0 ?? "employee"
                            }

                            Picker(getRolePlaceholder(), selection: $employeeRole) {
                                ForEach(availableRoles, id: \.0) { role in
                                    Text(role.1).tag(role.0)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding()
                            .background(AppTheme.secondaryBackground)
                            .cornerRadius(12)

                            PrimaryButton(title: getRegisterEmployeeText(),
                                        isDisabled: !isEmployeeFormValid || isLoading) {
                                registerEmployee()
                            }
                        }
                    }
                    .padding()
                    .background(AppTheme.cardBackground)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                }

                Spacer(minLength: 50)
            }
            .padding(.horizontal)
        }
        .background(AppTheme.background)
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

    private var isEmployeeFormValid: Bool {
        !employeeName.isEmpty &&
        !employeeEmail.isEmpty &&
        !employeePassword.isEmpty
    }

    private func loginToCompany() {
        loginError = ""
        Task { @MainActor in
            do {
                if let company = try await accounts.findCompanyByName(companyName) {
                    let cleanPin = company.pinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    let inputPin = companyPin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    if cleanPin == inputPin {
                        accounts.establishment = company
                        appState.isCompanySelected = true
                        appState.companyPinCode = companyPin
                        currentStep = 2
                    } else {
                        loginError = getInvalidPinText()
                    }
                } else {
                    loginError = getCompanyNotFoundText()
                }
            } catch {
                loginError = error.localizedDescription
            }
        }
    }

    private func createNewCompany() {
        registrationError = ""
        guard newCompanyGeneratedPin == companyPin else {
            registrationError = "\(getPinMismatchText()): \(newCompanyGeneratedPin)"
            return
        }
        // Откладываем создание до шага 3 (registerEmployee) — нужны данные владельца
        appState.isCompanySelected = true
        currentStep = 2
    }

    private func registerEmployee() {
        isLoading = true
        Task { @MainActor in
            do {
                if let company = accounts.establishment {
                    try await accounts.createEmployeeForCompany(
                        establishmentId: company.id,
                        fullName: employeeName,
                        email: employeeEmail,
                        password: employeePassword,
                        department: employeeDepartment,
                        role: employeeRole
                    )
                } else if !newCompanyName.isEmpty && newCompanyGeneratedPin == companyPin {
                    _ = try await accounts.createCompanyAndOwner(
                        companyName: newCompanyName,
                        fullName: employeeName,
                        email: employeeEmail,
                        password: employeePassword,
                        ownerRole: employeeRole
                    )
                }
            } catch {
                print("❌ Register employee error:", error)
            }
            isLoading = false
        }
    }

    // Localized text methods
    private func getWelcomeText() -> String {
        switch selectedLanguage {
        case "ru": return "Добро пожаловать!"
        case "en": return "Welcome!"
        case "es": return "¡Bienvenido!"
        case "de": return "Willkommen!"
        case "fr": return "Bienvenue!"
        default: return "Welcome!"
        }
    }

    private func getLanguageStepText() -> String {
        switch selectedLanguage {
        case "ru": return "1. Выберите язык"
        case "en": return "1. Choose Language"
        case "es": return "1. Elige idioma"
        case "de": return "1. Sprache wählen"
        case "fr": return "1. Choisir langue"
        default: return "1. Choose Language"
        }
    }

    private func getCompanyStepText() -> String {
        switch selectedLanguage {
        case "ru": return "2. Компания"
        case "en": return "2. Company"
        case "es": return "2. Empresa"
        case "de": return "2. Unternehmen"
        case "fr": return "2. Entreprise"
        default: return "2. Company"
        }
    }

    private func getEmployeeStepText() -> String {
        switch selectedLanguage {
        case "ru": return "3. Регистрация сотрудника"
        case "en": return "3. Employee Registration"
        case "es": return "3. Registro de empleado"
        case "de": return "3. Mitarbeiterregistrierung"
        case "fr": return "3. Inscription employé"
        default: return "3. Employee Registration"
        }
    }

    // ... остальные методы локализации
    private func getCompanyNamePlaceholder() -> String {
        switch selectedLanguage {
        case "ru": return "Название компании"
        case "en": return "Company name"
        default: return "Company name"
        }
    }

    private func getPinPlaceholder() -> String {
        switch selectedLanguage {
        case "ru": return "PIN код"
        case "en": return "PIN code"
        default: return "PIN code"
        }
    }

    private func getLoginButtonText() -> String {
        switch selectedLanguage {
        case "ru": return "Войти"
        case "en": return "Login"
        default: return "Login"
        }
    }

    private func getRegisterNewCompanyText() -> String {
        switch selectedLanguage {
        case "ru": return "Регистрация новой"
        case "en": return "Register New"
        default: return "Register New"
        }
    }

    private func getNewCompanyNamePlaceholder() -> String {
        switch selectedLanguage {
        case "ru": return "Название новой компании"
        case "en": return "New company name"
        default: return "New company name"
        }
    }

    private func getGeneratePinText() -> String {
        switch selectedLanguage {
        case "ru": return "Сгенерировать PIN"
        case "en": return "Generate PIN"
        default: return "Generate PIN"
        }
    }

    private func getCreateCompanyText() -> String {
        switch selectedLanguage {
        case "ru": return "Создать компанию"
        case "en": return "Create Company"
        default: return "Create Company"
        }
    }

    private func getBackToLoginText() -> String {
        switch selectedLanguage {
        case "ru": return "Назад ко входу"
        case "en": return "Back to Login"
        default: return "Back to Login"
        }
    }

    private func getEmployeeNamePlaceholder() -> String {
        switch selectedLanguage {
        case "ru": return "Ваше имя"
        case "en": return "Your name"
        default: return "Your name"
        }
    }

    private func getEmployeeEmailPlaceholder() -> String {
        switch selectedLanguage {
        case "ru": return "Email"
        case "en": return "Email"
        default: return "Email"
        }
    }

    private func getEmployeePasswordPlaceholder() -> String {
        switch selectedLanguage {
        case "ru": return "Пароль"
        case "en": return "Password"
        default: return "Password"
        }
    }

    private func getDepartmentPlaceholder() -> String {
        switch selectedLanguage {
        case "ru": return "Подразделение"
        case "en": return "Department"
        default: return "Department"
        }
    }

    private func getRolePlaceholder() -> String {
        switch selectedLanguage {
        case "ru": return "Должность"
        case "en": return "Role"
        default: return "Role"
        }
    }

    private func getRegisterEmployeeText() -> String {
        switch selectedLanguage {
        case "ru": return "Зарегистрироваться"
        case "en": return "Register"
        default: return "Register"
        }
    }

    private func getGeneratedPinText() -> String {
        switch selectedLanguage {
        case "ru": return "Сгенерированный PIN код:"
        case "en": return "Generated PIN code:"
        default: return "Generated PIN code:"
        }
    }

    private func getInvalidPinText() -> String {
        switch selectedLanguage {
        case "ru": return "Неверный PIN код"
        case "en": return "Invalid PIN code"
        default: return "Invalid PIN code"
        }
    }

    private func getCompanyNotFoundText() -> String {
        switch selectedLanguage {
        case "ru": return "Компания не найдена"
        case "en": return "Company not found"
        default: return "Company not found"
        }
    }

    private func getPinMismatchText() -> String {
        switch selectedLanguage {
        case "ru": return "Введите этот PIN код"
        case "en": return "Enter this PIN code"
        default: return "Enter this PIN code"
        }
    }
}

struct LanguageRow: View {
    let code: String
    let name: String
    let flag: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(flag)
                    .font(.system(size: 20))

                Text(name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppTheme.accent)
                        .font(.system(size: 18))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(isSelected ? AppTheme.primary.opacity(0.1) : Color.clear)
            .cornerRadius(12)
        }
    }
}