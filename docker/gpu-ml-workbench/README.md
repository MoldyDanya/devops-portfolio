# GPU ML Workbench

Лёгкий шаблон для запуска GPU-ускоренных ML/DS экспериментов внутри Docker. Образ собирается из официального 	ensorflow/tensorflow:2.17.0-gpu, добавляет OpenCV зависимости и устанавливает Python-пакеты из equirements.txt.

## Что внутри
- CUDA-ready окружение с TensorFlow 2.17 и поддержкой Keras / CuPy / scikit-learn
- NVIDIA runtime и проброс всех GPU устройств с помощью docker compose
- Общая папка . монтируется в контейнер как /workspace для доступа к коду и данным
- Интерактивный режим (TTY + stdin) для работы из Shell или Jupyter (можно запускать вручную)

## Как использовать
1. Перейдите в каталог docker/gpu-ml-workbench
2. Соберите образ и поднимите контейнер
   `
   docker compose up --build -d
   `
3. Подключитесь к контейнеру
   `
   docker exec -it gpu_ml_workbench bash
   `
4. Работайте с кодом в смонтированной директории /workspace

Остановить окружение: docker compose down.

## Кастомизация
- Добавляйте свои зависимости в equirements.txt
- Меняйте базовый образ в Dockerfile, если нужен другой фреймворк (например, PyTorch)
- Дополняйте docker-compose.yml сервисами (например, Jupyter, MLflow, PostgreSQL)

Этот каталог можно ссылкой включать в портфолио как пример готового GPU-ready dev окружения.
