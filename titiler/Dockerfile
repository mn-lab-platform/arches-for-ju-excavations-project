ARG TITILER_TAG=1.2.0
FROM ghcr.io/developmentseed/titiler:${TITILER_TAG}

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates build-essential pkg-config libssl-dev rustc cargo cmake nasm \
      autoconf automake libtool \
    && rm -rf /var/lib/apt/lists/*

ENV PYO3_USE_ABI3_FORWARD_COMPATIBILITY=1

RUN python -m venv /opt/iiif \
 && /opt/iiif/bin/pip install -U pip setuptools wheel maturin \
 && /opt/iiif/bin/pip install --no-cache-dir "uvicorn[standard]" \
 && /opt/iiif/bin/pip install --no-cache-dir \
      "titiler.image @ git+https://github.com/developmentseed/titiler-image.git@main" \
 && /opt/iiif/bin/pip check

COPY titiler/app.py /opt/iiif/app.py
WORKDIR /opt/iiif
ENV PATH="/opt/iiif/bin:${PATH}"
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]