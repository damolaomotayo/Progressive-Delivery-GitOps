FROM python:3.12-slim

# Baked in at build time so one codebase produces v1, v2 and a deliberately broken build.
ARG APP_VERSION=v1
ARG ERROR_RATE=0
ENV APP_VERSION=${APP_VERSION} ERROR_RATE=${ERROR_RATE} PYTHONUNBUFFERED=1

WORKDIR /app
COPY app/main.py .

USER 65534
EXPOSE 8080
CMD ["python", "main.py"]
