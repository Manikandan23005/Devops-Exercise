# Multi-stage build for slim security footprint
FROM python:3.10-slim AS builder

WORKDIR /build

COPY app/requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Final stage
FROM python:3.10-slim

WORKDIR /app

# Copy installed libraries from builder stage
COPY --from=builder /root/.local /root/.local
COPY app/ /app/

ENV PATH=/root/.local/bin:$PATH
ENV FLASK_ENV=production
ENV PORT=8080

EXPOSE 8080

# Create a non-privileged user and group for running the server securely
RUN groupadd -g 1000 appgroup && \
    useradd -r -u 1000 -g appgroup appuser && \
    chown -R appuser:appgroup /app

USER appuser

CMD ["python", "app.py"]
