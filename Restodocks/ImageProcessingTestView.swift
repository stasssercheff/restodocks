//
//  ImageProcessingTestView.swift
//  Restodocks
//
//  Тестовый view для проверки обработки изображений
//

import SwiftUI

struct ImageProcessingTestView: View {
    @State private var originalImage: UIImage?
    @State private var processedImage: UIImage?
    @State private var showingImagePicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Тест обработки изображений")
                    .font(.title2)
                    .bold()

                // Кнопка выбора изображения
                Button {
                    showingImagePicker = true
                } label: {
                    Text("Выбрать изображение")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                if let original = originalImage {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Оригинальное изображение:")
                            .font(.headline)

                        Image(uiImage: original)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(8)

                        Text("Размер: \(Int(original.size.width))x\(Int(original.size.height))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let processed = processedImage {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Обработанное изображение (\(ImageService.optimalSize)):")
                            .font(.headline)

                        Image(uiImage: processed)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(8)

                        Text("Размер: \(Int(processed.size.width))x\(Int(processed.size.height))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Качество сжатия: \(String(format: "%.1f", ImageService.optimalSize.compressionQuality))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Информация о платформе
                VStack(alignment: .leading, spacing: 8) {
                    Text("Информация о платформе:")
                        .font(.headline)

                    #if os(iOS)
                        Text("📱 iOS устройство")
                        let screenSize = UIScreen.main.bounds.size
                        Text("Размер экрана: \(Int(screenSize.width))x\(Int(screenSize.height))")
                        Text("Оптимальный размер: \(ImageService.optimalSize)")
                    #else
                        Text("💻 Десктоп/другая платформа")
                        Text("Оптимальный размер: \(ImageService.optimalSize)")
                    #endif
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $originalImage, sourceType: .photoLibrary)
                .onDisappear {
                    if let image = originalImage {
                        processedImage = ImageService.shared.processImage(image)
                    }
                }
        }
    }
}