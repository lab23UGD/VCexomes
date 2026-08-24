#!/bin/bash
# VCexomes | build the file-of-files lists used by the step scripts
#
# Each step reads the list produced by the previous one, so the lists have to
# be rebuilt between blocks of steps. This script writes them into fof_dir.
#
# Usage: bash src/make_fof.sh <config.cfg> <list>
#   list: samples | bam_raw | bam_merged | bam_rmdp | bam_bqsr | gvcf | all
#
# The raw_fastq list is not built here because the FASTQ deliveries live
# outside the workspace and were assembled from several delivery batches.
#
# Author: Celeste Moya-Valera (cmoya@incliva.es)

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=common.sh
source "${repo_dir}/src/common.sh"
load_config "${1:-}"

target=${2:-all}
mkdir -p "$fof_dir"

build_samples()    { find "$data_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort > "$samples_fof"; }
build_bam_raw()    { find "$data_dir" -path "*/raw_bam/*.bam" ! -name "*rgmod*" ! -name "*merged*" | sort > "$bam_raw_fof"; }
build_bam_merged() { find "$data_dir" -path "*/raw_bam/*_merged_files.bam" | sort > "$bam_merged_fof"; }
build_bam_rmdp()   { find "$data_dir" -path "*/raw_bam/*_rgmod.merged.sort.rmdp.bam" | sort > "$bam_rmdp_fof"; }
build_bam_bqsr()   { find "$data_dir" -path "*/raw_bam/*_rgmod.merged.sort.rmdp.BQSR.bam" | sort > "$bam_bqsr_fof"; }
build_gvcf()       { find "$data_dir" -path "*/raw_vcf_snps_indels/*_raw.snps.indels.g.vcf.gz" | sort > "$gvcf_fof"; }

case "$target" in
    samples)    build_samples ;;
    bam_raw)    build_bam_raw ;;
    bam_merged) build_bam_merged ;;
    bam_rmdp)   build_bam_rmdp ;;
    bam_bqsr)   build_bam_bqsr ;;
    gvcf)       build_gvcf ;;
    all)        build_samples; build_bam_raw; build_bam_merged; build_bam_rmdp; build_bam_bqsr; build_gvcf ;;
    *)          die "Unknown list: ${target}" ;;
esac

log_info "Lists written to ${fof_dir}"
wc -l "${fof_dir}"/*.fof

log_warn "The gVCF list is not coverage filtered. Before step 09, keep only the"
log_warn "samples with mean coverage above ${min_mean_coverage}x (see qc/coverage_plots.py)."
