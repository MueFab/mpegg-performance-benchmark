#!/usr/bin/env bash

set -e
set -o pipefail
set -u

readonly self="${0}"
readonly self_name="${self##*/}"

readonly git_root_dir="$(git rev-parse --show-toplevel)"




# Usage -----------------------------------------------------------------------

num_threads="1"
test_run=false
genie_run=false
work_dir="${git_root_dir}/tmp"

print_usage () {
    echo "usage: ${self_name} [options]"
    echo ""
    echo "options:"
    echo "  -h, --help                     print this help"
    echo "  -@, --num_threads NUM_THREADS  number of threads (does not apply to gzip and Quip) (default: ${num_threads})"
    echo "  -n, --test_run                 perform test run"
    echo "  -g, --genie_only               Perform genie roundtrips only" 
    echo "  -w, --work_dir WORK_DIR        work directory (default: ${work_dir})"
}

while [[ "${#}" -gt 0 ]]; do
    case ${1} in
        -h|--help) print_usage; exit 1;;
        -@|--num_threads) num_threads="${2}"; shift;;
        -n|--test_run) test_run=true;;
        -g|--genie_only) genie_run=true;;
        -w|--work_dir) work_dir="${2}"; shift;;
        *) echo "[${self_name}] error: unknown parameter passed: ${1}"; print_usage; exit 1;;
    esac
    shift
done

echo "[${self_name}] number of threads: ${num_threads}"
echo "[${self_name}] test run: ${test_run}"
echo "[${self_name}] genie run: ${genie_run}"
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
if [[ "${test_run}" == true ]]; then
    readarray -t fastq_gz_files < "${git_root_dir}/test/fastq_gz_files.txt"
    readarray -t bam_files < "${git_root_dir}/test/bam_files.txt"
else
    readarray -t fastq_gz_files < "${git_root_dir}/fastq_gz_files.txt"
    readarray -t bam_files < "${git_root_dir}/bam_files.txt"
fi

# Tools
readonly spring="${tools_dir}/spring-1.0.1/build/spring"
readonly genie="${tools_dir}/genie-develop/build/bin/genie"
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

function do_fastq_paired () {
    f="${1}"
    f2="${2}"

    if [ $genie_run == false ]
    then
        # SPRING
        name="SPRING"
        id="spring"
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${spring} --compress --num-threads ${num_threads} --input-file ${f} ${f2} --output-file ${f}.${id}" \
            "${spring} --decompress --num-threads ${num_threads} --input-file ${f}.${id} --output-file ${f}.${id}.fastq ${f2}.${id}.fastq" \
            "${f}"
        rm "${f}.${id}" "${f}.${id}.fastq" "${f2}.${id}.fastq"
    fi

    # Genie
    name="Genie_GA"
    id="genie_ga.mgb"
    ${genie} transcode-fastq --input-file ${f} --input-suppl-file ${f2} --output-file ${f}.mgrec --threads ${num_threads}
    do_roundtrip \
        "${name}" \
        "${id}" \
        "${num_threads}" \
        "${genie} run --threads ${num_threads} --input-file ${f}.mgrec --output-file ${f}.${id}" \
        "${genie} run --threads ${num_threads} --input-file ${f}.${id} --output-file ${f}.${id}.mgrec" \
        "${f}"
    rm "${f}.${id}" "${f}.${id}.mgrec" "${f}.mgrec"

    # Genie
    name="Genie_LL"
    id="genie_ll.mgb"
    ${genie} transcode-fastq --input-file ${f} --input-suppl-file ${f2} --output-file ${f}.mgrec --threads ${num_threads}
    do_roundtrip \
        "${name}" \
        "${id}" \
        "${num_threads}" \
        "${genie} run --low-latency --threads ${num_threads} --input-file ${f}.mgrec --output-file ${f}.${id}" \
        "${genie} run --threads ${num_threads} --input-file ${f}.${id} --output-file ${f}.${id}.mgrec" \
        "${f}"
    rm "${f}.${id}" "${f}.${id}.mgrec" "${f}.mgrec"
}

function do_fastq () {
    f="${1}"
    unpaired="${2}"

    if [ ${unpaired} == "True" ]; then
        if [ $genie_run == false ]
        then
            # SPRING
            name="SPRING"
            id="spring"
            do_roundtrip \
                "${name}" \
                "${id}" \
                "${num_threads}" \
                "${spring} --compress --num-threads ${num_threads} --input-file ${f} --output-file ${f}.${id}" \
                "${spring} --decompress --num-threads ${num_threads} --input-file ${f}.${id} --output-file ${f}.${id}.fastq" \
                "${f}"
            rm "${f}.${id}" "${f}.${id}.fastq"
        fi

        # Genie
        name="Genie_GA"
        id="genie_ga.mgb"
        ${genie} transcode-fastq --input-file ${f} --output-file ${f}.mgrec --threads ${num_threads}
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${genie} run --threads ${num_threads} --input-file ${f}.mgrec --output-file ${f}.${id}" \
            "${genie} run --threads ${num_threads} --input-file ${f}.${id} --output-file ${f}.${id}.mgrec" \
            "${f}"
        rm "${f}.${id}" "${f}.${id}.mgrec" "${f}.mgrec"

        # Genie
        name="Genie_LL"
        id="genie_ll.mgb"
        ${genie} transcode-fastq --input-file ${f} --output-file ${f}.mgrec --threads ${num_threads}
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${genie} run --low-latency --threads ${num_threads} --input-file ${f}.mgrec --output-file ${f}.${id}" \
            "${genie} run --threads ${num_threads} --input-file ${f}.${id} --output-file ${f}.${id}.mgrec" \
            "${f}"
        rm "${f}.${id}" "${f}.${id}.mgrec" "${f}.mgrec"
    fi

    if [ $genie_run == false ]
    then

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
    fi
}


function do_bam () {
    f="${1}"
    ref_file="${2}"
    
    if [ ${ref_file} != "" ]; then
        name="Genie_Ref"
        id="genie_ref.mgb"
        "${samtools}" sort -n -o ${f}.sorted.sam -@ ${num_threads} ${f}
        ${genie} transcode-sam --threads ${num_threads} --input-file ${f}.sorted.sam --output-file ${f}.mgrec -r ${ref_file} -w ${work_dir}
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${genie} run --threads ${num_threads} --input-file ${f}.mgrec --output-file ${f}.${id} --input-ref-file ${ref_file} --embedded-ref none" \
            "${genie} run --threads ${num_threads} --input-file ${f}.${id} --output-file ${f}.${id}.mgrec" \
            "${f}"
        rm "${f}.${id}" "${f}.${id}.mgrec" "${f}.mgrec" ${f}.sorted.sam
    fi
    
    name="Genie_LA"
    id="genie_la.mgb"
    "${samtools}" sort -n -o ${f}.sorted.sam -@ ${num_threads} ${f}
    ${genie} transcode-sam --threads ${num_threads} --input-file ${f}.sorted.sam --output-file ${f}.mgrec --no_ref -w ${work_dir}
    do_roundtrip \
        "${name}" \
        "${id}" \
        "${num_threads}" \
        "${genie} run --threads ${num_threads} --input-file ${f}.mgrec --output-file ${f}.${id}" \
        "${genie} run --threads ${num_threads} --input-file ${f}.${id} --output-file ${f}.${id}.mgrec" \
        "${f}"
    rm "${f}.${id}" "${f}.${id}.mgrec" "${f}.mgrec" ${f}.sorted.sam
    
    if [ $genie_run == false ]
    then
        # BAM
        name="BAM"
        id="bam"
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${samtools} view -@ ${num_threads} -b -h ${f} -o ${f}.${id}" \
            "${samtools} view -@ ${num_threads} -h ${f}.${id} -o ${f}.${id}.sam" \
            "${f}"
        rm "${f}.${id}" "${f}.${id}.sam"

        if [ ${ref_file} != "" ]; then
            # CRAM 3.0
            name="CRAM 3.0"
            id="cram-3.0"
            do_roundtrip \
                "${name}" \
                "${id}" \
                "${num_threads}" \
                "${samtools} view -@ ${num_threads} -C -h ${f} -T ${ref_file} -o ${f}.${id}" \
                "${samtools} view -@ ${num_threads} -h ${f}.${id} -o ${f}.${id}.sam" \
                "${f}"
            rm "${f}.${id}" "${f}.${id}.sam"
        else
            # CRAM 3.0
            name="CRAM 3.0"
            id="cram-3.0"
            do_roundtrip \
                "${name}" \
                "${id}" \
                "${num_threads}" \
                "${samtools} view -@ ${num_threads} -O CRAM,embed_ref -h ${f} -o ${f}.${id}" \
                "${samtools} view -@ ${num_threads} -h ${f}.${id} -o ${f}.${id}.sam" \
                "${f}"
            rm "${f}.${id}" "${f}.${id}.sam"
        fi
        
        if [ ${ref_file} != "" ]; then
            # DeeZ
            name="DeeZ"
            id="deez"
            do_roundtrip \
                "${name}" \
                "${id}" \
                "${num_threads}" \
                "${deez} --threads ${num_threads} --reference ${ref_file} ${f} --output ${f}.${id}" \
                "${deez} --threads ${num_threads} --reference ${ref_file} ${f}.${id} --output ${f}.${id}.sam --header" \
                "${f}"
            rm "${f}.${id}" "${f}.${id}.sam"
        else
            # DeeZ
            name="DeeZ"
            id="deez"
            do_roundtrip \
                "${name}" \
                "${id}" \
                "${num_threads}" \
                "${deez} --threads ${num_threads} ${f} --output ${f}.${id}" \
                "${deez} --threads ${num_threads} ${f}.${id} --output ${f}.${id}.sam --header" \
                "${f}"
            rm "${f}.${id}" "${f}.${id}.sam"
        fi
    fi
}

# Aligned -------------------------------------------------------------------

for g in "${bam_files[@]}"; do
    arrIN=(${g//;/ })
    
    bam_file=${arrIN[0]}
    echo "[${self_name}] unpacking: ${bam_file}"
    sam_file=$(basename "${bam_file%.*}.sam")
    sam_file="${work_dir}/${sam_file}"
    "${samtools}" view -@ "${num_threads}" -h "${bam_file}" -o "${sam_file}"

    if [ ${#arrIN[@]} == "2" ]; then
        g=${arrIN[1]}
        echo "[${self_name}] unpacking: ${g}"
        ref_file=$(basename "${g%.*}")
        ref_file="${work_dir}/${ref_file}"
        "${gzip}" --decompress --stdout "${g}" > "${ref_file}"
    else
        ref_file=""
    fi
    do_bam ${sam_file} ${ref_file}
    rm "${sam_file}"
    rm -f "${ref_file}"
done

# Unaligned -------------------------------------------------------------------

for g in "${fastq_gz_files[@]}"; do
    arrIN=(${g//;/ })
    
    # Unpack *.fastq.gz to *.fastq
    g=${arrIN[0]}
    echo "[${self_name}] unpacking: ${g}"
    file=$(basename "${g%.*}")
    file="${work_dir}/${file}"
    "${gzip}" --decompress --stdout "${g}" > "${file}"

    if [ ${#arrIN[@]} == "1" ]; then
        do_fastq "${file}" "True"
        rm "${file}"
    else
        do_fastq "${file}" "False"

        # Unpack *.fastq.gz to *.fastq
        g=${arrIN[1]}
        echo "[${self_name}] unpacking: ${g}"
        file2=$(basename "${g%.*}")
        file2="${work_dir}/${file2}"
        "${gzip}" --decompress --stdout "${g}" > "${file2}"

        do_fastq "${file2}" "False"

        do_fastq_paired "${file}" "${file2}"

        rm "${file}"
        rm "${file2}"
    fi
done
