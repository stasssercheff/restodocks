String privacyPolicyFullText(String languageCode) {
  switch (languageCode) {
    case 'en':
      return privacyPolicyFullTextEn;
    case 'es':
      return privacyPolicyFullTextEs;
    case 'tr':
      return privacyPolicyFullTextTr;
    case 'vi':
      return privacyPolicyFullTextVi;
    default:
      return privacyPolicyFullTextRu;
  }
}

String publicOfferFullText(String languageCode) {
  switch (languageCode) {
    case 'en':
      return publicOfferFullTextEn;
    case 'es':
      return publicOfferFullTextEs;
    case 'tr':
      return publicOfferFullTextTr;
    case 'vi':
      return publicOfferFullTextVi;
    default:
      return publicOfferFullTextRu;
  }
}

const String privacyPolicyFullTextRu = '''
PRIVACY POLICY (Политика конфиденциальности)

Дата вступления в силу: 27.03.2026
Версия: 1.0

Настоящая Политика конфиденциальности описывает, какие данные собирает и обрабатывает сервис RestoDocks (веб-сайт и мобильное приложение), для каких целей, на каком основании и как обеспечивается защита данных.

1. Оператор данных
Оператор персональных данных / Исполнитель сервиса:
Ребриков Станислав Александрович
Российская Федерация, г. Санкт-Петербург, Калининский район, Лабораторный пр., д. 20, к. 3, стр. А, кв. 127
info@restodocks.com

2. Кого касается Политика
Политика применяется к:
- владельцам заведений и управляющим;
- сотрудникам заведений, зарегистрированным в системе;
- тестировщикам мобильного приложения (в т.ч. через TestFlight);
- посетителям сайта и пользователям веб/мобильной версии.

3. Какие данные мы обрабатываем
3.1 Данные аккаунта и идентификации
- email, имя/фамилия, служебная роль, идентификатор пользователя;
- данные авторизации и сессий;
- технические журналы входа (в т.ч. время, IP/страна/город — если доступно).

3.2 Данные заведения и бизнеса
- название заведения, структура подразделений;
- контактные и реквизитные данные, если пользователь их заполняет;
- настройки валют, прав доступа, организационные настройки.

3.3 Операционные данные
- номенклатура, ТТК, ингредиенты, цены, себестоимость;
- инвентаризации, списания, заказы, графики, чеклисты;
- HACCP/санитарные журналы и иные производственные записи;
- служебная переписка (inbox, чаты), если функционал используется.

3.4 Файлы и медиа
- документы и файлы, загруженные пользователем (например, Excel/PDF/Doc/изображения);
- экспортируемые файлы (PDF/XLSX/TXT), сформированные пользователем;
- фотографии для карточек, документов и иных сущностей системы.

3.5 Технические и аналитические данные
- служебные логи, диагностическая информация, ошибки;
- локальный кэш и черновики на устройстве пользователя для ускорения работы и офлайн-поведения.

4. Цели и правовые основания обработки
Мы обрабатываем данные для:
- предоставления доступа к функционалу сервиса;
- выполнения пользовательских действий (создание/редактирование/экспорт/синхронизация);
- администрирования аккаунтов и прав доступа;
- обеспечения безопасности, предотвращения злоупотреблений и расследования инцидентов;
- улучшения качества сервиса, стабильности и производительности;
- исполнения требований законодательства.

Правовые основания:
- исполнение договора (оказание цифрового сервиса);
- законный интерес Оператора (безопасность, поддержка, развитие сервиса);
- согласие пользователя (в случаях, где это требуется законом).

5. AI-функции и внешние провайдеры
В сервисе используются AI-функции (например, распознавание/структурирование документов и генерация служебного контента).
Для работы таких функций данные могут передаваться внешним AI/API-провайдерам в объеме, необходимом для выполнения запроса пользователя.
Мы предпринимаем организационные и технические меры для минимизации объема передаваемых данных и ограничения доступа к секретам/ключам.

6. Кому передаются данные
Данные могут обрабатываться/храниться у доверенных инфраструктурных провайдеров, которые обеспечивают работу сервиса, в том числе:
- Supabase (БД, аутентификация, storage, edge functions);
- Cloudflare и/или иные CDN/edge-инфраструктуры;
- сервисы email-доставки;
- сервисы AI/перевода/обработки документов (по запросу пользователя).
Мы не продаем персональные данные третьим лицам.

7. Международная передача данных
В зависимости от выбранной инфраструктуры и провайдеров данные могут обрабатываться за пределами страны пользователя.
Оператор принимает разумные меры для обеспечения сопоставимого уровня защиты данных при трансграничной передаче.

8. Сроки хранения
Данные хранятся:
- пока активен аккаунт и/или действует договор;
- в течение срока, необходимого для целей обработки;
- дольше — если этого требует закон (например, бухгалтерский/налоговый/архивный учет).
По запросу пользователя и при наличии законных оснований данные могут быть удалены или обезличены.

9. Безопасность данных
Мы используем технические и организационные меры защиты, включая:
- ролевую модель доступа и политики разграничения доступа;
- серверные проверки прав и ограничения действий;
- шифрование каналов передачи данных (TLS);
- резервное копирование и контроль целостности;
- аудит и обновление политик безопасности.
При этом ни один способ передачи/хранения данных не гарантирует абсолютную защиту.

10. Права субъекта данных
Пользователь вправе:
- запросить информацию о своих данных;
- требовать исправления неточных/неполных данных;
- запросить удаление данных (если применимо);
- ограничить или возразить против обработки в случаях, предусмотренных законом;
- отозвать согласие (если обработка основана на согласии);
- подать жалобу в уполномоченный орган.
Запросы направляются на: info@restodocks.com.

11. Cookies и локальное хранение
В веб-версии могут использоваться cookies/локальное хранилище для:
- авторизации и поддержания сессии;
- сохранения пользовательских настроек и черновиков;
- кэширования данных для ускорения интерфейса.
Отключение cookies/local storage может ограничить работоспособность отдельных функций.

12. Данные детей
Сервис предназначен для профессионального/делового использования.
Если вам стало известно о передаче данных несовершеннолетних с нарушением применимого права, свяжитесь с Оператором для удаления таких данных.

13. Изменения Политики
Мы можем обновлять Политику. Актуальная версия публикуется по месту размещения документа и вступает в силу с даты публикации, если не указано иное.

14. Контакты по вопросам данных
Ребриков Станислав Александрович
info@restodocks.com
''';

const String privacyPolicyFullTextEn = '''
PRIVACY POLICY

Effective date: 27.03.2026
Version: 1.0

This Privacy Policy describes what data the RestoDocks service (website and mobile application) collects and processes, for what purposes, on what legal grounds, and how data protection is ensured.

1. Data Controller
Data Controller / Service Provider:
Stanislav A. Rebrikov
Russian Federation, Saint Petersburg, Kalininsky district, Laboratorny pr., 20, bld. 3, str. A, apt. 127
info@restodocks.com

2. Scope
This Policy applies to establishment owners, managers, employees registered in the system, TestFlight testers, and website/mobile users.

3. Data We Process
3.1 Account and identification data: email, first/last name, role, user identifier, authorization/session data, and technical sign-in logs (including time, IP/country/city when available).
3.2 Establishment and business data: establishment profile, organizational structure, contact/record details entered by users, currency and access settings.
3.3 Operational data: products, tech cards, ingredients, costs, inventories, write-offs, orders, schedules, checklists, HACCP and production records, work chats.
3.4 Files and media: uploaded files/documents/images and exported files.
3.5 Technical and analytics data: service logs, diagnostics, errors, local cache and drafts.

4. Purposes and Legal Grounds
We process data to provide service functionality, execute user actions, manage access rights, ensure security, investigate incidents, improve performance, and comply with legal obligations.
Legal grounds: contract performance, legitimate interests, and consent where required by law.

5. AI Features and External Providers
RestoDocks may use AI features (for example, document recognition/structuring). Data may be sent to external AI/API providers only to the extent required to process the user request.

6. Data Sharing
Data may be processed/stored by trusted infrastructure providers including database/storage/edge/CDN/email/AI services needed to run the platform.
We do not sell personal data.

7. International Transfers
Depending on infrastructure and providers, data may be processed outside the user’s country. Reasonable safeguards are applied.

8. Retention
Data is retained while the account/contract is active and as required for processing purposes or by law. Data may be deleted or anonymized upon lawful request.

9. Security
We use technical and organizational safeguards, including role-based access controls, server-side authorization checks, TLS, backup/integrity controls, and security policy updates.
No transmission/storage method is absolutely secure.

10. Data Subject Rights
Users may request access, correction, deletion (where applicable), restriction/objection, consent withdrawal, and complaint filing with a supervisory authority.
Requests: info@restodocks.com.

11. Cookies and Local Storage
Web version may use cookies/local storage for authentication, preferences, drafts, and caching.

12. Children’s Data
The service is intended for professional/business use.

13. Policy Changes
We may update this Policy. The current version becomes effective from publication date unless stated otherwise.

14. Contacts
Stanislav A. Rebrikov
info@restodocks.com
''';

const String privacyPolicyFullTextEs = '''
POLITICA DE PRIVACIDAD

Fecha de entrada en vigor: 27.03.2026
Version: 1.0

Esta Politica de Privacidad describe que datos recopila y procesa el servicio RestoDocks (sitio web y aplicacion movil), con que fines, bajo que bases legales y como se protege la informacion.

1. Responsable del tratamiento
Responsable / Prestador del servicio:
Stanislav A. Rebrikov
Federacion de Rusia, San Petersburgo, distrito Kalininsky, Laboratorny pr., 20, corp. 3, str. A, apto. 127
info@restodocks.com

2. Alcance
Se aplica a propietarios de establecimientos, directivos, empleados registrados, testers de TestFlight y usuarios web/movil.

3. Datos tratados
Cuenta e identificacion; datos de establecimiento; datos operativos (productos, fichas tecnicas, inventarios, pedidos, HACCP, etc.); archivos y medios; datos tecnicos y de analitica.

4. Finalidades y bases legales
Prestacion del servicio, ejecucion de acciones del usuario, gestion de permisos, seguridad, mejora del producto y cumplimiento legal.
Bases: ejecucion del contrato, interes legitimo y consentimiento cuando sea exigible.

5. Funciones de IA y proveedores externos
Podemos usar funciones de IA y proveedores externos para procesar solicitudes del usuario en el minimo volumen necesario.

6. Transferencia a terceros
Los datos pueden ser procesados por proveedores de infraestructura confiables (BD, almacenamiento, edge/CDN, correo, IA).
No vendemos datos personales.

7. Transferencias internacionales
Segun la infraestructura, el tratamiento puede realizarse fuera del pais del usuario con medidas razonables de proteccion.

8. Conservacion
Los datos se conservan mientras la cuenta/contrato este activo y durante los plazos requeridos por ley o por finalidad.

9. Seguridad
Aplicamos controles de acceso por roles, validaciones en servidor, TLS, copias de seguridad y controles de integridad.

10. Derechos del titular
Acceso, rectificacion, eliminacion (cuando proceda), limitacion/oposicion, retiro del consentimiento y reclamacion ante la autoridad competente.
Contacto: info@restodocks.com.

11. Cookies y almacenamiento local
Se usan para autenticacion, preferencias, borradores y cache.

12. Datos de menores
El servicio esta destinado a uso profesional/empresarial.

13. Cambios de la Politica
Podemos actualizar esta Politica; la version vigente rige desde su publicacion.

14. Contactos
Stanislav A. Rebrikov
info@restodocks.com
''';

const String privacyPolicyFullTextTr = '''
GIZLILIK POLITIKASI

Yururluk tarihi: 27.03.2026
Surum: 1.0

Bu Gizlilik Politikasi, RestoDocks hizmetinin (web sitesi ve mobil uygulama) hangi verileri isledigini, hangi amaclarla kullandigini, hukuki dayanaklarini ve veri koruma yontemlerini aciklar.

1. Veri Sorumlusu
Veri Sorumlusu / Hizmet Saglayici:
Stanislav A. Rebrikov
Rusya Federasyonu, Saint Petersburg, Kalininsky bolgesi, Laboratorny pr., 20, b.3, yapi A, daire 127
info@restodocks.com

2. Kapsam
Bu Politika isletme sahipleri, yoneticiler, kayitli calisanlar, TestFlight test kullanicilari ve web/mobil kullanicilar icin gecerlidir.

3. Islenen Veriler
Hesap kimlik verileri, isletme verileri, operasyon verileri (urunler, teknik kartlar, envanter, siparisler, HACCP vb.), dosya/medya ve teknik loglar.

4. Amaclar ve Hukuki Dayanak
Hizmeti sunmak, erisim yonetimi, guvenlik, performans iyilestirme ve yasal yukumlulukleri yerine getirmek.
Hukuki dayanaklar: sozlesmenin ifasi, mesru menfaat, gerekli hallerde acik riza.

5. YZ Ozellikleri ve Harici Saglayicilar
Kullanici talebini yerine getirmek icin gerekli oldugu olcude harici YZ/API saglayicilari kullanilabilir.

6. Veri Aktarimi
Veriler guvenilir altyapi saglayicilarinda (veritabani, depolama, edge/CDN, e-posta, YZ) islenebilir.
Kisisel veriler satilmaz.

7. Uluslararasi Aktarim
Altyapiya bagli olarak veriler kullanicinin ulkesi disinda islenebilir; makul koruma onlemleri uygulanir.

8. Saklama
Veriler hesap/sozlesme suresi boyunca ve yasal yukumlulukler kapsaminda saklanir.

9. Guvenlik
Rol tabanli yetkilendirme, sunucu tarafli kontrol, TLS, yedekleme ve butunluk kontrolleri uygulanir.

10. Veri Sahibi Haklari
Erisim, duzeltme, silme (uygunsa), islemeyi kisitlama/itiraz, rizanin geri alinmasi ve denetim otoritesine basvuru haklari.
Iletisim: info@restodocks.com.

11. Cerezler ve Yerel Depolama
Kimlik dogrulama, tercihler, taslaklar ve onbellek icin kullanilabilir.

12. Cocuk Verileri
Hizmet profesyonel/is kullanimi icindir.

13. Politika Degisiklikleri
Politika guncellenebilir; guncel surum yayinlandigi tarihten itibaren gecerlidir.

14. Iletisim
Stanislav A. Rebrikov
info@restodocks.com
''';

const String privacyPolicyFullTextVi = '''
CHINH SACH BAO MAT

Ngay hieu luc: 27.03.2026
Phien ban: 1.0

Chinh sach nay mo ta du lieu ma dich vu RestoDocks (website va ung dung di dong) thu thap/xu ly, muc dich xu ly, co so phap ly va bien phap bao ve du lieu.

1. Don vi kiem soat du lieu
Don vi kiem soat / Don vi cung cap dich vu:
Stanislav A. Rebrikov
Lien bang Nga, Saint Petersburg, quan Kalininsky, Laboratorny pr., 20, toa 3, khu A, can 127
info@restodocks.com

2. Pham vi ap dung
Ap dung cho chu nha hang, quan ly, nhan vien da dang ky, nguoi thu nghiem TestFlight va nguoi dung web/mobile.

3. Du lieu duoc xu ly
Du lieu tai khoan va nhan dang; du lieu co so nha hang; du lieu van hanh (san pham, TTK, kiem ke, don hang, HACCP...); tep/tai lieu/hinh anh; du lieu ky thuat va nhat ky.

4. Muc dich va co so phap ly
Cung cap tinh nang, thuc hien hanh dong nguoi dung, quan tri quyen truy cap, dam bao an toan, cai tien hieu nang va tuan thu phap luat.
Co so: thuc hien hop dong, loi ich hop phap, va su dong y khi phap luat yeu cau.

5. Tinh nang AI va nha cung cap ben thu ba
Du lieu co the duoc gui den nha cung cap AI/API ben ngoai trong pham vi can thiet de xu ly yeu cau nguoi dung.

6. Chia se du lieu
Du lieu co the duoc xu ly/lưu tru boi nha cung cap ha tang dang tin cay (co so du lieu, storage, edge/CDN, email, AI).
Chung toi khong ban du lieu ca nhan.

7. Chuyen du lieu xuyen bien gioi
Tuy theo ha tang, du lieu co the duoc xu ly ngoai quoc gia cua nguoi dung; bien phap bao ve hop ly duoc ap dung.

8. Thoi han luu tru
Du lieu duoc luu trong thoi gian tai khoan/hop dong con hieu luc va theo yeu cau phap luat.

9. Bao mat
Ap dung phan quyen theo vai tro, kiem tra quyen tren may chu, TLS, sao luu va kiem soat toan ven.

10. Quyen cua chu the du lieu
Quyen truy cap, chinh sua, xoa (neu ap dung), han che/phan doi xu ly, rut lai dong y, va khieu nai den co quan co tham quyen.
Lien he: info@restodocks.com.

11. Cookie va luu tru cuc bo
Su dung cho dang nhap, cai dat, ban nhap va cache.

12. Du lieu tre em
Dich vu danh cho muc dich chuyen mon/kinh doanh.

13. Thay doi chinh sach
Chinh sach co the duoc cap nhat; ban moi co hieu luc tu ngay cong bo.

14. Lien he
Stanislav A. Rebrikov
info@restodocks.com
''';

const String publicOfferFullTextRu = '''
ДОГОВОР-ОФЕРТА НА ИСПОЛЬЗОВАНИЕ СЕРВИСА RESTODOCKS

Дата вступления в силу: 27.03.2026
Версия: 1.0

Настоящий документ является публичной офертой о заключении договора на предоставление доступа к сервису RestoDocks (веб-сайт и мобильное приложение).

1. Термины
- Исполнитель — лицо, предоставляющее доступ к сервису RestoDocks.
- Пользователь — физическое лицо, действующее от своего имени или от имени заведения/компании, использующее Сервис.
- Сервис — программный комплекс RestoDocks (веб и мобильное приложение) для автоматизации ресторанных процессов.
- Акцепт оферты — регистрация в Сервисе, начало использования Сервиса или иное действие, явно подтверждающее согласие с условиями.

2. Стороны и реквизиты Исполнителя
Исполнитель: Ребриков Станислав Александрович
Адрес: Российская Федерация, г. Санкт-Петербург, Калининский район, Лабораторный пр., д. 20, к. 3, стр. А, кв. 127
Email: info@restodocks.com
Реквизиты: при необходимости предоставляются по запросу в рамках применимого законодательства

3. Предмет договора
3.1. Исполнитель предоставляет Пользователю неисключительное, ограниченное право использования Сервиса по модели SaaS (доступ через интернет).
3.2. Пользователь использует Сервис для ведения операционной деятельности заведения: ТТК, номенклатура, инвентаризации, списания, заказы, документация, HACCP, графики и др.
3.3. Конкретный состав функций определяется текущей версией Сервиса и ролью Пользователя.

4. Порядок заключения договора (акцепт)
4.1. Оферта является публичной.
4.2. Акцептом считается любое из действий:
- регистрация учетной записи;
- авторизация и фактическое использование Сервиса;
- подтверждение согласия в интерфейсе.
С момента акцепта договор считается заключенным.

5. Доступ, учетные записи и роли
5.1. Пользователь обязан предоставлять достоверные данные при регистрации.
5.2. Пользователь отвечает за сохранность учетных данных и все действия, совершенные через его аккаунт.
5.3. В Сервисе действует ролевая модель доступа (например: owner, executive_chef, sous_chef, manager, бар/зал/кухня и др.).
5.4. Исполнитель вправе ограничить/приостановить доступ при нарушении договора, требований безопасности или законодательства.

6. Стоимость и расчеты
6.1. Условия оплаты (тарифы, периодичность, лимиты, промо-коды, бесплатные периоды) публикуются в интерфейсе Сервиса/на сайте или в отдельном документе.
6.2. Если применимо, оплата производится в порядке и сроки, указанные Исполнителем.
6.3. При просрочке оплаты Исполнитель вправе ограничить функционал до устранения задолженности.

7. Права и обязанности Пользователя
Пользователь обязуется:
- использовать Сервис только законным способом;
- не нарушать права третьих лиц;
- не загружать вредоносный код/материалы;
- не пытаться несанкционированно получить доступ к данным и инфраструктуре;
- соблюдать правила обработки персональных данных сотрудников и контрагентов.
Пользователь вправе:
- использовать оплаченный/доступный функционал Сервиса;
- получать поддержку в пределах выбранного уровня обслуживания;
- экспортировать доступные данные/отчеты в предусмотренных форматах.

8. Права и обязанности Исполнителя
Исполнитель вправе:
- обновлять, изменять и улучшать Сервис;
- вводить ограничения для защиты инфраструктуры и данных;
- проводить технические работы (по возможности с уведомлением).
Исполнитель обязуется:
- обеспечивать доступность Сервиса в разумных пределах;
- принимать меры по защите данных;
- не разглашать данные Пользователя за исключением случаев, предусмотренных договором и законом.

9. Данные и конфиденциальность
9.1. Обработка персональных данных осуществляется в соответствии с Политикой конфиденциальности.
9.2. Пользователь гарантирует наличие законных оснований на обработку и загрузку данных сотрудников/контрагентов в Сервис.
9.3. Исполнитель использует данные Пользователя для исполнения договора, безопасности, поддержки и развития Сервиса.

10. Интеллектуальная собственность
10.1. Исключительные права на Сервис, код, интерфейсы, базы данных, дизайн и документацию принадлежат Исполнителю или правообладателям.
10.2. Пользователь получает только право использования Сервиса в рамках договора.
10.3. Запрещены декомпиляция, реверс-инжиниринг, копирование и распространение Сервиса вне предусмотренных законом случаев.

11. Гарантии, ограничения ответственности
11.1. Сервис предоставляется по принципу «как есть» (as is) в пределах, допустимых законом.
11.2. Исполнитель не несет ответственности за:
- сбои, вызванные действиями третьих лиц, провайдеров связи, платформ;
- ошибки, вызванные некорректными действиями Пользователя;
- косвенные убытки и упущенную выгоду (если иное не предусмотрено законом).
11.3. Совокупная ответственность Исполнителя ограничивается суммой фактически уплаченных Пользователем средств за последние 12 месяцев, если иное не установлено императивными нормами.

12. Форс-мажор
Стороны освобождаются от ответственности за неисполнение обязательств при наступлении обстоятельств непреодолимой силы, подтвержденных надлежащим образом.

13. Срок действия и расторжение
13.1. Договор действует с момента акцепта до прекращения использования Сервиса/удаления аккаунта или расторжения по основаниям договора/закона.
13.2. Пользователь вправе прекратить использование Сервиса в любое время.
13.3. Исполнитель вправе прекратить доступ при существенном нарушении условий.

14. Изменение условий оферты
14.1. Исполнитель вправе изменять Оферту в одностороннем порядке.
14.2. Новая редакция вступает в силу с момента публикации, если не указано иное.
14.3. Продолжение использования Сервиса после публикации изменений означает согласие Пользователя с новой редакцией.

15. Применимое право и споры
15.1. Применимое право: право Российской Федерации.
15.2. Споры разрешаются путем переговоров; при недостижении согласия — в суде по месту нахождения Исполнителя (г. Санкт-Петербург), если иное не предусмотрено законом.

16. Контакты
По вопросам договора, доступа, претензий и уведомлений:
info@restodocks.com
Российская Федерация, г. Санкт-Петербург, Калининский район, Лабораторный пр., д. 20, к. 3, стр. А, кв. 127
''';

const String publicOfferFullTextEn = '''
PUBLIC OFFER AGREEMENT FOR USE OF THE RESTODOCKS SERVICE

Effective date: 27.03.2026
Version: 1.0

This document is a public offer to conclude an agreement for access to the RestoDocks service (website and mobile application).

1. Terms
Provider: person providing access to RestoDocks.
User: individual acting on their own behalf or on behalf of an establishment/company.
Service: RestoDocks software suite for restaurant process automation.
Acceptance: registration, use of the Service, or other explicit confirmation.

2. Provider Details
Provider: Stanislav A. Rebrikov
Address: Russian Federation, Saint Petersburg, Kalininsky district, Laboratorny pr., 20, bld. 3, str. A, apt. 127
Email: info@restodocks.com
Details: provided upon request where required by applicable law.

3. Subject
Provider grants User a limited non-exclusive right to use the Service in SaaS format.

4. Agreement Conclusion
The offer is public. Acceptance occurs through registration, authorization, actual use, or consent confirmation in the interface.

5. Access and Accounts
User must provide accurate registration data, protect credentials, and comply with role-based access rules.

6. Fees and Payments
Tariffs and payment terms are published in the interface/website or separate documents.
Where applicable, payment is made within the procedures and deadlines set by Provider.

7. User Rights and Obligations
User must use the Service lawfully, not violate third-party rights, not upload harmful code, and not attempt unauthorized access.

8. Provider Rights and Obligations
Provider may update/improve the Service, introduce technical limits for security, and perform maintenance.

9. Data and Confidentiality
Personal data is processed under the Privacy Policy.

10. Intellectual Property
Exclusive rights to the Service belong to Provider or rights holders.

11. Warranties and Liability Limits
Service is provided “as is” to the extent permitted by law.
Total Provider liability is limited to amounts actually paid by User for the last 12 months, unless mandatory law states otherwise.

12. Force Majeure
Parties are released from liability for non-performance due to force majeure.

13. Term and Termination
Agreement is valid from acceptance until account/service termination per agreement/law.

14. Offer Changes
Provider may amend the Offer unilaterally; new version is effective upon publication unless specified otherwise.

15. Governing Law and Disputes
Governing law: laws of the Russian Federation.
Disputes are resolved by negotiation; failing agreement, in court at Provider location (Saint Petersburg), unless law provides otherwise.

16. Contacts
info@restodocks.com
Russian Federation, Saint Petersburg, Kalininsky district, Laboratorny pr., 20, bld. 3, str. A, apt. 127
''';

const String publicOfferFullTextEs = '''
CONTRATO DE OFERTA PUBLICA PARA USO DEL SERVICIO RESTODOCKS

Fecha de entrada en vigor: 27.03.2026
Version: 1.0

Este documento es una oferta publica para celebrar un contrato de acceso al servicio RestoDocks (sitio web y aplicacion movil).

1. Terminos
Prestador, Usuario, Servicio y Aceptacion (registro, uso o confirmacion explicita).

2. Datos del Prestador
Stanislav A. Rebrikov
Federacion de Rusia, San Petersburgo, distrito Kalininsky, Laboratorny pr., 20, corp. 3, str. A, apto. 127
info@restodocks.com

3. Objeto
Derecho no exclusivo y limitado de uso del Servicio en modelo SaaS.

4. Aceptacion
La aceptacion se produce mediante registro, inicio de sesion, uso del Servicio o confirmacion en la interfaz.

5. Acceso y cuentas
El Usuario debe proporcionar datos veraces y proteger sus credenciales.

6. Tarifas y pagos
Las condiciones de pago se publican en la interfaz/sitio o documento separado.

7. Derechos y obligaciones del Usuario
Uso licito, sin violar derechos de terceros ni intentar acceso no autorizado.

8. Derechos y obligaciones del Prestador
Actualizar/mejorar el Servicio, introducir limites tecnicos y realizar mantenimiento.

9. Datos y confidencialidad
Tratamiento de datos segun la Politica de Privacidad.

10. Propiedad intelectual
Los derechos exclusivos pertenecen al Prestador o titulares de derechos.

11. Garantias y limitacion de responsabilidad
Servicio “tal cual” en los limites de la ley.
Responsabilidad total limitada a los pagos efectivamente realizados por el Usuario durante los ultimos 12 meses, salvo norma imperativa.

12. Fuerza mayor
Exencion de responsabilidad por incumplimiento debido a fuerza mayor.

13. Vigencia y terminacion
Desde la aceptacion hasta la terminacion del uso/cuenta segun contrato o ley.

14. Cambios de la oferta
El Prestador puede modificar la oferta; la nueva version entra en vigor al publicarse.

15. Ley aplicable y disputas
Ley aplicable: Federacion de Rusia.
Disputas: negociacion; de no haber acuerdo, tribunal en San Petersburgo, salvo norma legal en contrario.

16. Contacto
info@restodocks.com
Federacion de Rusia, San Petersburgo, distrito Kalininsky, Laboratorny pr., 20, corp. 3, str. A, apto. 127
''';

const String publicOfferFullTextTr = '''
RESTODOCKS HIZMETI KULLANIMI ICIN KAMU TEKLIF SOZLESMESI

Yururluk tarihi: 27.03.2026
Surum: 1.0

Bu belge, RestoDocks hizmetine (web sitesi ve mobil uygulama) erisim icin kamuya acik bir teklif niteligindedir.

1. Terimler
Saglayici, Kullanici, Hizmet ve Kabul (kayit, kullanim veya arayuzde onay).

2. Saglayici Bilgileri
Stanislav A. Rebrikov
Rusya Federasyonu, Saint Petersburg, Kalininsky bolgesi, Laboratorny pr., 20, b.3, yapi A, daire 127
info@restodocks.com

3. Konu
Kullaniciya SaaS modeliyle sinirli ve inhisari olmayan kullanim hakki verilir.

4. Kabul
Kayit, giris, fiili kullanim veya arayuzde onay ile sozlesme kabul edilmis sayilir.

5. Erisim ve Hesaplar
Kullanici dogru bilgi vermek ve hesap guvenligini saglamakla yukumludur.

6. Ucretlendirme ve Odeme
Tarifeler ve odeme kosullari arayuzde/sitede veya ayri belgede yayinlanir.

7. Kullanici Hak ve Yukumlulukleri
Hizmet yasalara uygun kullanilmali; ucuncu taraf haklari ihlal edilmemeli; yetkisiz erisim girisiminde bulunulmamalidir.

8. Saglayici Hak ve Yukumlulukleri
Hizmeti guncelleme/gelistirme, teknik sinirlar koyma ve bakim yapma hakki.

9. Veri ve Gizlilik
Veri isleme Gizlilik Politikasi kapsaminda yapilir.

10. Fikri Mulkiyet
Munasir haklar Saglayiciya veya hak sahiplerine aittir.

11. Garanti ve Sorumluluk Siniri
Hizmet “oldugu gibi” sunulur.
Toplam sorumluluk, zorunlu hukuk aksini gerektirmedikce son 12 ayda odenen tutarla sinirlidir.

12. Mucbir Sebep
Mucbir sebep halinde taraflar sorumluluktan muaf olur.

13. Sure ve Fesih
Sozlesme kabul anindan feshe kadar gecerlidir.

14. Teklifte Degisiklik
Saglayici teklifi tek tarafli degistirebilir; yeni metin yayimla yururluge girer.

15. Uygulanacak Hukuk ve Uyusmazlik
Uygulanacak hukuk: Rusya Federasyonu hukuku.
Uyusmazliklar once muzakerelerle, sonuc alinmazsa Saint Petersburg mahkemelerinde cozumlenecektir (hukuk aksini belirtmedikce).

16. Iletisim
info@restodocks.com
Rusya Federasyonu, Saint Petersburg, Kalininsky bolgesi, Laboratorny pr., 20, b.3, yapi A, daire 127
''';

const String publicOfferFullTextVi = '''
THOA THUAN CHAO DICH VU CONG KHAI CHO VIEC SU DUNG RESTODOCKS

Ngay hieu luc: 27.03.2026
Phien ban: 1.0

Tai lieu nay la de nghi cong khai de ky ket thoa thuan cung cap quyen truy cap dich vu RestoDocks (website va ung dung di dong).

1. Dinh nghia
Ben cung cap, Nguoi dung, Dich vu va Chap nhan (dang ky, su dung hoac xac nhan tren giao dien).

2. Thong tin Ben cung cap
Stanislav A. Rebrikov
Lien bang Nga, Saint Petersburg, quan Kalininsky, Laboratorny pr., 20, toa 3, khu A, can 127
info@restodocks.com

3. Doi tuong thoa thuan
Nguoi dung duoc cap quyen su dung khong doc quyen, gioi han theo mo hinh SaaS.

4. Chap nhan de nghi
Dang ky, dang nhap, su dung thuc te hoac xac nhan tren giao dien duoc xem la chap nhan.

5. Truy cap va tai khoan
Nguoi dung phai cung cap thong tin chinh xac va bao mat thong tin dang nhap.

6. Phi va thanh toan
Dieu kien gia/phi duoc cong bo tren giao dien/trang web hoac tai lieu rieng.

7. Quyen va nghia vu cua Nguoi dung
Su dung hop phap, khong xam pham quyen ben thu ba, khong co hanh vi truy cap trai phep.

8. Quyen va nghia vu cua Ben cung cap
Cap nhat/cai tien dich vu, dat gioi han ky thuat de bao mat, bao tri he thong.

9. Du lieu va bao mat
Du lieu duoc xu ly theo Chinh sach Bao mat.

10. So huu tri tue
Quyen so huu tri tue thuoc Ben cung cap hoac chu so huu quyen.

11. Bao dam va gioi han trach nhiem
Dich vu duoc cung cap “nguyen trang”.
Tong trach nhiem cua Ben cung cap duoc gioi han trong so tien Nguoi dung da thanh toan trong 12 thang gan nhat, tru khi phap luat bat buoc quy dinh khac.

12. Bat kha khang
Hai ben duoc mien trach nhiem khi khong the thuc hien nghia vu do su kien bat kha khang.

13. Hieu luc va cham dut
Thoa thuan co hieu luc tu khi chap nhan den khi cham dut theo hop dong/phap luat.

14. Sua doi de nghi
Ben cung cap co quyen sua doi don phuong; ban moi co hieu luc khi cong bo.

15. Luat ap dung va giai quyet tranh chap
Luat ap dung: luat Lien bang Nga.
Tranh chap uu tien thuong luong; neu khong dat duoc thoa thuan, giai quyet tai toa an noi Ben cung cap dat tru so (Saint Petersburg), tru khi phap luat quy dinh khac.

16. Lien he
info@restodocks.com
Lien bang Nga, Saint Petersburg, quan Kalininsky, Laboratorny pr., 20, toa 3, khu A, can 127
''';
