# iOS Xcode Build & Deploy Workflow

- **Путь:** `.github/workflows/ios-xcode-build.yml`
- **Назначение:** обработка экспорта Unity-проекта в Xcode, подготовка CocoaPods, запуск Fastlane для сборки IPA и (при необходимости) публикации в TestFlight/App Store.

## Триггеры
- `workflow_dispatch` — ручной запуск с выбором артефактов/деплоя.
- `workflow_call` — используется из `unity-build-orchestrator` и других пайплайнов.

## Входные параметры
| Параметр | Тип | По умолчанию | Назначение |
|----------|-----|--------------|------------|
| `upload_ipa` | boolean | `false` | Загружать IPA в артефакты. |
| `deploy_to_store` | boolean | `false` | Запуск Fastlane `ios beta` (TestFlight). |
| `export_debug_symbols` | boolean | `true` | Сохранение dSYM. |
| `use_default_changelog` | boolean | `false` | Использовать дефолтный changelog. |
| `external_testers` | boolean | `false` | Отправка внешним тестерам (группа берётся из vars). |
| `specific_run_id` | string | — | Явный Run ID для загрузки артефактов. |

## Jobs
| Job | Назначение |
|-----|------------|
| `build-xcode` | Единственный job на `macos-14`: sparse checkout сервисных файлов, загрузка артефакта `build-iOS`, установка Xcode 16.1, настройка Ruby/CocoaPods, патч AppsFlyer, запуск Fastlane (`ios build` либо `ios beta`), выгрузка артефактов (IPA/dSYM/логи), финальный summary.

## Требуемые секреты
- `APPLE_CONNECT_EMAIL`
- `APPLE_DEVELOPER_EMAIL`
- `APPLE_TEAM_ID`
- `MATCH_REPOSITORY`, `MATCH_DEPLOY_KEY`, `MATCH_PASSWORD`
- `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_P8`
- `IOS_BUNDLE_ID`
- Переменные: `IOS_EXTERNAL_GROUP_NAME`, `PROJECT_NAME` (vars), `RUNNER_USERNAME` не требуется (работает на hosted macOS).

Источник артефакта (`build-iOS`) — `reusable-unity-build.yml`.

