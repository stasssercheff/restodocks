import SwiftUI
import CoreData

struct StaffView: View {
    @EnvironmentObject var lang: LocalizationManager
    @Environment(\.managedObjectContext) private var context
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \EmployeeEntity.fullName, ascending: true)],
        animation: .default
    )
    private var employees: FetchedResults<EmployeeEntity>

    var body: some View {
        List {
            ForEach(employees) { employee in
                VStack(alignment: .leading, spacing: 4) {
                    Text(employee.fullName ?? "—")
                        .font(.headline)
                    
                    if let email = employee.email {
                        Text(email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let department = employee.department {
                        Text(department.capitalized)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    if !employee.rolesArray.isEmpty {
                        Text(employee.rolesArray.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteEmployees)
            }
            .navigationTitle(lang.t("staff"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    EmployeeRegistrationView()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
    
    private func deleteEmployees(at offsets: IndexSet) {
        for index in offsets {
            let employee = employees[index]
            context.delete(employee)
        }
        
        do {
            try context.save()
        } catch {
            print("❌ Delete error:", error)
        }
    }
}
