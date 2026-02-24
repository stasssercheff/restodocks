import SwiftUI

struct ShiftRowView: View {
    let shift: Shift
    let employeeName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(employeeName)
                    .font(.body)
                    .bold()

                if shift.fullDay {
                    Text("full_day")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(shift.startHour):00 – \(shift.endHour):00")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
