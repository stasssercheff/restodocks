//
//  HotKitchenScheduleView.swift
//  Restodocks
//
//  Created by Stanislav Rebrikov on 1/6/26.
//


import SwiftUI
import CoreData

struct HotKitchenScheduleView: View {
    @EnvironmentObject var lang: LocalizationManager
    @Environment(\.managedObjectContext) private var context
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ShiftEntity.date, ascending: true)],
        predicate: NSPredicate(format: "department == %@", "hot_kitchen"),
        animation: .default
    )
    private var shifts: FetchedResults<ShiftEntity>
    
    var body: some View {
        List {
            ForEach(shifts, id: \.id) { shift in
                VStack(alignment: .leading, spacing: 6) {
                    Text(shift.employee?.fullName ?? "—")
                        .font(.headline)
                    
                    if let date = shift.date {
                        Text(formatDate(date))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if shift.fullDay {
                        Text(lang.t("full_day"))
                            .font(.caption)
                    } else {
                        Text("⏰ \(shift.startHour):00 – \(shift.endHour):00")
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle(lang.t("schedule"))
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}