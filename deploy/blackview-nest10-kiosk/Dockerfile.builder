FROM ubuntu:24.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bash bc binutils build-essential bzip2 ca-certificates cpio curl file findutils git gzip \
    libncurses-dev locales make patch perl python3 rsync sed tar unzip wget xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen C.UTF-8
ENV LANG=C.UTF-8
