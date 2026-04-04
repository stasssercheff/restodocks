#!/usr/bin/env python3
"""Merge UI keys into assets/translations/localizable.json (all 8 locales)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "assets/translations/localizable.json"

# Keys: semantic id -> { locale: text }
# Locales: ru en es de fr it tr vi
LANGS = ("ru", "en", "es", "de", "fr", "it", "tr", "vi")

# Language names as shown in language picker (in each UI language)
LANG_NAMES = {
    "ru": {
        "ru": "Русский",
        "en": "Английский",
        "es": "Испанский",
        "de": "Немецкий",
        "fr": "Французский",
        "it": "Итальянский",
        "tr": "Турецкий",
        "vi": "Вьетнамский",
    },
    "en": {
        "ru": "Russian",
        "en": "English",
        "es": "Spanish",
        "de": "German",
        "fr": "French",
        "it": "Italian",
        "tr": "Turkish",
        "vi": "Vietnamese",
    },
    "es": {
        "ru": "Ruso",
        "en": "Inglés",
        "es": "Español",
        "de": "Alemán",
        "fr": "Francés",
        "it": "Italiano",
        "tr": "Turco",
        "vi": "Vietnamita",
    },
    "de": {
        "ru": "Russisch",
        "en": "Englisch",
        "es": "Spanisch",
        "de": "Deutsch",
        "fr": "Französisch",
        "it": "Italienisch",
        "tr": "Türkisch",
        "vi": "Vietnamesisch",
    },
    "fr": {
        "ru": "Russe",
        "en": "Anglais",
        "es": "Espagnol",
        "de": "Allemand",
        "fr": "Français",
        "it": "Italien",
        "tr": "Turc",
        "vi": "Vietnamien",
    },
    "it": {
        "ru": "Russo",
        "en": "Inglese",
        "es": "Spagnolo",
        "de": "Tedesco",
        "fr": "Francese",
        "it": "Italiano",
        "tr": "Turco",
        "vi": "Vietnamita",
    },
    "tr": {
        "ru": "Rusça",
        "en": "İngilizce",
        "es": "İspanyolca",
        "de": "Almanca",
        "fr": "Fransızca",
        "it": "İtalyanca",
        "tr": "Türkçe",
        "vi": "Vietnamca",
    },
    "vi": {
        "ru": "Tiếng Nga",
        "en": "Tiếng Anh",
        "es": "Tiếng Tây Ban Nha",
        "de": "Tiếng Đức",
        "fr": "Tiếng Pháp",
        "it": "Tiếng Ý",
        "tr": "Tiếng Thổ Nhĩ Kỳ",
        "vi": "Tiếng Việt",
    },
}

def build_lang_name_keys():
    out = {lang: {} for lang in LANGS}
    for ui_lang in LANGS:
        for code in LANGS:
            out[ui_lang][f"lang_name_{code}"] = LANG_NAMES[ui_lang][code]
    return out


def flat_merge(*dicts):
    merged = {lang: {} for lang in LANGS}
    for d in dicts:
        for lang in LANGS:
            merged[lang].update(d.get(lang, {}))
    return merged


# Router & common
ROUTER = {
    "ru": {
        "router_invalid_link": "Недействительная ссылка",
        "router_invalid_invitation_link": "Недействительная ссылка приглашения",
        "router_error_title": "Ошибка",
        "router_screen_load_error": "Ошибка загрузки экрана: {error}",
    },
    "en": {
        "router_invalid_link": "Invalid link",
        "router_invalid_invitation_link": "Invalid invitation link",
        "router_error_title": "Error",
        "router_screen_load_error": "Could not load screen: {error}",
    },
    "es": {
        "router_invalid_link": "Enlace no válido",
        "router_invalid_invitation_link": "Enlace de invitación no válido",
        "router_error_title": "Error",
        "router_screen_load_error": "No se pudo cargar la pantalla: {error}",
    },
    "de": {
        "router_invalid_link": "Ungültiger Link",
        "router_invalid_invitation_link": "Ungültiger Einladungslink",
        "router_error_title": "Fehler",
        "router_screen_load_error": "Bildschirm konnte nicht geladen werden: {error}",
    },
    "fr": {
        "router_invalid_link": "Lien invalide",
        "router_invalid_invitation_link": "Lien d’invitation invalide",
        "router_error_title": "Erreur",
        "router_screen_load_error": "Impossible de charger l’écran : {error}",
    },
    "it": {
        "router_invalid_link": "Link non valido",
        "router_invalid_invitation_link": "Link di invito non valido",
        "router_error_title": "Errore",
        "router_screen_load_error": "Impossibile caricare la schermata: {error}",
    },
    "tr": {
        "router_invalid_link": "Geçersiz bağlantı",
        "router_invalid_invitation_link": "Geçersiz davet bağlantısı",
        "router_error_title": "Hata",
        "router_screen_load_error": "Ekran yüklenemedi: {error}",
    },
    "vi": {
        "router_invalid_link": "Liên kết không hợp lệ",
        "router_invalid_invitation_link": "Liên kết mời không hợp lệ",
        "router_error_title": "Lỗi",
        "router_screen_load_error": "Không tải được màn hình: {error}",
    },
}

SETTINGS_EXTRA = {
    "ru": {
        "settings_clearing_ttk": "Удаление ТТК…",
        "settings_beta_admin_subtitle": "Временно для тестов (Beta)",
        "settings_platform_admin_title": "Администратор платформы",
        "settings_platform_admin_subtitle": "Промокоды и управление",
    },
    "en": {
        "settings_clearing_ttk": "Deleting tech cards…",
        "settings_beta_admin_subtitle": "Temporary for tests (Beta)",
        "settings_platform_admin_title": "Platform admin",
        "settings_platform_admin_subtitle": "Promo codes and management",
    },
    "es": {
        "settings_clearing_ttk": "Eliminando fichas técnicas…",
        "settings_beta_admin_subtitle": "Temporal para pruebas (Beta)",
        "settings_platform_admin_title": "Administrador de la plataforma",
        "settings_platform_admin_subtitle": "Códigos promocionales y gestión",
    },
    "de": {
        "settings_clearing_ttk": "Technikkarten werden gelöscht…",
        "settings_beta_admin_subtitle": "Vorübergehend für Tests (Beta)",
        "settings_platform_admin_title": "Plattform-Administrator",
        "settings_platform_admin_subtitle": "Promo-Codes und Verwaltung",
    },
    "fr": {
        "settings_clearing_ttk": "Suppression des fiches techniques…",
        "settings_beta_admin_subtitle": "Temporaire pour les tests (Bêta)",
        "settings_platform_admin_title": "Administrateur plateforme",
        "settings_platform_admin_subtitle": "Codes promo et gestion",
    },
    "it": {
        "settings_clearing_ttk": "Eliminazione schede tecniche…",
        "settings_beta_admin_subtitle": "Provvisorio per test (Beta)",
        "settings_platform_admin_title": "Amministratore piattaforma",
        "settings_platform_admin_subtitle": "Codici promo e gestione",
    },
    "tr": {
        "settings_clearing_ttk": "Teknik kartlar siliniyor…",
        "settings_beta_admin_subtitle": "Testler için geçici (Beta)",
        "settings_platform_admin_title": "Platform yöneticisi",
        "settings_platform_admin_subtitle": "Promosyon kodları ve yönetim",
    },
    "vi": {
        "settings_clearing_ttk": "Đang xóa thẻ công nghệ…",
        "settings_beta_admin_subtitle": "Tạm thời để thử (Beta)",
        "settings_platform_admin_title": "Quản trị nền tảng",
        "settings_platform_admin_subtitle": "Mã khuyến mãi và quản lý",
    },
}

CHECKLIST_DOC = {
    "ru": {
        "checklist_not_found": "Чеклист не найден",
        "document_not_found": "Документ не найден",
    },
    "en": {
        "checklist_not_found": "Checklist not found",
        "document_not_found": "Document not found",
    },
    "es": {
        "checklist_not_found": "Lista de verificación no encontrada",
        "document_not_found": "Documento no encontrado",
    },
    "de": {
        "checklist_not_found": "Checkliste nicht gefunden",
        "document_not_found": "Dokument nicht gefunden",
    },
    "fr": {
        "checklist_not_found": "Liste de contrôle introuvable",
        "document_not_found": "Document introuvable",
    },
    "it": {
        "checklist_not_found": "Checklist non trovata",
        "document_not_found": "Documento non trovato",
    },
    "tr": {
        "checklist_not_found": "Kontrol listesi bulunamadı",
        "document_not_found": "Belge bulunamadı",
    },
    "vi": {
        "checklist_not_found": "Không tìm thấy checklist",
        "document_not_found": "Không tìm thấy tài liệu",
    },
}

PRODUCT_UPLOAD = {
    "ru": {
        "product_upload_title": "Загрузка продуктов",
        "product_upload_back": "Вернуться назад",
        "product_upload_test_api": "Тестировать API",
        "product_upload_must_login": "Необходимо войти в систему",
        "product_upload_import_moderation": "Импорт с модерацией",
        "product_upload_from_file": "Из файла",
        "product_upload_paste_text": "Вставить текст",
        "product_upload_paste_hint": "Из мессенджеров, заметок",
        "product_upload_extract_file_failed": "Не удалось извлечь данные из файла",
        "product_upload_analyze": "Анализ",
        "product_upload_ai_list_title": "AI обработка списка продуктов",
        "product_upload_add_to_venue_nomenclature": "Добавить в номенклатуру заведения",
        "product_upload_add_to_venue_hint": "Продукты будут доступны для создания техкарт",
        "product_upload_process_with_ai": "Обработать с AI",
        "product_upload_complete_title": "Загрузка завершена",
        "product_upload_stats_new": "Новые продукты: {count}",
        "product_upload_stats_prices": "Обновлены цены: {count}",
        "product_upload_stats_errors": "Ошибок: {count}",
        "product_upload_logs_copied": "Логи скопированы в буфер обмена",
        "product_upload_legal_subtitle": "Формат данных, типы файлов, модерация",
        "product_upload_format_data": "Формат данных:",
        "product_upload_supported_files": "Поддерживаемые файлы:",
        "product_upload_excel_format": "Формат Excel файла:",
        "product_upload_moderation": "Модерация:",
        "product_upload_recognize": "Распознать",
        "product_upload_iiko_unrecognized": "Не удалось распознать структуру бланка iiko",
        "product_upload_error_generic": "Ошибка: {error}",
        "product_upload_error_file": "Ошибка загрузки файла: {error}",
        "product_upload_error_ai_text": "Ошибка обработки текста AI: {error}",
        "product_upload_error_not_signed_in": "Ошибка: пользователь не авторизован",
        "product_upload_error_no_establishment": "Ошибка: не найдено заведение",
        "product_upload_error_file_process": "Ошибка обработки файла: {error}",
        "product_upload_not_signed_in": "Пользователь не авторизован",
        "product_upload_error_process": "Ошибка обработки: {error}",
        "product_upload_import_error": "Ошибка импорта",
        "product_upload_ambiguous_title": "Неоднозначное совпадение",
        "product_upload_file_product": "Продукт из файла: {name}",
        "product_upload_what_to_do": "Что сделать?",
        "product_upload_replace_existing": "Заменить существующий",
        "product_upload_create_new": "Создать новый",
        "product_upload_skip": "Пропустить",
        "debug_logs_title": "Логи отладки",
        "debug_logs_empty": "Логов пока нет",
        "product_upload_quick_actions": "Быстрые действия:",
        "product_upload_open_nomenclature": "Посмотреть номенклатуру",
        "product_upload_check_products": "Проверить добавленные продукты",
        "product_upload_create_ttk": "Создать ТТК",
        "product_upload_use_in_recipes": "Использовать новые продукты в рецептах",
    },
    "en": {
        "product_upload_title": "Product upload",
        "product_upload_back": "Go back",
        "product_upload_test_api": "Test API",
        "product_upload_must_login": "You must sign in",
        "product_upload_import_moderation": "Import with moderation",
        "product_upload_from_file": "From file",
        "product_upload_paste_text": "Paste text",
        "product_upload_paste_hint": "From messengers, notes",
        "product_upload_extract_file_failed": "Could not extract data from file",
        "product_upload_analyze": "Analyze",
        "product_upload_ai_list_title": "AI processing of product list",
        "product_upload_add_to_venue_nomenclature": "Add to establishment nomenclature",
        "product_upload_add_to_venue_hint": "Products will be available for tech cards",
        "product_upload_process_with_ai": "Process with AI",
        "product_upload_complete_title": "Upload complete",
        "product_upload_stats_new": "New products: {count}",
        "product_upload_stats_prices": "Prices updated: {count}",
        "product_upload_stats_errors": "Errors: {count}",
        "product_upload_logs_copied": "Logs copied to clipboard",
        "product_upload_legal_subtitle": "Data format, file types, moderation",
        "product_upload_format_data": "Data format:",
        "product_upload_supported_files": "Supported files:",
        "product_upload_excel_format": "Excel file format:",
        "product_upload_moderation": "Moderation:",
        "product_upload_recognize": "Recognize",
        "product_upload_iiko_unrecognized": "Could not recognize iiko form structure",
        "product_upload_error_generic": "Error: {error}",
        "product_upload_error_file": "File upload error: {error}",
        "product_upload_error_ai_text": "AI text processing error: {error}",
        "product_upload_error_not_signed_in": "Error: user not signed in",
        "product_upload_error_no_establishment": "Error: establishment not found",
        "product_upload_error_file_process": "File processing error: {error}",
        "product_upload_not_signed_in": "User not signed in",
        "product_upload_error_process": "Processing error: {error}",
        "product_upload_import_error": "Import error",
        "product_upload_ambiguous_title": "Ambiguous match",
        "product_upload_file_product": "Product from file: {name}",
        "product_upload_what_to_do": "What should we do?",
        "product_upload_replace_existing": "Replace existing",
        "product_upload_create_new": "Create new",
        "product_upload_skip": "Skip",
        "debug_logs_title": "Debug logs",
        "debug_logs_empty": "No logs yet",
        "product_upload_quick_actions": "Quick actions:",
        "product_upload_open_nomenclature": "View nomenclature",
        "product_upload_check_products": "Check added products",
        "product_upload_create_ttk": "Create tech card",
        "product_upload_use_in_recipes": "Use new products in recipes",
    },
}

# Spanish (full); other non-EN/RU locales fall back to English strings until translated.
PRODUCT_UPLOAD_ES = {
        "product_upload_title": "Carga de productos",
        "product_upload_back": "Volver",
        "product_upload_test_api": "Probar API",
        "product_upload_must_login": "Debe iniciar sesión",
        "product_upload_import_moderation": "Importar con moderación",
        "product_upload_from_file": "Desde archivo",
        "product_upload_paste_text": "Pegar texto",
        "product_upload_paste_hint": "De mensajeros, notas",
        "product_upload_extract_file_failed": "No se pudieron extraer datos del archivo",
        "product_upload_analyze": "Analizar",
        "product_upload_ai_list_title": "Procesamiento IA de la lista de productos",
        "product_upload_add_to_venue_nomenclature": "Añadir a la nomenclatura del local",
        "product_upload_add_to_venue_hint": "Los productos estarán disponibles para fichas técnicas",
        "product_upload_process_with_ai": "Procesar con IA",
        "product_upload_complete_title": "Carga completada",
        "product_upload_stats_new": "Productos nuevos: {count}",
        "product_upload_stats_prices": "Precios actualizados: {count}",
        "product_upload_stats_errors": "Errores: {count}",
        "product_upload_logs_copied": "Registros copiados al portapapeles",
        "product_upload_legal_subtitle": "Formato de datos, tipos de archivo, moderación",
        "product_upload_format_data": "Formato de datos:",
        "product_upload_supported_files": "Archivos admitidos:",
        "product_upload_excel_format": "Formato de archivo Excel:",
        "product_upload_moderation": "Moderación:",
        "product_upload_recognize": "Reconocer",
        "product_upload_iiko_unrecognized": "No se reconoció la estructura del formulario iiko",
        "product_upload_error_generic": "Error: {error}",
        "product_upload_error_file": "Error al cargar el archivo: {error}",
        "product_upload_error_ai_text": "Error al procesar texto con IA: {error}",
        "product_upload_error_not_signed_in": "Error: usuario no autenticado",
        "product_upload_error_no_establishment": "Error: establecimiento no encontrado",
        "product_upload_error_file_process": "Error al procesar el archivo: {error}",
        "product_upload_not_signed_in": "Usuario no autenticado",
        "product_upload_error_process": "Error de procesamiento: {error}",
        "product_upload_import_error": "Error de importación",
        "product_upload_ambiguous_title": "Coincidencia ambigua",
        "product_upload_file_product": "Producto del archivo: {name}",
        "product_upload_what_to_do": "¿Qué hacer?",
        "product_upload_replace_existing": "Reemplazar existente",
        "product_upload_create_new": "Crear nuevo",
        "product_upload_skip": "Omitir",
        "debug_logs_title": "Registros de depuración",
        "debug_logs_empty": "Aún no hay registros",
        "product_upload_quick_actions": "Acciones rápidas:",
        "product_upload_open_nomenclature": "Ver nomenclatura",
        "product_upload_check_products": "Comprobar productos añadidos",
        "product_upload_create_ttk": "Crear ficha técnica",
        "product_upload_use_in_recipes": "Usar productos nuevos en recetas",
}

PRODUCT_UPLOAD["es"] = {**PRODUCT_UPLOAD["en"], **PRODUCT_UPLOAD_ES}

for lang in ("de", "fr", "it", "tr", "vi"):
    PRODUCT_UPLOAD[lang] = dict(PRODUCT_UPLOAD["en"])

def main():
    with open(PATH, encoding="utf-8") as f:
        data = json.load(f)

    batch = flat_merge(
        build_lang_name_keys(),
        ROUTER,
        SETTINGS_EXTRA,
        CHECKLIST_DOC,
        PRODUCT_UPLOAD,
    )

    for lang in LANGS:
        if lang not in data:
            raise SystemExit(f"Missing locale {lang}")
        for k, v in batch[lang].items():
            data[lang][k] = v

    with open(PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("Merged", sum(len(batch[l]) for l in LANGS) // len(LANGS), "keys per locale")


if __name__ == "__main__":
    main()
