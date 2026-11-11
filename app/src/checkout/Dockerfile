# Multi-stage: la etapa 1 compila con NestJS, la etapa 2 solo ejecuta.
# Usa Yarn 4 (Berry), que viene versionado en .yarn/releases.

# ---- Etapa 1: build (temporal, se descarta) ----
FROM node:22-alpine AS builder
WORKDIR /src
# Yarn Berry necesita su binario y config antes de instalar
COPY package.json yarn.lock .yarnrc.yml ./
COPY .yarn ./.yarn
RUN yarn install --immutable
COPY . .
RUN yarn build

# ---- Etapa 2: runtime (imagen final) ----
FROM node:22-alpine
WORKDIR /app
COPY --from=builder /src/dist ./dist
COPY --from=builder /src/node_modules ./node_modules
COPY --from=builder /src/package.json ./
USER node
EXPOSE 8080
CMD ["node", "dist/main.js"]
