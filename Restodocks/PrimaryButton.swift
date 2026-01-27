import SwiftUI

struct PrimaryButton: View {

    let title: String

    var body: some View {
        Text(title)
            .foregroundColor(AppTheme.textOnPrimary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppTheme.primary)
            .cornerRadius(12)
    }
}
