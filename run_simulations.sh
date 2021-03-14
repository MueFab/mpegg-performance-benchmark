#!/usr/bin/env bash

set -e
set -o pipefail
set -u

readonly self="${0}"
readonly self_name="${self##*/}"

readonly git_root_dir="$(git rev-parse --show-toplevel)"




# Usage -----------------------------------------------------------------------

num_threads="1" # NB: does not apply to gzip and Quip!
work_dir="${git_root_dir}/tmp"

print_usage () {
    echo "usage: ${self_name} [options]"
    echo ""
    echo "options:"
    echo "  -h, --help                     print this help"
    echo "  -@, --num_threads NUM_THREADS  number of threads (does not apply to gzip and Quip) (default: ${num_threads})"
    echo "  -w, --work_dir WORK_DIR        work directory (default: ${work_dir})"
}

while [[ "${#}" -gt 0 ]]; do
    case ${1} in
        -h|--help) print_usage; exit 1;;
        -@|--num_threads) num_threads="${2}"; shift;;
        -w|--work_dir) work_dir="${2}"; shift;;
        *) echo "[${self_name}] error: unknown parameter passed: ${1}"; print_usage; exit 1;;
    esac
    shift
done

echo "[${self_name}] number of threads: ${num_threads}"
echo "[${self_name}] work directory: ${work_dir}"




# Setup -----------------------------------------------------------------------

# Work directory
if [[ -e "${work_dir}" ]]; then
    echo "[${self_name}] error: cannot create work directory '${work_dir}': file exists"
    exit 1
fi
mkdir "${work_dir}"

# Tools directory
readonly tools_dir="${git_root_dir}/tools"

# Input files
#   --> The input file paths must be absolute paths, or relative to the
#       location of this script.
readarray -t fastq_gz_files < "${git_root_dir}/test/fastq_gz_files.txt"
readarray -t bam_files < "${git_root_dir}/test/bam_files.txt"
readarray -t ref_files < "${git_root_dir}/test/ref_files.txt"
# readarray -t fastq_files < "${git_root_dir}/fastq_files.txt"
# readarray -t sam_files < "${git_root_dir}/sam_files.txt"
# readarray -t ref_files < "${git_root_dir}/ref_files.txt"

# Tools
readonly deez="${tools_dir}/deez-1.9/deez"
readonly dsrc="${tools_dir}/dsrc-2.00/dsrc"
readonly gzip="/usr/bin/gzip"
readonly samtools="${tools_dir}/samtools-1.11/install/bin/samtools"
readonly quip="${tools_dir}/quip-1.1.8/install/bin/quip"
readonly time="/usr/bin/time"




# The roundtrip function ------------------------------------------------------

function do_roundtrip () {
    name_=${1}
    id_=${2}
    num_threads_=${3}
    compress_cmd_=${4}
    decompress_cmd_=${5}
    input_=${6}

    printf "[%s] %-15s %10s @ %d thread(s)    %s\n" "${self_name}" "compressing:" "${name_}" "${num_threads_}" "${input_}"
    timed_compress_cmd_="${time} --verbose --output ${input_}.${id_}.time_compress.txt ${compress_cmd_}"
    eval "${timed_compress_cmd_}" || ( echo "[${self_name}] ${name_} compression error (proceeding)" && true )

    printf "[%s] %-15s %10s @ %d thread(s)    %s\n" "${self_name}" "decompressing:" "${name_}" "${num_threads_}" "${input_}"
    timed_decompress_cmd_="${time} --verbose --output ${input_}.${id_}.time_decompress.txt ${decompress_cmd_}"
    eval "${timed_decompress_cmd_}" || ( echo "[${self_name}] ${name_} decompression error (proceeding)" && true )

    wc --bytes "${input_}.${id_}" > "${input_}.${id_}.size.txt"
}




# Unaligned -------------------------------------------------------------------

for g in "${fastq_gz_files[@]}"; do

    # Unpack *.fastq.gz to *.fastq
    echo "[${self_name}] unpacking: ${g}"
    f=$(basename "${g%.*}")
    f="${work_dir}/${f}"
    "${gzip}" --decompress --stdout "${g}" > "${f}"

    # DSRC 2
    name="DSRC 2"
    id="dsrc-2"
    do_roundtrip \
        "${name}" \
        "${id}" \
        "${num_threads}" \
        "${dsrc} c -t${num_threads} ${f} ${f}.${id}" \
        "${dsrc} d -t${num_threads} ${f}.${id} ${f}.${id}.fastq" \
        "${f}"
    rm "${f}.${id}" "${f}.${id}.fastq"

    # gzip
    name="gzip"
    id="gzip"
    do_roundtrip \
        "${name}" \
        "${id}" \
        "1" \
        "${gzip} --stdout ${f} > ${f}.${id}" \
        "${gzip} --decompress --stdout ${f}.${id} > ${f}.${id}.fastq" \
        "${f}"
    rm "${f}.${id}" "${f}.${id}.fastq"

    # Quip
    name="Quip"
    id="qp"
    do_roundtrip \
        "${name}" \
        "${id}" \
        "1" \
        "${quip} ${f}" \
        "${quip} --decompress --stdout ${f}.${id} > ${f}.${id}.fastq" \
        "${f}"
    rm "${f}.${id}" "${f}.${id}.fastq"

    # Delete temporary *.fastq file
    rm "${f}"

done




# Aligned ---------------------------------------------------------------------

for ((i=0; i<${#bam_files[@]}; i++)); do

    bam=${bam_files[i]}
    ref=${ref_files[i]}

    # Unpack *.bam to *.sam
    echo "[${self_name}] unpacking: ${bam}"
    # sam="" # trim '.bam' and append '.sam'
    sam=$(basename "${bam%.*}.sam")
    sam="${work_dir}/${sam}"
    "${samtools}" view -@ "${num_threads}" -h "${bam}" -o "${sam}"

    # BAM
    name="BAM"
    id="bam"
    do_roundtrip \
        "${name}" \
        "${id}" \
        "${num_threads}" \
        "${samtools} view -@ ${num_threads} -b -h ${sam} -o ${sam}.${id}" \
        "${samtools} view -@ ${num_threads} -h ${sam}.${id} -o ${sam}.${id}.sam" \
        "${sam}"
    rm "${sam}.${id}" "${sam}.${id}.sam"

    # CRAM 3.0
    name="CRAM 3.0"
    id="cram-3.0"
    do_roundtrip \
        "${name}" \
        "${id}" \
        "${num_threads}" \
        "${samtools} view -@ ${num_threads} -C -h ${sam} -T ${ref} -o ${sam}.${id}" \
        "${samtools} view -@ ${num_threads} -h ${sam}.${id} -o ${sam}.${id}.sam" \
        "${sam}"
    rm "${sam}.${id}" "${sam}.${id}.sam"

    # DeeZ
    name="DeeZ"
    id="deez"
    do_roundtrip \
        "${name}" \
        "${id}" \
        "${num_threads}" \
        "${deez} --threads ${num_threads} --reference ${ref} ${sam} --output ${sam}.${id}" \
        "${deez} --threads ${num_threads} --reference ${ref} ${sam}.${id} --output ${sam}.${id}.sam --header" \
        "${sam}"
    rm "${sam}.${id}" "${sam}.${id}.sam"

    # Delete temporary *.sam file
    rm "${sam}"

done
