#!/bin/bash
# =====================================================================
# VCexomes | germline SNP and INDEL pipeline for whole-exome sequencing
# Genomics and Diabetes Unit, INCLIVA (Valencia, Spain)
# Author: Celeste Moya-Valera (cmoya@incliva.es)
#
# Usage: bash VCexomes.sh [-n] <config.cfg>
#        -n   dry run, print the sbatch commands without submitting them
#
# The launcher reads the configuration file, submits the steps enabled in it
# as SLURM array jobs and chains each step to the previous one with
# --dependency=afterok. Array sizes are taken from the corresponding FOF, so
# they never need to be edited inside the step scripts.
# =====================================================================

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=src/common.sh
source "${repo_dir}/src/common.sh"

dry_run=false

usage() {
    echo "Usage: $0 [-n] <config.cfg>"
    echo
    echo "Options:"
    echo "  -n    Dry run: print the sbatch commands without submitting them."
    echo "  -h    Display this help message and exit."
}

while getopts ":nh" opt; do
    case ${opt} in
        n ) dry_run=true ;;
        h ) usage; exit 0 ;;
        \? ) echo "Invalid option: -$OPTARG" >&2; usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

config=${1:-}
[[ -n "$config" ]] || { usage; exit 1; }
config=$(cd "$(dirname "$config")" && pwd)/$(basename "$config")
load_config "$config"

require_var workspace
require_var ref
require_var log_dir
mkdir -p "$log_dir" "$joint_dir"

printf '%b\n' "${MAGENTA}__     ______                                     ${NC}"
printf '%b\n' "${MAGENTA}\\ \\   / / ___|  _____  _____  _ __ ___   ___  ___ ${NC}"
printf '%b\n' "${MAGENTA} \\ \\ / / |     / _ \\ \\/ / _ \\| '_ \` _ \\ / _ \\/ __|${NC}"
printf '%b\n' "${MAGENTA}  \\ V /| |___ |  __/>  < (_) | | | | | |  __/\\__ \\${NC}"
printf '%b\n' "${MAGENTA}   \\_/  \\____| \\___/_/\\_\\___/|_| |_| |_|\\___||___/${NC}"
echo ""
echo "Genomics and Diabetes Unit (Valencia, Spain)"
echo "Version: 1.0"
echo "Author: Celeste Moya (cmoya@incliva.es)"
echo "========================================================================"
echo "Project:        ${project}"
echo "Workspace:      ${workspace}"
echo "Data directory: ${data_dir}"
echo "Reference:      ${ref}"
echo "Logs:           ${log_dir}"
echo "Configuration:  ${config}"
echo "========================================================================"
echo ""

previous_job=""

# array_from_fof <fof file>
# Builds a zero-based array specification with the configured throttle.
array_from_fof() {
    local fof=$1 n
    require_file "$fof"
    n=$(grep -c '' "$fof")
    [[ "$n" -gt 0 ]] || die "Empty FOF: ${fof}"
    printf '0-%s%%%s\n' "$((n - 1))" "$max_concurrent"
}

# submit <tag> <script> <array spec or empty> [script arguments...]
submit() {
    local tag=$1 script=$2 array_spec=$3
    shift 3

    local cmd=(sbatch --parsable
        --job-name="VCx_${tag}"
        --output="${log_dir}/${tag}_%A_%a.log"
        --error="${log_dir}/${tag}_%A_%a.err")

    [[ -n "$array_spec" ]] && cmd+=(--array="$array_spec")
    [[ -n "$previous_job" ]] && cmd+=(--dependency="afterok:${previous_job}")
    cmd+=("${repo_dir}/${script}" "$config" "$@")

    if $dry_run; then
        echo "${cmd[*]}"
        return
    fi

    local job_id
    job_id=$("${cmd[@]}")
    previous_job=$job_id
    log_info "Submitted ${tag} as job ${job_id}${array_spec:+ (array ${array_spec})}"
}

if [ "$STEP01" = "True" ]; then
    submit "s01_qctrim" "scripts/step01_qc_trim.batch" "$(array_from_fof "$raw_fastq_fof")"
fi

if [ "$STEP02" = "True" ]; then
    submit "s02_multiqc" "scripts/step02_multiqc.batch" ""
fi

if [ "$STEP03" = "True" ]; then
    submit "s03_align" "scripts/step03_alignment.batch" "$(array_from_fof "$raw_fastq_fof")"
fi

if [ "$STEP04" = "True" ]; then
    submit "s04_readgroups" "scripts/step04_add_readgroups.batch" "$(array_from_fof "$bam_raw_fof")"
fi

if [ "$STEP05" = "True" ]; then
    submit "s05_mergebam" "scripts/step05_merge_bam.batch" "$(array_from_fof "$samples_fof")"
fi

if [ "$STEP06" = "True" ]; then
    submit "s06_markdup" "scripts/step06_markdup.batch" "$(array_from_fof "$bam_merged_fof")"
fi

if [ "$STEP07" = "True" ]; then
    submit "s07_bqsr" "scripts/step07_bqsr.batch" "$(array_from_fof "$bam_rmdp_fof")"
fi

if [ "$STEP08" = "True" ]; then
    submit "s08_hc" "scripts/step08_haplotypecaller.batch" "$(array_from_fof "$bam_bqsr_fof")"
fi

if [ "$STEP09" = "True" ]; then
    submit "s09_combine" "scripts/step09_combine_gvcfs.batch" "$(array_from_fof "$shard_list")"
fi

if [ "$STEP10" = "True" ]; then
    submit "s10_genotype" "scripts/step10_genotype_gvcfs.batch" "$(array_from_fof "$shard_list")"
fi

if [ "$STEP11" = "True" ]; then
    submit "s11_vqsr" "scripts/step11_vqsr.batch" ""
fi

if [ "$STEP12" = "True" ]; then
    submit "s12_vep" "scripts/step12_vep_annotation.batch" ""
fi

echo ""
if $dry_run; then
    log_info "Dry run finished, nothing was submitted."
else
    log_info "All enabled steps have been submitted. Track them with: squeue -u \$USER"
fi
