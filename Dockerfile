FROM python:3.11-alpine
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5000

# ↙↙↙ NOWE (co 30s sprawdza /health; 3 próby po 2s)
HEALTHCHECK --interval=30s --timeout=2s --retries=3 CMD wget -qO- http://localhost:5000/health || exit 1

CMD ["python","app.py"]

