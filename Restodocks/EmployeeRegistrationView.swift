//
//  EmployeeRegistrationView.swift
//  Restodocks
//

import SwiftUI

struct EmployeeRegistrationView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager
    @EnvironmentObject var appState: AppState

    @State private var companyName = ""
    @State private var companyPin = ""
    @State private var employeeName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var employeeDepartment = "kitchen"
    @State private var employeeSection = "hot_kitchen" // For kitchen departments
    @State private var employeeRole = "cook"

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false

    let departments = [
        ("kitchen", "Кухня"),
        ("bar", "Бар"),
        ("dining_room", "Зал"),
        ("management", "Управление")
    ]

    var availableSections: [(String, String)] {
        switch employeeDepartment {
        case "kitchen":
            return [
                ("management", lang.t("management")),
                ("hot_kitchen", lang.t("hot_kitchen")),
                ("cold_kitchen", lang.t("cold_kitchen")),
                ("grill", lang.t("grill") + " (pro)"),
                ("pizza", lang.t("pizza") + " (pro)"),
                ("sushi_bar", lang.t("sushi_bar") + " (pro)"),
                ("prep", lang.t("prep")),
                ("pastry", lang.t("pastry")),
                ("bakery", lang.t("bakery") + " (pro)"),
                ("cleaning", lang.t("cleaning"))
            ]
        default:
            return []
        }
    }

    var availableRoles: [(String, String)] {
        switch employeeDepartment {
        case "kitchen":
            switch employeeSection {
            case "management":
                return [
                    ("brigadeLeader", lang.t("brigadeLeader")),
                    ("sousChef", lang.t("sousChef"))
                ]
            case "hot_kitchen":
                return [
                    ("senior_cook", lang.t("senior_cook")),
                    ("cook", lang.t("cook"))
                ]
            case "cold_kitchen":
                return [
                    ("senior_cook", lang.t("senior_cook")),
                    ("cook", lang.t("cook"))
                ]
            case "grill":
                return [
                    ("seniorGrillCook", lang.t("seniorGrillCook")),
                    ("grillCook", lang.t("grillCook"))
                ]
            case "pizza":
                return [
                    ("seniorPizzaiolo", lang.t("seniorPizzaiolo")),
                    ("pizzaiolo", lang.t("pizzaiolo"))
                ]
            case "sushi_bar":
                return [
                    ("seniorSushiChef", lang.t("seniorSushiChef")),
                    ("sushiChef", lang.t("sushiChef"))
                ]
            case "prep":
                return [
                    ("seniorPrepCook", lang.t("seniorPrepCook")),
                    ("prepCook", lang.t("prepCook"))
                ]
            case "pastry":
                return [
                    ("senior_pastry", "Старший кондитер"),
                    ("pastry", "Кондитер")
                ]
            case "bakery":
                return [
                    ("senior_baker", "Старший пекарь"),
                    ("baker", "Пекарь")
                ]
            case "cleaning":
                return [
                    ("dishwasher_male", "Мойщик"),
                    ("dishwasher_female", "Мойщица")
                ]
            default:
                return [("cook", "Повар")]
            }
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
                ("director", lang.t("director")),
                ("manager", lang.t("manager")),
                ("executive_chef", lang.t("executive_chef"))
            ]
        default:
            return [("employee", "Сотрудник")]
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Заголовок
                Text(getTitleText())
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)

                // Компания
                VStack(alignment: .leading, spacing: 16) {
                    Text(getCompanySectionText())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)

                    TextField(getCompanyNamePlaceholder(), text: $companyName)
                        .padding()
                        .background(AppTheme.cardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )

                    TextField(getPinPlaceholder(), text: $companyPin)
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
                }

                // Сотрудник
                VStack(alignment: .leading, spacing: 16) {
                    Text(getEmployeeSectionText())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)

                    TextField(getNamePlaceholder(), text: $employeeName)
                        .padding()
                        .background(AppTheme.cardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )

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
                }

                // Подразделение и должность
                VStack(alignment: .leading, spacing: 16) {
                    Text(getRoleSectionText())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)

                            Picker(getDepartmentPlaceholder(), selection: $employeeDepartment) {
                                Text(lang.t("kitchen")).tag("kitchen")
                                Text(lang.t("bar")).tag("bar")
                                Text(lang.t("dining_room")).tag("dining_room")
                                Text(lang.t("management")).tag("management")
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.cardBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            )
                            .onChange(of: employeeDepartment) {
                                employeeSection = availableSections.first?.0 ?? "hot_kitchen"
                                employeeRole = availableRoles.first?.0 ?? "cook"
                            }

                    if employeeDepartment == "kitchen" {
                        Picker(getSectionPlaceholder(), selection: $employeeSection) {
                            ForEach(availableSections, id: \.0) { section in
                                Text(section.1).tag(section.0)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.secondaryBackground)
                        .cornerRadius(12)
                        .onChange(of: employeeSection) {
                            employeeRole = availableRoles.first?.0 ?? "cook"
                        }
                    }

                    Picker(getRolePlaceholder(), selection: $employeeRole) {
                        ForEach(availableRoles, id: \.0) { r in
                            Text(r.1).tag(r.0)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                }

                // Ошибка
                if showError {
                    Text(errorMessage)
                        .foregroundColor(AppTheme.error)
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Кнопка регистрации
                PrimaryButton(title: getRegisterButtonText(),
                            isDisabled: !isFormValid || isLoading) {
                    registerEmployee()
                }
                .padding(.horizontal)

                Spacer(minLength: 50)
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationBarHidden(true)
        .onAppear {
            // Если есть сохраненная компания, заполняем поля
            if let company = accounts.establishment {
                companyName = company.name ?? ""
            }
        }
    }

    private var isFormValid: Bool {
        !companyName.isEmpty &&
        !companyPin.isEmpty &&
        !employeeName.isEmpty &&
        !email.isEmpty &&
        !password.isEmpty
    }

    private func registerEmployee() {
        isLoading = true
        showError = false

        // Ищем компанию по названию (очищаем от лишних символов)
        if let existingCompany = accounts.findCompanyByName(companyName.trimmingCharacters(in: .whitespacesAndNewlines)) {
            // Компания найдена, проверяем PIN (без учета регистра и лишних символов)
            let cleanExistingPin = existingCompany.pinCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
            let cleanInputPin = companyPin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if cleanExistingPin == cleanInputPin {
                // PIN верный, регистрируем сотрудника
                accounts.createEmployeeForCompany(
                    existingCompany,
                    fullName: employeeName,
                    email: email,
                    password: password,
                    department: employeeDepartment,
                    role: employeeRole
                )
                appState.isLoggedIn = true
            } else {
                showErrorMessage(getInvalidPinText())
            }
        } else {
            // Компания не найдена, создаем новую (PIN генерируется автоматически)
            _ = accounts.createEstablishment(name: companyName.trimmingCharacters(in: .whitespacesAndNewlines))
            if let newCompany = accounts.establishment {
                accounts.createEmployeeForCompany(
                    newCompany,
                    fullName: employeeName,
                    email: email,
                    password: password,
                    department: employeeDepartment,
                    role: employeeRole
                )
                appState.isLoggedIn = true
            } else {
                showErrorMessage(getErrorCreatingCompanyText())
            }
        }

        isLoading = false
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    // Локализованные тексты
    private func getTitleText() -> String {
        switch lang.currentLang {
        case "ru": return "Регистрация сотрудника"
        case "en": return "Employee Registration"
        case "es": return "Registro de Empleado"
        case "de": return "Mitarbeiterregistrierung"
        case "fr": return "Inscription Employé"
        default: return "Employee Registration"
        }
    }

    private func getCompanySectionText() -> String {
        switch lang.currentLang {
        case "ru": return "Компания"
        case "en": return "Company"
        case "es": return "Empresa"
        case "de": return "Unternehmen"
        case "fr": return "Entreprise"
        default: return "Company"
        }
    }

    private func getEmployeeSectionText() -> String {
        switch lang.currentLang {
        case "ru": return "Личные данные"
        case "en": return "Personal Information"
        case "es": return "Información Personal"
        case "de": return "Persönliche Informationen"
        case "fr": return "Informations Personnelles"
        default: return "Personal Information"
        }
    }

    private func getRoleSectionText() -> String {
        switch lang.currentLang {
        case "ru": return "Роль в компании"
        case "en": return "Role in Company"
        case "es": return "Rol en la Empresa"
        case "de": return "Rolle im Unternehmen"
        case "fr": return "Rôle dans l'Entreprise"
        default: return "Role in Company"
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

    private func getNamePlaceholder() -> String {
        switch lang.currentLang {
        case "ru": return "Ваше имя"
        case "en": return "Your name"
        case "es": return "Tu nombre"
        case "de": return "Ihr Name"
        case "fr": return "Votre nom"
        default: return "Your name"
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

    private func getDepartmentPlaceholder() -> String {
        switch lang.currentLang {
        case "ru": return "Подразделение"
        case "en": return "Department"
        case "es": return "Departamento"
        case "de": return "Abteilung"
        case "fr": return "Département"
        default: return "Department"
        }
    }

    private func getSectionPlaceholder() -> String {
        switch lang.currentLang {
        case "ru": return "Цех"
        case "en": return "Section"
        case "es": return "Sección"
        case "de": return "Abteilung"
        case "fr": return "Section"
        default: return "Section"
        }
    }

    private func getRolePlaceholder() -> String {
        switch lang.currentLang {
        case "ru": return "Должность"
        case "en": return "Position"
        case "es": return "Posición"
        case "de": return "Position"
        case "fr": return "Poste"
        default: return "Position"
        }
    }

    private func getRegisterButtonText() -> String {
        switch lang.currentLang {
        case "ru": return "Зарегистрироваться"
        case "en": return "Register"
        case "es": return "Registrarse"
        case "de": return "Registrieren"
        case "fr": return "S'inscrire"
        default: return "Register"
        }
    }

    private func getErrorCreatingCompanyText() -> String {
        switch lang.currentLang {
        case "ru": return "Ошибка создания компании"
        case "en": return "Error creating company"
        case "es": return "Error al crear empresa"
        case "de": return "Fehler beim Erstellen des Unternehmens"
        case "fr": return "Erreur lors de la création de l'entreprise"
        default: return "Error creating company"
        }
    }

    private func getNewCompanyPinText() -> String {
        switch lang.currentLang {
        case "ru": return "Для новой компании введите PIN код"
        case "en": return "For new company enter PIN code"
        case "es": return "Para nueva empresa ingrese código PIN"
        case "de": return "Für neues Unternehmen PIN-Code eingeben"
        case "fr": return "Pour nouvelle entreprise entrer code PIN"
        default: return "For new company enter PIN code"
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
}