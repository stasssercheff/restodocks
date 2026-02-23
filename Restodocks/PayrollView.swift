//
//  PayrollView.swift
//  Restodocks
//
//  ФЗП: сотрудники, стоимость смены/часа, количество смен/часов, итого за месяц.
//

import SwiftUI
import CoreData

struct PayrollView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \EmployeeEntity.fullName, ascending: true)],
        animation: .default
    )
    private var employees: FetchedResults<EmployeeEntity>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ShiftEntity.date, ascending: true)],
        animation: .default
    )
    private var allShifts: FetchedResults<ShiftEntity>

    @State private var selectedMonth: Date = Date()
    @State private var editingEmployee: EmployeeEntity?
    @State private var editCost: String = ""
    @State private var editMode: String = "shift"
    @State private var showEditSheet = false

    private var calendar: Calendar { Calendar.current }
    private var monthStart: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth }
    private var monthEnd: Date { calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? selectedMonth }

    private var shiftsInMonth: [ShiftEntity] {
        allShifts.filter { shift in
            guard let d = shift.date else { return false }
            return d >= monthStart && d <= monthEnd
        }
    }

    private var shiftsByEmployee: [UUID: [ShiftEntity]] {
        Dictionary(grouping: shiftsInMonth) { shift in
            shift.employee?.id ?? UUID()
        }
    }

    var body: some View {
        List {
            Section {
                DatePicker(lang.t("month"), selection: $selectedMonth, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }

            Section(header: Text(lang.t("staff"))) {
                ForEach(employees) { emp in
                    payrollRow(for: emp)
                }
            }

            Section(header: Text(lang.t("total"))) {
                HStack {
                    Text(lang.t("total_payroll"))
                        .font(.headline)
                    Spacer()
                    Text(formatCurrency(grandTotal))
                        .font(.headline)
                        .foregroundColor(AppTheme.primary)
                }
            }
        }
        .navigationTitle(lang.t("payroll"))
        .sheet(isPresented: $showEditSheet) {
            if let emp = editingEmployee {
                PayrollEditSheet(
                    employee: emp,
                    cost: $editCost,
                    mode: $editMode,
                    onSave: { savePayrollConfig(emp) },
                    onDismiss: {
                        editingEmployee = nil
                        showEditSheet = false
                    }
                )
            }
        }
    }

    private func payrollRow(for emp: EmployeeEntity) -> some View {
        let empShifts = shiftsByEmployee[emp.id ?? UUID()] ?? []
        let (units, total) = calculateForEmployee(emp, shifts: empShifts)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(emp.fullName ?? "—")
                    .font(.headline)
                Spacer()
                Button {
                    editingEmployee = emp
                    editCost = emp.costPerUnit > 0 ? String(Int(emp.costPerUnit)) : ""
                    editMode = emp.payrollCountingMode ?? "shift"
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(AppTheme.primary)
                }
            }

            HStack {
                Text(unitLabel(emp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(formatCurrency(emp.costPerUnit))")
                    .font(.subheadline)
            }

            HStack {
                Text(lang.t("quantity"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1f", units))
                    .font(.subheadline)
            }

            HStack {
                Text(lang.t("total_for_month"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatCurrency(total))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
        .padding(.vertical, 4)
    }

    private func calculateForEmployee(_ emp: EmployeeEntity, shifts: [ShiftEntity]) -> (units: Double, total: Double) {
        let mode = emp.payrollCountingMode ?? "shift"
        let cost = emp.costPerUnit

        let units: Double
        if mode == "hour" {
            units = shifts.reduce(0) { sum, s in sum + shiftHours(s) }
        } else {
            units = Double(shifts.count)
        }

        return (units, units * cost)
    }

    private var grandTotal: Double {
        employees.reduce(0) { sum, emp in
            let shifts = shiftsByEmployee[emp.id ?? UUID()] ?? []
            let (_, total) = calculateForEmployee(emp, shifts: shifts)
            return sum + total
        }
    }

    private func shiftHours(_ shift: ShiftEntity) -> Double {
        if shift.fullDay {
            return 8
        }
        let start = Int(shift.startHour)
        let end = Int(shift.endHour)
        return max(0, Double(end - start))
    }

    private func unitLabel(_ emp: EmployeeEntity) -> String {
        (emp.payrollCountingMode ?? "shift") == "hour"
            ? lang.t("cost_per_hour")
            : lang.t("cost_per_shift")
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = appState.defaultCurrency
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func savePayrollConfig(_ emp: EmployeeEntity) {
        emp.costPerUnit = Double(editCost.replacingOccurrences(of: ",", with: ".")) ?? 0
        emp.payrollCountingMode = editMode
        try? context.save()
        editingEmployee = nil
        showEditSheet = false
    }
}

// MARK: - Edit Sheet

struct PayrollEditSheet: View {
    let employee: EmployeeEntity
    @Binding var cost: String
    @Binding var mode: String
    let onSave: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(employee.fullName ?? "—")) {
                    Picker(lang.t("calculation_mode"), selection: $mode) {
                        Text(lang.t("per_shift")).tag("shift")
                        Text(lang.t("per_hour")).tag("hour")
                    }
                    .pickerStyle(.segmented)

                    TextField(lang.t("cost_per_unit"), text: $cost)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle(lang.t("edit_payroll"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.t("cancel")) { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.t("save")) { onSave() }
                }
            }
        }
    }
}

