ARG BASE=python:3.13-slim
FROM ${BASE}
LABEL org.opencontainers.image.source="https://github.com/GuardSkill/CFOpt"
LABEL org.opencontainers.image.description="Private CFOpt Mihomo subscription backend"
WORKDIR /app
COPY --chown=1000:1000 --chmod=0444 server.py /app/server.py
ENV CFOPT_BIND=0.0.0.0 CFOPT_PORT=8787 CFOPT_DATA_DIR=/data PYTHONDONTWRITEBYTECODE=1
USER 1000:1000
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8787/health', timeout=3).read()"]
CMD ["python", "/app/server.py"]
