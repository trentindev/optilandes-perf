FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py tournee.py ./

# L'application ne tourne pas en root
RUN useradd --system --uid 10001 appli
USER appli

EXPOSE 8000

# WORKERS fixe le nombre de processus. Il n'est jamais calculé automatiquement :
# dans un conteneur limité, Python voit tous les processeurs de la machine.
CMD ["sh", "-c", "exec gunicorn main:app --worker-class uvicorn_worker.UvicornWorker --workers ${WORKERS:-1} --bind 0.0.0.0:8000 --timeout 60 --graceful-timeout 20"]
