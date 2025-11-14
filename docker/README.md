# Docker Artifacts

Каталог содержит готовые контейнеры и окружения, которые использую в проектах.

| Каталог | Назначение | Команда запуска |
| --- | --- | --- |
| [gpu-ml-workbench](gpu-ml-workbench) | GPU-ready sandbox для ML/DS экспериментов (TensorFlow 2.17, CuPy, OpenCV). Есть docker-compose и README с инструкциями. | docker compose up --build -d внутри каталога |
| [unity-gpu](unity-gpu) | Кастомный образ UnityCI с GPU-ускорением, который тянет workflow unity-build-orchestrator.yml для Android билдов. | docker build -t unity-gpu docker/unity-gpu |

Каждый подпроект содержит свой README с деталями и ссылками на соответствующие workflow или документацию.
