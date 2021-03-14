#!/usr/bin/env bash

set -e
set -o pipefail
set -u

readonly self="${0}"
readonly self_name="${self##*/}"

# Usage
if [[ ${#} -ne 1 ]]; then echo "usage: ${0} <prefix>"; exit 1; fi
prefix="${1}"
if [[ ${prefix} != */ ]]; then prefix="${prefix}/"; fi # append '/' if needed
readonly git_root_dir="$(git rev-parse --show-toplevel)"

# Prefix prepend
safe_replacement=$(printf '%s\n' "${prefix}" | sed 's/[\&/]/\\&/g')
sed --in-place "s/^/${safe_replacement}/g" "${git_root_dir}/bam_files.txt"
echo "[${self_name}] updated paths: ${git_root_dir}/bam_files.txt"
sed --in-place "s/^/${safe_replacement}/g" "${git_root_dir}/fastq_gz_files.txt"
echo "[${self_name}] updated paths: ${git_root_dir}/fastq_gz_files.txt"
