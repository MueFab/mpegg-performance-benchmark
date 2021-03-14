#!/usr/bin/env bash

set -e
set -o pipefail
set -u

# Usage
if [[ ${#} -ne 1 ]]; then echo "usage: ${0} <prefix>"; exit 1; fi
readonly prefix="${1}"
if [[ ${prefix} != */ ]]; then prefix="${prefix}/"; fi # append '/' if needed
readonly git_root_dir="$(git rev-parse --show-toplevel)"

# Prefix prepend
safe_replacement=$(printf '%s\n' "${prefix}" | sed 's/[\&/]/\\&/g')
sed --in-place "s/^/${safe_replacement}/g" "${git_root_dir}/bam_files.txt"
sed --in-place "s/^/${safe_replacement}/g" "${git_root_dir}/fastq_gz_files.txt"
