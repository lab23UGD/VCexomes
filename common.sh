#!/bin/bash
# VCexomes | shared helper functions
# Author: Celeste Moya-Valera (cmoya@incliva.es)
#
# This file is sourced by every step script and is not meant to be executed
# directly. It provides logging, configuration loading, input validation and
# the FOF/array-index helpers shared across the pipeline.

BOLD='\033[1m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info()  { printf '[%s] [INFO]  %s\n' "$(date '+%F %T')" "$*"; }
log_warn()  { printf '[%s] [WARN]  %s\n' "$(date '+%F %T')" "$*"; }
log_error() { printf '[%s] [ERROR] %s\n' "$(date '+%F %T')" "$*" >&2; }
die()       { log_error "$*"; exit 1; }

# step_header <title>
step_header() {
    printf '\n%b\n' "${BOLD}=========================================================${NC}"
    printf '%b\n'   "${BOLD} VCexomes | ${1}${NC}"
    printf '%b\n\n' "${BOLD}=========================================================${NC}"
}

# load_config <config.cfg>
load_config() {
    local config=${1:-}
    [[ -n "$config" ]] || die "No configuration file given. Usage: sbatch <script> <config.cfg>"
    [[ -f "$config" ]] || die "Configuration file not found: ${config}"
    # shellcheck disable=SC1090
    source "$config"
}

require_var()  { local name=$1; [[ -n "${!name:-}" ]] || die "Missing configuration variable: ${name}"; }
require_file() { [[ -f "$1" ]] || die "File not found: $1"; }
require_dir()  { [[ -d "$1" ]] || die "Directory not found: $1"; }

# array_task_id
# Returns the SLURM array index and fails if the script was not submitted as an array job.
array_task_id() {
    [[ -n "${SLURM_ARRAY_TASK_ID:-}" ]] || die "This script must be submitted as a SLURM array job"
    printf '%s\n' "$SLURM_ARRAY_TASK_ID"
}

# fof_line <fof file> <zero-based index>
# Returns the entry of a file of files (FOF) for a given array index.
fof_line() {
    local fof=$1 index=$2 line
    require_file "$fof"
    line=$(sed -n "$((index + 1))p" "$fof")
    [[ -n "$line" ]] || die "No entry at index ${index} in ${fof}"
    printf '%s\n' "$line"
}

# sample_id <path>
# Sample identifier: first underscore-separated field of the file name.
sample_id() { basename "$1" | cut -d '_' -f 1; }

# run_id <path> [suffix]
# Run identifier (sample_batch_flowcell_lane): file name without the read suffix.
run_id() { basename "$1" "${2:-_1.fq.gz}"; }

# make_sample_dirs <base directory>
# Creates the per-sample bookkeeping tree used by the Picard and GATK steps.
make_sample_dirs() {
    local base=$1
    mkdir -p "${base}/logs" "${base}/metrics" "${base}/_status" "${base}/intermediate" "${base}/plots"
}

# mark_status <status directory> <START|DONE|FAILED> <label>
mark_status() {
    mkdir -p "$1"
    touch "${1}/${2}_${3}_$(date +'%Y-%m-%d_%H-%M-%S').log"
}

# skip_if_done <output file> <message>
# Returns 0 (skip) when the expected output already exists.
skip_if_done() {
    if [[ -s "$1" ]]; then
        log_info "$2"
        return 0
    fi
    return 1
}
