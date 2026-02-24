import SwiftUI

struct CreateShiftView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEmployee: Employee?
    @State private var date = Date()
    /// По умолчанию fullDay = true — выключен выбор времени (полный день/выходной).
    @State private var fullDay = true
    @State private var startHour: Int = 9
    @State private var endHour: Int = 18
    @State private var isSaving = false

    var body: some View {
        Form {
            Section(header: Text(lang.t("employee"))) {
                Picker(lang.t("select_employee"), selection: $selectedEmployee) {
                    Text("—").tag(nil as Employee?)
                    ForEach(accounts.employees) { emp in
                        Text(emp.fullName).tag(emp as Employee?)
                    }
                }
            }

            Section(header: Text(lang.t("date"))) {
                DatePicker(
                    lang.t("shift_date"),
                    selection: $date,
                    displayedComponents: .date
                )
            }

            Section {
                Toggle(lang.t("full_day"), isOn: $fullDay)
            }

            if !fullDay {
                Section(header: Text(lang.t("time"))) {
                    Stepper("\(lang.t("start")): \(startHour):00", value: $startHour, in: 0...23)
                    Stepper("\(lang.t("end")): \(endHour):00", value: $endHour, in: 0...23)
                }
            }

            Section {
                Button(lang.t("create_shift")) {
                    createShift()
                }
                .disabled(selectedEmployee == nil || isSaving)
            }
        }
        .navigationTitle(lang.t("new_shift"))
        .onAppear {
            fullDay = true
        }
        .task {
            await accounts.fetchEmployees()
        }
    }

    private func createShift() {
        guard let employee = selectedEmployee else { return }
        isSaving = true
        Task { @MainActor in
            do {
                try await accounts.createShift(
                    employeeId: employee.id,
                    date: date,
                    department: employee.department,
                    startHour: fullDay ? 0 : Int16(startHour),
                    endHour: fullDay ? 0 : Int16(endHour),
                    fullDay: fullDay
                )
                dismiss()
            } catch {
                print("❌ Shift save error:", error)
            }
            isSaving = false
        }
    }
}
