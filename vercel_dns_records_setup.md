# DNS записи для подключения restodocks.com к Vercel

## Шаги для получения точных DNS записей из Vercel Dashboard

### 1. Откройте Vercel Dashboard
- Перейдите на https://vercel.com/dashboard
- Найдите проект **restodocks** (или ваш Flutter проект)

### 2. Перейдите в настройки доменов
- Нажмите на проект
- Перейдите в **Settings** (настройки)
- Выберите **Domains** (домены) в левом меню

### 3. Добавьте домен restodocks.com
- Нажмите кнопку **Add Domain**
- Введите: `restodocks.com`
- Vercel спросит: "Add www.restodocks.com and redirect it to restodocks.com?"
  - ✅ Рекомендую выбрать **Yes** (добавит www автоматически)
- Нажмите **Add**

### 4. Vercel покажет DNS записи для настройки

После добавления домена Vercel покажет **точные DNS записи**, которые нужно добавить у вашего регистратора.

---

## DNS записи, которые Vercel предоставит

### Вариант А: Для Apex домена (restodocks.com)

Vercel покажет **A Record**:

```
Type: A
Name: @ (или оставьте пустым, или "restodocks.com")
Value: [IP адрес Vercel - будет показан в dashboard]
TTL: 3600 (или Auto)
```

**Важно:** IP адрес будет уникальным для вашего проекта. Обычно это один из:
- `76.76.21.21` (типичный для Vercel в 2024-2026)
- Или другой IP, который Vercel покажет в интерфейсе

### Вариант Б: Для www субдомена (www.restodocks.com)

Vercel покажет **CNAME Record**:

```
Type: CNAME
Name: www
Value: cname.vercel-dns.com
TTL: 3600 (или Auto)
```

**ИЛИ** Vercel может показать уникальный CNAME:

```
Type: CNAME
Name: www
Value: [уникальный-хэш].vercel-dns-017.com
TTL: 3600 (или Auto)
```

Пример: `d1d4fc829fe7bc7c.vercel-dns-017.com`

---

## Альтернативный метод: Vercel Nameservers (Рекомендуется)

Если Vercel предложит использовать nameservers, это **проще и надежнее**.

### Преимущества:
- Автоматическое управление всеми DNS записями
- Автоматическая настройка SSL
- Не нужно вручную добавлять A и CNAME записи

### Nameservers для настройки у регистратора:
```
ns1.vercel-dns.com
ns2.vercel-dns.com
```

### Где настроить:
1. Перейдите к вашему регистратору домена (где вы купили restodocks.com)
2. Найдите раздел "Nameservers" или "DNS Management"
3. Замените текущие nameservers:
   - **Старые:** dns1.registrar-servers.com, dns2.registrar-servers.com
   - **Новые:** ns1.vercel-dns.com, ns2.vercel-dns.com
4. Сохраните изменения

⚠️ **Внимание:** 
- Смена nameservers удалит ВСЕ существующие DNS записи
- Если у вас есть email или другие сервисы на домене, их нужно будет перенастроить в Vercel DNS

---

## Пошаговая инструкция для записи DNS записей

### Когда вы откроете Vercel Dashboard → Domains, вы увидите:

**Статус домена:** `Invalid Configuration` (красный)

**Сообщение:** "Configure your domain's DNS records"

**Показаны записи:**

#### Для restodocks.com:
```
Apex Domain (restodocks.com)
Type: A
Value: [IP адрес - запишите его!]
```

#### Для www.restodocks.com:
```
Subdomain (www)
Type: CNAME
Value: [CNAME адрес - запишите его!]
```

---

## Что нужно записать и где

### 1. Скопируйте точные значения из Vercel:
- [ ] IP адрес для A record (apex домена)
- [ ] CNAME для www субдомена
- [ ] (Опционально) Vercel nameservers, если предложены

### 2. Откройте панель управления вашего регистратора домена

**Где купили restodocks.com?**
- GoDaddy?
- Namecheap?
- Google Domains?
- Другой регистратор?

### 3. Найдите раздел DNS Management

Обычно находится:
- "DNS Management"
- "DNS Records"
- "Advanced DNS"
- "Manage DNS"

### 4. Добавьте записи

#### A Record для restodocks.com:
1. Нажмите "Add Record" или "Add DNS Record"
2. **Type:** A
3. **Host/Name:** @ (или пусто, или "restodocks.com")
4. **Value/Points to:** [IP из Vercel]
5. **TTL:** 3600 (или Auto)
6. Сохраните

#### CNAME Record для www.restodocks.com:
1. Нажмите "Add Record"
2. **Type:** CNAME
3. **Host/Name:** www
4. **Value/Points to:** [CNAME из Vercel]
5. **TTL:** 3600 (или Auto)
6. Сохраните

### 5. Удалите старую A запись (если есть)

Текущая A запись указывает на `216.198.79.1` - её нужно удалить или заменить.

---

## Проверка после настройки

### Сразу после добавления DNS записей:

```bash
# Проверить A запись
dig restodocks.com +short
# Должно показать IP из Vercel (не сразу, может занять время)

# Проверить CNAME для www
dig www.restodocks.com +short
# Должно показать cname.vercel-dns.com или уникальный CNAME

# Проверить распространение DNS (онлайн инструмент)
# https://www.whatsmydns.net/#A/restodocks.com
```

### В Vercel Dashboard:

После того как DNS записи распространятся (5 минут - 48 часов):
- Статус домена изменится с "Invalid Configuration" на "Valid" ✅
- Появится зеленая галочка
- SSL сертификат будет автоматически выпущен

---

## Контрольный чеклист

- [ ] Открыл Vercel Dashboard → Проект → Settings → Domains
- [ ] Добавил домен restodocks.com
- [ ] Записал точный IP адрес для A record
- [ ] Записал точный CNAME для www субдомена
- [ ] Открыл панель управления регистратора домена
- [ ] Удалил старую A запись (216.198.79.1)
- [ ] Добавил новую A запись с IP из Vercel
- [ ] Добавил CNAME запись для www
- [ ] Сохранил изменения
- [ ] Жду распространения DNS (обычно 5-60 минут)
- [ ] Проверил статус в Vercel Dashboard

---

## Следующие шаги

После того как DNS записи будут настроены и Vercel покажет статус "Valid":

1. **Проверьте Production Environment:**
   - В Vercel Dashboard → Domains
   - Убедитесь, что restodocks.com привязан к **Production**
   - Если нет - нажмите три точки → Edit → Environment: Production

2. **Проверьте деплой:**
   - Перейдите на https://restodocks.com
   - Приложение должно загрузиться
   - SSL должен работать (замок в браузере)

3. **Проверьте редирект www:**
   - Перейдите на https://www.restodocks.com
   - Должен редиректить на https://restodocks.com

---

## Типичные проблемы

### "Invalid Configuration" не исчезает
**Причина:** DNS не распространились  
**Решение:** Подождите 1-24 часа, проверьте правильность записей

### "Domain is already in use"
**Причина:** Домен уже используется в другом проекте  
**Решение:** Удалите домен из старого проекта

### SSL сертификат не выпускается
**Причина:** DNS записи неправильные или не распространились  
**Решение:** Проверьте A и CNAME записи с помощью dig

---

## Запишите сюда DNS записи из Vercel:

### A Record для restodocks.com:
```
IP адрес: _______________________
```

### CNAME для www.restodocks.com:
```
CNAME: _______________________
```

### (Если используете Nameservers):
```
ns1.vercel-dns.com
ns2.vercel-dns.com
```
