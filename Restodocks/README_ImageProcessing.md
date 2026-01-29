# Система обработки изображений

## Обзор

Система автоматически оптимизирует изображения при загрузке для разных платформ:
- **Мобильные устройства**: маленькие превью (200x200px)
- **Планшеты**: средний размер (400x400px)
- **Десктоп**: полный размер (800x800px)

## Компоненты

### 1. ImageService
Основной сервис для обработки изображений.

**Методы:**
- `resizeImage(_:toSize:)` - изменение размера с сохранением пропорций
- `compressImage(_:quality:)` - сжатие в JPEG
- `processImage(_:forSize:)` - полная обработка (ресайз + оптимизация)
- `createCircularAvatar(from:size:)` - создание круглого аватара

**Размеры изображений:**
```swift
enum ImageSize {
    case thumbnail // 200x200, качество 0.7
    case medium    // 400x400, качество 0.8
    case full      // 800x800, качество 0.9
}
```

**Автоматическое определение размера:**
```swift
let optimalSize = ImageService.optimalSize
// Возвращает .thumbnail для маленьких экранов
// .medium для средних, .full для больших
```

### 2. ImagePicker
UIViewControllerRepresentable для выбора изображений из галереи или камеры.

**Использование:**
```swift
.sheet(isPresented: $showingPicker) {
    ImagePicker(selectedImage: $image, sourceType: .photoLibrary)
}
```

### 3. ImageSourcePicker
Диалог выбора источника изображения (камера/галерея).

**Использование:**
```swift
.sheet(isPresented: $showingSourcePicker) {
    ImageSourcePicker(
        isPresented: $showingSourcePicker,
        selectedImage: $tempImage,
        onImageSelected: handleImage
    )
}
```

## Пример использования в ProfileView

```swift
struct ProfileView: View {
    @State private var profileImage: UIImage?
    @State private var showingImageSourcePicker = false

    var body: some View {
        // Кнопка изменения фото
        Button {
            showingImageSourcePicker = true
        } label: {
            Text("Изменить фото")
        }

        // Sheet для выбора источника
        .sheet(isPresented: $showingImageSourcePicker) {
            ImageSourcePicker(
                isPresented: $showingImageSourcePicker,
                selectedImage: $profileImage,
                onImageSelected: handleImageSelection
            )
        }
    }

    private func handleImageSelection(_ image: UIImage) {
        // Автоматический ресайз
        if let processedImage = ImageService.shared.processImage(image) {
            profileImage = processedImage
            saveProfileImage(processedImage)
        }
    }
}
```

## Сохранение и загрузка

```swift
// Сохранение
let filename = "profile_\(userId).jpg"
ImageService.shared.saveImageToDocuments(image, filename: filename)

// Загрузка
let loadedImage = ImageService.shared.loadImageFromDocuments(filename: filename)
```

## Преимущества

1. **Автоматическая оптимизация** - изображения автоматически подстраиваются под устройство
2. **Экономия трафика** - маленькие превью для мобильных
3. **Быстрая загрузка** - сжатие уменьшает размер файлов
4. **Универсальность** - работает на iOS, iPadOS, macOS
5. **Простота использования** - один метод для полной обработки

## Тестирование

Используйте `ImageProcessingTestView` для проверки работы системы на разных устройствах.