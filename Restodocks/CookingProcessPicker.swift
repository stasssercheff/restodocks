//
//  CookingProcessPicker.swift
//  Restodocks
//
//  Компонент для выбора кулинарного процесса
//

import SwiftUI

struct CookingProcessPicker: View {
    @EnvironmentObject var lang: LocalizationManager
    let productCategory: String
    @Binding var selectedProcess: CookingProcess?
    @State private var showingPicker = false

    private var availableProcesses: [CookingProcess] {
        CookingProcessManager.shared.processesForCategory(productCategory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.t("cooking_process"))
                .font(.headline)

            Button {
                showingPicker = true
            } label: {
                HStack {
                    Text(selectedProcess?.localizedName ?? lang.t("select_cooking_process"))
                        .foregroundColor(selectedProcess == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
            }
        }
        .sheet(isPresented: $showingPicker) {
            NavigationView {
                List(availableProcesses) { process in
                    Button {
                        selectedProcess = process
                        showingPicker = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(process.localizedName)
                                .font(.headline)

                            HStack(spacing: 12) {
                                Text("\(lang.t("weight_loss")): \(Int(process.weightLossPercentage))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("К: x\(String(format: "%.2f", process.calorieMultiplier))")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .navigationTitle(lang.t("select_cooking_process"))
                .navigationBarItems(
                    leading: Button(lang.t("cancel")) {
                        showingPicker = false
                    },
                    trailing: Button(lang.t("done")) {
                        showingPicker = false
                    }
                )
            }
        }
    }
}

// Расширение для локализации
extension LocalizationManager {
    func t(_ key: String, args: [String]) -> String {
        // Для будущей реализации с аргументами
        return t(key)
    }
}