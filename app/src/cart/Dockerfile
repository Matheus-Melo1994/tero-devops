# Multi-stage: la etapa 1 instala dependencias, la etapa 2 solo ejecuta.
# python:slim = Debian mínima con Python. Sin compiladores, sin root.

# ---- Etapa 1: build (temporal, se descarta) ----
FROM python:3.12-slim AS builder
WORKDIR /src
COPY requirements.txt .
# Instalar en una carpeta aparte para copiarla limpia a la etapa 2
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- Etapa 2: runtime (imagen final) ----
FROM python:3.12-slim
# Usuario no-root
RUN useradd -m -u 1000 app
WORKDIR /app
COPY --from=builder /install /usr/local
COPY app ./app
USER app
ENV CART_PERSISTENCE_PROVIDER=in-memory
ENV PORT=8080
EXPOSE 8080
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port $PORT"]