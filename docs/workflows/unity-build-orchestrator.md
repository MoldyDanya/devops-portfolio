# Unity Build Orchestrator Workflow

- **Путь:** `.github/workflows/unity-build-orchestrator.yml`
- **Назначение:** центральный оркестратор сборок и деплоев Unity-проекта, запускающий Android и iOS пайплайны параллельно и подключающий вспомогательные reusable workflows.

## Триггеры
- `workflow_dispatch` — ручной запуск с параметрами ветки/типов сборок.
- `workflow_call` — повторное использование из других workflow.

## Основные входные параметры
| Параметр | Тип | По умолчанию | Назначение |
|----------|-----|--------------|------------|
| `branch_name` | string | — | Git-ветка для сборки (обязателен). |
| `commit_hash` | string | — | Точный коммит; при задании перекрывает ветку. |
| `android_build_type` | choice | `APK (Development)` | Сценарий Android (Skip, APK, комбинации AAB/IAS/Deploy). |
| `android_release_status` | choice | `Draft` | Статус релиза в Google Play (`Draft`/`Published`). |
| `ios_build_type` | choice | `Build Only` | Сценарий iOS (Skip, Build, Build+Deploy, Dev-варианты). |
| `clean_build` | boolean | `false` | Принудительное отключение кэша Unity. |

## Jobs и взаимосвязи
| Job | Назначение | Зависимости |
|-----|------------|-------------|
| `show-run-info` | Выводит параметры запуска в Step Summary. | — |
| `start-instance` | Запускает self-hosted EC2 через `manage-ec2.yml`. | `show-run-info` |
| `build-android` | Делегирует Android сборку в `reusable-unity-build.yml`. | `start-instance` |
| `build-ios` | Делегирует iOS сборку в `reusable-unity-build.yml`. | `start-instance` |
| `deploy-android` | Деплой в Google Play через `android-deploy.yml` (если выбран Deploy). | `build-android` |
| `process-ios` | Xcode билд/деплой через `ios-xcode-build.yml`. | `build-ios` |
| `upload-android-ias` | Загрузка AAB в Google Play IAS (если выбран сценарий с IAS). | `build-android` |
| `collect-build-info` | Финальный отчёт по результатам обеих сборок. | `build-android`, `build-ios` |

## Подключаемые reusable workflows
- `.github/workflows/reusable-unity-build.yml`
- `.github/workflows/android-deploy.yml`
- `.github/workflows/ios-xcode-build.yml`
- `.github/workflows/android-ias.yml`
- `.github/workflows/manage-ec2.yml`

## Требуемые секреты и переменные
Workflow использует `secrets: inherit`. Необходимый набор описан в `README.md` (Unity лицензия, Google Play, App Store Connect, Match, AltTester и т.д.). Дополнительно требуются переменные `RUNNER_USERNAME`, `UNITY_CACHE_MAX_COUNT`, `UNITY_CACHE_MAX_AGE_DAYS`, `IOS_EXTERNAL_GROUP_NAME`.

