# GitHub Runner Lifecycle Management

Универсальная система автоматического управления жизненным циклом self-hosted GitHub Actions runners. Работает на любом Linux сервере или в облаке (AWS EC2). Мониторит активность runner'ов и автоматически останавливает простаивающие инстансы для оптимизации расходов.

## Обзор

Система автоматически управляет жизненным циклом GitHub Actions self-hosted runners:
- Мониторит статус runner'а (idle/active) через systemd и диагностические файлы
- Отслеживает время простоя и отправляет метрики через statsd (универсальный протокол)
- Автоматически останавливает сервер при превышении idle timeout
- Публикует события жизненного цикла (через кастомные hooks или AWS SNS)

**Пример экономии (AWS):** Инстанс t3.medium ($0.0416/час), работающий 4 часа в день с idle timeout 30 минут, экономит ~78% по сравнению с работой 24/7.

## Архитектура

Система использует **модульную архитектуру с провайдерами**, что позволяет работать на любом сервере или в облаке:

### Провайдеры

1. **`generic`** - Универсальный провайдер для любого Linux сервера
   - Остановка через `shutdown` или кастомную команду
   - События через кастомный hook скрипт
   - Не требует облачных зависимостей

2. **`aws`** - AWS-специфичный провайдер для EC2 инстансов
   - Остановка через AWS EC2 API
   - События через AWS SNS
   - Интеграция с CloudWatch Agent (опционально)

### Компоненты

#### 1. Setup Script (`setup-runner-monitoring.sh`)
Одноразовый скрипт подготовки, который настраивает инстанс для управления жизненным циклом.

**Обязанности:**
- Устанавливает провайдеры в `/usr/local/lib/github-runner-lifecycle/providers`
- Устанавливает AWS CloudWatch Agent (только для AWS провайдера, опционально)
- Настраивает CloudWatch Agent для сбора метрик и логов (только для AWS)
- Создаёт systemd сервис для мониторинга жизненного цикла
- Создаёт директорию конфигурации и файл конфигурации по умолчанию
- Автоматически определяет провайдер (проверяет AWS metadata)
- Проверяет зависимости (curl, jq, systemctl, nc)

**Когда запускать:** Во время инициализации инстанса (user-data скрипт, ручная установка или инструменты автоматизации).

#### 2. Lifecycle Monitor (`runner-lifecycle-monitor.sh`)
Основной runtime сервис, который мониторит состояние runner'а и управляет жизненным циклом инстанса.

**Как работает:**
1. Загружает конфигурацию из `/etc/github-runner/config.json`
2. Загружает провайдер на основе `PROVIDER` из конфигурации
3. Инициализирует провайдер (получение instance-id, region и т.д.)
4. Каждые `CHECK_INTERVAL` секунд проверяет статус runner'а:
   - Использует `systemctl` для проверки активности сервиса(ов) runner'а
   - Читает диагностические файлы runner'а в директории `_diag/` для определения статуса джобы
   - Определяет, находится ли runner в состоянии idle или busy
5. Отслеживает время простоя:
   - Когда runner становится idle, записывает timestamp в `/var/run/github-runner/idle_since`
   - Когда runner становится активным, очищает idle timestamp
6. Отправляет метрики на локальный statsd сервер (localhost:8125) - универсальный протокол, работает с любым statsd сервером
7. Публикует события жизненного цикла через провайдер:
   - Generic: через кастомный hook скрипт (если настроен `EVENT_HOOK_SCRIPT`)
   - AWS: через AWS SNS (если настроен `SNS_TOPIC_ARN`)
8. Когда достигается `IDLE_TIMEOUT` при idle состоянии, останавливает инстанс через провайдер:
   - Generic: `shutdown -h now` или кастомная команда из `STOP_COMMAND`
   - AWS: `aws ec2 stop-instances` через AWS API

**Запускается как:** systemd сервис `github-runner-lifecycle.service` (автоматически перезапускается при сбоях)

## Структура проекта

```
services/github-runner-lifecycle/
├── setup-runner-monitoring.sh          # Одноразовый скрипт установки
├── runner-lifecycle-monitor.sh         # Runtime сервис мониторинга
├── providers/                          # Провайдеры
│   ├── generic.sh                      # Универсальный провайдер (любой сервер)
│   └── aws.sh                          # AWS-специфичный провайдер
├── config/
│   ├── config.json.example              # Пример конфигурации (generic)
│   ├── config.json.example.aws         # Пример конфигурации (AWS)
│   ├── github-runner-lifecycle.service # systemd unit файл
│   └── cloudwatch-agent-config.json    # Пример конфигурации CloudWatch Agent (AWS)
└── README.md                           # Этот файл
```

## Требования

### Общие требования (для всех провайдеров)
- **ОС:** Ubuntu/Debian-based Linux (протестировано на Ubuntu 20.04+)
- **Доступ:** Требуются root привилегии для установки
- **Зависимости:** curl, jq, systemctl, nc (netcat)
- **Runner:** GitHub Actions runner установлен в `/opt/actions-runner` (или кастомный путь)

### Требования для AWS провайдера
- **AWS:** EC2 инстанс с IAM instance profile или настроенным AWS CLI
- **AWS CLI:** Устанавливается автоматически setup скриптом (опционально)
- **CloudWatch Agent:** Устанавливается автоматически для AWS провайдера (опционально)

### Требования для Generic провайдера
- **Никаких облачных зависимостей** - работает на любом Linux сервере

### IAM разрешения (только для AWS провайдера)

Если используете AWS провайдер, роль EC2 инстанса или AWS credentials должны иметь следующие разрешения:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:StopInstances",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "arn:aws:sns:*:*:github-runner-events"
    }
  ]
}
```

**Примечание по безопасности:** Используйте IAM instance profiles вместо хранения credentials в файлах.

## Установка

### Шаг 1: Установка GitHub Actions Runner

Сначала установите GitHub Actions runner, следуя [официальному руководству](https://docs.github.com/en/actions/hosting-your-own-runners/adding-self-hosted-runners). Runner должен быть установлен в `/opt/actions-runner` (или обновите `RUNNER_DIR` в конфигурации).

Убедитесь, что сервис runner'а настроен и может запускаться/останавливаться через systemd (например, сервис `actions.runner.*`).

### Шаг 2: Копирование файлов на сервер

Скопируйте файлы управления жизненным циклом на сервер:

```bash
# Копирование скриптов в системную директорию
sudo cp setup-runner-monitoring.sh /usr/local/bin/
sudo cp runner-lifecycle-monitor.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/{setup-runner-monitoring.sh,runner-lifecycle-monitor.sh}

# Копирование systemd service файла
sudo cp config/github-runner-lifecycle.service /etc/systemd/system/

# Копирование примера конфигурации (опционально - setup скрипт создаст дефолтную)
sudo mkdir -p /etc/github-runner
sudo cp config/config.json.example /etc/github-runner/config.json
# Или для AWS:
# sudo cp config/config.json.example.aws /etc/github-runner/config.json
```

**Важно:** Setup скрипт автоматически скопирует провайдеры из директории `providers/` в `/usr/local/lib/github-runner-lifecycle/providers/`, поэтому убедитесь, что директория `providers/` находится рядом со скриптами при копировании.

### Шаг 3: Настройка

Отредактируйте `/etc/github-runner/config.json` с вашими настройками:

```bash
sudo nano /etc/github-runner/config.json
```

#### Пример конфигурации для Generic провайдера (любой сервер):

```json
{
  "IDLE_TIMEOUT": 30,
  "CHECK_INTERVAL": 60,
  "RUNNER_NAME": "github-runner-01",
  "PROVIDER": "generic",
  "RUNNER_DIR": "/opt/actions-runner",
  "STOP_COMMAND": "shutdown -h now",
  "EVENT_HOOK_SCRIPT": "/path/to/event-hook.sh",
  "INSTANCE_ID": "",
  "REGION": ""
}
```

#### Пример конфигурации для AWS провайдера:

```json
{
  "IDLE_TIMEOUT": 30,
  "CHECK_INTERVAL": 60,
  "RUNNER_NAME": "github-runner-01",
  "PROVIDER": "aws",
  "RUNNER_DIR": "/opt/actions-runner",
  "SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:github-runner-events",
  "INSTANCE_ID": "",
  "REGION": ""
}
```

**Параметры конфигурации:**
- `IDLE_TIMEOUT` - Минуты простоя перед остановкой инстанса (по умолчанию: 30)
- `CHECK_INTERVAL` - Секунды между проверками статуса (по умолчанию: 60)
- `RUNNER_NAME` - Идентификатор этого runner'а (по умолчанию: hostname)
- `PROVIDER` - Провайдер: `"generic"` или `"aws"` (по умолчанию: `"generic"`)
- `RUNNER_DIR` - Путь к установке runner'а (по умолчанию: /opt/actions-runner)

**Параметры для Generic провайдера:**
- `STOP_COMMAND` - Кастомная команда для остановки сервера (по умолчанию: `"shutdown -h now"`)
- `EVENT_HOOK_SCRIPT` - Путь к скрипту для обработки событий (опционально)

**Параметры для AWS провайдера:**
- `SNS_TOPIC_ARN` - ARN SNS топика для событий жизненного цикла (опционально)
- `INSTANCE_ID` - ID EC2 инстанса (автоматически определяется из metadata, если не указан)
- `REGION` - AWS регион (автоматически определяется из metadata, если не указан)

### Шаг 4: Запуск Setup скрипта

Выполните setup скрипт для установки и настройки всех компонентов:

```bash
sudo /usr/local/bin/setup-runner-monitoring.sh
```

Это выполнит:
- Проверку необходимых зависимостей
- Копирование провайдеров в `/usr/local/lib/github-runner-lifecycle/providers`
- Автоматическое определение провайдера (проверка AWS metadata)
- Установку AWS CloudWatch Agent (только для AWS провайдера, опционально)
- Настройку CloudWatch Agent для сбора метрик и логов (только для AWS)
- Создание systemd service unit
- Создание конфигурации по умолчанию (если не существует)

**Примечание:** Setup скрипт автоматически определяет, находитесь ли вы на AWS EC2 (проверяя доступность metadata service), и устанавливает соответствующий провайдер по умолчанию.

### Шаг 5: Запуск Lifecycle сервиса

Запустите и включите сервис мониторинга жизненного цикла:

```bash
sudo systemctl daemon-reload
sudo systemctl enable github-runner-lifecycle
sudo systemctl start github-runner-lifecycle
sudo systemctl status github-runner-lifecycle
```

## Детали конфигурации

### Основной файл конфигурации

Расположение: `/etc/github-runner/config.json`

Этот JSON файл управляет поведением lifecycle monitor'а. Все параметры опциональны и имеют значения по умолчанию.

### Провайдеры

Провайдеры устанавливаются в `/usr/local/lib/github-runner-lifecycle/providers/` и загружаются динамически на основе конфигурации.

#### Generic провайдер

Работает на любом Linux сервере без облачных зависимостей:
- **Остановка:** Использует `shutdown -h now` или кастомную команду из `STOP_COMMAND`
- **События:** Вызывает кастомный hook скрипт из `EVENT_HOOK_SCRIPT` (если настроен)
- **Метрики:** Отправляет на statsd (localhost:8125) - работает с любым statsd сервером

#### AWS провайдер

Специализирован для AWS EC2:
- **Остановка:** Использует `aws ec2 stop-instances` через AWS API
- **События:** Публикует в AWS SNS (если настроен `SNS_TOPIC_ARN`)
- **Метрики:** Отправляет на statsd, CloudWatch Agent пересылает в CloudWatch
- **Metadata:** Автоматически получает instance-id и region из AWS metadata service

### Конфигурация CloudWatch Agent (только для AWS)

Setup скрипт генерирует конфигурацию CloudWatch Agent в `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json` с:

- **Namespace метрик:** `GitHub/Runners`
- **Statsd listener:** Порт 8125 (UDP)
- **Log groups:**
  - `/github/runner/lifecycle` - Логи lifecycle monitor'а (хранение 14 дней)
  - `/github/runner/hooks` - События hooks runner'а (хранение 7 дней, если hooks.log существует)
  - `/github/runner/diagnostic` - Диагностические логи runner'а (хранение 14 дней)

**Примечание:** CloudWatch Agent устанавливается и настраивается только для AWS провайдера. Для generic провайдера метрики отправляются на statsd, но CloudWatch Agent не требуется.

### Systemd сервис

Сервис запускается от root (требуется для операций systemd и shutdown). Автоматически перезапускается при сбоях с задержкой 10 секунд.

Расположение файла сервиса: `/etc/systemd/system/github-runner-lifecycle.service`

Для AWS провайдера сервис зависит от CloudWatch Agent (если установлен). Для generic провайдера зависимости минимальны.

## Мониторинг

### Просмотр логов

**Systemd journal:**
```bash
sudo journalctl -u github-runner-lifecycle -f
```

**Прямые log файлы (локальные):**
```bash
tail -f /var/log/github-runner/lifecycle.log
```

**Логи CloudWatch Agent (только для AWS):**
```bash
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

**Примечание:** Логи пишутся в локальные файлы (`/var/log/github-runner/lifecycle.log` и другие). Для AWS провайдера CloudWatch Agent читает эти файлы и отправляет их в AWS CloudWatch Logs. Для generic провайдера логи остаются локальными.

### Метрики

Метрики отправляются на локальный statsd сервер (localhost:8125) через UDP, используя протокол statsd. Это универсальный протокол, который работает с любым statsd сервером.

**Для AWS провайдера:** CloudWatch Agent слушает порт 8125 и автоматически отправляет метрики в AWS CloudWatch с namespace `GitHub/Runners` и dimensions:
- `InstanceId` - ID EC2 инстанса
- `RunnerName` - Идентификатор runner'а из конфигурации

**Для generic провайдера:** Метрики отправляются на statsd, но CloudWatch Agent не требуется. Можно использовать любой statsd сервер (например, Prometheus statsd exporter, Datadog agent и т.д.).

**Доступные метрики:**
- `runner.started` - Сервис запущен (count)
- `runner.active` - Runner занят (gauge, 1 = active, 0 = idle)
- `runner.idle_minutes` - Текущее время простоя в минутах (gauge)
- `runner.stopping` - Событие остановки инстанса (count)
- `runner.stopped` - Сервис остановлен (count)

### События жизненного цикла

#### Generic провайдер

Если настроен `EVENT_HOOK_SCRIPT`, события передаются в кастомный скрипт:

```bash
# Скрипт получает аргументы:
# $1 - event name (lifecycle_service_started, lifecycle_service_stopped, idle_timeout_reached)
# $2 - JSON data
# $3 - instance_id
# $4 - runner_name
# $5 - region
```

Пример hook скрипта:
```bash
#!/bin/bash
event=$1
data=$2
instance_id=$3
runner_name=$4
region=$5

echo "Event: $event" | logger -t github-runner-lifecycle
# Отправить в вашу систему мониторинга, webhook и т.д.
```

#### AWS провайдер

Если настроен `SNS_TOPIC_ARN`, публикуются следующие события напрямую в AWS SNS через AWS CLI (`aws sns publish`):

- `lifecycle_service_started` - Сервис мониторинга запущен
- `lifecycle_service_stopped` - Сервис мониторинга остановлен
- `idle_timeout_reached` - Инстанс останавливается из-за idle timeout

Payload события включает: `event`, `timestamp`, `instance_id`, `runner_name`, `region` и специфичные для события `data`.

## Как работает определение idle

Система определяет, находится ли runner в состоянии idle, используя двухэтапный процесс:

1. **Проверка статуса сервиса:** Проверяет, активен ли какой-либо systemd сервис `actions.runner.*`
2. **Проверка диагностических файлов:** Читает последний диагностический JSON файл из `RUNNER_DIR/_diag/` и проверяет поле `runnerStatus`

**Условия idle:**
- Не найдено сервисов runner'а → idle
- Сервисы существуют, но ни один не активен → idle
- Сервисы активны, но нет недавних диагностических файлов → idle
- Диагностический файл показывает `runnerStatus: "idle"` или `"online"` → idle

**Условия active:**
- Сервис активен И диагностический файл показывает статус отличный от `"idle"` или `"online"` → busy

**Важно:** Система предполагает idle, если диагностические файлы отсутствуют или не могут быть прочитаны. Это мера безопасности, чтобы избежать остановки инстансов во время запуска runner'а или проблем с конфигурацией.

## Устранение неполадок

### Сервис не запускается

```bash
# Проверка зависимостей
which jq curl nc systemctl

# Проверка прав на скрипт
ls -la /usr/local/bin/runner-lifecycle-monitor.sh

# Проверка провайдеров
ls -la /usr/local/lib/github-runner-lifecycle/providers/

# Проверка синтаксиса конфигурации
sudo cat /etc/github-runner/config.json | jq .

# Проверка статуса systemd сервиса
sudo systemctl status github-runner-lifecycle
sudo journalctl -u github-runner-lifecycle -n 50
```

### Инстанс не останавливается

**Для Generic провайдера:**
```bash
# Проверка логики определения idle
tail -f /var/log/github-runner/lifecycle.log | grep -i idle

# Проверка файла состояния idle
cat /var/run/github-runner/idle_since

# Тест команды остановки
sudo shutdown -h now
```

**Для AWS провайдера:**
```bash
# Проверка IAM разрешений
aws ec2 describe-instances --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Ручной тест команды остановки
aws ec2 stop-instances --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Проверка логики определения idle
tail -f /var/log/github-runner/lifecycle.log | grep -i idle

# Проверка файла состояния idle
cat /var/run/github-runner/idle_since
```

### Метрики не появляются

**Для Generic провайдера:**
```bash
# Проверка statsd сервера
nc -zv 127.0.0.1 8125

# Тест отправки метрики
echo "test.metric:1|c" | nc -u -w1 127.0.0.1 8125
```

**Для AWS провайдера:**
```bash
# Проверка статуса CloudWatch Agent
sudo amazon-cloudwatch-agent-ctl -m ec2 -a query

# Тест подключения statsd
echo "test.metric:1|c" | nc -u -w1 127.0.0.1 8125

# Проверка логов агента
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log

# Проверка конфигурации агента
sudo cat /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json | jq .
```

### Проблемы с определением статуса runner'а

```bash
# Проверка сервисов runner'а
systemctl list-units 'actions.runner.*' --no-legend

# Проверка диагностических файлов
ls -lah /opt/actions-runner/_diag/
cat /opt/actions-runner/_diag/Runner_*.json | jq . | tail -20

# Проверка статуса сервиса runner'а
systemctl status actions.runner.*
```

## Разработка и тестирование

### Локальное тестирование

```bash
# Запуск setup
sudo ./setup-runner-monitoring.sh

# Ручной тест lifecycle monitor'а с короткими таймаутами
sudo IDLE_TIMEOUT=5 CHECK_INTERVAL=10 ./runner-lifecycle-monitor.sh

# Симуляция idle состояния
sudo mkdir -p /var/run/github-runner
sudo sh -c 'echo $(date +%s) > /var/run/github-runner/idle_since'

# Просмотр логов
tail -f /var/log/github-runner/lifecycle.log
```

### Ручное управление сервисом

```bash
# Остановка сервиса
sudo systemctl stop github-runner-lifecycle

# Перезапуск сервиса
sudo systemctl restart github-runner-lifecycle

# Отключение автозапуска
sudo systemctl disable github-runner-lifecycle
```

## Оптимизация расходов

Эта система может значительно снизить облачные расходы для периодических нагрузок.

**Пример расчёта (AWS):**
- Инстанс: t3.medium ($0.0416/час)
- Использование: 4 часа в день фактического выполнения джоб
- Idle timeout: 30 минут
- Оценочное время работы: ~160 часов/месяц (4 часа/день + overhead)

**Месячные расходы:**
- Без lifecycle management: 720 часов × $0.0416 = **$29.95**
- С lifecycle management: ~160 часов × $0.0416 = **$6.66**
- **Экономия: ~78% ($23.29/месяц на runner)**

Фактическая экономия зависит от частоты джоб, настроек idle timeout и времени запуска инстанса.

## Соображения безопасности

1. **Root привилегии:** Сервис запускается от root для управления операциями systemd и выполнения shutdown. Оцените последствия безопасности для вашего окружения.

2. **IAM разрешения (AWS):** Используйте IAM роли с минимальными привилегиями. Рассмотрите ограничение разрешений EC2 stop для конкретных инстансов, используя resource tags или instance IDs.

3. **Credentials:** Никогда не храните AWS credentials в файлах конфигурации. Всегда используйте IAM instance profiles.

4. **Логи:** Логи могут содержать чувствительную информацию (instance IDs, имена runner'ов и т.д.). Оцените политики хранения и доступа к логам.

5. **Сеть:** Statsd listener (порт 8125) привязан только к localhost. CloudWatch Agent (для AWS) обрабатывает внешнюю коммуникацию.

6. **Кастомные команды (Generic):** Будьте осторожны с `STOP_COMMAND` и `EVENT_HOOK_SCRIPT` - они выполняются от root.

## Ограничения

- **Определение одного runner'а:** Система проверяет наличие любого сервиса `actions.runner.*`, но не различает несколько runner'ов на одном инстансе. Все runner'ы должны быть idle для остановки инстанса.

- **Зависимость от диагностических файлов:** Определение idle зависит от диагностических файлов runner'а. Если эти файлы не генерируются или имеют неожиданный формат, определение может быть неточным.

- **Нет метрик джоб:** Метрики на уровне джоб (started/completed/failed) в настоящее время не реализованы. Для этого потребуется интеграция с hooks GitHub Actions runner'а.

- **Spot инстансы (AWS):** Система определяет spot инстансы и избегает принудительного shutdown, но termination spot инстанса может прервать процесс жизненного цикла.

## Вклад в проект

При модификации этой системы:

1. Сохраняйте фокус компонентов (setup vs runtime vs providers)
2. Валидируйте конфигурацию рано с понятными сообщениями об ошибках
3. Логируйте ошибки с достаточным контекстом для отладки
4. Обрабатывайте сбои API корректно (проблемы сети, разрешения и т.д.)
5. Тестируйте на чистом сервере перед деплоем в production
6. Обновляйте этот README при добавлении функций или изменении поведения

## Лицензия

См. файл LICENSE репозитория.

## Ссылки

- [GitHub Actions Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [AWS CloudWatch Agent](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html)
- [systemd Service Management](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [AWS EC2 Instance Metadata](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html)
