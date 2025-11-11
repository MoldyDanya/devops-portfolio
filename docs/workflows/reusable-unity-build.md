# Reusable Unity Build Workflow

- **Путь:** `.github/workflows/reusable-unity-build.yml`
- **Назначение:** унифицированная сборка Unity-проекта под указанную платформу (Android/iOS) на self-hosted runner с управлением версиями, кэшем и пост-обработкой.

## Триггер
- `workflow_call` — подключается из других workflow (в т.ч. `unity-build-orchestrator`).

## Входные параметры
| Параметр | Тип | По умолчанию | Назначение |
|----------|-----|--------------|------------|
| `platform` | string | — | `Android` или `iOS` (обязателен). |
| `branch_name` | string | — | Ветка Unity-проекта (обязателен). |
| `commit_hash` | string | — | Конкретный коммит (опционально). |
| `build_type` | string | `AAB` | Тип Android-сборки (`AAB`/`APK`). |
| `upload_build` | boolean | `true` | Загружать артефакт `build-<platform>`. |
| `export_debug_symbols` | boolean | `true` | Генерация dSYM/mapping. |
| `deploy_to_store` | boolean | `false` | Включает магазинные сценарии (Fastlane). |
| `deploy_track` | string | `internal` | Трек Google Play (`internal`/`beta`). |
| `development_build` | boolean | `false` | Development-параметры Unity. |
| `clean_build` | boolean | `false` | Пропуск восстановления кэша Unity. |

## Outputs
| Output | Описание |
|--------|----------|
| `build_version` | Версия сборки (Unity builder). |
| `version_code` | Android versionCode (для Android). |
| `exit_code` | Код завершения Unity builder. |
| `commit` / `branch` | Фактический commit/branch. |

## Основные шаги
1. Очистка workspace (`FraBle/clean-after-action`).
2. Sparse checkout служебных директорий и checkout проекта (`checkout-project`).
3. Проверка секретов (`platform-secrets-check`).
4. Управление кэшем Unity (`unity-cache`).
5. Настройка проекта и define symbols (`platform-project-settings`, `platform-define-symbols`).
6. Платформенная аутентификация (`platform-auth-setup`).
7. Расчёт версии (`get-version`, `platform-version-calculation`).
8. Подготовка параметров Unity Builder (`platform-unity-build-params`).
9. Копирование кастомного build-скрипта и запуск `game-ci/unity-builder@v4`.
10. Исправление прав доступа (`fix-permissions`).
11. Пост-обработка (`platform-post-build`).
12. Итоговый отчёт и выгрузка артефактов.

## Требуемые секреты
Использует `secrets: inherit`; необходимы:
- **Общие:** `UNITY_EMAIL`, `UNITY_PASSWORD`, `UNITY_SERIAL`.
- **Android:** `GOOGLE_PLAY_KEY_FILE`, `ANDROID_PACKAGE_NAME`, `ANDROID_KEYSTORE_*` (при деплое/подписи).
- **iOS:** `IOS_BUNDLE_ID`, `APPLE_*`, `MATCH_*`, `APPSTORE_*`, `IOS_EXTERNAL_GROUP_NAME` (через vars).

## Требуемые переменные
- `RUNNER_USERNAME`
- `UNITY_CACHE_MAX_COUNT`
- `UNITY_CACHE_MAX_AGE_DAYS`

