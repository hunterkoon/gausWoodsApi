FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt ./

RUN pip install -r requirements.txt

COPY gauswoodsquote/ ./gauswoodsquote/

COPY run_api.py ./

CMD ["python", "run_api.py"]