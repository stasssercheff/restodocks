import SwiftUI

struct ScheduleCopyView: View {
    @EnvironmentObject var accounts: AccountManager
    @Environment(\.dismiss) private var dismiss

    let onCopy: ((Date, Date), (Date, Date), Employee) -> Void

    @State private var copyFromDate = Date()
    @State private var copyToDate = Date()
    @State private var pasteFromDate = Date()
    @State private var pasteToDate = Date()
    @State private var selectedEmployee: Employee?

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
                        ForEach(accounts.employees) { employee in
                            Text(employee.fullName).tag(employee as Employee?)
                        }
                    }
                }

                Section {
                    Button("Копировать график") {
                        guard let employee = selectedEmployee else { return }
                        onCopy((copyFromDate, copyToDate), (pasteFromDate, pasteToDate), employee)
                        dismiss()
                    }
                    .disabled(selectedEmployee == nil)
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