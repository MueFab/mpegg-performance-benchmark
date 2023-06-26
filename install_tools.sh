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


install_pigz () {(
    set -e
    git clone https://github.com/madler/pigz.git
    cd pigz
    git checkout tags/v2.7
    make --jobs
    cd ..
    pigz="$(pwd)/pigz/pigz"
    pigz_version="$(${pigz} --version | head --lines=1 | cut --delimiter=' ' --fields=2)"
    echo "[${self_name}] pigz ${pigz_version}: ${pigz}"
)}

install_htslib () {(
    set -e
    git clone https://github.com/samtools/htslib.git
    cd htslib
    git checkout tags/1.17
    git submodule update --init --recursive
    autoreconf -i
    mkdir build
    ./configure --prefix="${PWD}/build"
    make --jobs
    make install
    cd ..
)}

install_genie () {(
    set -e
    git clone https://github.com/mitogen/genie.git
    genie_version="578e939" # Genie does not have a '-v|--version' flag.
    cd genie
    git checkout $genie_version
    mkdir build
    cd build
    if [ -d ../../htslib/build/lib ]; then
        DHTSlib_LIBRARY="../../htslib/build/lib/libhts.so"
    else
        DHTSlib_LIBRARY="../../htslib/build/lib64/libhts.so"
    fi
    cmake .. -DHTSlib_INCLUDE_DIR=../../htslib/build/include -DHTSlib_LIBRARY=$DHTSlib_LIBRARY
    make --jobs
    cd ..
    cd ..
    genie="$(pwd)/genie/build/bin/genie"
    echo "[${self_name}] Genie ${genie_version}: ${genie}"
)}


install_deez () {(
    set -e
    git clone https://github.com/sfu-compbio/deez.git
    deez_version="92cd56b" # DeeZ does not have a '-v|--version' flag.
    cd deez
    git checkout $deez_version
    make --jobs
    cd ..
    deez="$(pwd)/deez/deez"
    echo "[${self_name}] DeeZ ${deez_version}: ${deez}"
)}

install_dsrc () {(
    set -e
    mkdir dsrc
    cd dsrc
    wget http://sun.aei.polsl.pl/REFRESH/dsrc/downloads/2.0rc2/linux/dsrc
    chmod u+x dsrc
    cd ..
    dsrc="$(pwd)/dsrc/dsrc"
    dsrc_version="$(${dsrc} --version 2>&1 | head --lines=2 | tail --lines=1 | cut --delimiter=' ' --fields=2 || true)"
    echo "[${self_name}] DSRC ${dsrc_version}: ${dsrc}"
)}

install_samtools () {(
    set -e
    git clone https://github.com/samtools/samtools.git
    cd samtools
    git checkout tags/1.17
    mkdir install
    autoheader
    autoconf -Wno-syntax
    ./configure --prefix="$(pwd)/install/"
    make --jobs
    make install
    cd ..
    samtools="$(pwd)/samtools/install/bin/samtools"
    samtools_version="$(${samtools} --version | head --lines=1 | cut --delimiter=' ' --fields=2)"
    echo "[${self_name}] Samtools ${samtools_version}: ${samtools}"
)}

install_genozip () {(
    set -e
    git clone https://github.com/divonlan/genozip.git
    cd genozip
    git checkout tags/genozip-15.0.4
    make --jobs
    cd ..
    genozip="$(pwd)/genozip/genozip"
    genozip_version="$(${genozip} --version | head --lines=1 | cut --delimiter='=' --fields=2 | cut --delimiter=' ' --fields=1)"
    echo "[${self_name}] Genozip ${genozip_version}: ${genozip}"
)}

install_mstcom () {(
    set -e
    git clone https://github.com/yuansliu/mstcom.git mstcom
    cd mstcom
    mstcom_version="8eb5ab2"
    git checkout $mstcom_version
    # Patch Makefile
    sed -i 's/Wno-used-function/Wno-unused-function/' Makefile
    sed -i 's/\$(CC) \$(CPPFLAGS) \$(LIBS) \$^ -o \$@/\$(CC) \$(CPPFLAGS) \$^ \$(LIBS) -o \$@/' Makefile
    make --jobs
    cd ..
    mstcom="$(pwd)/mstcom/mstcom"
    echo "[${self_name}] mstcom ${mstcom_version}: ${mstcom}"
)}

install_pgrc () {(
    set -e
    git clone https://github.com/kowallus/PgRC
    pgrc_version="1.2"
    cd PgRC
    git checkout tags/v${pgrc_version}
    mkdir build
    cd build
    cmake ..
    make --jobs PgRC
    cd ../..
    pgrc="$(pwd)/PgRC/build/PgRC"
    echo "[${self_name}] PgRC ${pgrc_version}: ${pgrc}"
)}

install_single() {
    echo "Installing $1..."
    install_$1 &> "${tools_dir}/install_$1.log"
    if [[ $? -ne 0 ]]; then
        echo "Installation of $1 failed!"
    else
        echo "Installed $1 successfully!"
    fi
}


install_tools () {
    set +e
    install_single "pigz" &
    install_single "htslib" &
    install_single "deez" &
    install_single "dsrc" &
    install_single "pgrc" &
    install_single "mstcom" &
    install_single "genozip" &
    wait $(jobs -p)
    
    install_single "genie" &
    install_single "samtools" &
    wait $(jobs -p)
    set -e
}

install_tools

