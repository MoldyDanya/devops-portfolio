# Composite Actions Overview

Каждый раздел ниже описывает соответствующий action из `.github/actions/*`. Формат единый: путь, назначение, входные параметры, Outputs (если есть) и требования к окружению/секретам.

---

## checkout-project
- **Путь:** `.github/actions/checkout-project`
- **Назначение:** checkout проекта с поддержкой Git LFS и резервным копированием `.github/actions`, `.github/scripts`, `fastlane` перед подстановкой подтянутых версий.
- **Особенность:** CI-логика и игровой проект могут жить в разных ветках/репозиториях: action сохраняет текущую инфраструктуру, потом выкачивает нужный branch/commit продукта, возвращая служебные директории на место после checkout.
- **Inputs:**
  | Имя | Обязателен | Описание |
  |-----|------------|----------|
  | `branch_name` | да | Ветка для checkout (если не задан commit). |
  | `commit_hash` | нет | Конкретный commit (приоритет над веткой). |
- **Outputs:** `checkout_ref` — фактически выкачанный ref.
- **Требования:** Runner с установленным Git LFS.

## download-build-artifact
- **Путь:** `.github/actions/download-build-artifact`
- **Назначение:** скачивание артефакта из текущего run, указанного run или последнего успешного run заданного workflow.
- **Inputs:**
  | Имя | Обязателен | Описание |
  |-----|------------|----------|
  | `artifact-name` | да | Имя артефакта. |
  | `destination-path` | да | Куда распаковать. |
  | `workflow-filename` | да | Имя workflow для поиска успешных запусков. |
  | `specific-run-id` | нет | Принудительный run для fallback. |
  | `github-token` | да | Токен с правом `actions:read` (используется GitHub CLI). |
- **Outputs:** —
- **Требования:** Установленный `gh` (доступен на стандартных GitHub runners).

## fix-permissions
- **Путь:** `.github/actions/fix-permissions`
- **Назначение:** рекурсивно устанавливает владельца и права на workspace.
- **Inputs:** `username` (обязателен), `workspace` (по умолчанию `$GITHUB_WORKSPACE`), `permission` (по умолчанию `755`).
- **Outputs:** —
- **Требования:** привилегии sudo на runner.

## get-version
- **Путь:** `.github/actions/get-version`
- **Назначение:** расчёт версии на основе git-тегов и количества коммитов после последнего тега.
- **Inputs:** —
- **Outputs:** `version`, `tag_version`, `commit_count`.
- **Требования:** git история с тегами.

## ios-ab-test-icons
- **Путь:** `.github/actions/ios-ab-test-icons`
- **Назначение:** подготовка ассетов для A/B тестирования иконок iOS.
- **Inputs:** `icons_folder_path` (по умолчанию `Assets/AppIcons/ABTest`), `xcode_project_dir` (по умолчанию `build/iOS/iOS`).
- **Outputs:** —
- **Требования:** Linux runner с `apt-get`; устанавливает `imagemagick`.

## platform-auth-setup
- **Путь:** `.github/actions/platform-auth-setup`
- **Назначение:** подготовка аутентификации для выбранной платформы (создание файла ключа Google Play и установка Ruby для Android).
- **Inputs:** `platform` (`Android`/`iOS`).
- **Outputs:** —
- **Требования:**
  - Android: переменная окружения `GOOGLE_PLAY_KEY_FILE`, возможность писать в `$GITHUB_ENV`; устанавливает Ruby 3.2.
  - iOS: доп. действий не выполняет.

## platform-define-symbols
- **Путь:** `.github/actions/platform-define-symbols`
- **Назначение:** генерация `Assets/csc.rsp` с набором define-символов для Unity.
- **Inputs:** `platform`, `export_debug_symbols`, `development_build` (в текущей реализации используются для логики, но генерация фиксированная `CI_CD`).
- **Outputs:** —
- **Требования:** каталог `Assets/` в workspace.

## platform-post-build
- **Путь:** `.github/actions/platform-post-build`
- **Назначение:** пост-обработка после Unity builder: включает A/B тесты иконок для iOS, либо логирует завершение для Android.
- **Inputs:** `platform`, `ab_test_icons` (по умолчанию `true`).
- **Outputs:** —
- **Требования:** для iOS использует `ios-ab-test-icons`.

## platform-project-settings
- **Путь:** `.github/actions/platform-project-settings`
- **Назначение:** правки `ProjectSettings/ProjectSettings.asset` под целевую платформу (Split Application Binary, splash screen).
- **Inputs:** `platform`, `deploy_to_store`, `android_build_type`.
- **Outputs:** —
- **Требования:** наличие файла `ProjectSettings/ProjectSettings.asset`.

## platform-secrets-check
- **Путь:** `.github/actions/platform-secrets-check`
- **Назначение:** валидация обязательных секретов для заданной платформы.
- **Inputs:** `platform`.
- **Outputs:** —
- **Требования:** при `Android` должен быть установлен `GOOGLE_PLAY_KEY_FILE` (иначе action прерывает workflow).

## platform-unity-build-params
- **Путь:** `.github/actions/platform-unity-build-params`
- **Назначение:** формирование параметров для `game-ci/unity-builder` (targetPlatform, export type).
- **Inputs:** `platform`, `android_build_type`, `version`, `android_version_code` (опционально).
- **Outputs:** `target_platform`, `android_export_type`.
- **Требования:** —

## platform-version-calculation
- **Путь:** `.github/actions/platform-version-calculation`
- **Назначение:** получение финальной версии из магазинов (Google Play / App Store) с использованием Fastlane lanes `get_android_version_code` и `get_ios_final_version`.
- **Inputs:** `platform`, `version`, `deploy_track` (для Android).
- **Outputs:** `android_version_code`, `android_version_name`, `ios_final_version`.
- **Требования:**
  - Android: `GOOGLE_PLAY_KEY_FILE` (JSON содержимое).
  - iOS: `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_P8`, `IOS_BUNDLE_ID`; наличие `Gemfile` (опционально) для `bundle install`.

## unity-cache
- **Путь:** `.github/actions/unity-cache`
- **Назначение:** node-action для восстановления/сохранения кэша Unity Library на локальном диске runner.
- **Inputs:** `platform`, `repository`, `branch`, `cache_base_path`, `runner_username`, `skip-save`, `max_caches`, `max_age_days`, `clean_build`.
- **Outputs:** `cache-hit` (`true`/`false`/`fallback`).
- **Требования:** Node.js 20 (запускается на self-hosted runner), доступ к файловой системе по `cache_base_path`.

## unity-test-runner-permissions
- **Путь:** `.github/actions/unity-test-runner-permissions`
- **Назначение:** запуск AltTester контейнера и (при включении) Unity test runner с последующей нормализацией прав доступа.
- **Inputs:** `unity_email`, `unity_password`, `unity_serial`, `github_token`, `username`, `run_as_host_user`, `project_path`, `test_mode`, `extra_parameters`, `alttester_license_key`.
- **Outputs:** `artifacts_path`, `test_results`, `coverage_results`, `outcome`.
- **Требования:** Docker на runner, доступ к интернету для образа `alttestertools/alttester:2.0.1`, sudo для установки `jq`, `lsof`.

## upload-internal-sharing
- **Путь:** `.github/actions/upload-internal-sharing`
- **Назначение:** загрузка AAB в Google Play Internal App Sharing (напрямую через HTTP API без Fastlane) и возврат download URL.
- **Inputs:** `aab-path`, `package-name`, `service-account-json` (полное содержимое JSON ключа).
- **Outputs:** `download-url`, `package-name`.
- **Требования:** `jq`, `curl`, `openssl` (устанавливаются при необходимости).
