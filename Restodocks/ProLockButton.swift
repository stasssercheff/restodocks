import SwiftUI

struct ProLockButton: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .medium))

            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.red)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
