# Multi-stage: la etapa 1 instala dependencias, la etapa 2 solo ejecuta.
# python:alpine en lugar de python:slim: la base Debian arrastraba 49 HIGH, 47 sin
# parche disponible (util-linux, ncurses, sqlite, systemd, perl). Sin compiladores, sin root.

# ---- Etapa 1: build (temporal, se descarta) ----
FROM python:3.12-alpine AS builder
WORKDIR /src
COPY requirements.txt .
# requirements.txt fija directas y transitivas con su hash (se genera desde requirements.in):
# --require-hashes rechaza cualquier paquete cuyo archivo no coincida con el hash fijado,
# --no-deps instala exactamente esa lista y --only-binary evita compilar en la imagen.
# Se instala en una carpeta aparte para copiarla limpia a la etapa 2.
RUN pip install --no-cache-dir --require-hashes --no-deps --only-binary=:all: --prefix=/install -r requirements.txt

# ---- Etapa 2: runtime (imagen final) ----
FROM python:3.12-alpine
# apk upgrade: aplica los parches de Alpine publicados después de la imagen base
# (krb5-libs 1.22.3-r0, que llega como dependencia de Python). Usuario no-root.
RUN apk upgrade --no-cache && adduser -D -u 1000 app
WORKDIR /app
COPY --from=builder /install /usr/local
COPY app ./app
USER app
ENV CART_PERSISTENCE_PROVIDER=in-memory
ENV PORT=8080
EXPOSE 8080
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port $PORT"]
