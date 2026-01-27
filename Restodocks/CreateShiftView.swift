//
//  CreateShiftView.swift
//  Restodocks
//

import SwiftUI

struct CreateShiftView: View {

    @ObservedObject var lang = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss

    // ВРЕМЕННО: потом будет из AccountManager
    let employees: [EmployeeAccount]

    @State private var selectedEmployee: EmployeeAccount?
    @State private var selectedDate = Date()
    @State private var fullDay = true

    @State private var startTime = "09:00"
    @State private var endTime = "18:00"

    @State private var department: Department = .kitchen
    @State private var kitchenSection: KitchenSection? = nil

    let onSave: (WorkShift) -> Void

    var body: some View {

        Form {

            // ===== СОТРУДНИК =====
            Section(header: Text(lang.t("employee"))) {
                Picker(lang.t("employee"), selection: $selectedEmployee) {
                    ForEach(employees) { employee in
                        Text(employee.fullName)
                            .tag(Optional(employee))
                    }
                }
            }

            // ===== ДАТА =====
            Section(header: Text(lang.t("date"))) {
                DatePicker(
                    lang.t("date"),
                    selection: $selectedDate,
                    displayedComponents: .date
                )
            }

            // ===== ПОДРАЗДЕЛЕНИЕ =====
            Section(header: Text(lang.t("department"))) {
                Picker(lang.t("department"), selection: $department) {
                    ForEach(Department.allCases) { dep in
                        Text(lang.t(dep.rawValue)).tag(dep)
                    }
                }
            }

            // ===== ЦЕХ КУХНИ =====
            if department == .kitchen {
                Section(header: Text(lang.t("kitchen_section"))) {
                    Picker(lang.t("kitchen_section"), selection: $kitchenSection) {
                        ForEach(KitchenSection.allCases) { section in
                            Text(lang.t(kitchenKey(section)))
                                .tag(Optional(section))
                        }
                    }
                }
            }

            // ===== ВРЕМЯ =====
            Section(header: Text(lang.t("shift_time"))) {

                Toggle(lang.t("full_day"), isOn: $fullDay)

                if !fullDay {
                    TextField(lang.t("start_time"), text: $startTime)
                    TextField(lang.t("end_time"), text: $endTime)
                }
            }

            // ===== СОХРАНИТЬ =====
            Button {
                saveShift()
            } label: {
                Text(lang.t("save"))
            }
            .disabled(selectedEmployee == nil)
        }
        .navigationTitle(lang.t("create_shift"))
    }

    // ===== СОХРАНЕНИЕ =====
    private func saveShift() {
        guard let employee = selectedEmployee else { return }

        let shift = WorkShift(
            id: UUID(),
            employeeId: employee.id,
            employeeName: employee.fullName,
            department: department,
            kitchenSection: department == .kitchen ? kitchenSection : nil,
            date: selectedDate,
            fullDay: fullDay,
            startTime: fullDay ? nil : startTime,
            endTime: fullDay ? nil : endTime
        )

        onSave(shift)
        dismiss()
    }

    // ===== КЛЮЧИ ПЕРЕВОДА =====
    private func kitchenKey(_ section: KitchenSection) -> String {
        switch section {
        case .hotKitchen:  return "hot_kitchen"
        case .coldKitchen: return "cold_kitchen"
        case .grill:       return "grill"
        case .pizza:       return "pizza"
        case .sushi:       return "sushi_bar"
        case .bakery:      return "bakery"
        case .pastry:      return "pastry"
        case .prep:        return "prep"
        }
    }
}