# Image du back-office (ADR 0003) : sortie « standalone » de Next.js, sans le dossier node_modules
# complet. Construite par la CI à chaque fusion sur main :
#   docker build -t ivia-admin admin/

FROM node:24-alpine AS deps
WORKDIR /app
RUN npm install -g pnpm@10.34.9
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

FROM node:24-alpine AS build
WORKDIR /app
RUN npm install -g pnpm@10.34.9
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN pnpm build

FROM node:24-alpine
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0
COPY --from=build --chown=node:node /app/.next/standalone ./
COPY --from=build --chown=node:node /app/.next/static ./.next/static
USER node
EXPOSE 3000
CMD ["node", "server.js"]
