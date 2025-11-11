# Fastlane Configuration

Конфигурация Fastlane для автоматизации деплоя мобильных приложений в Google Play Store и Apple App Store.

## Структура

```
fastlane/
├── Appfile              # Конфигурация приложений
├── Fastfile             # Основной файл с lanes
└── metadata/
    └── changelog.json   # Changelog для релизов
```

## Основные Lanes

### Android

#### `android internal` / `android beta`
Деплой Android приложения в Google Play Store.

```bash
bundle exec fastlane android internal
bundle exec fastlane android beta
```

**Требуемые переменные:**
- `ANDROID_BUILD_FILE_PATH` - Путь к AAB файлу
- `ANDROID_PACKAGE_NAME` - Package name
- `GOOGLE_PLAY_KEY_FILE_PATH` - Путь к JSON ключу Google Play API
- `RELEASE_STATUS` - `draft` или `completed`
- `USE_DEFAULT_CHANGELOG` - `true`/`false`
- `EXPORT_DEBUG_SYMBOLS` - `true`/`false`
- `ANDROID_DEBUG_SYMBOLS_PATTERN` - Паттерн для mapping файлов

### iOS

#### `ios build`
Сборка iOS приложения в IPA без деплоя.

```bash
bundle exec fastlane ios build
```

#### `ios beta`
Сборка и деплой в TestFlight.

```bash
bundle exec fastlane ios beta
bundle exec fastlane ios beta distribute_external:true external_group_name:"External Testers"
```

**Требуемые переменные:**
- `IOS_BUILD_PATH` - Путь к iOS проекту
- `IOS_BUNDLE_ID` - Bundle ID
- `APPLE_TEAM_ID` - Apple Team ID
- `MATCH_REPOSITORY` - Репозиторий для Match (формат: `org/repo`)
- `MATCH_DEPLOY_KEY` - SSH ключ для Match
- `MATCH_PASSWORD` - Пароль для Match
- `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_P8` - App Store Connect API ключи
- `USE_DEFAULT_CHANGELOG` - `true`/`false` (для beta)
- `EXPORT_DEBUG_SYMBOLS` - `true`/`false`

#### `ios sync_certificates`
Синхронизация сертификатов через Fastlane Match.

```bash
bundle exec fastlane ios sync_certificates
```

### Вспомогательные Lanes

#### `get_android_version_code`
Расчет версии для Android на основе git версии и версий в Google Play Store.

```bash
bundle exec fastlane get_android_version_code version:"1.2.3" track:"beta"
```

#### `get_ios_final_version`
Расчет финальной версии для iOS.

```bash
bundle exec fastlane get_ios_final_version version:"1.2.3"
```

#### `get_internal_sharing_link`
Загрузка AAB в Google Play Internal App Sharing.

```bash
bundle exec fastlane get_internal_sharing_link aab_path:"./app.aab"
```

## Changelog

Changelog хранится в `metadata/changelog.json`:

```json
{
  "default": {
    "en-US": "- Bug fixes and improvements"
  },
  "versions": {
    "n": {
      "en-US": "- Latest changes"
    }
  }
}
```

- `default` - используется если `USE_DEFAULT_CHANGELOG=true`
- `versions.n` - используется для последней версии

## Установка

```bash
bundle install
```

## Примечания

- Все конфигурация берется из переменных окружения (см. `Appfile`)
- Сертификаты iOS управляются через Fastlane Match
- Версии автоматически рассчитываются на основе git tags и версий в магазинах
- Debug symbols загружаются автоматически, если найдены соответствующие файлы
