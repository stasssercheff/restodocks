# Как задеплоить Edge Functions (пошагово)

Сделай всё по шагам в **Терминале** (в Cursor: меню Terminal → New Terminal, или на Mac — программа «Терминал»). Команды просто **копируй и вставляй** в терминал, затем нажимай Enter.

---

## Шаг 1. Войти в Supabase (один раз)

В терминале выполни:

```
npx supabase login
```

- Откроется **браузер** и страница Supabase.
- Если попросят — **войди** в свой аккаунт Supabase (логин/пароль или через Google/GitHub).
- В браузере может быть кнопка «Authorize» или «Разрешить» — нажми её.
- После этого в терминале должно появиться что-то вроде «Finished supabase login». Больше этот шаг делать не нужно.

Если браузер не открылся — скопируй ссылку из терминала и открой её вручную в браузере.

---

## Шаг 2. Привязать проект (один раз)

1. Открой в браузере: **https://supabase.com/dashboard**
2. Выбери **свой проект** (тот, куда ты добавлял ключи GigaChat и OpenAI).
3. Зайди в **Project Settings** (иконка шестерёнки слева внизу).
4. В блоке **General** найди **Reference ID** — это короткий код вроде `abcdefghijklmnop`. **Скопируй его.**

5. В терминале выполни (подставь вместо `ТВОЙ_REF` свой Reference ID):

```
cd /Users/masurfsker/Documents/Restodocks/Restodocks/restodocks_flutter
npx supabase link --project-ref ТВОЙ_REF
```

Пример: если Reference ID = `xyzabc123`, команда будет:
```
npx supabase link --project-ref xyzabc123
```

Если спросят пароль базы данных — можно нажать Enter (оставить пустым) или ввести пароль из Supabase Dashboard → Project Settings → Database, если знаешь.

После успешной привязки в терминале будет что-то вроде «Linked project ...». Шаг 2 больше повторять не нужно.

---

## Шаг 3. Деплой функций

В терминале выполни по очереди (каждую строку — Enter):

```
cd /Users/masurfsker/Documents/Restodocks/Restodocks/restodocks_flutter
npx supabase functions deploy ai-generate-checklist
npx supabase functions deploy ai-recognize-tech-card
npx supabase functions deploy ai-recognize-tech-cards-batch
npx supabase functions deploy ai-recognize-product
npx supabase functions deploy ai-refine-nutrition
npx supabase functions deploy ai-verify-product
```

Можно скопировать все строки и вставить — они выполнятся по очереди. Для каждой функции в конце должно быть что-то вроде «Deployed function ai-...».

**Важно:** Секреты (GIGACHAT_AUTH_KEY, OPENAI_API_KEY и т.д.) ты уже добавил в Supabase Dashboard. При деплое они автоматически подхватываются — отдельно их вводить в терминал не нужно.

---

## Шаг 4. (По желанию) Деплой функции для чека по фото

Если нужна ещё и распознавание чека по фото:

```
npx supabase functions deploy ai-recognize-receipt
```

---

## Если что-то пошло не так

- **«command not found: npx»** — значит, на Mac не установлен Node.js. Напиши об этом — подскажу, как установить.
- **«Access token not provided»** — не выполнен Шаг 1 (нужно `npx supabase login`).
- **«Project not found» или ошибка при link** — проверь, что Reference ID скопирован правильно и проект именно твой.
- Другие сообщения об ошибках можно скопировать и прислать — разберём.

После успешного деплоя все текстовые фичи с ИИ (чеклист, ТТК из Excel, продукты, КБЖУ, верификация) будут использовать твой ключ GigaChat в Supabase.
