#!/usr/bin/env python3
"""Один раз выровнять ключи localizable.json по языкам supported в LocalizationService."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "assets/translations/localizable.json"

# Ключи есть в ru, не хватало в en — английские строки.
EN_FROM_RU: dict[str, str] = {
    "documentation_body": "Document body",
    "documentation_create": "Create document",
    "documentation_created": "Document created",
    "documentation_delete_confirm": "Delete document?",
    "documentation_deleted": "Document deleted",
    "documentation_edit": "Edit",
    "documentation_empty": "No documents",
    "documentation_empty_body": "No body text",
    "documentation_name": "Title",
    "documentation_name_required": "Enter a title",
    "documentation_topic": "Topic",
    "documentation_updated": "Document updated",
    "documentation_visibility": "Visible to",
    "documentation_visibility_all": "Everyone",
    "documentation_visibility_department": "Departments",
    "documentation_visibility_employee": "Employees",
    "documentation_visibility_section": "Kitchen sections",
    "expenses_orders_excluded_from_total": "Not included in total: %s",
    "expenses_orders_include_in_total_hint": "Include in expenses total",
    "expenses_tab_writeoffs": "Write-offs",
    "expenses_writeoffs_empty": "Write-offs will appear here after you send them from the write-offs screen",
    "expenses_writeoffs_total_period": "For period: %s",
    "expenses_writeoffs_total_selected": "Total for selected",
    "haccp_action": "Action (replace/top-up)",
    "haccp_agent": "Agent",
    "haccp_company": "Organization",
    "haccp_concentration": "Concentration",
    "haccp_config_table_missing": "Journal settings table not found. Apply Supabase migrations (supabase db push).",
    "haccp_configure_in_settings": "The owner and management staff select journals in Settings",
    "haccp_description": "Description",
    "haccp_duration": "Duration",
    "haccp_entry_immutable_hint": "View only. Editing journal entries is not available.",
    "haccp_entry_view": "Entry",
    "haccp_export_do": "Save PDF",
    "haccp_export_pdf": "Export to PDF",
    "haccp_healthy": "Healthy",
    "haccp_hours": "Working hours",
    "haccp_humidity": "Humidity %",
    "haccp_incident_type": "Type (water/power/sewer)",
    "haccp_location": "Location (kitchen)",
    "haccp_no_arvi_ok": "No ARI or purulent skin conditions",
    "haccp_oil_name": "Oil brand",
    "haccp_pdf_cover": "Cover page",
    "haccp_pdf_cover_hint": "Organization name, dates",
    "haccp_pdf_no_entries": "No entries for the selected period",
    "haccp_pdf_stitching": "Binding sheet",
    "haccp_pdf_stitching_hint": "“Numbered and bound”",
    "haccp_period": "Period",
    "haccp_period_custom": "Pick range",
    "haccp_period_month": "Month",
    "haccp_period_month_to_today": "From the 1st to today",
    "haccp_period_today": "Today",
    "haccp_period_week": "Week",
    "haccp_reason": "Write-off reason",
    "haccp_result_exam": "Exam result (cleared / suspended)",
    "haccp_result_ok": "Exam result (Healthy / OK)",
    "haccp_rinse_temp_ok": "Rinse temperature OK",
    "haccp_temp": "Temperature °C",
    "haccp_wash_temp_ok": "Wash temperature OK",
    "haccp_weight": "Weight, kg",
    "no_results": "Nothing found",
    "notification_banner": "Top banner",
    "notification_categories": "Which notifications are enabled",
    "notification_checklist_assigned": "Checklists assigned to you",
    "notification_disabled": "Disabled",
    "notification_display_type": "Notification style",
    "notification_modal": "Center dialog",
    "notification_schedule_changes": "Changes to the standard schedule",
    "saving": "Saving…",
    "tech_cards_import_already_saved": "Already saved",
    "ttk_import_all_dishes": "All dishes",
    "ttk_import_all_pf": "All semi-finished",
    "ttk_import_empty_parse_hint": "Could not parse automatically. Fill in the card manually — learning will apply on the next import of a similar file.",
    "ttk_import_ensure_pf_prefix": 'Prefix name with "SF"\n(if missing)',
    "ttk_learn_error_hint": "Learning was not saved (write error). See console for details.",
}

# Ключи были только в en — добавляем в ru (для паритета).
RU_FROM_EN: dict[str, str] = {
    "haccp_agreement_address": "Адрес",
    "haccp_agreement_body": "Настоящим подтверждается, что ввод данных в электронные журналы и учётные формы системы Restodocks под личным логином (логин и пароль) признаётся равнозначным собственноручной подписи в соответствии с:\n\n— {{E_SIGNATURE_LAW}};\n— {{SYSTEM_NAME}};\n— {{FOOD_LAW}};\n— {{DATA_PRIVACY_LAW}}.\n\nРаботник обязуется соблюдать порядок учёта и не разглашать данные для входа в систему.",
    "haccp_agreement_date_line": "дата: «____» ______________ 20____",
    "haccp_agreement_doc_subtitle": "Признание записей в электронных журналах личной подписью",
    "haccp_agreement_doc_title": "СОГЛАШЕНИЕ С СОТРУДНИКОМ",
    "haccp_agreement_employer": "Работодатель",
    "haccp_agreement_heading": "СОГЛАШЕНИЕ О ПРИЗНАНИИ ЭЛЕКТРОННОЙ ПОДПИСИ",
    "haccp_agreement_inn_bin": "ИНН/БИН",
    "haccp_agreement_lang_title": "Язык соглашения",
    "haccp_agreement_org": "Организация",
    "haccp_agreement_position": "Должность",
    "haccp_agreement_stamp_hint": "Печать (при наличии)",
    "haccp_agreement_worker": "Сотрудник",
    "haccp_agreement_worker_fio_hint": "(ФИО полностью)",
    "haccp_agreement_worker_sign": "Сотрудник",
    "schedule_who_works": "Кто работает?",
    "screen_settings": "Настройки экрана",
    "ttk_cook_loss_override_hint": "По умолчанию из метода. Измените, если на практике иначе.",
    "weight_g": "Вес, г",
}

SUPPORTED = ("ru", "en", "es", "de", "fr", "it", "tr", "vi")


def main() -> None:
    data = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    ru: dict = data["ru"]
    en: dict = data["en"]

    for k, v in EN_FROM_RU.items():
        if k not in ru:
            raise SystemExit(f"EN_FROM_RU key not in ru: {k}")
        en[k] = v

    for k, v in RU_FROM_EN.items():
        ru[k] = v

    master = set(ru.keys()) | set(en.keys())
    for k in master:
        if k not in ru:
            ru[k] = en.get(k, k)
        if k not in en:
            en[k] = ru.get(k, k)

    for lang in SUPPORTED:
        block: dict = data[lang]
        for k in master:
            if k not in block:
                block[k] = en.get(k) or ru.get(k) or k

    JSON_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print("OK:", JSON_PATH)
    for lang in SUPPORTED:
        if lang in data:
            print(f"  {lang}: {len(data[lang])} keys")


if __name__ == "__main__":
    main()
