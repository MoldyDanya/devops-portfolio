FROM tensorflow/tensorflow:2.17.0-gpu

RUN apt-get update && apt-get install -y libgl1-mesa-glx

WORKDIR /workspace

COPY requirements.txt .

RUN pip install --upgrade pip && pip install -r requirements.txt

CMD ["bash"]


