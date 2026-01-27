import SwiftUI

enum AppTheme {

    // MARK: - Brand
    static let primary = Color(red: 0.694, green: 0.165, blue: 0.173) // #B12A2C
    static let primaryDark = Color(red: 0.55, green: 0.12, blue: 0.13)

    // MARK: - Backgrounds
    static let background = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)

    // MARK: - Text
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textOnPrimary = Color.white

    // MARK: - UI States
    static let disabled = Color.gray.opacity(0.4)
    static let divider = Color.gray.opacity(0.2)
}
