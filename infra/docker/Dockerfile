FROM node:22-alpine AS builder

# Create app user and group
RUN addgroup app && adduser -S -G app app

WORKDIR /usr/src

# Copy package files and install dependencies as root
COPY package*.json ./
RUN npm install

# Copy rest of the app
COPY . .

# Production stage
FROM node:22-alpine

# Create app user and group
RUN addgroup app && adduser -S -G app app

WORKDIR /usr/src

# Copy installed dependencies from builder
COPY --from=builder /usr/src/node_modules ./node_modules
COPY --from=builder /usr/src/package*.json ./
COPY --from=builder /usr/src/app.js ./

# Switch to non-root user for runtime
USER app

EXPOSE 3000
CMD ["node", "app.js"]
