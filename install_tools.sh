#!/usr/bin/env bash

set -e
set -o pipefail
set -u

readonly self="${0}"
readonly self_name="${self##*/}"

readonly git_root_dir="$(git rev-parse --show-toplevel)"
readonly tools_dir="${git_root_dir}/tools"
mkdir "${tools_dir}"
cd "${tools_dir}"

# DeeZ
git clone https://github.com/sfu-compbio/deez.git deez-1.9
cd deez-1.9
git checkout 92cd56b
make --jobs
cd ..
deez="$(pwd)/deez-1.9/deez"
deez_version="1.9" # DeeZ does not have a '-v|--version' flag.

# DSRC
mkdir dsrc-2.00
cd dsrc-2.00
wget sun.aei.polsl.pl/REFRESH/dsrc/downloads/2.0rc2/linux/dsrc
chmod u+x dsrc
cd ..
dsrc="$(pwd)/dsrc-2.00/dsrc"
dsrc_version="$(${dsrc} --version 2>&1 | head --lines=2 | tail --lines=1 | cut --delimiter=' ' --fields=2 || true)"

# gzip
gzip="$(command -v gzip)"
gzip_version="$(${gzip} --version | head --lines=1 | cut --delimiter=' ' --fields=2)"

# Samtools
wget https://github.com/samtools/samtools/releases/download/1.11/samtools-1.11.tar.bz2
tar --extract --file=samtools-1.11.tar.bz2
rm samtools-1.11.tar.bz2
cd samtools-1.11
./configure --prefix="$(pwd)/install/"
make --jobs
make install
cd ..
samtools="$(pwd)/samtools-1.11/install/bin/samtools"
samtools_version="$(${samtools} --version | head --lines=1 | cut --delimiter=' ' --fields=2)"

# Quip
wget https://homes.cs.washington.edu/~dcjones/quip/quip-1.1.8.tar.gz
tar --extract --file=quip-1.1.8.tar.gz
rm quip-1.1.8.tar.gz
cd quip-1.1.8
./configure --prefix="$(pwd)/install/"
make --jobs
make install
cd ..
quip="$(pwd)/quip-1.1.8/install/bin/quip"
quip_version="$(${quip} --version | cut --delimiter=' ' --fields=2)"

echo "[${self_name}] DeeZ ${deez_version}: ${deez}"
echo "[${self_name}] DSRC ${dsrc_version}: ${dsrc}"
echo "[${self_name}] gzip ${gzip_version}: ${gzip}"
echo "[${self_name}] Samtools ${samtools_version}: ${samtools}"
echo "[${self_name}] Quip ${quip_version}: ${quip}"
