# Multi-stage build for optimized Docker image
FROM rust:1.75-slim as builder

# Install system dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy manifest files
COPY Cargo.toml Cargo.lock ./

# Create a dummy main.rs to build dependencies first
RUN mkdir src && echo "fn main() {}" > src/main.rs

# Build dependencies (this will be cached)
RUN cargo build --release && rm -rf src target/release/deps/bitcoin_matcher*

# Copy source code
COPY src ./src

# Build the application
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Create app user
RUN useradd -r -s /bin/false appuser

# Create app directory
WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder /app/target/release/bitcoin-matcher /app/bitcoin-matcher

# Change ownership
RUN chown appuser:appuser /app/bitcoin-matcher

# Switch to app user
USER appuser

# Set default environment variables
ENV RUST_LOG=info
ENV BUCKET_NAME=""
ENV THREADS=4
ENV BATCH_SIZE=1000
ENV NETWORK=mainnet
ENV REPORT_INTERVAL=30

# Expose any ports if needed (none for this app)
# EXPOSE 8080

# Health check
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD pgrep bitcoin-matcher || exit 1

# Run the application
CMD ["./bitcoin-matcher", \
     "--bucket", "${BUCKET_NAME}", \
     "--threads", "${THREADS}", \
     "--batch-size", "${BATCH_SIZE}", \
     "--network", "${NETWORK}", \
     "--report-interval", "${REPORT_INTERVAL}"]