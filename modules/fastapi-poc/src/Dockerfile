FROM python:3.9-slim

RUN apt-get update && apt-get install -y curl

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV DD_SERVICE="fastapi-poc"
ENV DD_ENV="production"

EXPOSE 5000

CMD ["python", "main.py"]