//
//  ScheduleView.swift
//  Restodocks
//

import SwiftUI
import CoreData

struct ScheduleView: View {
    @EnvironmentObject var lang: LocalizationManager
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ShiftEntity.date, ascending: true)],
        animation: .default
    )
    private var shifts: FetchedResults<ShiftEntity>

    var body: some View {
        NavigationStack {

            List {
                ForEach(shifts) { shift in
                    VStack(alignment: .leading, spacing: 6) {

                        Text(shift.employee?.fullName ?? "—")
                            .font(.headline)

                        Text(formattedDate(shift.date))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if shift.fullDay {
                            Text(lang.t("full_day"))
                                .font(.caption)
                        } else {
                            Text("⏰ \(shift.startHour):00 – \(shift.endHour):00")
                                .font(.caption)
                        }
                    }
                }
                .onDelete(perform: deleteShift)
            }
            .navigationTitle(lang.t("schedule"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        CreateShiftView()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    // MARK: - DELETE

    private func deleteShift(at offsets: IndexSet) {
        for index in offsets {
            let shift = shifts[index]
            context.delete(shift)
        }

        do {
            try context.save()
        } catch {
            print("❌ Delete error:", error)
        }
    }

    // MARK: - DATE FORMAT

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
