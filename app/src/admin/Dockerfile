# Multi-stage: la etapa 1 compila TypeScript, la etapa 2 solo ejecuta.
# La imagen final lleva Node + dist/ + dependencias de producción. Sin TypeScript, sin root.

# ---- Etapa 1: build (temporal, se descarta) ----
FROM node:22-alpine AS builder
WORKDIR /src
# Dependencias primero: Docker las cachea si package.json no cambia
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build
# Dejar solo dependencias de producción
RUN npm prune --omit=dev

# ---- Etapa 2: runtime (imagen final) ----
FROM node:22-alpine
# node:alpine ya trae el usuario "node" sin privilegios
WORKDIR /app
COPY --from=builder /src/dist ./dist
COPY --from=builder /src/node_modules ./node_modules
COPY --from=builder /src/package.json ./
COPY --from=builder /src/public ./public
USER node
ENV PORT=8080
EXPOSE 8080
CMD ["node", "dist/app.js"]