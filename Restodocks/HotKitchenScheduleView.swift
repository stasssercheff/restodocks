import SwiftUI

struct HotKitchenScheduleView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager

    private var hotShifts: [Shift] {
        accounts.shifts.filter { $0.department == "hot_kitchen" }
    }

    var body: some View {
        List {
            ForEach(hotShifts) { shift in
                VStack(alignment: .leading, spacing: 6) {
                    Text(accounts.employeeName(for: shift.employeeId))
                        .font(.headline)

                    Text(formatDate(shift.date))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if shift.fullDay {
                        Text(lang.t("full_day"))
                            .font(.caption)
                    } else {
                        Text("⏰ \(shift.startHour):00 – \(shift.endHour):00")
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle(lang.t("schedule"))
        .task {
            await accounts.fetchEmployees()
            await accounts.fetchShifts()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
