# EditHub

Единый комбайн для монтажёра — объединяет создатель структуры проектов, скачивалку
с Google Drive / Dropbox, проводник проектов (как Finder) и консервацию проектов
в iCloud. Собран из двух приложений: **ProjectCreator** и **GoogleDropboxDownloader**.

## Возможности

- **Проводник проектов** — список всех проектов (`<КОРЕНЬ>/<ГОД>/<МЕСЯЦ>/<ИМЯ>`),
  дерево папок, открытие в Finder.
- **Создатель проектов** — вводишь название → создаётся структура папок
  (`FOOTAGE, READY VIDEO, MUSIC, VOICE, B-ROLL, SUBS, MISC`) + шаблоны Premiere/DaVinci.
- **Скачивалка** — Google Drive / Dropbox прямо в нужную папку проекта.
- **Drag-and-drop сортировка** — кидаешь скачанные файлы на проект, они сами
  раскладываются по папкам по расширению + словам в имени (`voice`, `music`,
  `broll`, `sfx`…). Внизу показывается сводка раскладки.
- **Консервация** — `FOOTAGE` (легко перекачать) удаляется, ценное
  (`MUSIC/VOICE/B-ROLL/SUBS/MISC` + файлы проекта) пакуется в zip и уходит в
  **iCloud Drive**. В корне остаётся файл-манифест `<ИМЯ>.edithub`.
- **Восстановление** — двойной клик по `.edithub` (или кнопка в приложении) →
  архив тянется из iCloud и распаковывается обратно. Остаётся дозалить футажи.

## Структура кода

```
Sources/EditHub/
  EditHubApp.swift          — точка входа, окно NavigationSplitView
  AppDelegate.swift         — обработка открытия .edithub из Finder
  Models/
    Project.swift           — модель проекта на диске
    ProjectStore.swift      — сканирование корня + наблюдение за изменениями
  Scaffolder/
    ProjectFolders.swift    — единый источник истины о папках (heavy / valuable)
    ProjectScaffolder.swift — создание структуры (из ProjectCreator)
  Core/
    FileClassifier.swift    — классификатор файлов → папка
    FileSorter.swift        — перемещение файлов + сводка
    ProjectArchiver.swift   — консервация / восстановление
    ProjectManifest.swift   — формат .edithub
    iCloudStore.swift       — доступ к iCloud Drive
    ZipArchiver.swift       — zip/unzip (из GoogleDropboxDownloader)
    RestoreCoordinator.swift
    FolderBookmarkStore.swift
  Downloader/               — движок скачивания (из GoogleDropboxDownloader)
  DesignSystem/             — GlassUI, VisualEffectView (из ProjectCreator)
  Views/                    — экраны (список, дерево, деталь, создание, скачивание)
```

## Сборка

**Через Xcode (рекомендуется):**

```sh
xcodegen generate        # пересобрать EditHub.xcodeproj из project.yml
open EditHub.xcodeproj    # ⌘R для запуска
```

`project.yml` — источник истины для Xcode-проекта (Info.plist и entitlements
генерируются из него; правь их там, не в `App/`).

**Через SwiftPM:**

```sh
swift build              # отладочная сборка
swift run EditHub        # запуск
./scripts/build-macos-app.sh   # .app-бандл в dist/
```

Иконку положить в `Packaging/macOS/AppIcon.icns`.

## iCloud

Для консервации нужен iCloud Drive. При распространении подпиши приложение с
entitlements из `Packaging/macOS/EditHub.entitlements` и своим iCloud-контейнером
(замени `iCloud.com.local.EditHub` и Team ID).

## Консервация: что удаляется

Тяжёлые папки (`FOOTAGE`, `READY VIDEO`) при консервации удаляются локально —
их легко перекачать. Перед архивацией открывается диалог, где для конкретного
проекта можно выбрать, что именно удалять (показывается размер каждой папки),
а что оставить. Ценные папки (`MUSIC, VOICE, B-ROLL, SFX, SUBS, MISC`) всегда
уходят в архив.

Что считается тяжёлым/ценным — задаётся в одном месте: `isHeavy` в
[ProjectFolders.swift](Sources/EditHub/Scaffolder/ProjectFolders.swift).
