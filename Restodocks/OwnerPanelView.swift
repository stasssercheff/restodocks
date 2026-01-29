//
//  OwnerPanelView.swift
//  Restodocks
//

import SwiftUI
import CoreData

struct OwnerPanelView: View {

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var lang: LocalizationManager

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \EmployeeEntity.fullName, ascending: true)
        ],
        animation: .default
    )
    private var employees: FetchedResults<EmployeeEntity>

    var body: some View {
        List {

            Section(header: Text(lang.t("staff"))) {

                ForEach(employees) { employee in
                    VStack(alignment: .leading, spacing: 4) {

                        Text(employee.fullName ?? "—")
                            .font(.headline)

                        Text(employee.rolesArray.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(lang.t("owner_panel"))
    }
}
