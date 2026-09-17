# Lab 02 — demo application image
#
# ★ The key line is the ENTRYPOINT: `opentelemetry-instrument` is the zero-code
#   launcher from opentelemetry-distro. It configures the SDK, the OTLP exporter
#   and auto-instrumentation for FastAPI/requests/logging WITHOUT any code
#   changes in main.py. That is why main.py only imports opentelemetry.trace
#   (the API) and never the SDK.
#
# See ../../09-sdks-and-instrumentation.md

FROM python:3.12-slim

WORKDIR /app

# Install deps first so this layer caches independently of app code.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ★ `opentelemetry-bootstrap` reads the installed packages and installs the
#   matching instrumentation libraries. -a install = do it now, at build time.
#   Running it at container start instead would slow every boot and require
#   network access at runtime.
RUN opentelemetry-bootstrap -a install

COPY main.py .

# ★ Non-root, matching what a restricted Kubernetes PSA profile expects.
RUN useradd --create-home --uid 10001 appuser
USER appuser

EXPOSE 8000

# All OTel configuration comes from environment variables (set in compose),
# which is the twelve-factor way and means the SAME image runs unchanged in
# dev, staging and production. See ../../09-sdks-and-instrumentation.md
ENTRYPOINT ["opentelemetry-instrument"]
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
