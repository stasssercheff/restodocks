import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager

    let department: String? // nil = все, иначе фильтр по department

    init(department: String? = nil) {
        self.department = department
    }

    var filteredShifts: [Shift] {
        if let dept = department {
            return accounts.shifts.filter { $0.department == dept }
        }
        return accounts.shifts
    }

    var body: some View {
        List {
            ForEach(filteredShifts) { shift in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(accounts.employeeName(for: shift.employeeId))
                            .font(.headline)
                        Text(formattedDate(shift.date))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Text(positionDisplayName(accounts.employeePosition(for: shift.employeeId)))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(6)
                    Spacer()
                    if shift.fullDay {
                        Text(lang.t("full_day"))
                            .font(.caption)
                    } else {
                        Text("⏰ \(shift.startHour):00 – \(shift.endHour):00")
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
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

    private func deleteShift(at offsets: IndexSet) {
        for index in offsets {
            let shift = filteredShifts[index]
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

    private func positionDisplayName(_ role: String) -> String {
        let translated = lang.t(role)
        return translated != role ? translated : role.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
