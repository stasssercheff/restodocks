# Restodocks — Descripción técnica (ENISA / Startup Visa)

## 1. Arquitectura del sistema

### 1.1 Capa cliente

- Cliente principal: Flutter 3.x (Dart SDK ≥3.5), una sola base de código para iOS, Android y Web (supabase_flutter, go_router, provider).
- Persistencia local: shared_preferences, SQLite (sqflite) para instantáneas JSON grandes, además de servicios orientados a modo offline (caché, hidratación del establecimiento).
- Red: cliente Supabase con reintentos HTTP; suscripciones Realtime a `tech_cards` y `products` con actualización diferida (~700 ms) y comprobación periódica.

### 1.2 Capa backend

- BaaS: Supabase — PostgreSQL, PostgREST, Auth (sesiones JWT), Row Level Security (RLS), Realtime, Storage, Edge Functions (Deno/TypeScript).
- APIs operativas: Edge Functions para parsing con IA, recepciones de compras, facturación (p. ej. verificación Apple IAP), flujos de correo.
- Administración: aplicación Next.js separada (rutas API, Supabase en servidor) para tareas operativas — no es la UI principal del restaurante.

### 1.3 Modelo de datos híbrido

- Fuente de verdad: PostgreSQL — tablas relacionales de inquilinos (establishments), empleados, productos, precios de nomenclatura (`establishment_products`), cabeceras de fichas técnicas (`tech_cards`), líneas de ingredientes normalizadas (`tt_ingredients`), documentos de compras, traducciones, ajustes fiscales.
- Bloques estructurados: JSON/JSONB donde procede (secciones de ficha técnica, payloads de documentos).
- Mapeo en cliente: los modelos Flutter proyectan filas en grafos en memoria; el coste de alimentos suele derivarse en lectura a partir de precios actuales y estructura de receta.
- Caché: precios/catálogo en memoria, refresco por TTL, hidratación por establecimiento — UX offline-first con reconciliación con el servidor.

Es un diseño híbrido relacional + estilo documento: normalización donde importa la integridad; JSON flexible donde los bloques de UI lo requieren.

---

## 2. Coste alimentario dinámico — algoritmo central

### 2.1 Fuente de verdad de precios

- Precio unitario por establecimiento: `establishment_products` (precio + moneda), actualización mediante upsert sobre `(establishment_id, product_id)`.
- Historial de precios: `product_price_history` cuando el precio efectivo cambia más allá de un epsilon pequeño (0,001).

### 2.2 Compras → actualización de precios

- Líneas de recepción: cantidad recibida, precio real por unidad, % de descuento.
- Precio unitario efectivo = actualPrice × (1 − descuento/100).
- Las líneas que difieren de la nomenclatura se recogen; según la política, flujos Edge o aprobación en dispositivo; las líneas seleccionadas actualizan el precio de nomenclatura (incl. catálogo compartido entre sedes).

### 2.3 «Recálculo» de fichas técnicas

- Las recetas referencian productos y semi-elaborados (`sourceTechCardId`).
- El coste mostrado se obtiene por hidratación: `TechCardCostHydrator` resuelve hojas con `getEstablishmentPrice` (reserva `basePrice`), convierte bruto/neto/piezas a cantidad equivalente en kg, calcula cost = pricePerKg × qty.
- Semi-elaborados anidados: resolución recursiva con protección contra ciclos (memo + conjunto resolving); el peso de salida y la suma de costes del anidado implican precio por kg para la línea padre.
- Capas de UI (p. ej. tabla tipo Excel) aplican la misma resolución por coherencia.

Cambiar el precio en una factura no ejecuta un UPDATE masivo sobre todas las fichas en SQL; se actualiza `establishment_products`. La siguiente carga, refresco Realtime o pasada de hidratación recalcula — baja amplificación de escrituras, sin un único agregado obsoleto en BD.

### 2.4 Rendimiento y comportamiento numérico

- Complejidad: O(ingredientes × profundidad de anidación) con memoización.
- Latencia: dominada por la red y el parseo JSON, no por la aritmética (double en Dart).
- Precisión: coma flotante IEEE-754; igualdad de precios con epsilon 0,001; g↔kg mediante /1000 — adecuado para coste operativo, no para auditoría legal certificada.

### 2.5 Casos límite

- Sin precio: coste 0 o sin cambio hasta que exista precio.
- Unidades en piezas (`pcs` / `шт`): masa vía `gramsPerPiece` (por defecto 50 g).
- Moneda: por línea; no se asume consolidación multimonetaria sin reglas de cambio explícitas.

---

## 3. Innovación tecnológica

### 3.1 IA en producción

- Edge Functions: LLM convierte imágenes de ticket/ficha técnica en JSON estructurado (modelos de visión vía capa de proveedor compartida); extracción por lotes, PDF, listas de productos, duplicados, listas de chequeo.
- Las claves API permanecen en servidor (Edge/Vault); Flutter solo invoca funciones.
- OCR en dispositivo (móvil): Google ML Kit + Apple Vision para baja latencia sin ida-vuelta al servidor.

### 3.2 Escalabilidad de ingeniería

- Los proveedores LLM/OCR son intercambiables tras el límite de las funciones sin reescribir el dominio Flutter (patrones documentados en el repositorio).

### 3.3 Arquitectura multilingüe

- UI: un único `localizable.json` por códigos de idioma; `LocalizationService` — claves en código, cadenas en assets; `intl` para formato.
- Locales de UI implementados: nueve (`ru`, `en`, `es`, `kk`, `de`, `fr`, `it`, `tr`, `vi`).
- Contenido de dominio (productos, fichas técnicas): `TranslationManager` + `TranslationService` — traducciones persistidas, opcionalmente Google Cloud Translation / MyMemory / IA, anulaciones manuales.
- Scripts de mantenimiento de paridad de claves. Las compilaciones nativas incluyen traducciones en el binario; la web puede cargar JSON tras el despliegue.

---

## 4. Seguridad y enfoque GDPR (técnico)

### 4.1 Autenticación

- Supabase Auth — sesiones JWT; confirmación de correo por deep link (flujo implícito donde aplica).

### 4.2 Autorización

- RLS en tablas de inquilinos; políticas para roles autenticados y predicados por establecimiento.
- RPC `check_establishment_access(establishment_id)` centraliza suscripción, promociones, derechos de uso; migraciones con GRANT/REVOKE endurecidos.
- Flujos sensibles (compras, documentos de pedido) mediante Edge Functions con validación en servidor y service role cuando procede.

### 4.3 Notas GDPR (sin asesoramiento jurídico)

- Texto de política de privacidad multilingüe en la app (`legal_texts.dart`).
- Modelo multi-inquilino con aislamiento de datos por establecimiento.
- Retención: la política menciona plazos legales/contables; copias de seguridad y exportación son decisiones operativas.

---

## 5. Escalabilidad y nuevos mercados

### 5.1 Moneda

- Moneda por defecto del establecimiento y moneda por línea de nomenclatura; listas centralizadas de códigos ISO — ampliar mercados es sobre todo datos + UX, no rediseño de esquema.

### 5.2 Impuestos (IVA / regionales)

- Presets fiscales: JSON versionado (`world_tax_presets.json`) — regiones con listas de tipos de IVA, IVA por defecto, modo de precio (`tax_included` / `tax_excluded`), impuestos adicionales opcionales.
- Anulaciones por establecimiento: código de región, anulación de IVA, modo de precio; `effectiveVatPercent` resuelve preset ± anulación.
- Nueva jurisdicción (p. ej. España / IVA): añadir bloque de región, etiquetas y traducciones — trabajo incremental sobre el módulo fiscal existente.

### 5.3 Carga

- PostgreSQL + Edge escala con patrones habituales (pooling de conexiones, réplicas si se usan).
- Debounce y TTL en el cliente reducen picos de lectura con muchos dispositivos concurrentes.

---

## 6. Madurez operativa

- Migraciones SQL versionadas; herramientas i18n; registro en Edge (`log-system-error`); verificación de pagos Apple.
- El driver de hardware fiscal no está conectado en código (`isKktDriverConfigured == false`) — existe cola fiscal; la integración completa con registradora es un hito aparte.

---

*Documento basado en la estructura del código de Restodocks (Flutter + Supabase). Descripción técnica para solicitud ENISA / Startup Visa.*
