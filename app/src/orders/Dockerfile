# Multi-stage: la etapa 1 compila, la etapa 2 solo ejecuta.
# La imagen final es la etapa 2: sin compilador, sin código fuente, sin root.

# ---- Etapa 1: build (temporal, se descarta) ----
FROM golang:1.24-alpine AS builder
WORKDIR /src
# Dependencias primero: Docker las cachea si go.mod no cambia
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# CGO_ENABLED=0 = binario estático; -s -w = sin símbolos de debug
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /orders .

# ---- Etapa 2: runtime (imagen final) ----
FROM alpine:3.20
# ca-certificates para HTTPS; adduser crea usuario no-root
RUN apk add --no-cache ca-certificates && adduser -D -u 1000 app
WORKDIR /app
COPY --from=builder /orders /app/orders
USER app
EXPOSE 8080
ENTRYPOINT ["/app/orders"]