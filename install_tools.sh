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

# htslib
git clone https://github.com/samtools/htslib.git
cd htslib
git checkout tags/1.13
git submodule update --init --recursive
autoreconf -i
mkdir build
./configure --prefix="${PWD}/build"
make --jobs
make install
cd ..

# genie
git clone https://github.com/mitogen/genie.git
mv genie genie-develop
cd genie-develop
git checkout develop
mkdir build
cd build
cmake .. -DHTSlib_INCLUDE_DIR=../../htslib/build/include -DHTSlib_LIBRARY=../../htslib/build/lib/libhts.so
make --jobs
cd ..
cd ..
genie="$(pwd)/genie-develop/build/bin/genie"
genie_version="develop" # Genie does not have a '-v|--version' flag.

# SPRING
git clone https://github.com/shubhamchandak94/Spring
mv Spring spring-1.0.1
cd spring-1.0.1
git checkout tags/v1.0.1
mkdir build
cd build
cmake ..
make --jobs
cd ..
cd ..
spring="$(pwd)/spring-1.0.1/build/spring"
spring_version="1.0.1" # SPRING does not have a '-v|--version' flag.

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
wget http://sun.aei.polsl.pl/REFRESH/dsrc/downloads/2.0rc2/linux/dsrc
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
git clone https://github.com/dcjones/quip.git
mv quip quip-1.1.8
cd quip-1.1.8
git checkout tags/v1.1.8
sed --in-place 's/AM_INIT_AUTOMAKE(\[foreign -Wall -Werror\])/AM_INIT_AUTOMAKE(\[foreign -Wall -Werror subdir-objects\])/' configure.ac  # Need subdir-objects option to compile on some systems
autoreconf --install
./configure --prefix="$(pwd)/install/"
make --jobs
make install
cd ..
quip="$(pwd)/quip-1.1.8/install/bin/quip"
quip_version="$(${quip} --version | cut --delimiter='-' --fields=1 | cut --delimiter=' ' --fields=2)"

echo "[${self_name}] Genie ${genie_version}: ${genie}"
echo "[${self_name}] Spring ${spring_version}: ${spring}"
echo "[${self_name}] DeeZ ${deez_version}: ${deez}"
echo "[${self_name}] DSRC ${dsrc_version}: ${dsrc}"
echo "[${self_name}] gzip ${gzip_version}: ${gzip}"
echo "[${self_name}] Samtools ${samtools_version}: ${samtools}"
echo "[${self_name}] Quip ${quip_version}: ${quip}"
