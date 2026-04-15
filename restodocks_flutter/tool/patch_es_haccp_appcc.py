#!/usr/bin/env python3
"""One-off helper: fill Spanish (es) HACCP/APPCC regulatory strings in localizable.json."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "assets" / "translations" / "localizable.json"

# Normativa base España (referencias orientativas para explotaciones alimentarias).
_BASE = "Reglamento (CE) n.º 852/2004 y Real Decreto 191/2011"

PATCH: dict[str, str] = {
    "haccp_journals": "Registros APPCC",
    "haccp_no_journals_hint": "Los registros APPCC no están configurados",
    "haccp_no_journals_subtitle": "El titular y el personal de gestión activan los registros en Ajustes. Tras configurarlos, aparecerán aquí los disponibles para su establecimiento.",
    "haccp_scroll_right_hint": "Tabla según modelo de registro para autocontrol alimentario en España — desplace horizontalmente si no cabe en pantalla.",
    "haccp_not_supported_title": "Este tipo de registro ya no está disponible en la app.",
    "haccp_not_supported_body": "La app ofrece registros alineados con el autocontrol (APPCC) para España y el conjunto de modelos activables en ajustes del establecimiento.",
    "haccp_recommended_sample": "Modelo recomendado de registro (APPCC)",
    "haccp_configure_in_settings": "El titular y la gestión configuran los registros en Ajustes",
    "haccp_journals_settings_hint": "Selección de registros APPCC del establecimiento",
    "haccp_enabled_journals": "Registros activados",
    "haccp_log_health_hygiene_title": "Registro de higiene y vigilancia sanitaria del personal manipulador",
    "haccp_log_fridge_temperature_title": "Registro de temperaturas de equipos de refrigeración y congelación",
    "haccp_log_warehouse_temp_humidity_title": "Registro de temperatura y humedad en almacenes y cámaras",
    "haccp_log_finished_product_brakerage_title": "Registro de evaluación organoléptica y liberación de producto terminado",
    "haccp_log_incoming_raw_brakerage_title": "Registro de control organoléptico en recepción de materias primas perecederas",
    "haccp_log_frying_oil_title": "Registro de seguimiento de aceites de fritura",
    "haccp_log_med_book_registry_title": "Registro de documentación sanitaria del personal alimentario",
    "haccp_log_med_examinations_title": "Registro de reconocimientos médicos del personal alimentario",
    "haccp_log_disinfectant_accounting_title": "Registro de desinfectantes y tratamientos de desinfección",
    "haccp_log_equipment_washing_title": "Registro de limpieza y desinfección de equipos y utensilios",
    "haccp_log_general_cleaning_schedule_title": "Registro y planificación de limpiezas (incluidas generales)",
    "haccp_log_sieve_filter_magnet_title": "Registro de inspección y limpieza de cribas, filtros y separadores magnéticos",
    "haccp_sanpin_line_health_hygiene": f"Vigilancia diaria del personal — APPCC. Base: {_BASE}.",
    "haccp_sanpin_line_fridge_temperature": f"Control de temperatura en cadena de frío — APPCC. Base: {_BASE}.",
    "haccp_sanpin_line_warehouse_temp_humidity": f"Control ambiental en almacenamiento — APPCC. Base: {_BASE}.",
    "haccp_sanpin_line_finished_product_brakerage": f"Evaluación organoléptica / liberación — APPCC. Base: {_BASE}.",
    "haccp_sanpin_line_incoming_raw_brakerage": f"Recepción y control organoléptico de MP — APPCC. Base: {_BASE}.",
    "haccp_sanpin_line_frying_oil": f"Seguimiento de aceites de fritura y renovación — buenas prácticas. Base: {_BASE}.",
    "haccp_sanpin_line_med_book_registry": "Documentación sanitaria del personal (normativa laboral y sanitaria española aplicable al sector alimentario).",
    "haccp_sanpin_line_med_examinations": "Vigilancia de la salud del personal (normativa sobre prevención de riesgos y sector alimentario en España).",
    "haccp_sanpin_line_disinfectant_accounting": f"Tratamientos de desinfección y trazabilidad de biocidas — APPCC. Base: {_BASE}.",
    "haccp_sanpin_line_equipment_washing": f"Limpieza y desinfección de superficies en contacto con alimentos — APPCC. Base: {_BASE}.",
    "haccp_sanpin_line_general_cleaning_schedule": f"Planificación documentada de limpieza — APPCC. Base: {_BASE}.",
    "haccp_sanpin_line_sieve_filter_magnet": f"Defensa física frente a cuerpos extraños — APPCC. Base: {_BASE}.",
    "haccp_sanpin_footer_health_hygiene": f"Vigilancia del personal — APPCC. Base: {_BASE}.",
    "haccp_sanpin_footer_fridge_temperature": f"Temperaturas de frío — APPCC. Base: {_BASE}.",
    "haccp_sanpin_footer_warehouse_temp_humidity": f"Almacén: temperatura/humedad — APPCC. Base: {_BASE}.",
    "haccp_sanpin_footer_finished_product_brakerage": f"Producto terminado — APPCC. Base: {_BASE}.",
    "haccp_sanpin_footer_incoming_raw_brakerage": f"Materias primas — APPCC. Base: {_BASE}.",
    "haccp_sanpin_footer_frying_oil": f"Aceites de fritura — APPCC. Base: {_BASE}.",
    "haccp_sanpin_footer_med_book_registry": "Documentación sanitaria del personal (España).",
    "haccp_sanpin_footer_med_examinations": "Reconocimientos médicos del personal (España).",
    "haccp_sanpin_footer_disinfectant_accounting": f"Desinfección — APPCC. Base: {_BASE}.",
    "haccp_sanpin_footer_equipment_washing": f"Limpieza de equipos — APPCC. Base: {_BASE}.",
    "haccp_sanpin_footer_general_cleaning_schedule": f"Limpieza programada — APPCC. Base: {_BASE}.",
    "haccp_sanpin_footer_sieve_filter_magnet": f"Cribas/imanes — APPCC. Base: {_BASE}.",
    "haccp_legal_hint": "APPCC (RD 191/2011), Regl. 852/2004, eIDAS (Regl. UE 910/2014), RGPD/LOPDGDD",
    "haccp_legal_text": (
        "Legitimidad de los registros digitales (APPCC en España):\n\n"
        "El Reglamento (CE) n.º 852/2004 exige procedimientos de higiene y autocontrol basados en los principios HACCP. "
        "El Real Decreto 191/2011 desarrolla en España esos procedimientos para establecimientos de restauración y actividades afines. "
        "Los registros electrónicos en Restodocks documentan vigilancias y medidas de autocontrol con fines de trazabilidad y diligencia debida.\n\n"
        "Firma e identificación:\n"
        "El acceso con usuario y contraseña puede considerarse firma electrónica en el marco del Reglamento (UE) n.º 910/2014 (eIDAS) "
        "y la normativa española aplicable, complementada por el acuerdo con el trabajador disponible en la app.\n\n"
        "Protección de datos:\n"
        "El tratamiento de datos personales se rige por el RGPD, la LOPDGDD y la política de privacidad del responsable del tratamiento.\n\n"
        "Integridad e inmutabilidad:\n"
        "Restodocks registra fecha y hora del servidor en cada entrada, lo que dificulta la alteración a posteriori y refuerza la integridad documental.\n\n"
        "Nota: las plantillas son de apoyo; el titular debe asegurarse de que los registros cubren los puntos críticos de su plan APPCC "
        "y los requisitos de su comunidad autónoma."
    ),
    "haccp_legal_sp_extract": (
        "Extracto orientativo: Reglamento (CE) n.º 852/2004 sobre higiene de los productos alimenticios "
        "y Real Decreto 191/2011 (procedimientos de autocontrol basados en principios HACCP en España)"
    ),
    "haccp_legal_sp_paragraphs": (
        "Vigilancia de la higiene del personal manipulador:\n"
        "Las buenas prácticas de restauración exigen controles periódicos de salud e higiene del personal que manipula alimentos, "
        "registrados de forma fehaciente. Este registro sustenta la diligencia del operador ante inspección.\n\n"
        "Control de la cadena de frío y del almacenamiento:\n"
        "El operador debe disponer de registros que demuestren el mantenimiento de las temperaturas y condiciones ambientales "
        "necesarias para la inocuidad en almacenes, cámaras frías y vitrinas, conforme a su evaluación de peligros APPCC."
    ),
    "haccp_pdf_document_producer": "Restodocks (APPCC — España: Regl. 852/2004, RD 191/2011)",
    "haccp_pdf_health_form_caption": "Modelo de registro de higiene del personal (APPCC — España)",
    "haccp_pdf_frying_oil_subtitle": "Modelo de registro de control de aceites de fritura (APPCC — España)",
    "documentation_haccp_subtitle": "Documentación, registros APPCC y acuerdos para firma electrónica",
    "tour_tile_haccp": (
        "Registros de autocontrol (APPCC): temperaturas, organoléptico, higiene, desinfección y más. "
        "Tras guardar, las entradas no se editan."
    ),
    "haccp_order_pdf_p1_intro_sanpin": (
        "Para optimizar los procesos de trabajo, garantizar el control operativo y la integridad de los datos, "
        "y en el marco del autocontrol alimentario (APPCC) conforme al Reglamento (CE) n.º 852/2004 y el Real Decreto 191/2011,"
    ),
    "post_registration_trial_paid_list": (
        "1. Más de 6 empleados.\n"
        "2. Importación de TTK — solo creación manual.\n"
        "3. Subida de fotos en TTK (semiacabados/platos).\n"
        "4. Inventarios (cualquier interacción).\n"
        "5. Registros APPCC (cualquier interacción).\n"
        "6. Bajas/mermas (cualquier interacción).\n"
        "7. Configuración del botón central.\n"
        "8. Banquetes / catering.\n"
        "9. Cambio de estado fijo/temporal (sin suscripción — solo fijo).\n"
        "10. Todo el bloque Gastos.\n"
        "11. Chats grupales en mensajes.\n"
        "12. Envío de fotos en mensajes.\n"
        "13. Añadir copropietario con acceso completo."
    ),
}


def main() -> None:
    data = json.loads(PATH.read_text(encoding="utf-8"))
    es = data.get("es")
    if not isinstance(es, dict):
        raise SystemExit("Missing es locale in localizable.json")
    missing = [k for k in PATCH if k not in es]
    if missing:
        print("Warning: keys not in es (skipped):", ", ".join(missing[:20]))
    for k, v in PATCH.items():
        if k in es:
            es[k] = v
    PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Patched {sum(1 for k in PATCH if k in es)} keys in es.")


if __name__ == "__main__":
    main()
