ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install Node.js 20, bash (for bashio), and curl (for HA API calls)
RUN apk add --no-cache \
    nodejs=~20 \
    npm \
    bash \
    curl \
    jq

# Set working directory
WORKDIR /app

# Copy package files first for better layer caching
COPY package.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source files
COPY src/ ./src/
COPY public/ ./public/

# Copy HA integration files (will be installed by run.sh)
COPY packages/ ./packages/
COPY themes/ ./themes/
COPY dashboard.yaml ./dashboard.yaml

# Copy background image
COPY calbackgrd.png ./calbackgrd.png

# Copy run script
COPY run.sh /

# Make run script executable
RUN chmod a+x /run.sh

CMD ["/run.sh"]
