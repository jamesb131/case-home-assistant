FROM python:3.12-alpine
WORKDIR /app
COPY app.py .
RUN pip install --no-cache-dir aiohttp
CMD ["python", "app.py"]
