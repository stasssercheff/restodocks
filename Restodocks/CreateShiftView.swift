//
//  CreateShiftView.swift
//  Restodocks
//

import SwiftUI
import CoreData

struct CreateShiftView: View {
    @EnvironmentObject var lang: LocalizationManager
    // Core Data
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    // сотрудники
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \EmployeeEntity.fullName, ascending: true)],
        animation: .default
    )
    private var employees: FetchedResults<EmployeeEntity>

    // state
    @State private var selectedEmployee: EmployeeEntity?
    @State private var date = Date()
    @State private var fullDay = false
    @State private var startHour: Int = 9
    @State private var endHour: Int = 18

    var body: some View {
        Form {

            // ===== СОТРУДНИК =====
            Section(header: Text(lang.t("employee"))) {
                Picker(lang.t("select_employee"), selection: $selectedEmployee) {
                    ForEach(employees) { emp in
                        Text(emp.fullName ?? "—")
                            .tag(emp as EmployeeEntity?)
                    }
                }
            }

            // ===== ДАТА =====
            Section(header: Text(lang.t("date"))) {
                DatePicker(
                    lang.t("shift_date"),
                    selection: $date,
                    displayedComponents: .date
                )
            }

            // ===== ТИП СМЕНЫ =====
            Section {
                Toggle(lang.t("full_day"), isOn: $fullDay)
            }

            // ===== ВРЕМЯ =====
            if !fullDay {
                Section(header: Text(lang.t("time"))) {
                    Stepper("\(lang.t("start")): \(startHour):00", value: $startHour, in: 0...23)
                    Stepper("\(lang.t("end")): \(endHour):00", value: $endHour, in: 0...23)
                }
            }

            // ===== СОХРАНИТЬ =====
            Section {
                Button(lang.t("create_shift")) {
                    createShift()
                }
                .disabled(selectedEmployee == nil)
            }
        }
        .navigationTitle(lang.t("new_shift"))
    }

    // MARK: - CREATE

    private func createShift() {
        guard let employee = selectedEmployee else { return }

        let shift = ShiftEntity(context: context)
        shift.id = UUID()
        shift.date = date
        shift.department = employee.department ?? "unknown"
        shift.fullDay = fullDay
        shift.startHour = fullDay ? 0 : Int16(startHour)
        shift.endHour = fullDay ? 0 : Int16(endHour)
        shift.employee = employee

        do {
            try context.save()
            dismiss()
        } catch {
            print("❌ Shift save error:", error)
        }
    }
}
