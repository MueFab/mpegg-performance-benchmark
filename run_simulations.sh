#!/usr/bin/env bash

set -e
set -o pipefail
set -u




# Usage -----------------------------------------------------------------------

if [[ ${#} -ne 1 ]]; then
    echo "Usage: ${0} <num_threads>"
    exit 1
fi




# Setup -----------------------------------------------------------------------

result_files=()

readonly git_root_dir="$(git rev-parse --show-toplevel)"
readonly tools_dir="${git_root_dir}/tools"

# Parallelism
readonly num_threads="${1}" # NB: does not apply to gzip and Quip!

# Input files
#   --> The input file paths must be absolute paths, or relative to the
#       location of this script.
readarray -t fastq_files < "${git_root_dir}/test/fastq_files.txt"
readarray -t sam_files < "${git_root_dir}/test/sam_files.txt"
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

    printf "%s %-10s %-15s @ %d thread(s)    %s\n" "---" "${name_}" "compress" "${num_threads_}" "${input_}"
    timed_compress_cmd_="${time} --verbose --output ${input_}.${id_}.time_compress.txt ${compress_cmd_}"
    eval "${timed_compress_cmd_}" || ( echo "--- ${name_} compression error (proceeding)" && true )

    printf "%s %-10s %-15s @ %d thread(s)    %s\n" "---" "${name_}" "decompress" "${num_threads_}" "${input_}"
    timed_decompress_cmd_="${time} --verbose --output ${input_}.${id_}.time_decompress.txt ${decompress_cmd_}"
    eval "${timed_decompress_cmd_}" || ( echo "--- ${name_} decompression error (proceeding)" && true )

    wc --bytes "${input_}.${id_}" > "${input_}.${id_}.size.txt"
    result_files=("${result_files[@]}" "${input_}.${id_}.time_decompress.txt")
    result_files=("${result_files[@]}" "${input_}.${id_}.time_decompress.txt")
    result_files=("${result_files[@]}" "${input_}.${id_}.size.txt")
}




# Unaligned -------------------------------------------------------------------

for f in "${fastq_files[@]}"; do

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

done




# Aligned ---------------------------------------------------------------------

for ((i=0; i<${#sam_files[@]}; i++)); do

    sam=${sam_files[i]}
    ref=${ref_files[i]}

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

done




# Result files ----------------------------------------------------------------

readonly result_files_file="${git_root_dir}/result_files.txt"
truncate --size=0 "${result_files_file}"
for f in "${result_files[@]}"; do
    echo "${f}" >> "${result_files_file}"
done
