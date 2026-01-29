import SwiftUI

enum AppTheme {

    // MARK: - Brand Colors (Restaurant Theme - Logo Red)
    static let primary = Color(red: 0.678, green: 0.161, blue: 0.173) // #AD292C - Логотип красный
    static let primaryLight = Color(red: 0.808, green: 0.369, blue: 0.384) // #CE5E62 - Светлый красный
    static let accent = Color(red: 0.902, green: 0.710, blue: 0.275) // #E6B546 - Золотой акцент
    static let accentSecondary = Color(red: 0.741, green: 0.569, blue: 0.216) // #BD9137 - Темный золотой

    // MARK: - Backgrounds (Clean and Modern)
    static let background = Color(red: 0.996, green: 0.988, blue: 0.976) // #FEFCF9 - Очень светлый кремовый
    static let secondaryBackground = Color(red: 0.984, green: 0.976, blue: 0.961) // #FBF9F5 - Светлый кремовый
    static let cardBackground = Color.white
    static let overlayBackground = Color.black.opacity(0.03)

    // MARK: - Text Colors (Modern grays)
    static let textPrimary = Color(red: 0.200, green: 0.200, blue: 0.200) // #333333 - Темный серый
    static let textSecondary = Color(red: 0.502, green: 0.502, blue: 0.502) // #808080 - Средний серый
    static let textTertiary = Color(red: 0.698, green: 0.698, blue: 0.698) // #B2B2B2 - Светлый серый
    static let textOnPrimary = Color.white
    static let textOnAccent = Color(red: 0.678, green: 0.161, blue: 0.173) // Красный на золотом

    // MARK: - Status Colors
    static let success = Color(red: 0.267, green: 0.569, blue: 0.376) // #44915F - Зеленый успех
    static let warning = Color(red: 0.902, green: 0.710, blue: 0.275) // #E6B546 - Золотой предупреждение
    static let error = Color(red: 0.753, green: 0.318, blue: 0.282) // #C05148 - Красный ошибка
    static let info = Color(red: 0.208, green: 0.341, blue: 0.475) // #355770 - Синий информация

    // MARK: - UI Elements (Clean borders)
    static let border = Color(red: 0.890, green: 0.890, blue: 0.890) // #E3E3E3 - Светло-серая граница
    static let divider = Color(red: 0.929, green: 0.929, blue: 0.929) // #EDEDED - Разделитель
    static let shadow = Color.black.opacity(0.06)

    // MARK: - Interactive States
    static let pressed = Color(red: 0.678, green: 0.161, blue: 0.173).opacity(0.8)
    static let disabled = Color(red: 0.698, green: 0.698, blue: 0.698)
    static let highlight = Color(red: 0.902, green: 0.710, blue: 0.275).opacity(0.08)

    // MARK: - Semantic Colors (Restaurant specific)
    static let glutenFree = Color(red: 0.267, green: 0.569, blue: 0.376) // Зеленый для безглютеновых
    static let lactoseFree = Color(red: 0.208, green: 0.341, blue: 0.475) // Синий для безлактозных
    static let containsAllergen = Color(red: 0.753, green: 0.318, blue: 0.282) // Красный для аллергенов

    // MARK: - Kitchen Section Colors (for visual distinction)
    static let hotKitchen = Color(red: 0.753, green: 0.318, blue: 0.282) // Красный для горячего цеха
    static let coldKitchen = Color(red: 0.314, green: 0.569, blue: 0.635) // Голубой для холодного цеха
    static let grill = Color(red: 0.667, green: 0.427, blue: 0.208) // Коричневый для гриля
    static let bar = Color(red: 0.451, green: 0.341, blue: 0.608) // Фиолетовый для бара
    static let diningRoom = Color(red: 0.902, green: 0.710, blue: 0.275) // Золотой для зала
}
