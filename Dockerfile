# The campus router server: Python server + the C routing engine, in one small image.
#
#   docker build -t ucsc-router .
#   docker run --rm -p 8000:8000 ucsc-router      # then open http://localhost:8000
#
# Hosting platforms (Render, Fly.io, Cloud Run, ...) run this file as is and set PORT.

FROM python:3.12-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY engine/ engine/
RUN make -C engine route

FROM python:3.12-slim
# zoneinfo needs a time zone database, which the slim image does not include
RUN pip install --no-cache-dir tzdata \
    && useradd --create-home --uid 10001 app
WORKDIR /app
COPY --from=build /src/engine/route engine/route
COPY server/ server/
COPY data-pipeline/room_parser.py data-pipeline/room_parser.py
COPY data/ data/
COPY graph/ graph/
COPY web/ web/
USER app
# 0.0.0.0 so the container is reachable; this also turns Claude photo reading off (see server.py)
ENV HOST=0.0.0.0 PORT=8000
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/healthz' % os.environ.get('PORT', '8000'), timeout=4)"
CMD ["python", "server/server.py"]
