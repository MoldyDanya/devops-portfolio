# Android Deploy Workflow

- **Путь:** `.github/workflows/android-deploy.yml`
- **Назначение:** загрузка собранного AAB в Google Play Console (internal/beta) с подготовкой Fastlane окружения и управлением changelog.

## Триггеры
- `workflow_dispatch` — ручной запуск (например, вручную из UI).
- `workflow_call` — вызов из других workflow (например, из `unity-build-orchestrator`).

## Входные параметры
| Параметр | Тип | По умолчанию | Назначение |
|----------|-----|--------------|------------|
| `self_hosted` | boolean | `false` | Использовать self-hosted runner (`self-hosted`). |
| `deploy_track` | choice | `internal` | Целевой трек (`internal` / `beta`). |
| `release_status` | choice | `draft` | Статус публикации (`draft` / `completed`). |
| `use_default_changelog` | boolean | `false` | Использовать `metadata/default`. |
| `export_debug_symbols` | boolean | `true` | Загружать mapping/dSYMs. |
| `specific_run_id` | string | — | Run ID для поиска артефактов (опционально). |

## Jobs
| Job | Назначение |
|-----|------------|
| `deploy-to-play-store` | Единый job: checkout минимального набора файлов, установка зависимостей, загрузка артефакта (`download-build-artifact`), подготовка Google Play service account, запуск `maierj/fastlane-action@v3.0.0` с lane `android <track>`.

## Требуемые секреты и переменные
- `GOOGLE_PLAY_KEY_FILE`
- `ANDROID_PACKAGE_NAME`
- `UNITY_EMAIL/PASSWORD/SERIAL` не требуются (используются на шаге сборки).
- `RUNNER_USERNAME` (для self-hosted сценариев, используется в env).

Артефакт `build-Android` ожидается от `reusable-unity-build` / `unity-build-orchestrator`.

