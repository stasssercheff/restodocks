import SwiftUI

struct ScheduleCopyView: View {
    @EnvironmentObject var accounts: AccountManager
    @Environment(\.dismiss) private var dismiss

    let department: String? // nil = все departments
    let onCopy: ((Date, Date), (Date, Date), Employee) async -> Void

    @State private var copyFromDate = Date()
    @State private var copyToDate = Date()
    @State private var pasteFromDate = Date()
    @State private var pasteToDate = Date()
    @State private var selectedEmployee: Employee?
    @State private var isCopying = false

    init(department: String? = nil, onCopy: @escaping ((Date, Date), (Date, Date), Employee) async -> Void) {
        self.department = department
        self.onCopy = onCopy
    }

    var filteredEmployees: [Employee] {
        if let dept = department {
            return accounts.employees.filter { $0.department == dept }
        }
        return accounts.employees
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Копировать диапазон")) {
                    DatePicker("С даты", selection: $copyFromDate, displayedComponents: .date)
                    DatePicker("По дату", selection: $copyToDate, displayedComponents: .date)
                }

                Section(header: Text("Вставить диапазон")) {
                    DatePicker("С даты", selection: $pasteFromDate, displayedComponents: .date)
                    DatePicker("По дату", selection: $pasteToDate, displayedComponents: .date)
                }

                Section(header: Text("Сотрудник")) {
                    Picker("Выберите сотрудника", selection: $selectedEmployee) {
                        ForEach(filteredEmployees) { employee in
                            Text(employee.fullName).tag(employee as Employee?)
                        }
                    }
                }

                Section {
                    Button("Копировать график") {
                        guard let employee = selectedEmployee else { return }
                        isCopying = true
                        Task {
                            await onCopy((copyFromDate, copyToDate), (pasteFromDate, pasteToDate), employee)
                            await MainActor.run {
                                isCopying = false
                                dismiss()
                            }
                        }
                    }
                    .disabled(selectedEmployee == nil || isCopying)
                }
            }
            .navigationTitle("Копирование графика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await accounts.fetchEmployees()
        }
    }
}