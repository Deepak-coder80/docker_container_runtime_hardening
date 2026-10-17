FROM python:3.12-slim

# No .pyc writes, which a read-only filesystem would block anyway
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Create the non-root user with a fixed UID/GID
RUN groupadd -g 1000 app \
 && useradd -u 1000 -g app -s /usr/sbin/nologin -M app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Code stays owned by root, so the app user can't modify it
COPY --chown=root:root . .

USER 1000:1000

EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]