#!/usr/bin/env bash

set -e
set -o pipefail
set -x

# DeeZ
sudo apt-get install \
    libbz2-dev \
    libcurl4-openssl-dev \
    libssl-dev

# Samtools
sudo apt-get install \
    autoconf \
    automake \
    gcc \
    make \
    perl \
    libbz2-dev \
    libcurl4-openssl-dev \
    liblzma-dev \
    libncurses5-dev
    libssl-dev \
    zlib1g-dev
