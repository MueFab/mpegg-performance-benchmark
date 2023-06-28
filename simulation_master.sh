#!/usr/bin/env bash

set -e
set -o pipefail
set -u

readonly self="${0}"
readonly self_name="${self##*/}"

git_root_dir="$(git rev-parse --show-toplevel)"


# Usage -----------------------------------------------------------------------

num_threads="8"
test_run=false
work_dir="/localstorage/${USER}/tmp/genie_sim_data"
result_dir="${git_root_dir}/tmp"

mkdir -p "$result_dir"
mkdir -p "$work_dir"

print_usage () {
    echo "usage: ${self_name} [options]"
    echo ""
    echo "options:"
    echo "  -h, --help                     print this help"
    echo "  -@, --num_threads NUM_THREADS  number of threads (does not apply to pigz and Quip) (default: ${num_threads})"
    echo "  -n, --test_run                 perform test run"
    echo "  -g, --genie_only               Perform genie roundtrips only" 
    echo "  -w, --work_dir WORK_DIR        work directory (default: ${work_dir})"
}

while [[ "${#}" -gt 0 ]]; do
    case ${1} in
        -h|--help) print_usage; exit 1;;
        -@|--num_threads) num_threads="${2}"; shift;;
        -n|--test_run) test_run=true;;
        -w|--work_dir) work_dir="${2}"; shift;;
        *) echo "[${self_name}] error: unknown parameter passed: ${1}"; print_usage; exit 1;;
    esac
    shift
done

if [[ "${test_run}" == true ]]; then
    work_dir="$git_root_dir"
    readarray -t fastq_gz_files < "${git_root_dir}/test/fastq_gz_files.txt"
    readarray -t bam_files < "${git_root_dir}/test/bam_files.txt"
else
    readarray -t fastq_gz_files < "${git_root_dir}/fastq_gz_files.txt"
    readarray -t bam_files < "${git_root_dir}/bam_files.txt"
fi

readarray -t fastq_tools < "${git_root_dir}/fastq_tools.txt"
readarray -t bam_tools < "${git_root_dir}/bam_tools.txt"


uncompressed_file=""

function uncompressed_file_name () {
    file_src=${1}
    if [[ ${file_src##*.} == "gz" ]]; then
        uncompressed_file=${file_src%.*}
    elif [[ ${file_src##*.} == "bam" ]]; then
        uncompressed_file="${file_src%.*}.sam"
    fi
}


# Aligned -------------------------------------------------------------------

 for g in "${bam_files[@]}"; do
    arrIN=(${g//;/ })

    bam_file=${arrIN[0]}

    if [ ${#arrIN[@]} == "2" ]; then
        ref_file=${arrIN[1]}
    else
        ref_file=""
    fi
    for tool in "${bam_tools[@]}"; do
	if [[ "$tool" == "" ]]; then
		break
	fi
        base_name=$(basename ${bam_file})
        echo "********* Start Simulation **********************"
	uncompressed_file_name "$base_name"
        echo "Submitted: $tool:$uncompressed_file"
        sbatch -o "$result_dir/$uncompressed_file.$tool.log" -J "$tool:$uncompressed_file" "${git_root_dir}"/single_simulation.sh -f "${bam_file}" -g "${ref_file}" -t "$tool" -w "$work_dir" -@ "$num_threads" -r "$result_dir"
        sleep 1
        echo "********* Finish Simulation **********************"
    done
 done

# Unaligned -------------------------------------------------------------------

 for g in "${fastq_gz_files[@]}"; do
    arrIN=(${g//;/ })
    file=${arrIN[0]}

    if [ ${#arrIN[@]} == "1" ]; then
        for tool in "${fastq_tools[@]}"; do
	    if [[ "$tool" == "" ]]; then
                break
            fi

            base_name=$(basename ${file})
            echo "********* Start Simulation **********************"
            uncompressed_file_name "$base_name"
            echo "Submitted: $tool:$uncompressed_file"
            sbatch -o "$result_dir/$uncompressed_file.$tool.log" -J "$tool:$uncompressed_file" "${git_root_dir}"/single_simulation.sh -f "${file}" -t "$tool" -w "$work_dir" -@ "$num_threads" -r "$result_dir"
            sleep 1
            echo "********* Finish Simulation **********************"
        done
    else
        file2=${arrIN[1]}

        for tool in "${fastq_tools[@]}"; do
	    if [[ "$tool" == "" ]]; then
                break
            fi

            base_name=$(basename ${file})
            echo "********* Start Simulation **********************"
            uncompressed_file_name "$base_name"
	    echo "Submitted: $tool:$uncompressed_file"
            sbatch -o "$result_dir/$uncompressed_file.$tool.log" -J "$tool:$uncompressed_file" "${git_root_dir}"/single_simulation.sh -f "${file}" -g "${file2}" -t "$tool" -w "$work_dir" -@ "$num_threads" -r "$result_dir"
            sleep 1
            echo "********* Finish Simulation **********************"
        done
    fi
 done
