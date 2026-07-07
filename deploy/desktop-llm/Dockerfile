FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY deploy/desktop-llm/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY deploy/desktop-llm/app.py /app/app.py

EXPOSE 11435

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "11435"]
