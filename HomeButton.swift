import SwiftUI

struct HomeButton: View {
    let title: String
    var systemImage: String = "chevron.right"

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .medium))

            Spacer()

            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
