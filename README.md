# calto

[English](#english) · [Русский](#русский)

---

## English

**calto** is a native macOS menu bar app that turns screenshots and text (invitations, chats, posters,
schedules) into Apple Calendar events. You paste something, an LLM of your choice extracts the events,
you review and edit them, and calto adds them to any calendar connected to Apple Calendar — iCloud,
Google, Exchange and others.

Idea inspired by [Smart Calendars AI](https://www.smartcalendars.ai/); calto implements only the
"text/screenshot → calendar event" part, as open source (MIT).

> **Status: MVP in progress.** Working: the menu bar popup (paste, drag-and-drop, preview,
> instruction, global shortcut), calendar access, settings (provider, API key, model, your own prompt)
> and releases. Coming next: recognition, the review screen and history.

### Requirements

macOS 27 on Apple silicon.

### Install

1. Download `calto-vX.Y.Z.dmg` from [Releases](https://github.com/NickCool0/calto/releases), open it
   and drag **calto** into **Applications**.
2. The build is ad-hoc signed and not notarized (no paid Apple Developer account), so Gatekeeper blocks
   the first launch. Allow it **once**: open the app, then go to **System Settings → Privacy & Security**
   and click **Open Anyway**. Alternatively run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/calto.app
   ```
3. On first launch calto asks for access to your calendars — allow it.
4. Click the calto icon → ⚙︎ (or right-click → **Settings…**), choose a provider, paste an API key and
   press **Check Key and Load Models**.

### Usage

- **⌃⌥⌘C** anywhere, or a click on the menu bar icon, opens the popup under the icon. A right click
  (or ⌃-click) on the icon shows the menu. **Esc** or a click elsewhere closes the popup; its content stays.
- Paste a screenshot or text with **⌘V**, drop images onto the popup, or just type. Up to 5 images;
  they are downscaled to 2048 px and stripped of metadata (EXIF, GPS) before anything is sent anywhere.
- Add an optional instruction ("only meetings with Anna", "remind me an hour before") and press
  **Recognize** (⌘↩).
- **Settings → Prompt**: your own instructions added to every request (default calendar, language,
  time zone…).

Every CI build is a new ad-hoc signature, so after updating, macOS may ask for calendar access (and,
later, Keychain access) again. This is expected.

Builds from any commit are also available as artifacts of the
[CI workflow](https://github.com/NickCool0/calto/actions/workflows/ci.yml).

### Build from source

Requires Xcode 27.

```sh
swift test --package-path Packages/CaltoKit          # core logic tests
xcodebuild -project calto.xcodeproj -scheme calto \
  -configuration Release -derivedDataPath build clean build
open build/Build/Products/Release/calto.app
```

Project layout:

| Path | Contents |
|---|---|
| `calto/` | The app: menu bar item, windows, EventKit access (SwiftUI + AppKit) |
| `Packages/CaltoKit/` | Pure Swift core — models, calendar rules, date logic; tested with Swift Testing |
| `Config/` | `Info.plist` and sandbox entitlements |
| `scripts/verify-bundle.sh` | Checks the built app for sandbox, calendar entitlement, usage description, menu-bar-only mode |
| `.github/workflows/ci.yml` | Clean build + tests on every push/PR; publishes GitHub Releases |

No third-party dependencies — only Apple frameworks.

**Releasing:** Actions → CI → **Run workflow**, enter a version (e.g. `0.2.0`). The workflow builds that
branch, creates tag `v0.2.0` and publishes a GitHub Release with the DMG. Pushing a `v*` tag does the same.

### LLM providers

Choose one in **Settings → Model**. Keys are stored only in the macOS Keychain, one per provider, so you
can switch between them. **Check Key and Load Models** verifies the key and loads the provider's model
list. For screenshots, pick a model that understands images.

| Provider | Where to get a key |
|---|---|
| Anthropic (Claude) | [console.anthropic.com → API keys](https://console.anthropic.com/settings/keys) |
| OpenAI | [platform.openai.com → API keys](https://platform.openai.com/api-keys) |
| Google Gemini | [aistudio.google.com → Get API key](https://aistudio.google.com/apikey) |
| OpenRouter | [openrouter.ai → Keys](https://openrouter.ai/keys); server address `https://openrouter.ai/api/v1` |
| Apple Intelligence | no key — Apple's on-device model, when Apple Intelligence is on |

**Local model** (nothing leaves your Mac): choose **OpenAI-compatible** and set the server address.

- [Ollama](https://ollama.com): `ollama pull qwen2.5vl` (or another vision model), address
  `http://localhost:11434/v1`, no key.
- [LM Studio](https://lmstudio.ai): load a model, start the local server, address `http://localhost:1234/v1`.
- osaurus or any other OpenAI-compatible server: its `/v1` address.

### Privacy

- No telemetry, no analytics, no backend of our own.
- Your input is sent only to the LLM provider you choose — or nowhere, with an on-device model.
- API keys are stored only in the macOS Keychain.
- Calendar data never leaves your Mac; calto reads calendars only to detect conflicts and duplicates.

### License

[MIT](LICENSE).

---

## Русский

**calto** — нативное приложение для строки меню macOS, которое превращает скриншоты и текст
(приглашения, переписку, афиши, расписания) в события Apple Calendar. Вы вставляете содержимое,
выбранная вами LLM извлекает события, вы проверяете и правите их, и calto добавляет их в любой
календарь, подключённый к Apple Calendar, — iCloud, Google, Exchange и другие.

Идея вдохновлена [Smart Calendars AI](https://www.smartcalendars.ai/); calto реализует только часть
«текст/скриншот → событие календаря», с открытым исходным кодом (MIT).

> **Статус: MVP в работе.** Работают всплывающее окно в строке меню (вставка, drag-and-drop, превью,
> инструкция, глобальная горячая клавиша), доступ к календарю, настройки (провайдер, API-ключ, модель,
> свой промпт) и релизы. Дальше: распознавание, экран проверки и история.

### Требования

macOS 27 на Apple silicon.

### Установка

1. Скачайте `calto-vX.Y.Z.dmg` из [Releases](https://github.com/NickCool0/calto/releases), откройте его
   и перетащите **calto** в **Программы**.
2. Сборка подписана ad-hoc и не нотаризована (без платного аккаунта Apple Developer), поэтому Gatekeeper
   блокирует первый запуск. Разрешите его **один раз**: откройте приложение, затем
   **Системные настройки → Конфиденциальность и безопасность → «Всё равно открыть»**. Или выполните:
   ```sh
   xattr -dr com.apple.quarantine /Applications/calto.app
   ```
3. При первом запуске calto запросит доступ к календарям — разрешите.
4. Нажмите на иконку calto → ⚙︎ (или правый клик → **Настройки…**), выберите провайдера, вставьте
   API-ключ и нажмите **Проверить ключ и загрузить модели**.

### Использование

- **⌃⌥⌘C** в любом приложении или клик по иконке в строке меню открывает окно под иконкой. Правый клик
  (или ⌃-клик) по иконке показывает меню. **Esc** или клик мимо закрывает окно; содержимое сохраняется.
- Вставьте скриншот или текст через **⌘V**, перетащите изображения в окно или просто введите текст.
  До 5 изображений; перед отправкой куда-либо они уменьшаются до 2048 px и очищаются от метаданных
  (EXIF, GPS).
- Добавьте необязательную инструкцию («только встречи с Аней», «напомни за час») и нажмите
  **Распознать** (⌘↩).
- **Настройки → Промпт**: ваши инструкции, которые добавляются к каждому запросу (календарь по
  умолчанию, язык, часовой пояс…).

Каждая сборка CI получает новую ad-hoc подпись, поэтому после обновления macOS может снова запросить
доступ к календарю (а позже и к Keychain). Это ожидаемо.

Сборки любого коммита также доступны как артефакты
[CI-workflow](https://github.com/NickCool0/calto/actions/workflows/ci.yml).

### Сборка из исходников

Нужен Xcode 27.

```sh
swift test --package-path Packages/CaltoKit          # тесты основной логики
xcodebuild -project calto.xcodeproj -scheme calto \
  -configuration Release -derivedDataPath build clean build
open build/Build/Products/Release/calto.app
```

Структура проекта:

| Путь | Содержимое |
|---|---|
| `calto/` | Приложение: иконка в строке меню, окна, доступ к EventKit (SwiftUI + AppKit) |
| `Packages/CaltoKit/` | Чистое ядро на Swift — модели, правила календарей, работа с датами; тесты на Swift Testing |
| `Config/` | `Info.plist` и entitlements песочницы |
| `scripts/verify-bundle.sh` | Проверяет собранное приложение: песочница, entitlement календаря, текст запроса доступа, режим без Dock |
| `.github/workflows/ci.yml` | Чистая сборка и тесты на каждый push/PR; публикация GitHub Releases |

Сторонних зависимостей нет — только фреймворки Apple.

**Выпуск релиза:** Actions → CI → **Run workflow**, укажите версию (например, `0.2.0`). Workflow соберёт
выбранную ветку, создаст тег `v0.2.0` и опубликует GitHub Release с DMG. Push тега `v*` делает то же самое.

### LLM-провайдеры

Выбираются в **Настройки → Модель**. Ключи хранятся только в Связке ключей macOS, отдельно для каждого
провайдера, поэтому между ними можно переключаться. **Проверить ключ и загрузить модели** проверяет
ключ и загружает список моделей провайдера. Для скриншотов выбирайте модель, которая понимает
изображения.

| Провайдер | Где взять ключ |
|---|---|
| Anthropic (Claude) | [console.anthropic.com → API keys](https://console.anthropic.com/settings/keys) |
| OpenAI | [platform.openai.com → API keys](https://platform.openai.com/api-keys) |
| Google Gemini | [aistudio.google.com → Get API key](https://aistudio.google.com/apikey) |
| OpenRouter | [openrouter.ai → Keys](https://openrouter.ai/keys); адрес сервера `https://openrouter.ai/api/v1` |
| Apple Intelligence | ключ не нужен — модель Apple на устройстве, если Apple Intelligence включена |

**Локальная модель** (данные не покидают Mac): выберите **OpenAI-совместимый** и укажите адрес сервера.

- [Ollama](https://ollama.com): `ollama pull qwen2.5vl` (или другая модель с поддержкой изображений),
  адрес `http://localhost:11434/v1`, ключ не нужен.
- [LM Studio](https://lmstudio.ai): загрузите модель, запустите локальный сервер, адрес
  `http://localhost:1234/v1`.
- osaurus или любой другой OpenAI-совместимый сервер: его адрес `/v1`.

### Приватность

- Никакой телеметрии, аналитики и собственного бэкенда.
- Ваши данные уходят только выбранному LLM-провайдеру — или никуда, если выбрана локальная модель.
- API-ключи хранятся только в Keychain macOS.
- Данные календаря не покидают ваш Mac; calto читает календари только для поиска конфликтов и дубликатов.

### Лицензия

[MIT](LICENSE).
