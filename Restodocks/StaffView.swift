import SwiftUI

struct StaffView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager
    @EnvironmentObject var appState: AppState

    @State private var selectedEmployee: Employee?
    @State private var showingActionSheet = false
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var searchText = ""

    private var filteredEmployees: [Employee] {
        if searchText.isEmpty { return accounts.employees }
        let q = searchText.lowercased()
        return accounts.employees.filter {
            $0.fullName.lowercased().contains(q) ||
            $0.email.lowercased().contains(q) ||
            $0.department.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(lang.t("search_by_name"), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.top, 8)

            // Table header
            HStack(spacing: 0) {
                Text(lang.t("col_name"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(lang.t("dept_kitchen").prefix(1) + lang.t("dept_bar").prefix(1))
                    .hidden()
                    .frame(width: 0)
                Group {
                    Text(lang.t("department"))
                        .frame(width: 90, alignment: .leading)
                    Text(lang.t("position"))
                        .frame(width: 90, alignment: .leading)
                    Text(lang.t("payroll_mode"))
                        .frame(width: 70, alignment: .leading)
                    Text(lang.t("rate_per_unit"))
                        .frame(width: 60, alignment: .trailing)
                }
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.secondaryBackground)

            Divider()

            // Table rows
            if accounts.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if filteredEmployees.isEmpty {
                Spacer()
                Text(lang.t("empty"))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredEmployees.enumerated()), id: \.element.id) { idx, employee in
                            StaffTableRow(
                                employee: employee,
                                isEven: idx % 2 == 0,
                                onTap: {
                                    selectedEmployee = employee
                                    showingActionSheet = true
                                }
                            )
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .refreshable {
                    await accounts.fetchEmployees()
                }
            }
        }
        .navigationTitle(lang.t("staff"))
        .task {
            await accounts.fetchEmployees()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        popCurrentNavigationToRoot()
                    } label: {
                        Image(systemName: "house.fill")
                    }
                    .accessibilityLabel(lang.t("home"))
                    NavigationLink {
                        EmployeeRegistrationView()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .confirmationDialog(
            selectedEmployee?.fullName ?? "",
            isPresented: $showingActionSheet,
            titleVisibility: .visible
        ) {
            Button(lang.t("edit_profile")) {
                showingEditSheet = true
            }
            Button(lang.t("access")) {
                // TODO: открыть настройки доступа
            }
            Button(lang.t("delete"), role: .destructive) {
                showingDeleteAlert = true
            }
            Button(lang.t("cancel"), role: .cancel) {}
        }
        .alert(lang.t("delete"), isPresented: $showingDeleteAlert) {
            Button(lang.t("delete"), role: .destructive) {
                if let emp = selectedEmployee {
                    Task { await accounts.deleteEmployee(emp) }
                }
            }
            Button(lang.t("cancel"), role: .cancel) {}
        } message: {
            Text(lang.t("confirm_delete"))
        }
        .sheet(isPresented: $showingEditSheet) {
            if let emp = selectedEmployee {
                EmployeeEditSheet(employee: emp)
            }
        }
    }
}

// MARK: - Table Row

private struct StaffTableRow: View {
    let employee: Employee
    let isEven: Bool
    let onTap: () -> Void

    @ObservedObject private var lang = LocalizationManager.shared

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(employee.fullName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(employee.email)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(localizedDept(employee.department))
                    .font(.caption)
                    .foregroundColor(.blue)
                    .frame(width: 90, alignment: .leading)
                    .lineLimit(1)

                Text(localizedRole(employee.rolesArray.first ?? "employee"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)
                    .lineLimit(1)

                Text(localizedPayMode(employee.payrollCountingMode))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .leading)
                    .lineLimit(1)

                if let cost = employee.costPerUnit {
                    Text(String(format: "%.0f", cost))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isEven ? Color.clear : AppTheme.secondaryBackground.opacity(0.4))
        }
        .buttonStyle(.plain)
    }

    private func localizedDept(_ dept: String) -> String {
        switch dept {
        case "kitchen": return lang.t("dept_kitchen")
        case "bar": return lang.t("dept_bar")
        case "dining_room": return lang.t("dept_dining_room")
        case "management": return lang.t("dept_management")
        default: return dept.capitalized
        }
    }

    private func localizedRole(_ role: String) -> String {
        switch role {
        case "owner": return lang.t("role_owner")
        case "executive_chef": return lang.t("role_executive_chef")
        case "sous_chef": return lang.t("role_sous_chef")
        case "cook": return lang.t("role_cook")
        case "brigadier": return lang.t("role_brigadier")
        case "bartender": return lang.t("role_bartender")
        case "waiter": return lang.t("role_waiter")
        default: return lang.t("role_employee")
        }
    }

    private func localizedPayMode(_ mode: String?) -> String {
        switch mode {
        case "hourly": return lang.t("payroll_mode_hourly")
        case "shift": return lang.t("payroll_mode_shift")
        default: return "—"
        }
    }
}

// MARK: - Edit Sheet

private struct EmployeeEditSheet: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager
    @Environment(\.dismiss) private var dismiss

    let employee: Employee

    @State private var fullName: String
    @State private var selectedDept: String
    @State private var selectedRole: String
    @State private var selectedPayMode: String
    @State private var costPerUnit: Double

    private let departments = ["kitchen", "bar", "dining_room", "management"]
    private let roles = ["owner", "executive_chef", "sous_chef", "cook", "brigadier", "bartender", "waiter", "employee"]
    private let payModes = ["hourly", "shift"]

    init(employee: Employee) {
        self.employee = employee
        _fullName = State(initialValue: employee.fullName)
        _selectedDept = State(initialValue: employee.department)
        _selectedRole = State(initialValue: employee.rolesArray.first ?? "employee")
        _selectedPayMode = State(initialValue: employee.payrollCountingMode ?? "hourly")
        _costPerUnit = State(initialValue: employee.costPerUnit ?? 0)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(lang.t("personal_data"))) {
                    TextField(lang.t("name"), text: $fullName)
                }

                Section(header: Text(lang.t("department"))) {
                    Picker(lang.t("department"), selection: $selectedDept) {
                        ForEach(departments, id: \.self) { dept in
                            Text(localizedDept(dept)).tag(dept)
                        }
                    }
                }

                Section(header: Text(lang.t("position"))) {
                    Picker(lang.t("position"), selection: $selectedRole) {
                        ForEach(roles, id: \.self) { role in
                            Text(localizedRole(role)).tag(role)
                        }
                    }
                }

                Section(header: Text(lang.t("payroll_mode"))) {
                    Picker(lang.t("payroll_mode"), selection: $selectedPayMode) {
                        ForEach(payModes, id: \.self) { mode in
                            Text(localizedPayMode(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text(lang.t("rate_per_unit"))
                        Spacer()
                        TextField("0", value: $costPerUnit, formatter: NumberFormatter.decimal)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
            }
            .navigationTitle(lang.t("edit_profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.t("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.t("save")) {
                        Task {
                            await accounts.updateEmployee(
                                employee,
                                fullName: fullName,
                                department: selectedDept,
                                role: selectedRole,
                                payMode: selectedPayMode,
                                costPerUnit: costPerUnit
                            )
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func localizedDept(_ dept: String) -> String {
        switch dept {
        case "kitchen": return lang.t("dept_kitchen")
        case "bar": return lang.t("dept_bar")
        case "dining_room": return lang.t("dept_dining_room")
        case "management": return lang.t("dept_management")
        default: return dept.capitalized
        }
    }

    private func localizedRole(_ role: String) -> String {
        switch role {
        case "owner": return lang.t("role_owner")
        case "executive_chef": return lang.t("role_executive_chef")
        case "sous_chef": return lang.t("role_sous_chef")
        case "cook": return lang.t("role_cook")
        case "brigadier": return lang.t("role_brigadier")
        case "bartender": return lang.t("role_bartender")
        case "waiter": return lang.t("role_waiter")
        default: return lang.t("role_employee")
        }
    }

    private func localizedPayMode(_ mode: String) -> String {
        switch mode {
        case "hourly": return lang.t("payroll_mode_hourly")
        case "shift": return lang.t("payroll_mode_shift")
        default: return mode
        }
    }
}

private extension NumberFormatter {
    static var decimal: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }
}
