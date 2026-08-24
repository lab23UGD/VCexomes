# VCexomes

Germline SNP and INDEL calling pipeline for whole-exome sequencing data,
following the GATK Best Practices on a SLURM cluster.

Developed at the Genomics and Diabetes Unit, INCLIVA Biomedical Research
Institute (Valencia, Spain).

This repository is a record of the analysis performed on the FISDM4 cohort:
2,198 exomes captured with the IDT xGen Exome Hybridisation Panel v2 and
aligned to GRCh38 with decoy contigs. The configuration file holds the
parameters and reference data used for that run, and `docs/VERSIONS.md` the
software versions. It documents the analysis as it was carried out rather than
providing a turnkey re-run, see Scope and limitations.

## Pipeline details

| Field | Value |
|---|---|
| **Name** | VCexomes |
| **Version** | 1.0 |
| **Author** | Celeste Moya-Valera (cmoya@incliva.es) |
| **Reference build** | GRCh38, `Homo_sapiens_assembly38.fasta` (with decoy) |
| **Capture panel** | IDT xGen Exome Hybridisation Panel v2 |
| **Scheduler** | SLURM |

## Workflow

<img width="916" height="562" alt="vcexomes" src="https://github.com/user-attachments/assets/4ec9d1a3-fa19-409b-90dc-1814ecee4cc0" />



| Step | Script | Tool | Output |
|---|---|---|---|
| **01** | `step01_qc_trim.batch` | FastQC, Trim Galore | Trimmed FASTQ per sequencing run, pre- and post-trimming QC |
| **02** | `step02_multiqc.batch` | MultiQC | Cohort-level QC reports |
| **03** | `step03_alignment.batch` | bwa-mem2, SAMtools | Sorted BAM per run, on-target coverage |
| **04** | `step04_add_readgroups.batch` | Picard AddOrReplaceReadGroups | BAM with read groups from the sequencing manifest |
| **05** | `step05_merge_bam.batch` | Picard MergeSamFiles | One BAM per sample |
| **06** | `step06_markdup.batch` | Picard SortSam, MarkDuplicates | Coordinate-sorted BAM without PCR duplicates |
| **07** | `step07_bqsr.batch` | GATK BQSR | Recalibrated BAM and covariate plots |
| **08** | `step08_haplotypecaller.batch` | GATK HaplotypeCaller | Per-sample gVCF |
| **09** | `step09_combine_gvcfs.batch` | GATK CombineGVCFs | Cohort gVCF per shard |
| **10** | `step10_genotype_gvcfs.batch` | GATK GenotypeGVCFs | Genotyped VCF per shard |
| **11** | `step11_vqsr.batch` | GATK VariantRecalibrator, ApplyVQSR | Recalibrated cohort VCF |
| **12** | `step12_vep_annotation.batch` | BCFtools, Ensembl VEP | Annotated cohort VCF |

Steps 01 to 08 run one array task per sequencing run or per sample. Steps 09
and 10 run one array task per shard, where a shard is a primary-assembly contig
or the group of decoy contigs. Steps 02, 11 and 12 are single jobs.

Two QC utilities sit outside the sequential workflow: `qc/collect_hs_metrics.batch`
computes the hybrid selection metrics on the recalibrated BAM files, and
`qc/coverage_plots.py` draws the cumulative coverage curves used to decide which
samples enter the joint genotyping.

## Repository layout

```
.
├── VCexomes.sh                 # Launcher: reads the config and submits the enabled steps
├── config/
│   └── fisdm4.cfg              # Parameters and paths of the FISDM4 run
├── scripts/                    # The twelve pipeline steps
├── qc/
│   ├── collect_hs_metrics.batch
│   └── coverage_plots.py
├── src/
│   ├── common.sh               # Logging, validation and FOF helpers
│   ├── make_fof.sh             # Builds the file-of-files lists
│   └── autoadapter.sh          # Adapter detection utility, not called by any step
├── fof/                        # Generated lists (not tracked, see fof/README.md)
├── deprecated/                 # Original scripts kept for the record
└── docs/
    ├── workflow.png
    ├── VERSIONS.md             # Software versions used for the FISDM4 run
    └── CHANGES.md              # Every deviation from the original scripts
```

## Requirements

Versions used for the FISDM4 run are listed in `docs/VERSIONS.md`. The tools
are available through the cluster modules (`biotools`, `gatk`, `R`,
`singularity`):

* FastQC and MultiQC
* Trim Galore with Cutadapt
* bwa-mem2 and SAMtools
* Picard (as a jar, path set in the configuration file)
* GATK 4.6
* BCFtools
* R, for the BQSR and VQSR plots
* Ensembl VEP, run offline from a Singularity image
* Python 3 with pandas, numpy, scipy, matplotlib and seaborn, for the QC plots

Reference data: the GRCh38 decoy FASTA with its indexes, the GATK resource
bundle (HapMap, Omni, 1000 Genomes high-confidence SNPs, dbSNP 146, Mills gold
standard indels), the capture panel BED and interval lists, and a 20-column
sequencing manifest with one row per run.

## Configuration

All parameters live in a single file. Copy `config/fisdm4.cfg`, adjust the
paths and set the `STEP01` to `STEP12` flags to `True` or `False`.

Two entries are marked `TODO` because they were not recorded in the original
scripts: `picard_jar`, which was inherited from the environment, and
`raw_fastq_dir`, the root of the FASTQ deliveries.

## Usage

```bash
# Check what would be submitted, without submitting anything
bash VCexomes.sh -n config/fisdm4.cfg

# Submit the enabled steps
bash VCexomes.sh config/fisdm4.cfg
```

The launcher chains each step to the previous one with
`--dependency=afterok`, so a whole block can be queued at once.

Each step reads its input from the list produced by the previous step, and
those lists have to exist at submission time. The pipeline is therefore meant
to be launched in three blocks, rebuilding the lists in between:

```bash
# Block 1: QC, trimming and alignment
bash VCexomes.sh config/fisdm4.cfg          # STEP01 to STEP03
bash src/make_fof.sh config/fisdm4.cfg all

# Block 2: BAM processing and per-sample calling
bash VCexomes.sh config/fisdm4.cfg          # STEP04 to STEP08
bash src/make_fof.sh config/fisdm4.cfg gvcf
# keep only the samples above the coverage threshold in gvcf_more_20x_cov.fof

# Block 3: joint genotyping, recalibration and annotation
bash VCexomes.sh config/fisdm4.cfg          # STEP09 to STEP12
```

Every step is idempotent: it checks whether its output already exists and exits
without repeating the work, so an interrupted array can be resubmitted as is.

Individual steps can also be submitted by hand:

```bash
sbatch --array=0-2197%100 scripts/step06_markdup.batch config/fisdm4.cfg
```

## Output

Per-sample results are written under `data_dir/<sample>/`:

```
<sample>/
├── trim_fastq/          # Trimmed reads
├── QC/{preQC,postQC}/   # FastQC reports
└── raw_bam/
    ├── cov_files/       # samtools depth output over the capture targets
    ├── <run>.bam                                    # step 03
    ├── <run>.rgmod.bam                              # step 04
    ├── <sample>_merged_files.bam                    # step 05
    ├── <sample>_rgmod.merged.sort.rmdp.bam          # step 06
    ├── <sample>_rgmod.merged.sort.rmdp.BQSR.bam     # step 07
    └── <sample>/{logs,metrics,plots,_status}/       # per-sample bookkeeping
```

Cohort-level files are written to `joint_dir`, ending in
`VCexomes_raw_allSamples_snps_indels_tags_type_ann.vcf.gz`.
