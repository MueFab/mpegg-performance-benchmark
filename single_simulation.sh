#!/bin/bash

#SBATCH --mail-user=muenteferi@tnt.uni-hannover.de # only <UserName>@tnt.uni-hannover.de is allowed as mail address
#SBATCH --mail-type=ALL             # Eine Mail wird bei Job-Start/Ende versendet

#SBATCH --time=3-0             # Maximale Laufzeit des Jobs, bis Slurm diesen abbricht (HH:MM:SS)
#SBATCH --partition=cpu_normal     # Partition auf der gerechnet werden soll. Ohne Angabe des Parameters wird auf der
                                    #   Default-Partition gerechnet. Es können mehrere angegeben werden, mit Komma getrennt.
#SBATCH --tasks-per-node=8          # Reservierung von 4 CPUs pro Rechenknoten
#SBATCH --mem=64G                   # Reservierung von 10GB RAM

set -e
set -o pipefail

source /home/muenteferi/nobackup/anaconda/etc/profile.d/conda.sh
conda activate genie

set -u

readonly self="${0}"
readonly self_name="${self##*/}"

git_root_dir="$(git rev-parse --show-toplevel)"




# Usage -----------------------------------------------------------------------

num_threads="1"
test_run=false
genie_run=false
work_dir="/localstorage/${USER}/tmp/genie_sim_data"
result_dir="${git_root_dir}/tmp"
tool=""
file1=""
file2=""


print_usage () {
    echo "usage: ${self_name} [options]"
    echo ""
    echo "options:"
    echo "  -h, --help                     print this help"
    echo "  -@, --num_threads NUM_THREADS  number of threads (does not apply to pigz and Quip) (default: ${num_threads})"
    echo "  -w, --work_dir WORK_DIR        work directory (default: ${work_dir})"
    echo "  -r, --result_dir               result directory (default: ${result_dir})"
    echo "  -t, --tool"
    echo "  -f, --fileOne"
    echo "  -g, --fileTwo"
}

while [[ "${#}" -gt 0 ]]; do
    case ${1} in
        -h|--help) print_usage; exit 1;;
        -@|--num_threads) num_threads="${2}"; shift;;
        -w|--work_dir) work_dir="${2}"; shift;;
        -t|--tool) tool="${2}"; shift;;
        -f|--fileOne) file1="${2}"; shift;;
        -g|--fileTwo) file2="${2}"; shift;;
        -r|--result_dir) result_dir="${2}"; shift;;
        *) echo "[${self_name}] error: unknown parameter passed: ${1}"; print_usage; exit 1;;
    esac
    shift
done

host_name=`hostname`
echo "[${self_name}] host: ${host_name}"
echo "[${self_name}] number of threads: ${num_threads}"
echo "[${self_name}] work directory: ${work_dir}"
echo "[${self_name}] result directory: ${result_dir}"
echo "[${self_name}] file 1: ${file1}"
echo "[${self_name}] file 2: ${file2}"
echo "[${self_name}] tool: ${tool}"
echo "[${self_name}] job ID: $SLURM_JOB_ID"

# Tools directory
readonly tools_dir="${git_root_dir}/tools"

# Tools
readonly genie="${tools_dir}/genie/build/bin/genie"
readonly deez="${tools_dir}/deez/deez"
readonly dsrc="${tools_dir}/dsrc/dsrc"
readonly pigz="${tools_dir}/pigz/pigz"
readonly mstcom="${tools_dir}/mstcom/mstcom"
readonly samtools="${tools_dir}/samtools/install/bin/samtools"
readonly genozip="${tools_dir}/genozip/genozip"
readonly pgrc="${tools_dir}/PgRC/build/PgRC"
readonly fastore_dir="${tools_dir}/FaStore/bin"
readonly fastore_comp="${tools_dir}/FaStore/scripts/fastore_compress.sh"
readonly fastore_decomp="${tools_dir}/FaStore/scripts/fastore_decompress.sh"
readonly time="/usr/bin/time"

mkdir -p "$work_dir"
cd "$work_dir"


# The roundtrip function ------------------------------------------------------

function do_roundtrip () {
    name_=${1}
    id_=${2}
    num_threads_=${3}
    compress_cmd_=${4}
    decompress_cmd_=${5}
    input_=${6}

    printf "[%s] %-15s %10s @ %d thread(s)    %s\n" "${self_name}" "compressing:" "${name_}" "${num_threads_}" "${input_}"
    echo "$compress_cmd_"
    timed_compress_cmd_="${time} --verbose --output ${input_}.${id_}.time_compress.txt ${compress_cmd_}"
    eval "${timed_compress_cmd_}" || ( echo "[${self_name}] ${name_} compression error (proceeding)" && true )
    
    printf "[%s] %-15s %10s @ %d thread(s)    %s\n" "${self_name}" "decompressing:" "${name_}" "${num_threads_}" "${input_}"
    echo "$decompress_cmd_"
    timed_decompress_cmd_="${time} --verbose --output ${input_}.${id_}.time_decompress.txt ${decompress_cmd_}"
    eval "${timed_decompress_cmd_}" || ( echo "[${self_name}] ${name_} decompression error (proceeding)" && true )

    if [[ $name == "fastore" ]]; then
        wc --bytes "${input_}.${id_}.cmeta" > "${input_}.${id_}.size.txt"
        wc --bytes "${input_}.${id_}.cdata" >> "${input_}.${id_}.size.txt"
    else
        wc --bytes "${input_}.${id_}" > "${input_}.${id_}.size.txt"
    fi

    in_path=${input_%/*}
    mv "${input_}.${id_}.size.txt" "${result_dir}"
    mv "${input_}.${id_}.time_compress.txt" "${result_dir}"
    mv "${input_}.${id_}.time_decompress.txt" "${result_dir}"
}

function do_fastq_paired () {
    f="${1}"
    f2="${2}"
    tool="$3"

    if [[ "$tool" == "mstcom" ]]; then
        name="mstcom"
        id="mstcom"
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${mstcom} e -t ${num_threads} -i ${f} -f ${f2} -o ${f}.${id}" \
            "${mstcom} d -i ${f}.${id} -o ${f}.${id}.fastq" \
            "${f}"
        rm "${f}.${id}" "${f}.${id}.fastq_1" "${f}.${id}.fastq_2"
        return 0
    elif [[ "$tool" == "pgrc" ]]; then
        name="pgrc"
        id="pgrc"
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${pgrc} -t ${num_threads} -i ${f} ${f2} ${f}.${id}" \
            "${pgrc} -t ${num_threads} -d ${f}.${id}" \
            "${f}"
        rm "${f}.${id}" "${f}.pgrc_out_1" "${f}.pgrc_out_2"
        return 0
    elif [[ "$tool" == "fastore" ]]; then
        name="fastore"
        id="fastore"
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "bash ${fastore_comp} --lossless --in ${f} --pair ${f2} --out ${f}.$id --threads ${num_threads}" \
            "bash ${fastore_decomp} --in ${f}.$id --out ${f}.$id.fastq --pair ${f2}.$id.fastq --threads ${num_threads}" \
            "${f}"
        rm "${f}.${id}.cdata" "${f}.${id}.cmeta" "${f}.${id}.fastq" "${f2}.${id}.fastq"
        return 0
    elif [[ "$tool" == "genie_ga" ]]; then
        # Genie
        name="Genie_GA"
        id="genie_ga.mgb"
        ${genie} transcode-fastq --input-file "${f}" --input-suppl-file "${f2}" --output-file "${f}"."${id}".mgrec --threads "${num_threads}" -f
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${genie} run --threads ${num_threads} --input-file ${f}.${id}.mgrec --output-file ${f}.${id} -f" \
            "${genie} run --threads ${num_threads} --input-file ${f}.${id} --output-file ${f}.${id}.dec.mgrec -f" \
            "${f}"
        rm "${f}.${id}" "${f}.${id}.json" "${f}.${id}.mgrec" "${f}.${id}.dec.mgrec"
        return 0
    elif [[ "$tool" == "genie_ll" ]]; then
        # Genie
        name="Genie_LL"
        id="genie_ll.mgb"
        ${genie} transcode-fastq --input-file "${f}" --input-suppl-file "${f2}" --output-file "${f}"."${id}".mgrec --threads "${num_threads}" -f
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${genie} run --low-latency --threads ${num_threads} --input-file ${f}.${id}.mgrec --output-file ${f}.${id} -f" \
            "${genie} run --threads ${num_threads} --input-file ${f}.${id} --output-file ${f}.${id}.dec.mgrec -f" \
            "${f}"
        rm "${f}.${id}" "${f}.${id}.json" "${f}.${id}.mgrec" "${f}.${id}.dec.mgrec"
        return 0
    else
        echo "No tool $tool for paired fastq files."
    fi
}

function do_fastq () {
    f="${1}"
    unpaired="${2}"
    tool="$3"

    if [ "${unpaired}" == "True" ]; then
        if [[ "$tool" == "fastore" ]]; then
            name="fastore"
            id="fastore"
            do_roundtrip \
                "${name}" \
                "${id}" \
                "${num_threads}" \
                "bash ${fastore_comp} --lossless --in ${f} --out ${f}.$id --threads ${num_threads}" \
                "bash ${fastore_decomp} --in ${f}.$id --out ${f}.$id.fastq --threads ${num_threads}" \
                "${f}"
            rm "${f}.${id}.cdata" "${f}.${id}.cmeta" "${f}.${id}.fastq"
            return 0
        elif [[ "$tool" == "pgrc" ]]; then
            name="pgrc"
            id="pgrc"
            do_roundtrip \
                "${name}" \
                "${id}" \
                "${num_threads}" \
                "${pgrc} -t ${num_threads} -i ${f} ${f}.${id}" \
                "${pgrc} -t ${num_threads} -d ${f}.${id}" \
                "${f}"
            rm "${f}.${id}" "${f}.pgrc_out"
            return 0
        elif [[ "$tool" == "mstcom" ]]; then
            name="mstcom"
            id="mstcom"
            do_roundtrip \
                "${name}" \
                "${id}" \
                "${num_threads}" \
                "${mstcom} e -t ${num_threads} -i ${f} -o ${f}.${id}" \
                "${mstcom} d -i ${f}.${id} -o ${f}.${id}.fastq" \
                "${f}"
            rm "${f}.${id}" "${f}.${id}.fastq"
            return 0
        elif [[ "$tool" == "genie_ga" ]]; then
            # Genie
            name="Genie_GA"
            id="genie_ga.mgb"
            ${genie} transcode-fastq --input-file "${f}" --output-file "${f}"."${id}".mgrec --threads "${num_threads}" -f
            do_roundtrip \
                "${name}" \
                "${id}" \
                "${num_threads}" \
                "${genie} run --threads ${num_threads} --input-file ${f}.${id}.mgrec --output-file ${f}.${id} -f" \
                "${genie} run --threads ${num_threads} --input-file ${f}.${id} --output-file ${f}.${id}.dec.mgrec -f" \
                "${f}"
            rm "${f}.${id}" "${f}.${id}.json" "${f}.${id}.mgrec" "${f}.${id}.dec.mgrec"
            return 0
        elif [[ "$tool" == "genie_ll" ]]; then
            # Genie
            name="Genie_LL"
            id="genie_ll.mgb"
            ${genie} transcode-fastq --input-file "${f}" --output-file "${f}"."${id}".mgrec --threads "${num_threads}" -f
            do_roundtrip \
                "${name}" \
                "${id}" \
                "${num_threads}" \
                "${genie} run --low-latency --threads ${num_threads} --input-file ${f}.${id}.mgrec --output-file ${f}.${id} -f" \
                "${genie} run --threads ${num_threads} --input-file ${f}.${id} --output-file ${f}.${id}.dec.mgrec -f" \
                "${f}"
            rm "${f}.${id}" "${f}.${id}.json" "${f}.${id}.mgrec" "${f}.${id}.dec.mgrec"
            return 0
        fi
    fi
    if [[ "$tool" == "dsrc" ]]; then
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
        return 0
    elif [[ "$tool" == "pigz" ]]; then
        # pigz
        name="pigz"
        id="pigz"
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${pigz} --processes ${num_threads} --stdout ${f} > ${f}.${id}" \
            "${pigz} --processes ${num_threads} --decompress --stdout ${f}.${id} > ${f}.${id}.fastq" \
            "${f}"
        rm "${f}.${id}" "${f}.${id}.fastq"
        return 0
    elif [[ "$tool" == "genozip" ]]; then
       # Genozip
        name="genozip"
        id="genozip"
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${genozip} -@ ${num_threads} --no-test ${f} -o ${f}.${id}" \
            "${genozip} -@ ${num_threads} -d ${f}.${id} -o ${f}.${id}.fastq" \
            "${f}"
        rm "${f}.${id}" "${f}.${id}.fastq"
        return 0
    fi
}


function do_bam () {
    f="${1}"
    ref_file="${2}"
    tool="$3"
    if [[ "$tool" == "bam" ]]; then
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
    elif [[ "$tool" == "cram" ]]; then
         # CRAM 3.1 normal
        name="CRAM 3.1-normal"
        id="cram-3.1-normal"
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${samtools} view -@ ${num_threads} -C -h ${f} -T ${ref_file} --output-fmt-option version=3.1 -o ${f}.${id}" \
            "${samtools} view -@ ${num_threads} -h ${f}.${id} -o ${f}.${id}.sam" \
            "${f}"
        rm "${f}.${id}" "${f}.${id}.sam" "${ref_file}.fai"
    elif [[ "$tool" == "deez" ]]; then
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
        rm "${f}.${id}" "${f}.${id}.sam" "${ref_file}.fai"
    elif [[ "$tool" == "genozip" ]]; then
        name="genozip"
        id="genozip"
        ${genozip} --make-reference "$ref_file"
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${genozip} -@ ${num_threads} ${f} --no-test --reference $ref_file -o ${f}.${id}" \
            "${genozip} -@ ${num_threads} -d ${f}.${id} --reference $ref_file -o ${f}.${id}.sam" \
            "${f}"
        rm "${f}.${id}" "${f}.${id}.sam" "${ref_file%%.*}.ref.genozip"
    elif [[ "${ref_file}" != "" && "$tool" == "genie_ref" ]]; then
        name="Genie_Ref"
        id="genie_ref.mgb"
        "${samtools}" sort -n -o "${f}"."${id}".sorted.sam -@ "${num_threads}" "${f}"
        ${genie} transcode-sam --threads "${num_threads}" --input-file "${f}"."${id}".sorted.sam --output-file "${f}"."${id}".mgrec -r "${ref_file}" -w "${work_dir}" -f
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${genie} run --threads ${num_threads} --input-file ${f}.${id}.mgrec --output-file ${f}.${id} --input-ref-file ${ref_file} -f" \
            "${genie} run --threads ${num_threads} --input-file ${f}.${id} --output-file ${f}.${id}.dec.mgrec -f" \
            "${f}"
        rm "${f}.${id}" "${f}.${id}.mgrec" "${f}.${id}.dec.mgrec" "${f}"."${id}".sorted.sam
    elif [[ "$tool" == "genie_la" ]]; then
        name="Genie_LA"
        id="genie_la.mgb"
        "${samtools}" sort -n -o "${f}"."${id}".sorted.sam -@ "${num_threads}" "${f}"
        ${genie} transcode-sam --threads "${num_threads}" --input-file "${f}"."${id}".sorted.sam --output-file "${f}"."${id}".mgrec --no_ref -w "${work_dir}" -f
        do_roundtrip \
            "${name}" \
            "${id}" \
            "${num_threads}" \
            "${genie} run --threads ${num_threads} --input-file ${f}.${id}.mgrec --output-file ${f}.${id} -f" \
            "${genie} run --threads ${num_threads} --input-file ${f}.${id} --output-file ${f}.${id}.dec.mgrec -f" \
            "${f}"
        rm "${f}.${id}" "${f}.${id}.mgrec" "${f}.${id}.dec.mgrec" "${f}"."${id}".sorted.sam
    else
        echo "No tool $tool for bam files."
    fi
}

uncompressed_file=""

function sync_file () {
    file_src=${1}
    echo "F: $file_src"
    DATA_TARGET=tmp/genie_sim_data
    bash -c "[ -d \"/localstorage/${USER}/${DATA_TARGET}\" ] || mkdir -p \"/localstorage/${USER}/${DATA_TARGET}\""
    target_file="/localstorage/${USER}/${DATA_TARGET}/${file_src##*/}"
   # /usr/bin/python /usr/bin/withlock -w 86400 "/localstorage/${USER}/sync.lock" rsync -avHAPSx "$file_src" "/localstorage/${USER}/${DATA_TARGET}/${file_src##*/}"
    RSYNC_COMMAND=$(/usr/bin/python /usr/bin/withlock -w 86400 "/localstorage/${USER}/sync.lock" rsync -aEim "$file_src" "/localstorage/${USER}/${DATA_TARGET}/${file_src##*/}")
    echo "Downloading: $file_src to $target_file"
    if [[ ${target_file##*.} == "gz" ]]; then
        uncompressed_file=${target_file%.*}
    elif [[ ${target_file##*.} == "bam" ]]; then
        uncompressed_file="${target_file%.*}.sam"    
    fi
    if [ -n "${RSYNC_COMMAND}" ]; then
        if [[ ${target_file##*.} == "gz" ]]; then
            echo "File changed! decompressing to $uncompressed_file"
            "${pigz}" --processes ${num_threads} --decompress --stdout "$target_file" > "$uncompressed_file"
        elif [[ ${target_file##*.} == "bam" ]]; then
            echo "File changed! decompressing to $uncompressed_file"
            "${samtools}" view -@ "${num_threads}" -h "$target_file" -o "$uncompressed_file"    
        fi
    else
        echo "File $target_file already up to date!"
    fi
} 

if [[ "$tool" == "" ]]; then
    echo "No tool specified"
    exit 1
fi

if [[ ! -f "$file1" ]]; then
    echo "File 1 is invalid"
    exit 1
fi

sync_file "${file1}"
file1="$uncompressed_file"

if [[ "$file2" != "" ]]; then
    if [[ ! -f "$file2" ]]; then
        echo "File 2 is invalid"
        exit 1
    fi
    sync_file "${file2}"
    file2="$uncompressed_file"
fi

echo "Final files: $file1; $file2"

if [[ ${file1##*.} == "fastq" && ${file2##*.} == "fastq" ]]; then
    echo "Paired fastq!"
    do_fastq "${file1}" "False" "${tool}"
    do_fastq "${file2}" "False" "${tool}"
    do_fastq_paired "${file1}" "${file2}" "${tool}"
elif [[ ${file1##*.} == "fastq" && ${file2} == "" ]]; then
    echo "Unpaired fastq!"
    do_fastq "${file1}" "True" "${tool}"
elif [[ ${file1##*.} == "sam" ]]; then
    do_bam "${file1}" "${file2}" "${tool}"
else
    echo "Error: Unknown file extensions."
    exit 1
fi
