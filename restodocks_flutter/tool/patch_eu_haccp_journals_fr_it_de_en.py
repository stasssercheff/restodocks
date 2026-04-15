#!/usr/bin/env python3
"""Patch fr, it, de, en HACCP journal strings for EU national framing (not SanPiN)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "assets" / "translations" / "localizable.json"

FR_BASE = "Règlement (CE) n° 852/2004 et Arrêté du 21 décembre 2009"
IT_BASE = "Regolamento (CE) n. 852/2004 e D.Lgs. 193/2007"
DE_BASE = "Verordnung (EG) Nr. 852/2004 und Lebensmittelhygiene-Verordnung (LMHV)"
EN_BASE = "Regulation (EC) No 852/2004 (EU food hygiene)"

FR: dict[str, str] = {
    "haccp_journals": "Registres HACCP / PMS",
    "haccp_no_journals_hint": "Aucun registre HACCP n'est configuré",
    "haccp_no_journals_subtitle": "Le responsable et la direction activent les registres dans Réglages. Une fois configurés, ils apparaissent ici.",
    "haccp_scroll_right_hint": "Tableau selon le modèle de registre d'autocontrôle (France / UE) — faites défiler horizontalement si besoin.",
    "haccp_not_supported_title": "Ce type de registre n'est plus proposé dans l'application.",
    "haccp_not_supported_body": "L'application propose des registres alignés sur l'autocontrôle alimentaire (HACCP / PMS) et les modèles activables pour l'établissement.",
    "haccp_recommended_sample": "Modèle de registre recommandé (HACCP / PMS)",
    "haccp_configure_in_settings": "Le responsable et la direction configurent les registres dans Réglages",
    "haccp_journals_settings_hint": "Sélection des registres HACCP de l'établissement",
    "haccp_enabled_journals": "Registres activés",
    "haccp_log_health_hygiene_title": "Registre de surveillance sanitaire et d'hygiène du personnel manipulateur",
    "haccp_log_fridge_temperature_title": "Registre des températures des équipements de réfrigération et de congélation",
    "haccp_log_warehouse_temp_humidity_title": "Registre de température et d'humidité en entrepôt et chambres froides",
    "haccp_log_finished_product_brakerage_title": "Registre d'évaluation organoleptique et de mise en circulation du produit fini",
    "haccp_log_incoming_raw_brakerage_title": "Registre de contrôle organoleptique à la réception des denrées périssables",
    "haccp_log_frying_oil_title": "Registre de suivi des huiles de friture",
    "haccp_log_med_book_registry_title": "Registre des documents sanitaires du personnel en restauration",
    "haccp_log_med_examinations_title": "Registre des visites médicales du personnel alimentaire",
    "haccp_log_disinfectant_accounting_title": "Registre des désinfectants et des opérations de désinfection",
    "haccp_log_equipment_washing_title": "Registre de nettoyage et de désinfection du matériel et des ustensiles",
    "haccp_log_general_cleaning_schedule_title": "Registre et planification des nettoyages (y compris généraux)",
    "haccp_log_sieve_filter_magnet_title": "Registre d'inspection et de nettoyage des tamis, filtres et séparateurs magnétiques",
    "haccp_sanpin_line_health_hygiene": f"Surveillance quotidienne du personnel — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_line_fridge_temperature": f"Contrôle des températures de la chaîne du froid — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_line_warehouse_temp_humidity": f"Contrôle du stockage (T°, humidité) — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_line_finished_product_brakerage": f"Organoleptique / mise sur le marché — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_line_incoming_raw_brakerage": f"Réception et contrôle organoleptique — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_line_frying_oil": f"Huiles de friture — bonnes pratiques. Réf. : {FR_BASE}.",
    "haccp_sanpin_line_med_book_registry": "Documents sanitaires du personnel (droit du travail et santé publique applicables en France).",
    "haccp_sanpin_line_med_examinations": "Surveillance médicale du personnel (Code du travail et obligations secteur alimentaire).",
    "haccp_sanpin_line_disinfectant_accounting": f"Désinfection et biocides — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_line_equipment_washing": f"Nettoyage-desinfection des surfaces alimentaires — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_line_general_cleaning_schedule": f"Plan de nettoyage documenté — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_line_sieve_filter_magnet": f"Défense physique (tamis, aimants) — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_footer_health_hygiene": f"Personnel — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_footer_fridge_temperature": f"Froid — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_footer_warehouse_temp_humidity": f"Entrepôt — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_footer_finished_product_brakerage": f"Produit fini — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_footer_incoming_raw_brakerage": f"Matières premières — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_footer_frying_oil": f"Friture — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_footer_med_book_registry": "Documents sanitaires du personnel (France).",
    "haccp_sanpin_footer_med_examinations": "Visites médicales du personnel (France).",
    "haccp_sanpin_footer_disinfectant_accounting": f"Désinfection — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_footer_equipment_washing": f"Matériel — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_footer_general_cleaning_schedule": f"Nettoyage planifié — PMS. Réf. : {FR_BASE}.",
    "haccp_sanpin_footer_sieve_filter_magnet": f"Tamis/aimants — PMS. Réf. : {FR_BASE}.",
    "haccp_legal_hint": "HACCP/PMS, Règl. 852/2004, eIDAS (Règl. UE 910/2014), RGPD et Loi Informatique et Libertés",
    "haccp_legal_text": (
        "Fondement des registres numériques (HACCP / PMS en France) :\n\n"
        "Le règlement (CE) n° 852/2004 impose des procédures d'hygiene et d'autocontrôle fondées sur les principes HACCP. "
        "En France, l'arrêté du 21 décembre 2009 et les règles sanitaires sectorielles précisent les registres attendus pour la restauration. "
        "Les enregistrements dans Restodocks documentent les surveillances et mesures pour la traçabilité et la diligence de l'exploitant.\n\n"
        "Identification et signature :\n"
        "La connexion par compte utilisateur s'inscrit dans le cadre du règlement (UE) n° 910/2014 (eIDAS) et du droit français applicable, "
        "complétée par l'accord employé disponible dans l'application.\n\n"
        "Données personnelles :\n"
        "Le traitement est régi par le RGPD, la loi « Informatique et Libertés » et la politique de confidentialité du responsable de traitement.\n\n"
        "Intégrité :\n"
        "Restodocks horodate chaque saisie côté serveur, ce qui limite les modifications rétroactives.\n\n"
        "Note : les modèles sont une aide ; l'exploitant doit couvrir les points critiques de son plan et les exigences locales."
    ),
    "haccp_legal_sp_extract": (
        "Extrait d'orientation : Règlement (CE) n° 852/2004 et arrêté du 21 décembre 2009 "
        "(plan de maîtrise sanitaire / HACCP en restauration en France)"
    ),
    "haccp_legal_sp_paragraphs": (
        "Surveillance de l'hygiène du personnel :\n"
        "Les bonnes pratiques imposent un suivi documenté de l'état de santé apparent et de l'hygiène des personnes en contact avec les denrées.\n\n"
        "Chaîne du froid et stockage :\n"
        "L'exploitant tient des preuves (températures, conditions) pour les chambres froides, entrepôts et vitrines, conformément à son analyse des dangers."
    ),
    "haccp_pdf_document_producer": "Restodocks (HACCP/PMS — France : 852/2004, arrêté 21/12/2009)",
    "haccp_pdf_health_form_caption": "Modèle de registre d'hygiène du personnel (France / UE)",
    "haccp_pdf_frying_oil_subtitle": "Modèle de registre des huiles de friture (France / UE)",
    "documentation_haccp_subtitle": "Documentation, registres HACCP/PMS et accords de signature électronique",
    "tour_tile_haccp": (
        "Registres d'autocontrôle : températures, organoleptique, hygiène, désinfection, etc. "
        "Après enregistrement, les lignes ne sont plus modifiables."
    ),
    "haccp_order_pdf_p1_intro_sanpin": (
        "Afin d'optimiser les processus, d'assurer le contrôle opérationnel et l'intégrité des données, "
        "et dans le cadre de l'autocontrôle alimentaire (HACCP / PMS) conformément au Règlement (CE) n° 852/2004 "
        "et à l'arrêté du 21 décembre 2009,"
    ),
    "post_registration_trial_paid_list": (
        "1. Plus de 6 employés.\n"
        "2. Import des fiches techniques — création manuelle uniquement.\n"
        "3. Photos sur les fiches (demi-produits/plats).\n"
        "4. Inventaires (toute interaction).\n"
        "5. Registres HACCP (toute interaction).\n"
        "6. Pertes/mermes (toute interaction).\n"
        "7. Configuration du bouton central.\n"
        "8. Banquets / traiteur.\n"
        "9. Statut fixe/temporaire (sans abonnement — fixe seulement).\n"
        "10. Tout le bloc Dépenses.\n"
        "11. Chats de groupe dans les messages.\n"
        "12. Envoi de photos dans les messages.\n"
        "13. Ajouter un co-propriétaire avec accès complet."
    ),
}

IT: dict[str, str] = {
    "haccp_journals": "Registri HACCP (autocontrollo)",
    "haccp_no_journals_hint": "Nessun registro HACCP configurato",
    "haccp_no_journals_subtitle": "Il titolare e la gestione attivano i registri in Impostazioni. Poi compariranno qui.",
    "haccp_scroll_right_hint": "Tabella secondo modello di registro per autocontrollo alimentare (Italia/UE) — scorrere in orizzontale se necessario.",
    "haccp_not_supported_title": "Questo tipo di registro non è più disponibile nell'app.",
    "haccp_not_supported_body": "L'app offre registri coerenti con l'autocontrollo alimentare (HACCP) e i modelli attivabili per l'esercizio.",
    "haccp_recommended_sample": "Modello di registro consigliato (HACCP)",
    "haccp_configure_in_settings": "Il titolare e la gestione configurano i registri in Impostazioni",
    "haccp_journals_settings_hint": "Selezione dei registri HACCP dell'esercizio",
    "haccp_enabled_journals": "Registri attivati",
    "haccp_log_health_hygiene_title": "Registro di igiene e sorveglianza sanitaria del personale manipolatore",
    "haccp_log_fridge_temperature_title": "Registro delle temperature di frigoriferi e congelatori",
    "haccp_log_warehouse_temp_humidity_title": "Registro di temperatura e umidità in magazzino e celle",
    "haccp_log_finished_product_brakerage_title": "Registro di valutazione organolettica e rilascio del prodotto finito",
    "haccp_log_incoming_raw_brakerage_title": "Registro di controllo organoleptico in ricevimento di materie prime deperibili",
    "haccp_log_frying_oil_title": "Registro di monitoraggio degli oli per frittura",
    "haccp_log_med_book_registry_title": "Registro della documentazione sanitaria del personale alimentare",
    "haccp_log_med_examinations_title": "Registro delle visite mediche del personale alimentare",
    "haccp_log_disinfectant_accounting_title": "Registro di disinfettanti e trattamenti di disinfezione",
    "haccp_log_equipment_washing_title": "Registro di pulizia e disinfezione di attrezzature e utensili",
    "haccp_log_general_cleaning_schedule_title": "Registro e pianificazione delle pulizie (anche generali)",
    "haccp_log_sieve_filter_magnet_title": "Registro di ispezione e pulizia di setacci, filtri e separatori magnetici",
    "haccp_sanpin_line_health_hygiene": f"Sorveglianza giornaliera del personale — autocontrollo. Rif. : {IT_BASE}.",
    "haccp_sanpin_line_fridge_temperature": f"Catena del freddo — autocontrollo. Rif. : {IT_BASE}.",
    "haccp_sanpin_line_warehouse_temp_humidity": f"Stoccaggio (T°, umidità) — autocontrollo. Rif. : {IT_BASE}.",
    "haccp_sanpin_line_finished_product_brakerage": f"Organolettica / rilascio prodotto finito — autocontrollo. Rif. : {IT_BASE}.",
    "haccp_sanpin_line_incoming_raw_brakerage": f"Ricevimento MP — autocontrollo. Rif. : {IT_BASE}.",
    "haccp_sanpin_line_frying_oil": f"Oli da frittura — buone pratiche. Rif. : {IT_BASE}.",
    "haccp_sanpin_line_med_book_registry": "Documentazione sanitaria del personale (normativa italiana sul lavoro e sicurezza alimentare).",
    "haccp_sanpin_line_med_examinations": "Sorveglianza sanitaria del personale (normativa italiana applicabile).",
    "haccp_sanpin_line_disinfectant_accounting": f"Disinfezione e biocidi — autocontrollo. Rif. : {IT_BASE}.",
    "haccp_sanpin_line_equipment_washing": f"Pulizia superfici a contatto con alimenti — autocontrollo. Rif. : {IT_BASE}.",
    "haccp_sanpin_line_general_cleaning_schedule": f"Piano di pulizia documentato — autocontrollo. Rif. : {IT_BASE}.",
    "haccp_sanpin_line_sieve_filter_magnet": f"Difesa fisica (setacci, magneti) — autocontrollo. Rif. : {IT_BASE}.",
    "haccp_sanpin_footer_health_hygiene": f"Personale — HACCP. Rif. : {IT_BASE}.",
    "haccp_sanpin_footer_fridge_temperature": f"Freddo — HACCP. Rif. : {IT_BASE}.",
    "haccp_sanpin_footer_warehouse_temp_humidity": f"Magazzino — HACCP. Rif. : {IT_BASE}.",
    "haccp_sanpin_footer_finished_product_brakerage": f"Prodotto finito — HACCP. Rif. : {IT_BASE}.",
    "haccp_sanpin_footer_incoming_raw_brakerage": f"Materie prime — HACCP. Rif. : {IT_BASE}.",
    "haccp_sanpin_footer_frying_oil": f"Frittura — HACCP. Rif. : {IT_BASE}.",
    "haccp_sanpin_footer_med_book_registry": "Documentazione sanitaria del personale (Italia).",
    "haccp_sanpin_footer_med_examinations": "Visite mediche del personale (Italia).",
    "haccp_sanpin_footer_disinfectant_accounting": f"Disinfezione — HACCP. Rif. : {IT_BASE}.",
    "haccp_sanpin_footer_equipment_washing": f"Attrezzature — HACCP. Rif. : {IT_BASE}.",
    "haccp_sanpin_footer_general_cleaning_schedule": f"Pulizie programmate — HACCP. Rif. : {IT_BASE}.",
    "haccp_sanpin_footer_sieve_filter_magnet": f"Setacci/magneti — HACCP. Rif. : {IT_BASE}.",
    "haccp_legal_hint": "HACCP, Reg. 852/2004, eIDAS (Reg. UE 910/2014), GDPR e Codice della Privacy",
    "haccp_legal_text": (
        "Legittimità dei registri digitali (autocontrollo alimentare in Italia) :\n\n"
        "Il regolamento (CE) n. 852/2004 impone procedure di autocontrollo basate sui principi HACCP. "
        "In Italia il D.Lgs. 193/2007 e la normativa di settore definiscono gli adempimenti per la ristorazione. "
        "I dati in Restodocks documentano le verifiche per la tracciabilità e la diligenza dell'operatore.\n\n"
        "Identificazione e firma :\n"
        "L'accesso con utente e password si inquadra nel regolamento (UE) n. 910/2014 (eIDAS) e nel diritto italiano, "
        "con l'accordo con il lavoratore scaricabile dall'app.\n\n"
        "Dati personali :\n"
        "Trattamento secondo GDPR, Codice privacy e policy del titolare del trattamento.\n\n"
        "Integrità :\n"
        "Ogni voce è marcata temporalmente dal server.\n\n"
        "Nota : modelli di supporto; il titolare deve coprire i punti critici del proprio piano e i requisiti regionali."
    ),
    "haccp_legal_sp_extract": (
        "Estratto orientativo : Regolamento (CE) n. 852/2004 e D.Lgs. 193/2007 (autocontrollo alimentare in Italia)"
    ),
    "haccp_legal_sp_paragraphs": (
        "Igiene del personale manipolatore :\n"
        "È necessario un registro che documenti controlli su salute apparente e igiene delle persone a contatto con gli alimenti.\n\n"
        "Catena del freddo e magazzino :\n"
        "L'operatore conserva evidenze di temperature e condizioni per celle, magazzini e banchi, coerenti con l'analisi dei pericoli."
    ),
    "haccp_pdf_document_producer": "Restodocks (HACCP — Italia : Reg. 852/2004, D.Lgs. 193/2007)",
    "haccp_pdf_health_form_caption": "Modello di registro igiene del personale (Italia/UE)",
    "haccp_pdf_frying_oil_subtitle": "Modello di registro oli da frittura (Italia/UE)",
    "documentation_haccp_subtitle": "Documentazione, registri HACCP e accordi per firma elettronica",
    "tour_tile_haccp": (
        "Registri di autocontrollo: temperature, organolettica, igiene, disinfezione e altro. "
        "Dopo il salvataggio le righe non si modificano."
    ),
    "haccp_order_pdf_p1_intro_sanpin": (
        "Per ottimizzare i processi, garantire il controllo operativo e l'integrità dei dati, "
        "nell'ambito dell'autocontrollo alimentare (HACCP) conformemente al Regolamento (CE) n. 852/2004 e al D.Lgs. 193/2007,"
    ),
    "post_registration_trial_paid_list": (
        "1. Più di 6 dipendenti.\n"
        "2. Import schede — solo creazione manuale.\n"
        "3. Foto sulle schede (semilavorati/piatti).\n"
        "4. Inventari (qualsiasi interazione).\n"
        "5. Registri HACCP (qualsiasi interazione).\n"
        "6. Scarichi di magazzino (qualsiasi interazione).\n"
        "7. Configurazione pulsante centrale.\n"
        "8. Banchetti / catering.\n"
        "9. Stato fisso/temporaneo (senza abbonamento — solo fisso).\n"
        "10. Intero blocco Spese.\n"
        "11. Chat di gruppo nei messaggi.\n"
        "12. Invio foto nei messaggi.\n"
        "13. Aggiungere co-proprietario con accesso completo."
    ),
}

DE: dict[str, str] = {
    "haccp_journals": "HACCP-Protokolle (Eigenkontrolle)",
    "haccp_no_journals_hint": "Keine HACCP-Protokolle konfiguriert",
    "haccp_no_journals_subtitle": "Inhaber und Management aktivieren Protokolle in den Einstellungen; danach erscheinen sie hier.",
    "haccp_scroll_right_hint": "Tabelle nach Protokollmodell für Lebensmittelhygiene (DE/EU) — bei Bedarf horizontal scrollen.",
    "haccp_not_supported_title": "Dieser Protokolltyp wird in der App nicht mehr angeboten.",
    "haccp_not_supported_body": "Die App bietet Protokolle zur Eigenkontrolle (HACCP) und die im Betrieb aktivierbaren Vorlagen.",
    "haccp_recommended_sample": "Empfohlenes Protokollmuster (HACCP / Eigenkontrolle)",
    "haccp_configure_in_settings": "Inhaber und Management wählen Protokolle in den Einstellungen",
    "haccp_journals_settings_hint": "Auswahl der HACCP-Protokolle des Betriebs",
    "haccp_enabled_journals": "Aktivierte Protokolle",
    "haccp_log_health_hygiene_title": "Protokoll zur Hygiene und Gesundheitsüberwachung des Personals",
    "haccp_log_fridge_temperature_title": "Protokoll Temperaturen Kühl- und Gefriergeräte",
    "haccp_log_warehouse_temp_humidity_title": "Protokoll Temperatur und Feuchte in Lagern und Kühlräumen",
    "haccp_log_finished_product_brakerage_title": "Protokoll sensorische Prüfung / Freigabe Fertigerzeugnis",
    "haccp_log_incoming_raw_brakerage_title": "Protokoll sensorische Eingangskontrolle verderblicher Rohstoffe",
    "haccp_log_frying_oil_title": "Protokoll Frittieröle / Ölwechsel",
    "haccp_log_med_book_registry_title": "Protokoll Gesundheitsunterlagen des Lebensmittelpersonals",
    "haccp_log_med_examinations_title": "Protokoll arbeitsmedizinische Vorsorge des Personals",
    "haccp_log_disinfectant_accounting_title": "Protokoll Desinfektionsmittel und Desinfektionsmaßnahmen",
    "haccp_log_equipment_washing_title": "Protokoll Reinigung und Desinfektion von Geräten und Utensilien",
    "haccp_log_general_cleaning_schedule_title": "Protokoll und Planung der Reinigungen (einschließlich Grundreinigung)",
    "haccp_log_sieve_filter_magnet_title": "Protokoll Prüfung und Reinigung von Sieben, Filtern und Magnetabscheidern",
    "haccp_sanpin_line_health_hygiene": f"Tägliche Personalüberwachung — Eigenkontrolle. Ref. : {DE_BASE}.",
    "haccp_sanpin_line_fridge_temperature": f"Kühlkette — Eigenkontrolle. Ref. : {DE_BASE}.",
    "haccp_sanpin_line_warehouse_temp_humidity": f"Lagerbedingungen — Eigenkontrolle. Ref. : {DE_BASE}.",
    "haccp_sanpin_line_finished_product_brakerage": f"Sensorik / Freigabe — Eigenkontrolle. Ref. : {DE_BASE}.",
    "haccp_sanpin_line_incoming_raw_brakerage": f"Wareneingang — Eigenkontrolle. Ref. : {DE_BASE}.",
    "haccp_sanpin_line_frying_oil": f"Frittierfette — gute Praxis. Ref. : {DE_BASE}.",
    "haccp_sanpin_line_med_book_registry": "Gesundheitsdokumentation des Personals (deutsches Arbeits- und Gesundheitsrecht).",
    "haccp_sanpin_line_med_examinations": "Arbeitsmedizinische Betreuung (anwendbares deutsches Recht).",
    "haccp_sanpin_line_disinfectant_accounting": f"Desinfektion — Eigenkontrolle. Ref. : {DE_BASE}.",
    "haccp_sanpin_line_equipment_washing": f"Reinigung lebensmittelberührender Flächen — Eigenkontrolle. Ref. : {DE_BASE}.",
    "haccp_sanpin_line_general_cleaning_schedule": f"Reinigungsplan — Eigenkontrolle. Ref. : {DE_BASE}.",
    "haccp_sanpin_line_sieve_filter_magnet": f"Fremdkörpervorsorge — Eigenkontrolle. Ref. : {DE_BASE}.",
    "haccp_sanpin_footer_health_hygiene": f"Personal — HACCP. Ref. : {DE_BASE}.",
    "haccp_sanpin_footer_fridge_temperature": f"Kühlung — HACCP. Ref. : {DE_BASE}.",
    "haccp_sanpin_footer_warehouse_temp_humidity": f"Lager — HACCP. Ref. : {DE_BASE}.",
    "haccp_sanpin_footer_finished_product_brakerage": f"Fertigprodukt — HACCP. Ref. : {DE_BASE}.",
    "haccp_sanpin_footer_incoming_raw_brakerage": f"Rohstoffe — HACCP. Ref. : {DE_BASE}.",
    "haccp_sanpin_footer_frying_oil": f"Frittieren — HACCP. Ref. : {DE_BASE}.",
    "haccp_sanpin_footer_med_book_registry": "Gesundheitsunterlagen (Deutschland).",
    "haccp_sanpin_footer_med_examinations": "Arbeitsmedizin (Deutschland).",
    "haccp_sanpin_footer_disinfectant_accounting": f"Desinfektion — HACCP. Ref. : {DE_BASE}.",
    "haccp_sanpin_footer_equipment_washing": f"Geräte — HACCP. Ref. : {DE_BASE}.",
    "haccp_sanpin_footer_general_cleaning_schedule": f"Reinigung — HACCP. Ref. : {DE_BASE}.",
    "haccp_sanpin_footer_sieve_filter_magnet": f"Siebe/Magnete — HACCP. Ref. : {DE_BASE}.",
    "haccp_legal_hint": "HACCP, VO 852/2004, eIDAS (EU-VO 910/2014), DSGVO und BDSG",
    "haccp_legal_text": (
        "Rechtsgrundlage digitaler Protokolle (Eigenkontrolle in Deutschland) :\n\n"
        "Die Verordnung (EG) Nr. 852/2004 verlangt lebensmittelhygienische Verfahren und Eigenkontrolle nach HACCP-Prinzipien. "
        "In Deutschland ergänzen u. a. die LMHV und Landesvorschriften die Anforderungen. "
        "Einträge in Restodocks dokumentieren Überwachungen für Rückverfolgbarkeit und Sorgfalt des Betreibers.\n\n"
        "Identifikation und Signatur :\n"
        "Die Anmeldung mit Benutzerkonto ordnet sich in den Rahmen der Verordnung (EU) Nr. 910/2014 (eIDAS) und des nationalen Rechts ein, "
        "ergänzt durch die Mitarbeitervereinbarung in der App.\n\n"
        "Personenbezogene Daten :\n"
        "Verarbeitung nach DSGVO, BDSG und der Datenschutzerklärung des Verantwortlichen.\n\n"
        "Integrität :\n"
        "Serverseitige Zeitstempel erschweren nachträgliche Änderungen.\n\n"
        "Hinweis : Vorlagen sind Hilfestellung; der Betrieb muss kritische Punkte seines HACCP-Plans und Behördenanforderungen abdecken."
    ),
    "haccp_legal_sp_extract": (
        "Orientierung : Verordnung (EG) Nr. 852/2004 und Lebensmittelhygiene-Verordnung (LMHV) — Eigenkontrolle in Deutschland"
    ),
    "haccp_legal_sp_paragraphs": (
        "Überwachung der Personalhygiene :\n"
        "Es ist ein dokumentierter Nachweis zu Gesundheitszustand und Hygiene von Personen mit Lebensmittelkontakt erforderlich.\n\n"
        "Kühlkette und Lagerung :\n"
        "Der Betrieb führt Nachweise zu Temperaturen und Bedingungen für Kühlräume, Lager und Theken entsprechend seiner Gefahrenanalyse."
    ),
    "haccp_pdf_document_producer": "Restodocks (HACCP — DE : VO 852/2004, LMHV)",
    "haccp_pdf_health_form_caption": "Musterprotokoll Personalhygiene (DE/EU)",
    "haccp_pdf_frying_oil_subtitle": "Musterprotokoll Frittieröle (DE/EU)",
    "documentation_haccp_subtitle": "Dokumentation, HACCP-Protokolle und Vereinbarungen zur elektronischen Signatur",
    "tour_tile_haccp": (
        "Eigenkontroll-Protokolle: Temperaturen, Sensorik, Hygiene, Desinfektion u. a. "
        "Nach dem Speichern sind Einträge nicht mehr änderbar."
    ),
    "haccp_order_pdf_p1_intro_sanpin": (
        "Zur Optimierung der Abläufe, zur Gewährleistung der betrieblichen Kontrolle und der Datenintegrität "
        "und im Rahmen der lebensmittelhygienischen Eigenkontrolle (HACCP) gemäß Verordnung (EG) Nr. 852/2004 "
        "und Lebensmittelhygiene-Verordnung (LMHV),"
    ),
    "post_registration_trial_paid_list": (
        "1. Mehr als 6 Mitarbeitende.\n"
        "2. Rezeptkarten-Import — nur manuelle Anlage.\n"
        "3. Fotos in Rezeptkarten (Halbfabrikate/Gerichte).\n"
        "4. Inventare (jede Interaktion).\n"
        "5. HACCP-Protokolle (jede Interaktion).\n"
        "6. Schwund/Abschreibungen (jede Interaktion).\n"
        "7. Konfiguration der Mitteltaste.\n"
        "8. Bankette / Catering.\n"
        "9. Fest/Temporär-Status (ohne Abo — nur fest).\n"
        "10. Gesamter Bereich Ausgaben.\n"
        "11. Gruppenchats in Nachrichten.\n"
        "12. Fotos in Nachrichten senden.\n"
        "13. Miteigentümer mit vollem Zugang hinzufügen."
    ),
}

EN: dict[str, str] = {
    "haccp_journals": "HACCP logs (EU hygiene)",
    "haccp_no_journals_hint": "No HACCP logs are configured",
    "haccp_no_journals_subtitle": "The owner and management enable logs in Settings. Once configured, they appear here.",
    "haccp_scroll_right_hint": "Table layout for food hygiene self-monitoring (EU) — scroll horizontally if needed.",
    "haccp_not_supported_title": "This log type is no longer available in the app.",
    "haccp_not_supported_body": "The app provides logs aligned with food safety self-monitoring (HACCP) and the templates your site enables.",
    "haccp_recommended_sample": "Recommended log template (HACCP)",
    "haccp_configure_in_settings": "Owner and management select logs in Settings",
    "haccp_journals_settings_hint": "Which HACCP logs are enabled for the site",
    "haccp_enabled_journals": "Enabled logs",
    "haccp_log_health_hygiene_title": "Staff hygiene and health monitoring log",
    "haccp_log_fridge_temperature_title": "Refrigeration and freezing equipment temperature log",
    "haccp_log_warehouse_temp_humidity_title": "Warehouse and cold room temperature and humidity log",
    "haccp_log_finished_product_brakerage_title": "Finished product organoleptic assessment and release log",
    "haccp_log_incoming_raw_brakerage_title": "Perishable goods intake organoleptic check log",
    "haccp_log_frying_oil_title": "Frying oil monitoring log",
    "haccp_log_med_book_registry_title": "Food handlers’ health documentation log",
    "haccp_log_med_examinations_title": "Mandatory health surveillance log for food handlers",
    "haccp_log_disinfectant_accounting_title": "Disinfectants and disinfection treatments log",
    "haccp_log_equipment_washing_title": "Equipment and utensil cleaning and disinfection log",
    "haccp_log_general_cleaning_schedule_title": "Cleaning schedule log (including deep cleaning)",
    "haccp_log_sieve_filter_magnet_title": "Sieves, filters and magnetic traps inspection log",
    "haccp_sanpin_line_health_hygiene": f"Daily staff health/hygiene checks — HACCP self-monitoring. Ref: {EN_BASE}.",
    "haccp_sanpin_line_fridge_temperature": f"Cold chain temperature control — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_line_warehouse_temp_humidity": f"Storage conditions — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_line_finished_product_brakerage": f"Organoleptic / release — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_line_incoming_raw_brakerage": f"Intake checks — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_line_frying_oil": f"Frying media — good practice. Ref: {EN_BASE}.",
    "haccp_sanpin_line_med_book_registry": "Health records for staff (applicable employment and food safety law in your jurisdiction).",
    "haccp_sanpin_line_med_examinations": "Occupational health surveillance (applicable national law).",
    "haccp_sanpin_line_disinfectant_accounting": f"Disinfection — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_line_equipment_washing": f"Cleaning of food-contact surfaces — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_line_general_cleaning_schedule": f"Documented cleaning plan — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_line_sieve_filter_magnet": f"Physical contamination prevention — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_footer_health_hygiene": f"Staff — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_footer_fridge_temperature": f"Refrigeration — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_footer_warehouse_temp_humidity": f"Warehouse — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_footer_finished_product_brakerage": f"Finished product — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_footer_incoming_raw_brakerage": f"Raw materials — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_footer_frying_oil": f"Frying — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_footer_med_book_registry": "Health documentation (national law).",
    "haccp_sanpin_footer_med_examinations": "Health surveillance (national law).",
    "haccp_sanpin_footer_disinfectant_accounting": f"Disinfection — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_footer_equipment_washing": f"Equipment — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_footer_general_cleaning_schedule": f"Scheduled cleaning — HACCP. Ref: {EN_BASE}.",
    "haccp_sanpin_footer_sieve_filter_magnet": f"Sieves/magnets — HACCP. Ref: {EN_BASE}.",
    "haccp_legal_hint": "HACCP, Regulation 852/2004, eIDAS (EU 910/2014), GDPR",
    "haccp_legal_text": (
        "Legitimacy of digital logs (EU food hygiene / HACCP) :\n\n"
        "Regulation (EC) No 852/2004 requires food business operators to apply hygiene procedures and HACCP-based self-monitoring. "
        "National rules in each Member State add detail. Entries in Restodocks document checks for traceability and due diligence.\n\n"
        "Sign-in and signature :\n"
        "Account-based access aligns with Regulation (EU) No 910/2014 (eIDAS) and national law, together with the staff agreement available in the app.\n\n"
        "Personal data :\n"
        "Processing under the GDPR (and UK GDPR where applicable) and the controller’s privacy policy.\n\n"
        "Integrity :\n"
        "Server timestamps are stored for each entry.\n\n"
        "Note: templates are aids; you must cover critical control points in your plan and any local authority requirements."
    ),
    "haccp_legal_sp_extract": (
        "Orientation: Regulation (EC) No 852/2004 — EU food hygiene and HACCP-based self-monitoring"
    ),
    "haccp_legal_sp_paragraphs": (
        "Staff hygiene monitoring :\n"
        "Documented checks help demonstrate control of visible health and hygiene for people handling food.\n\n"
        "Cold chain and storage :\n"
        "Keep evidence of temperatures and conditions for cold rooms, stores and display, consistent with your hazard analysis."
    ),
    "haccp_pdf_document_producer": "Restodocks (HACCP — EU: Regulation 852/2004)",
    "haccp_pdf_health_form_caption": "Staff hygiene log template (EU)",
    "haccp_pdf_frying_oil_subtitle": "Frying oil control log template (EU)",
    "documentation_haccp_subtitle": "Documentation, HACCP logs and electronic signature agreements",
    "tour_tile_haccp": (
        "Self-monitoring logs: temperatures, organoleptic checks, hygiene, disinfection and more. "
        "Saved entries cannot be edited."
    ),
    "haccp_order_pdf_p1_intro_sanpin": (
        "To optimise workflows, ensure operational control and data integrity, "
        "and within food safety self-monitoring (HACCP) under Regulation (EC) No 852/2004,"
    ),
    "post_registration_trial_paid_list": (
        "1. More than 6 employees.\n"
        "2. Tech card import — manual creation only.\n"
        "3. Photo upload on tech cards (semi-finished / dishes).\n"
        "4. Inventories (any interaction).\n"
        "5. HACCP logs (any interaction).\n"
        "6. Write-offs (any interaction).\n"
        "7. Central button configuration.\n"
        "8. Banquets / catering.\n"
        "9. Permanent/temporary status (without subscription — permanent only).\n"
        "10. Entire Expenses section.\n"
        "11. Group chats in messages.\n"
        "12. Sending photos in messages.\n"
        "13. Adding a co-owner with full access."
    ),
}

LOCALES: dict[str, dict[str, str]] = {
    "fr": FR,
    "it": IT,
    "de": DE,
    "en": EN,
}


def main() -> None:
    data = json.loads(PATH.read_text(encoding="utf-8"))
    total = 0
    for lang, patch in LOCALES.items():
        block = data.get(lang)
        if not isinstance(block, dict):
            print(f"Skip missing locale: {lang}")
            continue
        n = 0
        for k, v in patch.items():
            if k in block:
                block[k] = v
                n += 1
        print(f"Patched {n} keys in {lang}.")
        total += n
    PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Total patches: {total}")


if __name__ == "__main__":
    main()
