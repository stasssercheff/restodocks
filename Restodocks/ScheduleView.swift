import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager

    var body: some View {
        NavigationStack {
            List {
                ForEach(accounts.shifts) { shift in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(accounts.employeeName(for: shift.employeeId))
                            .font(.headline)

                        Text(formattedDate(shift.date))
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
                .onDelete(perform: deleteShift)
            }
            .navigationTitle(lang.t("schedule"))
            .task {
                await accounts.fetchEmployees()
                await accounts.fetchShifts()
            }
            .refreshable {
                await accounts.fetchShifts()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        CreateShiftView()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    private func deleteShift(at offsets: IndexSet) {
        for index in offsets {
            let shift = accounts.shifts[index]
            Task {
                await accounts.deleteShift(shift)
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
