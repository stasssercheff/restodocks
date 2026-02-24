//
//  PayrollView.swift
//  Restodocks
//

import SwiftUI

struct PayrollView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var accounts: AccountManager

    @State private var selectedMonth: Date = Date()
    @State private var editingEmployee: Employee?
    @State private var editCost: String = ""
    @State private var editMode: String = "shift"
    @State private var showEditSheet = false

    private var calendar: Calendar { Calendar.current }
    private var monthStart: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth }
    private var monthEnd: Date { calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? selectedMonth }

    private var shiftsInMonth: [Shift] {
        accounts.shifts.filter { $0.date >= monthStart && $0.date <= monthEnd }
    }

    private var shiftsByEmployee: [UUID: [Shift]] {
        Dictionary(grouping: shiftsInMonth) { $0.employeeId }
    }

    var body: some View {
        List {
            Section {
                DatePicker(lang.t("month"), selection: $selectedMonth, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }

            Section(header: Text(lang.t("staff"))) {
                ForEach(accounts.employees) { emp in
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
        .task {
            await accounts.fetchEmployees()
            await accounts.fetchShifts()
        }
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

    private func payrollRow(for emp: Employee) -> some View {
        let empShifts = shiftsByEmployee[emp.id] ?? []
        let (units, total) = calculateForEmployee(emp, shifts: empShifts)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(emp.fullName)
                    .font(.headline)
                Spacer()
                Button {
                    editingEmployee = emp
                    editCost = (emp.costPerUnit ?? 0) > 0 ? String(Int(emp.costPerUnit ?? 0)) : ""
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
                Text(formatCurrency(emp.costPerUnit ?? 0))
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

    private func calculateForEmployee(_ emp: Employee, shifts: [Shift]) -> (units: Double, total: Double) {
        let mode = emp.payrollCountingMode ?? "shift"
        let cost = emp.costPerUnit ?? 0

        let units: Double
        if mode == "hour" {
            units = shifts.reduce(0) { sum, s in sum + shiftHours(s) }
        } else {
            units = Double(shifts.count)
        }

        return (units, units * cost)
    }

    private var grandTotal: Double {
        accounts.employees.reduce(0) { sum, emp in
            let shifts = shiftsByEmployee[emp.id] ?? []
            let (_, total) = calculateForEmployee(emp, shifts: shifts)
            return sum + total
        }
    }

    private func shiftHours(_ shift: Shift) -> Double {
        if shift.fullDay { return 8 }
        return max(0, Double(shift.endHour - shift.startHour))
    }

    private func unitLabel(_ emp: Employee) -> String {
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

    private func savePayrollConfig(_ emp: Employee) {
        let cost = Double(editCost.replacingOccurrences(of: ",", with: ".")) ?? 0
        Task {
            await accounts.updateEmployeePayroll(employeeId: emp.id, costPerUnit: cost, payrollCountingMode: editMode)
        }
        editingEmployee = nil
        showEditSheet = false
    }
}

struct PayrollEditSheet: View {
    let employee: Employee
    @Binding var cost: String
    @Binding var mode: String
    let onSave: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(employee.fullName)) {
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
