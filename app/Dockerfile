# Pinned by tag for Phase 1. Phase 2 replaces this with a digest pin so the
# base image cannot drift between the scan and the deploy.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Non-root from the start. Phase 2 adds a Kyverno policy that rejects any pod
# able to run as root, and retrofitting that is more painful than doing it now.
RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin appuser

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

USER 10001
EXPOSE 8080

# One worker, several threads. prometheus_client keeps its registry in process
# memory, so multiple workers would return whichever worker's counters happened
# to serve /metrics. Threads give concurrency without splitting the registry.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "4", \
     "--access-logfile", "-", "--error-logfile", "-", "app:app"]
