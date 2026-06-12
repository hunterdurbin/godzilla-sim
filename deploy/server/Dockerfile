# Dedicated game server image. Build context expects the exported server
# binary at build/server/ (export the "Linux Server" preset first):
#
#   godot --headless --export-release "Linux Server" build/server/godzilla_tcg_server.x86_64
#   docker build -f deploy/server/Dockerfile -t godzilla-tcg-server .
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libfontconfig1 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY build/server/godzilla_tcg_server.x86_64 ./server.x86_64
RUN chmod +x ./server.x86_64
# 12091 = game (WebSocket), 12092 = HTTP status + public room listing
EXPOSE 12091 12092
CMD ["./server.x86_64", "--headless", "--", "--server", "--port=12091"]
