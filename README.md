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

> **Status: stage 2 of the MVP.** The menu bar app, calendar access, CI/releases and the input window
> (paste, drag-and-drop, preview, instruction, global shortcut) work. Recognition, the review screen,
> LLM providers, settings and history are coming in the next stages.

### Requirements

macOS 27 on Apple silicon.

### Install

1. Download `calto-vX.Y.Z.zip` from [Releases](https://github.com/NickCool0/calto/releases), unzip it
   and move `calto.app` to `/Applications`.
2. The build is ad-hoc signed and not notarized (no paid Apple Developer account), so Gatekeeper blocks
   the first launch. Allow it **once**: open the app, then go to **System Settings → Privacy & Security**
   and click **Open Anyway**. Alternatively run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/calto.app
   ```
3. Right-click the calto icon in the menu bar → **Grant Calendar Access…**.

### Usage

- **⌃⌥⌘C** anywhere, or a left click on the menu bar icon, opens the input window. A right click
  (or ⌃-click) on the icon shows the menu.
- Paste a screenshot or text with **⌘V**, drop images onto the window, or just type. Up to 5 images;
  they are downscaled to 2048 px and stripped of metadata (EXIF, GPS) before anything is sent anywhere.
- Add an optional instruction ("only meetings with Anna", "remind me an hour before") and press
  **Recognize** (⌘↩). **Esc** closes the window.

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
branch, creates tag `v0.2.0` and publishes a GitHub Release with the zip. Pushing a `v*` tag does the same.

### LLM providers

Coming in a later stage: Anthropic (Claude), OpenAI, Google Gemini, any OpenAI-compatible endpoint
(Ollama, LM Studio, osaurus, OpenRouter) and Apple's on-device model. This section will explain how to
get an API key for each provider and how to connect a local model.

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

> **Статус: этап 2 MVP.** Работают приложение в строке меню, доступ к календарю, CI/релизы и окно ввода
> (вставка, drag-and-drop, превью, инструкция, глобальная горячая клавиша). Распознавание, экран
> проверки, LLM-провайдеры, настройки и история — на следующих этапах.

### Требования

macOS 27 на Apple silicon.

### Установка

1. Скачайте `calto-vX.Y.Z.zip` из [Releases](https://github.com/NickCool0/calto/releases), распакуйте
   и перенесите `calto.app` в `/Applications`.
2. Сборка подписана ad-hoc и не нотаризована (без платного аккаунта Apple Developer), поэтому Gatekeeper
   блокирует первый запуск. Разрешите его **один раз**: откройте приложение, затем
   **Системные настройки → Конфиденциальность и безопасность → «Всё равно открыть»**. Или выполните:
   ```sh
   xattr -dr com.apple.quarantine /Applications/calto.app
   ```
3. Нажмите правой кнопкой на иконку calto в строке меню → **Разрешить доступ к календарю…**.

### Использование

- **⌃⌥⌘C** в любом приложении или левый клик по иконке в строке меню открывает окно ввода. Правый клик
  (или ⌃-клик) по иконке показывает меню.
- Вставьте скриншот или текст через **⌘V**, перетащите изображения в окно или просто введите текст.
  До 5 изображений; перед отправкой куда-либо они уменьшаются до 2048 px и очищаются от метаданных
  (EXIF, GPS).
- Добавьте необязательную инструкцию («только встречи с Аней», «напомни за час») и нажмите
  **Распознать** (⌘↩). **Esc** закрывает окно.

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
выбранную ветку, создаст тег `v0.2.0` и опубликует GitHub Release с zip. Push тега `v*` делает то же самое.

### LLM-провайдеры

Появятся на следующих этапах: Anthropic (Claude), OpenAI, Google Gemini, любой OpenAI-совместимый
эндпоинт (Ollama, LM Studio, osaurus, OpenRouter) и локальная модель Apple на устройстве. Здесь будет
описано, как получить API-ключ у каждого провайдера и как подключить локальную модель.

### Приватность

- Никакой телеметрии, аналитики и собственного бэкенда.
- Ваши данные уходят только выбранному LLM-провайдеру — или никуда, если выбрана локальная модель.
- API-ключи хранятся только в Keychain macOS.
- Данные календаря не покидают ваш Mac; calto читает календари только для поиска конфликтов и дубликатов.

### Лицензия

[MIT](LICENSE).
