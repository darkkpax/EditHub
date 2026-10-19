# edithub

настольное пространство для монтажа на **tauri 2 + rust + react/typescript**.

основное приложение — [`desktop/`](desktop/README.md). интерфейс ориентирован на kpax / kpaxvpn: крупные готические заголовки, читаемый текст, матовый блюр, чёрная и светлая темы. шрифты встроены и работают без интернета.

```powershell
cd desktop
npm ci
npm run tauri dev
```

```powershell
npm test
cargo test --manifest-path src-tauri/Cargo.toml --lib
npm run tauri build
```

windows-установщик появляется в `desktop/src-tauri/target/release/bundle/nsis/`. workflow `.github/workflows/release.yml` собирает tauri; flutter больше не используется.

поддерживаются создание и просмотр проектов, google drive/dropbox, отмена и докачка, запуск resolve, сгрузка/восстановление в папке iCloud, корзина и трей. существующие `~/.edithub/settings.json` и `google-drive.json` подхватываются автоматически.

подробности, ограничения и проверка настоящего окна — в [desktop/README.md](desktop/README.md).

`Sources/` — историческая macOS-версия; `windows/` — прежний electron-клиент. текущий desktop-клиент не зависит от них. исходники flutter удалены; оставшийся локальный кэш исключён из git.

превью проектов извлекаются из FOOTAGE через установленный ffmpeg и кэшируются локально; интерфейс не ждёт генерации кадров.
