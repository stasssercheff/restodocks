//
//  SuppliersView.swift
//  Restodocks
//

import SwiftUI

struct SuppliersView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager

    @State private var selectedSupplier: Supplier?
    @State private var showingAddSupplier = false

    var body: some View {
        Group {
            if accounts.suppliers.isEmpty {
                ContentUnavailableView(
                    lang.t("suppliers"),
                    systemImage: "building.2",
                    description: Text(lang.t("suppliers_empty_hint"))
                )
            } else {
                List {
                    ForEach(accounts.suppliers) { supplier in
                        Button {
                            selectedSupplier = supplier
                        } label: {
                            SupplierRow(supplier: supplier)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await accounts.deleteSupplier(supplier)
                                }
                            } label: {
                                Text(lang.t("delete"))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(lang.t("suppliers"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddSupplier = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await accounts.fetchSuppliers()
        }
        .refreshable {
            await accounts.fetchSuppliers()
        }
        .sheet(item: $selectedSupplier) { supplier in
            SupplierEditView(supplier: supplier) {
                selectedSupplier = nil
            }
        }
        .sheet(isPresented: $showingAddSupplier) {
            SupplierEditView(isNew: true) {
                showingAddSupplier = false
            }
        }
    }
}

struct SupplierRow: View {
    let supplier: Supplier

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(supplier.name)
                .font(.headline)
                .foregroundColor(.primary)
            if let phone = supplier.phone, !phone.isEmpty {
                Label(phone, systemImage: "phone.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let email = supplier.email, !email.isEmpty {
                Label(email, systemImage: "envelope.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let address = supplier.address, !address.isEmpty {
                Label(address, systemImage: "mappin.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SupplierEditView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager
    @Environment(\.dismiss) private var dismiss

    let supplier: Supplier?
    let isNew: Bool
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var email: String = ""
    @State private var address: String = ""
    @State private var comment: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(supplier: Supplier? = nil, isNew: Bool = false, onDismiss: @escaping () -> Void) {
        self.supplier = supplier
        self.isNew = supplier == nil
        self.onDismiss = onDismiss
        _name = State(initialValue: supplier?.name ?? "")
        _phone = State(initialValue: supplier?.phone ?? "")
        _email = State(initialValue: supplier?.email ?? "")
        _address = State(initialValue: supplier?.address ?? "")
        _comment = State(initialValue: supplier?.comment ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(lang.t("supplier_name"))) {
                    TextField(lang.t("supplier_name_placeholder"), text: $name)
                        .textContentType(.name)
                }
                Section(header: Text(lang.t("supplier_contacts"))) {
                    TextField(lang.t("phone"), text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField(lang.t("email"), text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                }
                Section(header: Text(lang.t("address"))) {
                    TextField(lang.t("address_placeholder"), text: $address)
                        .textContentType(.streetAddressLine1)
                }
                Section(header: Text(lang.t("comment_optional"))) {
                    TextField(lang.t("comment_placeholder"), text: $comment, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(isNew ? lang.t("add_supplier") : lang.t("edit_supplier"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.t("cancel")) {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.t("save")) {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            do {
                if isNew {
                    try await accounts.createSupplier(
                        name: trimmedName,
                        phone: phone.isEmpty ? nil : phone.trimmingCharacters(in: .whitespaces),
                        email: email.isEmpty ? nil : email.trimmingCharacters(in: .whitespaces),
                        address: address.isEmpty ? nil : address.trimmingCharacters(in: .whitespaces),
                        comment: comment.isEmpty ? nil : comment.trimmingCharacters(in: .whitespaces)
                    )
                } else if let s = supplier {
                    var updated = s
                    updated.name = trimmedName
                    updated.phone = phone.isEmpty ? nil : phone.trimmingCharacters(in: .whitespaces)
                    updated.email = email.isEmpty ? nil : email.trimmingCharacters(in: .whitespaces)
                    updated.address = address.isEmpty ? nil : address.trimmingCharacters(in: .whitespaces)
                    updated.comment = comment.isEmpty ? nil : comment.trimmingCharacters(in: .whitespaces)
                    try await accounts.updateSupplier(updated)
                }
                onDismiss()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
