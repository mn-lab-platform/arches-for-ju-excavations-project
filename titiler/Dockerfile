FROM ghcr.io/developmentseed/titiler:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates build-essential pkg-config libssl-dev rustc cargo \
    && rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/iiif \
 && /opt/iiif/bin/pip install -U pip setuptools wheel maturin uvicorn[standard] fastapi \
 && /opt/iiif/bin/pip install --no-cache-dir "titiler.image @ git+https://github.com/developmentseed/titiler-image.git@main"

# Copy your custom application
COPY titiler/app.py /opt/iiif/app.py
WORKDIR /opt/iiif

ENV PATH="/opt/iiif/bin:${PATH}"
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]