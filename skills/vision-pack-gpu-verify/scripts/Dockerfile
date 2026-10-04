FROM ubuntu:24.04

ARG ROCM_DATE=20261004
ARG VISION_PACK_DATE=20261004

ENV DEBIAN_FRONTEND=noninteractive
ENV ROCM_PATH=/opt/rocm

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build python3-dev python3-pip python3-venv \
    ffmpeg patchelf curl ca-certificates libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# The SDK tarball and DEBs must be mounted at /sdk.tar.gz and /debs.
# Use the prepare_verify_run.sh helper to launch this image correctly.

COPY verify_in_container.sh /verify_in_container.sh
CMD ["bash", "/verify_in_container.sh"]
