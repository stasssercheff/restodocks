//
//  ProfileView.swift
//  Restodocks
//

import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager
    @EnvironmentObject var appState: AppState

    @State private var showingLanguagePicker = false
    @State private var isEditingProfile = false
    @State private var editedName = ""
    @State private var editedEmail = ""
    @State private var selectedLanguage = "ru"
    @State private var selectedCurrency = "RUB"
    @State private var showingCurrencyPicker = false
    @State private var profileImage: UIImage?
    @State private var showingImageSourcePicker = false
    @State private var tempSelectedImage: UIImage?

    private var languages: [(String, String)] = [
        ("ru", "Русский"),
        ("en", "English"),
        ("es", "Español"),
        ("de", "Deutsch"),
        ("fr", "Français")
    ]

    private var currencies: [(String, String)] = [
        ("RUB", "₽ Рубль (RUB)"),
        ("USD", "$ Доллар (USD)"),
        ("EUR", "€ Евро (EUR)"),
        ("GBP", "£ Фунт (GBP)"),
        ("JPY", "¥ Йена (JPY)"),
        ("CNY", "¥ Юань (CNY)")
    ]

    var body: some View {

        ScrollView {
            VStack(spacing: 24) {
                // Заголовок
                Text(lang.t("profile"))
                    .font(.title2)
                    .bold()

                // Информация о компании
                if let establishment = accounts.establishment {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lang.t("company") + ":")
                            .font(.headline)
                        Text(establishment.name ?? "—")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                }

                // 1. Смена языка
                VStack(alignment: .leading, spacing: 12) {
                    Text(lang.t("language_settings"))
                        .font(.headline)

                    Button {
                        showingLanguagePicker = true
                    } label: {
                        HStack {
                            Text(lang.t("current_language") + ": \(languages.first { $0.0 == lang.currentLang }?.1 ?? lang.t("russian"))")
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
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
                }

                // 1.5. Выбор валюты (только для шеф-повара и выше)
                if appState.canManageSchedule {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(lang.t("currency_settings"))
                            .font(.headline)

                        Button {
                            showingCurrencyPicker = true
                        } label: {
                            HStack {
                                Text("Текущая валюта: \(currencies.first { $0.0 == appState.defaultCurrency }?.1 ?? "₽ Рубль (RUB)")")
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
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
                    }
                }

                // 2. Данные профиля
                VStack(alignment: .leading, spacing: 12) {
                    Text(lang.t("personal_data"))
                        .font(.headline)

                    if isEditingProfile {
                        profileEditForm
                    } else {
                        profileDisplay
                    }
                }

                // 3. Личный график (только для сотрудников)
                if let employee = accounts.currentEmployee,
                   !employee.rolesArray.contains("owner") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(lang.t("my_schedule"))
                            .font(.headline)

                        personalScheduleView
                    }
                }

                // Кнопка выхода
                Button(role: .destructive) {
                    accounts.logout()
                } label: {
                    Text(lang.t("logout"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(12)
                }

                Spacer()
            }
            .padding()
        }
        .onAppear {
            loadProfileImage()
        }
        .sheet(isPresented: $showingLanguagePicker) {
            languagePickerSheet
        }
        .sheet(isPresented: $showingCurrencyPicker) {
            currencyPickerSheet
        }
        .sheet(isPresented: $showingImageSourcePicker) {
            ImageSourcePicker(
                isPresented: $showingImageSourcePicker,
                selectedImage: $tempSelectedImage,
                onImageSelected: handleImageSelection
            )
        }
        .onAppear {
            loadProfileData()
            loadProfileImage()
        }
    }

    // Отображение профиля
    private var profileDisplay: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Фото профиля
            HStack {
                if let image = profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(AppTheme.secondaryBackground)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "person.circle")
                                .font(.system(size: 40))
                                .foregroundColor(AppTheme.textSecondary)
                        )
                }

                Spacer()
            }

            // Информация о сотруднике
            if let employee = accounts.currentEmployee {
                VStack(alignment: .leading, spacing: 8) {
                    Text(lang.t("name") + ": \(employee.fullName ?? "—")")
                    Text("Email: \(employee.email ?? "—")")
                    Text(lang.t("position") + ": \(getRoleDisplayName(employee.rolesArray.first ?? "employee"))")
                    Text(lang.t("department") + ": \(getDepartmentDisplayName(employee.department ?? "unknown"))")
                }
                .foregroundColor(AppTheme.textSecondary)
            }

            Button {
                isEditingProfile = true
            } label: {
                Text(lang.t("edit_profile"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppTheme.primary)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }

    // Форма редактирования профиля
    private var profileEditForm: some View {
        VStack(spacing: 16) {
            // Фото профиля
            VStack {
                if let image = profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(AppTheme.secondaryBackground)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "person.circle")
                                .font(.system(size: 50))
                                .foregroundColor(AppTheme.textSecondary)
                        )
                }

                Button {
                    showingImageSourcePicker = true
                } label: {
                    Text(lang.t("change_photo"))
                        .font(.caption)
                        .foregroundColor(AppTheme.primary)
                }
            }

            // Поля редактирования
            VStack(spacing: 12) {
                TextField("Имя", text: $editedName)
                    .padding()
                    .background(AppTheme.secondaryBackground)
                    .cornerRadius(8)

                TextField("Email", text: $editedEmail)
                    .padding()
                    .background(AppTheme.secondaryBackground)
                    .cornerRadius(8)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
            }

            // Кнопки сохранения/отмены
            HStack(spacing: 12) {
                Button {
                    saveProfileChanges()
                } label: {
                    Text(lang.t("save"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.primary)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                Button {
                    cancelProfileEditing()
                } label: {
                    Text(lang.t("cancel"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.secondaryBackground)
                        .foregroundColor(AppTheme.textPrimary)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }

    // Личный график сотрудника
    private var personalScheduleView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if accounts.currentEmployee != nil {
                // TODO: Реализовать отображение личного графика
                Text("График сотрудника будет отображаться здесь")
                    .foregroundColor(AppTheme.textSecondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(AppTheme.secondaryBackground)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }

    // Выбор языка
    private var languagePickerSheet: some View {
        NavigationView {
            List(languages, id: \.0) { language in
                Button {
                    changeLanguage(to: language.0)
                } label: {
                    HStack {
                        Text(language.1)
                        Spacer()
                        if language.0 == lang.currentLang {
                            Image(systemName: "checkmark")
                                .foregroundColor(AppTheme.primary)
                        }
                    }
                }
            }
            .navigationTitle(lang.t("select_language"))
            .navigationBarItems(trailing: Button(lang.t("done")) {
                showingLanguagePicker = false
            })
        }
    }

    // Выбор валюты
    private var currencyPickerSheet: some View {
        NavigationView {
            List(currencies, id: \.0) { currency in
                Button {
                    changeCurrency(to: currency.0)
                } label: {
                    HStack {
                        Text(currency.1)
                        Spacer()
                        if currency.0 == appState.defaultCurrency {
                            Image(systemName: "checkmark")
                                .foregroundColor(AppTheme.primary)
                        }
                    }
                }
            }
            .navigationTitle(lang.t("select_currency"))
            .navigationBarItems(trailing: Button(lang.t("done")) {
                showingCurrencyPicker = false
            })
        }
    }

    // Вспомогательные функции
    private func loadProfileData() {
        if let employee = accounts.currentEmployee {
            editedName = employee.fullName ?? ""
            editedEmail = employee.email ?? ""
        }
        selectedLanguage = lang.currentLang
        selectedCurrency = appState.defaultCurrency
    }

    private func saveProfileChanges() {
        if let employee = accounts.currentEmployee {
            employee.fullName = editedName
            employee.email = editedEmail
            accounts.saveContext()
        }
        isEditingProfile = false
    }

    private func cancelProfileEditing() {
        loadProfileData()
        isEditingProfile = false
    }

    private func changeLanguage(to languageCode: String) {
        lang.setLang(languageCode)
        selectedLanguage = languageCode
        showingLanguagePicker = false
    }

    private func changeCurrency(to currencyCode: String) {
        appState.defaultCurrency = currencyCode
        selectedCurrency = currencyCode
        showingCurrencyPicker = false
    }

    private func getRoleDisplayName(_ role: String) -> String {
        // TODO: Добавить локализацию ролей
        switch role {
        case "owner": return "Владелец"
        case "executive_chef": return "Шеф-повар"
        case "sous_chef": return "Су-шеф"
        case "cook": return "Повар"
        case "brigadier": return "Бригадир"
        case "bartender": return "Бармен"
        case "waiter": return "Официант"
        default: return "Сотрудник"
        }
    }

    private func getDepartmentDisplayName(_ department: String) -> String {
        // TODO: Добавить локализацию отделов
        switch department {
        case "kitchen": return "Кухня"
        case "bar": return "Бар"
        case "dining_room": return "Зал"
        case "management": return "Управление"
        default: return "Неизвестно"
        }
    }

    // Обработка выбранного изображения
    private func handleImageSelection(_ image: UIImage) {
        // Автоматический ресайз в зависимости от платформы
        if let processedImage = ImageService.shared.processImage(image) {
            profileImage = processedImage
            saveProfileImage(processedImage)
        }
    }

    // Сохранение изображения профиля
    private func saveProfileImage(_ image: UIImage) {
        guard let employeeId = accounts.currentEmployee?.id else { return }

        let filename = "profile_\(employeeId.uuidString).jpg"
        if let _ = ImageService.shared.saveImageToDocuments(image, filename: filename) {
            print("✅ Фото профиля сохранено")
        }
    }

    // Загрузка изображения профиля при открытии профиля
    private func loadProfileImage() {
        guard let employeeId = accounts.currentEmployee?.id else { return }

        let filename = "profile_\(employeeId.uuidString).jpg"
        if let image = ImageService.shared.loadImageFromDocuments(filename: filename) {
            profileImage = image
        }
    }
}
