//
//  ImageService.swift
//  Restodocks
//
//  Сервис для обработки изображений с автоматическим ресайзом
//

import UIKit
import SwiftUI

class ImageService {
    static let shared = ImageService()

    // Размеры изображений для разных платформ
    enum ImageSize {
        case thumbnail // Маленькое превью для мобильных (200x200)
        case medium    // Средний размер для планшетов (400x400)
        case full      // Полный размер для десктопа (800x800)

        var maxSize: CGSize {
            switch self {
            case .thumbnail:
                return CGSize(width: 200, height: 200)
            case .medium:
                return CGSize(width: 400, height: 400)
            case .full:
                return CGSize(width: 800, height: 800)
            }
        }

        var compressionQuality: CGFloat {
            switch self {
            case .thumbnail:
                return 0.7
            case .medium:
                return 0.8
            case .full:
                return 0.9
            }
        }
    }

    // Определение подходящего размера на основе устройства
    static var optimalSize: ImageSize {
        #if os(iOS)
            let screenSize = UIScreen.main.bounds.size
            let maxDimension = max(screenSize.width, screenSize.height)

            if maxDimension <= 600 {
                // iPhone SE, маленькие экраны
                return .thumbnail
            } else if maxDimension <= 900 {
                // iPhone обычный, средние экраны
                return .medium
            } else {
                // iPad, большие экраны
                return .full
            }
        #else
            // macOS и другие платформы
            return .full
        #endif
    }

    // Ресайз изображения с сохранением пропорций
    func resizeImage(_ image: UIImage, toSize size: ImageSize) -> UIImage? {
        let maxSize = size.maxSize

        // Рассчитываем размер с сохранением пропорций
        let aspectRatio = image.size.width / image.size.height

        var newSize: CGSize
        if aspectRatio > 1 {
            // Широкое изображение
            newSize = CGSize(width: maxSize.width, height: maxSize.width / aspectRatio)
        } else {
            // Высокое изображение
            newSize = CGSize(width: maxSize.height * aspectRatio, height: maxSize.height)
        }

        // Ограничиваем максимальный размер
        if newSize.width > maxSize.width {
            newSize = CGSize(width: maxSize.width, height: maxSize.width / aspectRatio)
        }
        if newSize.height > maxSize.height {
            newSize = CGSize(width: maxSize.height * aspectRatio, height: maxSize.height)
        }

        // Создаем контекст для рисования
        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        // Рисуем изображение
        image.draw(in: CGRect(origin: .zero, size: newSize))

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // Сжатие изображения в JPEG с указанным качеством
    func compressImage(_ image: UIImage, quality: CGFloat) -> Data? {
        return image.jpegData(compressionQuality: quality)
    }

    // Полная обработка изображения: ресайз + сжатие
    func processImage(_ image: UIImage, forSize size: ImageSize = optimalSize) -> UIImage? {
        guard let resizedImage = resizeImage(image, toSize: size) else {
            return nil
        }
        return resizedImage
    }

    // Полная обработка с возвратом Data для сохранения
    func processImageToData(_ image: UIImage, forSize size: ImageSize = optimalSize) -> Data? {
        guard let processedImage = processImage(image, forSize: size) else {
            return nil
        }
        return compressImage(processedImage, quality: size.compressionQuality)
    }

    // Создание кругового аватара из квадратного изображения
    func createCircularAvatar(from image: UIImage, size: CGSize = CGSize(width: 100, height: 100)) -> UIImage? {
        let rect = CGRect(origin: .zero, size: size)

        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // Создаем круглую маску
        context.addEllipse(in: rect)
        context.clip()

        // Рисуем изображение
        image.draw(in: rect)

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // Сохранение изображения в документы приложения
    func saveImageToDocuments(_ image: UIImage, filename: String, size: ImageSize = optimalSize) -> URL? {
        guard let data = processImageToData(image, forSize: size) else {
            return nil
        }

        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("❌ Ошибка сохранения изображения: \(error)")
            return nil
        }
    }

    // Загрузка изображения из документов
    func loadImageFromDocuments(filename: String) -> UIImage? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDirectory.appendingPathComponent(filename)

        do {
            let data = try Data(contentsOf: fileURL)
            return UIImage(data: data)
        } catch {
            print("❌ Ошибка загрузки изображения: \(error)")
            return nil
        }
    }
}