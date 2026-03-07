//
//  LanguageSelectionView.swift
//  Restodocks
//

import SwiftUI

struct LanguageSelectionView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var appState: AppState

    let onLanguageSelected: () -> Void

    /// Языки из Localizable.json — добавляя перевод для нового кода, он появится здесь
    private var languages: [(String, String, String)] {
        lang.supportedLanguages.map { code in
            let info = LocalizationManager.displayInfo(for: code)
            return (code, info.name, info.flag)
        }
    }

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

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
                Text(getWelcomeText())
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Описание
                Text(getDescriptionText())
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Кнопки выбора языка
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(languages, id: \.0) { language in
                            LanguageButton(
                                code: language.0,
                                name: language.1,
                                flag: language.2,
                                isSelected: lang.currentLang == language.0
                            ) {
                                lang.setLang(language.0)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 300)

                Spacer()

                // Кнопка продолжить
                PrimaryButton(title: getContinueText()) {
                    // Переходим к следующему экрану на основе состояния приложения
                    navigateToNextScreen()
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .padding(.vertical, 20)
        }
        .onAppear {
            // Если язык еще не выбран, устанавливаем английский по умолчанию
            if !lang.isLanguageSelected {
                lang.setLang("en")
            }
        }
    }

    private func getWelcomeText() -> String {
        switch lang.currentLang {
        case "ru": return "Добро пожаловать!"
        case "en": return "Welcome!"
        case "es": return "¡Bienvenido!"
        case "de": return "Willkommen!"
        case "fr": return "Bienvenue!"
        default: return "Welcome!"
        }
    }

    private func getDescriptionText() -> String {
        switch lang.currentLang {
        case "ru": return "Выберите язык для продолжения"
        case "en": return "Choose your language to continue"
        case "es": return "Elige tu idioma para continuar"
        case "de": return "Wählen Sie Ihre Sprache um fortzufahren"
        case "fr": return "Choisissez votre langue pour continuer"
        default: return "Choose your language to continue"
        }
    }

    private func getContinueText() -> String {
        switch lang.currentLang {
        case "ru": return "Продолжить"
        case "en": return "Continue"
        case "es": return "Continuar"
        case "de": return "Fortfahren"
        case "fr": return "Continuer"
        default: return "Continue"
        }
    }

    private func navigateToNextScreen() {
        // Вызываем callback для перехода к следующему экрану
        onLanguageSelected()
    }
}

struct LanguageButton: View {
    let code: String
    let name: String
    let flag: String
    let isSelected: Bool
    let action: () -> Void

    private var backgroundView: some View {
        Group {
            if isSelected {
                LinearGradient(
                    colors: [AppTheme.primary, AppTheme.primaryLight],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                AppTheme.cardBackground
            }
        }
    }

    private var shadowColor: Color {
        isSelected ? AppTheme.primary.opacity(0.3) : AppTheme.shadow
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {  // Уменьшил spacing
                Text(flag)
                    .font(.system(size: 24))  // Уменьшил размер флага

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))  // Уменьшил размер текста
                        .foregroundColor(isSelected ? AppTheme.textOnPrimary : AppTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)  // Позволяет тексту масштабироваться
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppTheme.accent)
                        .font(.system(size: 18))  // Уменьшил размер иконки
                }
            }
            .padding(.vertical, 14)  // Уменьшил вертикальный padding
            .padding(.horizontal, 16)  // Уменьшил горизонтальный padding
            .background(backgroundView)
            .cornerRadius(12)  // Уменьшил радиус скругления
            .shadow(color: shadowColor, radius: 4, y: 2)  // Уменьшил тень
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? AppTheme.primary : AppTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())  // Убирает стандартный стиль кнопки
    }
}