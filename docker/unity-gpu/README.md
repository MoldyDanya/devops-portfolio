# Unity GPU Builder

Минимальный контейнер на базе unityci/editor:ubuntu-2022.3.40f1-android-3.1.0, подготовленный для запусков Unity CI с GPU поддержкой. Образ ставит набор инструментов (Xvfb, Openbox, GDB и т.п.) и включает переменные NVIDIA_VISIBLE_DEVICES/NVIDIA_DRIVER_CAPABILITIES, чтобы GitHub Actions runner мог использовать GPU.

## Как собирать
`powershell
docker build -t unity-gpu docker/unity-gpu
`

## Где используется
- Workflow unity-build-orchestrator.yml (GitHub Actions) тянет этот образ для GPU-accelerated Android билдов. Сама сборка запускается через self-hosted runner с подключенной NVIDIA картой.

## Настройка
- Добавьте --gpus all при запуске docker run, если используете контейнер локально.
- Обновите базовый тег UnityCI в Dockerfile, чтобы перейти на другую версию редактора/модуля платформы.

README держу коротким, потому что весь сценарий задокументирован в docs/workflows/.
