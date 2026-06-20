# EditHub Accounts and Sync Plan

## Goal

EditHub should work on multiple computers with one shared project hub:

- macOS computers use the current native app.
- A future Windows computer can log into the same account.
- Each computer has its own local project root, usually a `VIDEOS` folder.
- Project metadata syncs through the EditHub server.
- Lightweight project archives stay in iCloud Drive.
- Heavy footage is not uploaded to iCloud; EditHub stores download links and re-downloads footage when needed.

## Core Model

Use three separate layers:

1. Local project root
   - Example on macOS: `/Users/name/VIDEOS`
   - Example on Windows: `D:\VIDEOS`
   - Contains active working projects.
   - Treated as a local cache/workspace, not the global source of truth.

2. iCloud Drive archive root
   - Example on macOS: `iCloud Drive/EditHub`
   - Example on Windows with iCloud for Windows: `C:\Users\name\iCloudDrive\EditHub`
   - Contains lightweight archives only.
   - Should be user-selected on every computer.

3. EditHub server
   - Stores account, workspace, and project catalog data.
   - Does not store footage.
   - Does not need to store project zip files if iCloud remains the archive storage.

## Important iCloud Decision

For Windows support, do not rely on the macOS app-specific iCloud container as the main storage.

The current macOS code uses:

```swift
FileManager.default.url(forUbiquityContainerIdentifier: nil)
```

That is macOS-specific and does not translate cleanly to Windows.

Instead, use a normal user-visible iCloud Drive folder:

```text
iCloud Drive/EditHub/
  Archive/
    2026/
      JUNE/
        PROJECT.zip
```

On Windows, iCloud for Windows syncs that same folder as ordinary files. The app stores only relative archive paths, for example:

```text
Archive/2026/JUNE/PROJECT.zip
```

Then each computer resolves:

```text
selectedICloudRoot + archiveRelativePath
```

## Project Record on the Server

Minimum server project shape:

```json
{
  "id": "uuid",
  "workspaceId": "uuid",
  "name": "PROJECT NAME",
  "year": "2026",
  "month": "JUNE",
  "template": "premiere",
  "footageLinks": ["https://example.com/footage-folder"],
  "archiveRelativePath": "Archive/2026/JUNE/PROJECT NAME.zip",
  "archiveByteCount": 123456789,
  "archiveChecksum": "sha256-optional",
  "archivedAt": "2026-06-17T00:00:00Z",
  "createdAt": "2026-06-17T00:00:00Z",
  "updatedAt": "2026-06-17T00:00:00Z",
  "createdByUserId": "uuid",
  "updatedByUserId": "uuid"
}
```

## Local Metadata

Every project needs a stable ID that does not depend on the local path.

Current local sidecar:

```text
.edithub-metadata.json
```

Should eventually contain:

```json
{
  "version": 2,
  "projectId": "uuid",
  "footageLinks": ["https://example.com/footage-folder"],
  "updatedAt": "2026-06-17T00:00:00Z"
}
```

Archived project manifest:

```text
PROJECT.edithub
```

Should contain the same `projectId`, `archiveRelativePath`, and footage links so an archived local project can reconnect to the server record.

## Project States in the UI

The project list should merge local scan results with server records.

Suggested states:

- `local`
  - Full project folder exists on this computer.

- `archivedLocal`
  - Local project folder exists with `.edithub`.
  - Lightweight archive can be restored from iCloud.

- `remoteOnly`
  - Project exists on the server but not in this computer's local `VIDEOS`.

- `restoreAvailable`
  - Project exists on the server and has an `archiveRelativePath`.
  - The app can restore from iCloud if the archive exists locally or can be synced by iCloud.

- `missingArchive`
  - Server says an archive should exist, but it is not found under the selected iCloud root.

- `downloading`
  - Footage or archive restore is currently running.

## Sync Flow

### First login on a Mac

1. User logs into EditHub.
2. User selects local project root, for example `VIDEOS`.
3. User selects iCloud archive root, for example `iCloud Drive/EditHub`.
4. App scans local projects.
5. App scans local archived manifests.
6. App sends local project metadata to the server.
7. App downloads server project records.
8. UI shows a merged project hub.

### Creating a project

1. Create local folder structure under `VIDEOS/YEAR/MONTH/PROJECT`.
2. Create or reuse `projectId`.
3. Save `.edithub-metadata.json`.
4. If a footage link was entered, save it in metadata and server record.
5. Create/update project record on the server.
6. If a link exists, queue footage download into `FOOTAGE`.

### Archiving a project

1. Package valuable folders and project files into a zip.
2. Do not include `FOOTAGE` or `READY VIDEO`.
3. Write zip to:

   ```text
   selectedICloudRoot/Archive/YEAR/MONTH/PROJECT.zip
   ```

4. Leave `PROJECT.edithub` in the local project folder.
5. Store `archiveRelativePath` and footage links in the manifest.
6. Update the server record with archive metadata.
7. Remove selected heavy local folders.

### Restoring on another computer

1. User logs in.
2. User selects local `VIDEOS`.
3. User selects iCloud archive root.
4. App receives project records from the server.
5. For a remote project, user clicks restore/download.
6. App creates the local project folder.
7. App resolves the archive path from selected iCloud root + relative path.
8. App unzips valuable files into the project folder.
9. App queues footage download using `footageLinks`.

## Existing iCloud Archives

Need an import command:

```text
Import Existing iCloud Archives
```

It should scan:

```text
iCloud Drive/EditHub/Archive/
```

Optionally, on macOS it can also scan the old app-container archive location.

For each zip:

1. Infer `year`, `month`, and `projectName` from the path.
2. If a manifest exists nearby or inside a restored project, read richer metadata.
3. Create or update the server project record.
4. Mark the project as `restoreAvailable`.

This lets already archived iCloud projects appear after login.

## Windows Notes

Windows cannot use macOS iCloud ubiquity APIs.

The Windows app should treat iCloud as a normal folder selected by the user:

```text
C:\Users\name\iCloudDrive\EditHub
```

Limitations:

- No reliable Apple API to force-download a file.
- The app can only check if the zip exists as a local file.
- If a zip is not downloaded yet, show a clear instruction to keep it locally in iCloud for Windows.
- The app can open the archive folder in Explorer to help the user trigger iCloud download.

This is acceptable for a personal/internal tool and keeps iCloud as the archive storage.

## Server API Draft

Minimum API:

```text
POST /auth/login
POST /auth/logout
GET  /me

GET    /projects
POST   /projects
PATCH  /projects/:id
DELETE /projects/:id

POST /sync/local-scan
POST /sync/import-icloud-archives
```

`POST /sync/local-scan` can accept all local projects from one computer and let the server upsert records.

## Database Draft

Tables:

```text
users
  id
  email
  password_hash
  created_at

workspaces
  id
  name
  created_at

workspace_members
  workspace_id
  user_id
  role

projects
  id
  workspace_id
  name
  year
  month
  template
  footage_links_json
  archive_relative_path
  archive_byte_count
  archive_checksum
  archived_at
  created_by_user_id
  updated_by_user_id
  created_at
  updated_at
```

For two users, a single workspace is enough.

## Implementation Order

1. Add `projectId` to `.edithub-metadata.json` and `.edithub`.
2. Replace macOS app-container iCloud archive root with user-selected `iCloud Drive/EditHub` archive root.
3. Add account login and token storage.
4. Add server project catalog.
5. Make `ProjectStore` merge local projects with server projects.
6. Add restore for `remoteOnly` projects.
7. Add import for existing iCloud archives.
8. Add Windows folder-based restore flow later.

## Recommendation

Keep iCloud, but use it as a normal cross-platform iCloud Drive folder:

```text
iCloud Drive/EditHub
```

Do not use the macOS app-specific iCloud container as the long-term shared archive root if Windows support matters.

---

# Итоговый пайплайн (сквозной)

Этот раздел — главное и авторитетное описание того, как вся система должна
работать в готовом виде. Всё, что выше, — обоснование и предыстория; здесь —
цель. Текущий код (`Project`, `ProjectStore`, `iCloudStore`, `ProjectArchiver`,
`ProjectMetadata`, `ProjectManifest`) реализует только ранние части. Пробелы
помечены прямо по тексту как **TODO**.

## Правила идентичности (фундамент)

Два идентификатора, которые нельзя смешивать:

- `projectId` (UUID) — стабильная идентичность. Живёт в
  `.edithub-metadata.json` и в манифесте `.edithub`. Не меняется при
  переименовании, перемещении, консервации или восстановлении на другой машине.
- `url` / локальный путь — это просто *местоположение* на одном компьютере.
  Одноразовое. На каждой машине разное.

**TODO (текущий код):** `Project.id` сейчас — это `URL` папки. Должно стать
`projectId: UUID`, читаемым из метаданных, а `url` остаётся отдельным полем
местоположения. Это самая важная правка — без неё не строится ничего ниже.

Разрешение конфликтов для двух пользователей: **побеждает последняя запись по
`updatedAt`** — на уровне поля, где это дёшево (footage links), иначе на уровне
записи. Двое, правящих один проект в одну и ту же секунду, — не наш сценарий,
поэтому держим просто и задокументированно, без CRDT.

Дедупликация: upsert на сервере ключуется по `projectId`. Если проект приходит
без него (например, старый архив, импортированный из iCloud без манифеста),
сервер сопоставляет по `archiveRelativePath`, затем по `(year, month, name)`, и
только потом создаёт новую запись. Это не даёт одному проекту задвоиться.

## Слои хранения (конкретно)

| Слой | Что хранит | Источник истины для |
|---|---|---|
| Локальный корень `VIDEOS` | Активные рабочие папки + footage | Ничего — это кэш |
| `iCloud Drive/EditHub` | Лёгкие архивы (`Archive/ГОД/МЕСЯЦ/ИМЯ.zip`) | Байтов архива |
| Сервер EditHub | Аккаунт + каталог проектов (только метаданные) | Какие проекты существуют |

Сервер никогда не хранит footage и не хранит zip-архивы. iCloud никогда не
хранит footage. Footage всегда можно перекачать по `footageLinks`.

## Пайплайн аккаунта

### A. Первый запуск на любом компьютере

1. Приложение стартует. В keychain нет токена → показываем логин.
2. Пользователь логинится (один общий workspace на двоих).
3. Приложение кладёт токен в keychain. **TODO:** слоя аутентификации пока нет.
4. Пользователь выбирает **локальный корень проектов** (`VIDEOS`). Уже сделано
   через `FolderBookmarkStore` (security-scoped bookmark).
5. Пользователь выбирает **корень архива в iCloud** (`iCloud Drive/EditHub`).
   **TODO:** сейчас корень архива — это macOS app-container
   (`forUbiquityContainerIdentifier:`), а не выбранная пользователем папка Drive.
   Должен стать вторым bookmark'ом, рядом с тем, что для VIDEOS.
6. Приложение сканирует локальные проекты (`ProjectStore.scan` — есть) и
   локальные манифесты `.edithub`.
7. Приложение делает `POST /sync/local-scan` → сервер upsert'ит каждый локальный
   проект по `projectId`.
8. Приложение делает `GET /projects` → скачивает весь каталог.
9. Приложение мёрджит локальный скан + серверные записи в один список.
   **TODO:** `ProjectStore` сегодня знает только про локальный скан; нужно
   подмешивать удалённые записи.

### B. Обычный запуск (уже залогинен)

1. Стартуем, токен есть, оба корня резолвятся из bookmark'ов.
2. Скан локального + загрузка каталога + мёрдж → показываем хаб.
3. `DirectoryWatcher` (есть) держит локальную сторону живой; ручной или
   периодический pull держит свежей удалённую.

## Жизненный цикл проекта

### Создание

1. Создаём `VIDEOS/ГОД/МЕСЯЦ/ИМЯ/` со стандартной структурой папок.
2. Генерируем новый `projectId` и пишем `.edithub-metadata.json` (версия 2).
3. Если введена ссылка на footage — сохраняем её в метаданные.
4. `POST /projects` с метаданными + `projectId`.
5. Если ссылка есть — ставим в очередь скачивание footage в `FOOTAGE`.

### Консервация (архивация)

(Логика уже реализована в `ProjectArchiver.archive`; TODO только корень iCloud
и добавление checksum/`projectId`.)

1. Стейджим ценные папки + `.edithub-metadata.json` + файлы проекта в корне
   (`.prproj/.aep/.drp/...`). Никогда `FOOTAGE` и `READY VIDEO`.
2. Zip → `selectedICloudRoot/Archive/ГОД/МЕСЯЦ/ИМЯ.zip`.
3. Считаем `archiveChecksum` (sha256) от zip. **TODO:** сейчас не считается;
   нужно, чтобы ловить недокачанные файлы на Windows.
4. Очищаем выбранные тяжёлые/ценные папки локально, оставляя структуру.
5. Пишем манифест `.edithub` с `projectId`, `archiveRelativePath`,
   `archiveByteCount`, `archiveChecksum`, `footageLinks`.
6. `PATCH /projects/:id` с метаданными архива.

### Восстановление — два разных пути

**Путь 1: папка проекта ещё есть локально** (есть `.edithub`).
Уже реализован как `ProjectArchiver.restore(manifestURL:)`.

1. Резолвим `selectedICloudRoot + archiveRelativePath`.
2. Дожидаемся скачивания zip (см. платформенную заметку ниже).
3. Проверяем `archiveChecksum`. **TODO.**
4. Распаковываем поверх папки проекта, восстанавливаем footage links, удаляем
   манифест.

**Путь 2: проект `remoteOnly`** (его вообще нет на этом компьютере).
**TODO — пока не существует.**

1. По серверной записи воссоздаём `VIDEOS/ГОД/МЕСЯЦ/ИМЯ/`.
2. Пишем `.edithub-metadata.json` с серверным `projectId`.
3. Резолвим + скачиваем + проверяем zip, распаковываем в новую папку.
4. Ставим в очередь скачивание footage по `footageLinks`.

## Триггер скачивания из iCloud (требование «пользователь ничего не делает»)

Zip архива может физически ещё не лежать на диске — iCloud синхронит лениво.
Получение байтов зависит от платформы, но в обоих случаях **триггерит само
приложение; пользователь руками ничего не делает.**

### macOS

Уже корректно в `iCloudStore.ensureDownloaded`: проверяем
`ubiquitousItemDownloadingStatus`, вызываем `startDownloadingUbiquitousItem`,
опрашиваем до `.current`/`.downloaded`, с таймаутом.

### Windows

**Нет API**, чтобы форсировать скачивание. Но в iCloud for Windows
placeholder-файл материализуется просто **чтением**. Поэтому Windows-аналог
`ensureDownloaded`:

1. Резолвим путь (`selectedICloudRoot + archiveRelativePath`).
2. Открываем zip и читаем его **целиком в поток**, показывая
   «Downloading from iCloud…». Само чтение заставляет iCloud подтянуть байты.
3. Когда чтение завершилось — файл локальный → проверяем checksum → распаковываем.

Fallback (только сразу после свежей установки iCloud for Windows, до её первого
прохода индексации): если нет даже placeholder'а — показать одну строку
«Waiting for iCloud to sync…» + кнопку «Открыть папку архива в Explorer». Это
можно убрать совсем, если пользователь один раз сделает правый клик по папке
EditHub → «Always keep on this device».

**Следствие для архитектуры:** `ProjectArchiver` остаётся кроссплатформенным и
не меняется. Своя реализация на платформу есть только у хелпера «дождаться, пока
файл станет читаемым». На Windows iCloud-файл трактуется как обычный файл — там
**нельзя** вызывать macOS-овые ubiquity-API.

## Состояния UI — вычисляемые, не хранимые

Не сохранять их. Вычислять на лету из трёх булевых флагов:
`localFolderExists`, `archiveZipExists(подВыбраннымКорнем)`, `serverRecordExists`.

| Состояние | локально | архив | сервер |
|---|---|---|---|
| `local` | ✓ | – | любое |
| `archivedLocal` | ✓ (есть `.edithub`) | ✓ | любое |
| `remoteOnly` | ✗ | – | ✓ |
| `restoreAvailable` | ✗ | ✓ | ✓ |
| `missingArchive` | – | ✗ (но сервер говорит, что должен быть) | ✓ |
| `downloading` | временное, пока идёт восстановление/скачивание footage |

## Старые архивы в iCloud (реальное состояние) — «понимать как есть»

На момент написания в iCloud уже лежат архивы по схеме, которая отличается от
плановой. Подтверждено сканированием диска:

```text
iCloud Drive/Videos/2025/October/WPP Penthouse.zip
iCloud Drive/Videos/2025/December/F1 X T-Mobile.zip
iCloud Drive/Videos/2025/July/кино.zip
iCloud Drive/Videos/2026/January/...
```

Отличия от плановой схемы (`Archive/ГОД/МЕСЯЦ/ИМЯ.zip`):

| Что | В iCloud сейчас | Ожидает план/код |
|---|---|---|
| Папка-корень | `Videos` | `EditHub` |
| Расположение zip | `ГОД/Месяц/ИМЯ.zip` (рядом с проектами) | `Archive/ГОД/МЕСЯЦ/ИМЯ.zip` |
| Регистр месяца | `October` (англ., с заглавной) | `OCTOBER` (`.uppercased()`) |
| Манифест `.edithub` | отсутствует | есть, с `projectId` |

**Решение: ничего физически не двигаем.** Приложение учится читать обе
раскладки. Это нулевой риск для уже существующих файлов.

### Нормализация месяца (общий механизм)

Сейчас `ProjectScaffolder.yearMonth` строит месяц как английское слово в верхнем
регистре через POSIX-локаль. Из-за этого `October` (на диске) ≠ `OCTOBER`
(в коде), и один и тот же месяц двоится.

Ввести **канонический ключ месяца = номер `1...12`** и сравнивать/группировать
проекты по номеру, а не по строке. Отображать можно как угодно. Парсер месяца
принимает любой из вариантов и возвращает номер:

- английское слово в любом регистре (`October`, `OCTOBER`, `october`);
- русское слово в любом регистре (`Октябрь`, `ОКТЯБРЬ`) — на случай совсем
  старых папок;
- число (`10`, `06`, `6`).

Это разом чинит регистр, возможный русский и любые будущие расхождения.
**TODO:** добавить `MonthKey`/парсер; `ProjectStore.grouped` и дедуп должны
ключеваться по номеру месяца, а не по `month`-строке.

### Импорт понимает обе раскладки

Команда импорта (ниже) сканирует выбранный корень iCloud и принимает оба
варианта пути:

- `Archive/ГОД/МЕСЯЦ/ИМЯ.zip` — плановая схема;
- `ГОД/Месяц/ИМЯ.zip` — текущая схема `Videos/...`.

Так как у старых zip нет манифеста, импорт **генерирует `projectId`** для
каждого и заводит запись со статусом `restoreAvailable`.

## Импорт существующих архивов из iCloud

Разовая команда. Сканирует выбранный корень iCloud (и `Archive/...`, и старую
плоскую схему `ГОД/Месяц/ИМЯ.zip`; опционально ещё и app-container ради
совместимости). Для каждого zip: выводит `год` / нормализованный `месяц` (по
номеру) / `имя` из пути, читает более богатые метаданные, если рядом доступен
манифест, иначе генерирует `projectId`, upsert'ит серверную запись (по правилам
дедупликации, ключ `(year, monthNumber, name)`), помечает `restoreAvailable`.

## Порядок реализации (заменяет ранний список)

1. **Идентичность:** добавить `projectId` в `ProjectMetadata` (v2) и
   `ProjectManifest`; сменить `Project.id` с `URL` на UUID; лениво генерировать
   для существующих проектов. *Чисто локально, без сервера. Заодно чинит баг,
   когда переименование папки ломает идентичность.*
1a. **Нормализация месяца:** ввести парсер месяца → номер `1...12` (англ./рус./
   число, любой регистр); группировать и дедуплицировать по номеру, а не по
   строке. *Нужно рано — иначе старый `October` двоится с новым `OCTOBER`.*
2. **Корень iCloud:** ✅ СДЕЛАНО. `iCloudStore` переведён с app-container на
   выбранный пользователем bookmark (второй `FolderBookmarkStore` с ключами
   `selectedICloudArchive*`). Стал `@MainActor @Observable` синглтоном
   (`iCloudStore.shared`). `ProjectArchiver.archive/restore` теперь принимают
   резолвнутые URL/корень параметром, чтобы тяжёлая работа шла в фоне без
   обращения к MainActor-стору. В UI — иконка `icloud`/`icloud.fill` рядом с
   выбором корня проектов (`RootSplitView.chooseICloud`).
3. **Аутентификация + хранение токена** (рассмотреть Sign in with Apple /
   magic-link / общий токен вместо самописного `password_hash`).
4. **Серверный каталог** + `GET/POST/PATCH /projects`, `POST /sync/local-scan`.
5. **Мёрдж** локального скана с серверными записями в `ProjectStore`; выводить
   состояния UI.
6. **Восстановление Путь 2** для `remoteOnly` проектов.
7. **Импорт** существующих архивов из iCloud.
8. **Windows**: восстановление по папке + хелпер скачивания через чтение-триггер.
9. **Checksum** при записи архива + проверка при восстановлении (можно вшить в 1–2).
