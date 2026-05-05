#!/usr/bin/env python3
"""
Генерирует PDF с описанием проекта Restodocks по фактам из кодовой базы.
Запуск: python3 scripts/generate_restodocks_overview_pdf.py
"""

from __future__ import annotations

import datetime
import sys
from pathlib import Path

try:
    from fpdf import FPDF
except ImportError:
    print("Установите fpdf2: pip install fpdf2", file=sys.stderr)
    sys.exit(1)

# macOS: Arial Unicode; при отсутствии — попытка альтернатив
_FONT_CANDIDATES = [
    Path("/Library/Fonts/Arial Unicode.ttf"),
    Path("/System/Library/Fonts/Supplemental/Arial Unicode.ttf"),
]


def _find_font() -> Path:
    for p in _FONT_CANDIDATES:
        if p.is_file():
            return p
    raise FileNotFoundError(
        "Не найден шрифт с кириллицей. Укажите путь к .ttf в скрипте."
    )


SECTIONS: list[tuple[str, list[str]]] = [
    (
        "1. Назначение и границы продукта",
        [
            "Restodocks — приложение для операционного управления заведениями общественного "
            "питания: справочник продуктов и цен по точке, технологические карты (ТТК) с расчётом "
            "себестоимости, POS зала (столы, заказы, оплаты), упрощённый склад в пересчёте на граммы, "
            "закупки и приёмка. Клиент — одна кодовая база Flutter (iOS, Android, Web); сервер — Supabase "
            "(PostgreSQL, Auth, Row Level Security, Realtime, Storage, Edge Functions). Отдельно "
            "существует административное веб-приложение (Next.js) для операционных задач вне основного UI "
            "зала и кухни.",
            "Продукт сознательно не закрывает полный ERP (единый финансовый контур «закупка‑продажа‑деньги»), "
            "полноценный WMS (партии, сроки годности, несколько складов, штрихкоды) и прямую интеграцию "
            "с физической контрольно-кассовой техникой — эти направления в репозитории отмечены как бэклог "
            "или частичная подготовка (см. docs/GRAND_PLAN.md).",
        ],
    ),
    (
        "2. Техническая архитектура",
        [
            "Клиент: Flutter, навигация go_router, состояние в том числе через provider; доступ к данным — "
            "supabase_flutter (PostgREST, RPC, Realtime, вызовы Edge Functions). Локально используются "
            "shared_preferences и SQLite (sqflite) для кэшей и крупных снимков — UX с ориентацией на офлайн "
            "и последующую сверку с сервером.",
            "Сервер: Supabase. Источник истины — PostgreSQL с мультитенантностью по заведению "
            "(establishment_id и связанные политики RLS). Чувствительные сценарии (часть документов, "
            "приёмки, биллинг) проходят через Edge Functions с серверной валидацией.",
            "Себестоимость блюд в типичном случае не хранится как один устаревающий агрегат на все ТТК: "
            "актуальные цены номенклатуры по заведению задаются в establishment_products; при отображении "
            "ТТК выполняется расчёт по текущим ценам и структуре рецепта (в т.ч. вложенные полуфабрикаты). "
            "Подход согласован с описанием в scripts/enisa_docs/ru.md (динамический food cost).",
            "Подписки Realtime на ключевые сущности (например tech_cards, products) используются для "
            "обновления списков без полного опроса; дополнительно возможны периодические проверки.",
        ],
    ),
    (
        "3. Безопасность и соответствие модели доступа",
        [
            "Аутентификация: Supabase Auth (JWT-сессии). Авторизация на уровне строк: RLS по таблицам "
            "арендаторов; проверки доступа к заведению через RPC вроде check_establishment_access с учётом "
            "тарифа и промо (см. миграции в supabase/migrations/).",
            "Журналирование ошибок клиента: таблица system_errors; при сбое прямой вставки возможен fallback "
            "через Edge Function log-system-error.",
        ],
    ),
    (
        "4. Функциональность, подтверждённая кодом и схемой БД",
        [
            "Учётные записи и онбординг: регистрация компании и сотрудников, потоки владельца и co-owner, "
            "подтверждение e-mail; часть писем и сценариев — через Edge (send-registration-email и др.). "
            "Сброс и смена пароля — через функции request-password-reset, request-change-password, reset-password.",
            "Сотрудники и роли: многоуровневая модель (владелец, позиции, отделы); ограничения по числу "
            "активных сотрудников завязаны на тариф establishment (см. subscription_entitlements.dart и RPC на стороне БД).",
            "Номенклатура: продукты, цены по заведению, история изменения цен; КБЖУ — в том числе через "
            "Open Food Facts (Edge fetch-nutrition-off). Переводы названий и контента — TranslationManager / "
            "TranslationService; автоперевод отдельных сущностей — Edge auto-translate-product.",
            "ТТК: создание и редактирование, строки состава tt_ingredients, вложенные техкарты, расчёт "
            "себестоимости при просмотре; хранение фото/вложений в Storage (политики RLS на бакеты). "
            "Заявки на изменение ТТК от сотрудников и согласование владельцем (tech_card_change_requests).",
            "POS: столы и зал, заказы и строки, оплаты (включая разбиение счёта и чаевые), кассовые смены "
            "зала, KDS и настройки отображения заказов; отдельные режимы для кухни/бара без лишних полей.",
            "Склад (упрощённая модель): остатки и движения по заведению; списание по ТТК при закрытии счёта; "
            "защита от повторного списания по строке заказа; приход из списков закупок; ручные корректировки "
            "и сверки.",
            "Закупки: списки заказов поставщикам, сохранение документов (save-order-document), приёмка "
            "через save-procurement-receipt с возможностью обновления цен номенклатуры по факту.",
            "Импорт номенклатуры и модерация: единый поток ревью перед записью в БД (ImportReviewScreen); "
            "разбор старых Excel через Edge parse-xls-bytes; интеллектуальный разбор текста и таблиц — "
            "в связке с AiService и шаблонами (parse-ttk-by-templates, parse-doc-bytes).",
            "Чеклисты: создание, заполнение, назначения; генерация пунктов через ИИ — Edge ai-generate-checklist.",
            "HACCP: журналы и связанные поля в БД (миграции haccp_*).",
            "Коммуникации: чаты между сотрудниками (таблицы chat_*); политика вложений зависит от тарифа.",
            "Фискализация: настройки заведения и очередь fiscal_outbox для отложенной обработки; физическая "
            "отправка в ККТ в продукте не заявлена как закрытый эпик.",
            "Монетизация: подтверждение покупок Apple через Edge billing-verify-apple; промокоды и типы "
            "подписки — в миграциях и модели Establishment.",
            "Платформенный админ: маршрут /admin с ограничением по списку администраторов (не часть обычного "
            "ресторанного сценария).",
        ],
    ),
    (
        "5. ИИ и серверные функции (фактические вызовы из клиента)",
        [
            "Ниже перечислены функции, на которые есть прямые вызовы из Dart-кода (в первую очередь "
            "lib/services/ai_service_supabase.dart и смежные сервисы). Наличие функции не означает «идеальное "
            "качество на любом входе» — это контуры, которые развёрнуты и используются в UI.",
            "Парсинг и нормализация номенклатуры: ai-parse-product-list, ai-normalize-product-names, "
            "ai-find-duplicates.",
            "Чеклисты: ai-generate-checklist.",
            "Чеки закупки (изображение): ai-recognize-receipt.",
            "ТТК: ai-recognize-tech-card (изображение), ai-recognize-tech-cards-batch, ai-parse-tech-cards-pdf, "
            "ai-create-tech-card (в т.ч. режим checkOnly для квот), parse-ttk-by-templates, tt-parse-save-learning "
            "(обучение/уточнение разборщика по заведению).",
            "Продукт по тексту: ai-recognize-product, ai-verify-product; КБЖУ: ai-refine-nutrition.",
            "Перевод строк: translate-text (например названия ТТК), fetch-nutrition-off для внешнего справочника.",
            "Операционные: save-order-document, save-procurement-receipt, billing-verify-apple, log-system-error, "
            "parse-xls-bytes, parse-doc-bytes (разбор документов для импорта).",
            "Тарифные лимиты на ИИ-создание ТТК учитываются на клиенте (например AiTtkQuotaCacheService) "
            "совместно с ответом ai-create-tech-card.",
        ],
    ),
    (
        "6. Какие проблемы операционного учёта закрывает продукт",
        [
            "Разрозненные цены и рецептуры: единая номенклатура и ТТК с пересчётом себестоимости от текущих "
            "цен без массового ручного обновления «замороженных» сумм в базе.",
            "Изменение состава и технологии: формализованный поток заявок на изменение ТТК и утверждение "
            "руководством.",
            "Связка продаж и склада: списание ингредиентов по техкартам при закрытии счёта в упрощённой модели "
            "остатков.",
            "Закупки и ценообразование: приёмка накладных с обновлением учётных цен для последующего расчёта маржи.",
            "Многоязычный персонал и контент: локализация интерфейса и переводы доменных сущностей.",
            "Наблюдаемость сбоев в полевых условиях: журнал system_errors для диагностики.",
        ],
    ),
    (
        "7. Ограничения и зоны ответственности (честно)",
        [
            "Не заявляется закрытым: полноценный складской учёт с партиями и сроками годности; интеграция с "
            "физической ККТ; консолидация управленческой отчётности уровня P&L по заведению; готовый коннектор "
            "к внешним POS вроде iiko (в репозитории — подготовительные материалы и заготовки).",
            "ИИ-разбор ТТК и документов зависит от качества исходников и настроек провайдера; результат всегда "
            "предполагает просмотр и правку человеком перед сохранением в учётной базе.",
            "Документ сформирован по состоянию кодовой базы и docs/GRAND_PLAN.md; при расхождении с маркетинговыми "
            "материалами приоритет у фактической реализации в репозитории.",
        ],
    ),
]


class DocPDF(FPDF):
    def __init__(self, font_name: str, font_path: Path, generated_on: str) -> None:
        super().__init__()
        self._font_name = font_name
        self._generated_on = generated_on
        self.add_font(font_name, "", str(font_path))
        self.set_auto_page_break(auto=True, margin=18)

    def header(self) -> None:
        if self.page_no() == 1:
            return
        self.set_font(self._font_name, "", 9)
        self.set_text_color(80, 80, 80)
        self.cell(
            0,
            8,
            "Restodocks — описание проекта (техническое и функциональное)",
            align="C",
            new_x="LMARGIN",
            new_y="NEXT",
        )
        self.ln(4)

    def footer(self) -> None:
        self.set_y(-14)
        self.set_font(self._font_name, "", 8)
        self.set_text_color(128, 128, 128)
        self.cell(
            0,
            6,
            f"Стр. {self.page_no()} · сгенерировано {self._generated_on}",
            align="C",
        )


def build_pdf(out_path: Path) -> None:
    font_path = _find_font()
    gen_date = datetime.date.today().isoformat()
    pdf = DocPDF("RD", font_path, gen_date)
    pdf.set_margins(18, 18, 18)
    pdf.add_page()
    pdf.set_font("RD", "", 16)
    pdf.set_text_color(20, 20, 20)
    pdf.cell(0, 10, "Restodocks", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)
    pdf.set_font("RD", "", 11)
    intro = (
        "Текстовое описание для специалистов и ИИ. Основано на структуре репозитория, "
        "маршрутах клиента, вызовах Edge Functions и документе docs/GRAND_PLAN.md. "
        "Цель — отразить реализованные контуры, а не планы или отменённые эксперименты."
    )
    pdf.multi_cell(0, 6, intro)
    pdf.ln(1)
    pdf.set_font("RD", "", 9)
    pdf.set_text_color(90, 90, 90)
    pdf.cell(
        0,
        5,
        f"Дата генерации PDF: {gen_date}",
        new_x="LMARGIN",
        new_y="NEXT",
    )
    pdf.set_text_color(30, 30, 30)
    pdf.ln(3)

    for title, paragraphs in SECTIONS:
        pdf.set_font("RD", "", 13)
        pdf.set_text_color(0, 51, 102)
        pdf.multi_cell(0, 8, title)
        pdf.ln(1)
        pdf.set_font("RD", "", 10)
        pdf.set_text_color(30, 30, 30)
        for p in paragraphs:
            pdf.multi_cell(0, 5.5, p)
            pdf.ln(2)
        pdf.ln(2)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    pdf.output(str(out_path))


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    out = root / "docs" / "Restodocks_описание_проекта.pdf"
    build_pdf(out)
    print(f"Записано: {out}")


if __name__ == "__main__":
    main()
