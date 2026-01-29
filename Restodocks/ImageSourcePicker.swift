//
//  ImageSourcePicker.swift
//  Restodocks
//
//  Диалог выбора источника изображения
//

import SwiftUI

struct ImageSourcePicker: View {
    @Binding var isPresented: Bool
    @Binding var selectedImage: UIImage?
    let onImageSelected: (UIImage) -> Void

    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Выберите источник")
                    .font(.headline)
                    .padding(.top)

                VStack(spacing: 16) {
                    Button {
                        showingCamera = true
                        isPresented = false
                    } label: {
                        HStack {
                            Image(systemName: "camera")
                                .font(.title2)
                            Text("Камера")
                                .font(.title3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                    }

                    Button {
                        showingPhotoLibrary = true
                        isPresented = false
                    } label: {
                        HStack {
                            Image(systemName: "photo")
                                .font(.title2)
                            Text("Галерея")
                                .font(.title3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarItems(trailing: Button("Отмена") {
                isPresented = false
            })
        }
        .sheet(isPresented: $showingCamera) {
            ImagePicker(selectedImage: $selectedImage, sourceType: .camera)
                .onDisappear {
                    if let image = selectedImage {
                        onImageSelected(image)
                    }
                }
        }
        .sheet(isPresented: $showingPhotoLibrary) {
            ImagePicker(selectedImage: $selectedImage, sourceType: .photoLibrary)
                .onDisappear {
                    if let image = selectedImage {
                        onImageSelected(image)
                    }
                }
        }
    }
}