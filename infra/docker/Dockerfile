# Build stage
FROM node:22-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY app.js ./app.js
COPY src ./src

# Runtime stage
FROM node:22-alpine AS runtime

ENV NODE_ENV=production
ENV PORT=3000

WORKDIR /app

COPY --from=builder --chown=node:node /app/package.json ./package.json
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --from=builder --chown=node:node /app/app.js ./app.js
COPY --from=builder --chown=node:node /app/src ./src

USER node

EXPOSE 3000

CMD ["node", "app.js"]
