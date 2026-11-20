# =============================================================================
# Dockerfile — Container image for iBIOM CropMapping & Pasture-Livestock WKUBE
# =============================================================================
FROM rocker/geospatial:4.4.1

LABEL description="iBIOM European Pasture, Livestock & Crop Mapping WKUBE Routine"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      libopenblas-dev liblapack-dev ca-certificates git curl jq \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY init.R /app/init.R
RUN Rscript /app/init.R

COPY . /app

# Clean any host-compiled shared libraries and install vendored external/cascade-core natively
RUN if [ -d /app/external/cascade-core ]; then \
      rm -f /app/external/cascade-core/src/*.so /app/external/cascade-core/src/*.o /app/external/cascade-core/src/*.dll \
      && R CMD INSTALL /app/external/cascade-core; \
    fi

# Ensure unprivileged cluster runtime uid can create output/ symlinks and user_config.R under /app
RUN chmod +x /app/entrypoint.sh /app/tools/build_id.sh /app/tools/gen_config.R /app/tools/stage_wkube_inputs.sh \
 && chmod -R a+rwX /app

# Compute deterministic build fingerprint and fail build if hashing breaks
RUN sh /app/tools/build_id.sh /app > /app/.build_id && chmod a+r /app/.build_id \
 && echo "iBIOM build id: $(cat /app/.build_id)" \
 && case "$(cat /app/.build_id)" in \
      [0-9a-f]??????????[0-9a-f]) : ;; \
      *) echo "FATAL: build id is '$(cat /app/.build_id)', not a hex hash" >&2; exit 1 ;; \
    esac

# Setup entrypoint shim on PATH because WKUBE invokes commands via `sh -c`
RUN printf '#!/bin/sh\nexec /app/entrypoint.sh "$@"\n' > /usr/local/bin/entrypoint.sh \
 && chmod 0755 /usr/local/bin/entrypoint.sh \
 && ln -s /usr/local/bin/entrypoint.sh /usr/local/bin/ibiom-run

# Pin BLAS/OpenMP thread pools to 1 to prevent thread oversubscription on shared nodes
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    VECLIB_MAXIMUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    CASCADE_CORE_PATH=installed \
    APP_DIR=/app

ENTRYPOINT ["/app/entrypoint.sh"]

