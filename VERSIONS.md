# Software versions

Versions used for the FISDM4 analysis. Where two versions are listed, both were
present during the analysis; the note explains which step used which.

| Software | Version | Used in |
|---|---|---|
| **Trim Galore** | 0.6.10 | Step 01, adapter and quality trimming |
| **Cutadapt** | 4.9 | Step 01, called by Trim Galore |
| **FastQC** | 0.12.1 | Step 01, pre- and post-trimming QC |
| **MultiQC** | 1.25 | Step 02, cohort-level QC reports |
| **bwa-mem2** | 2.2.1 | Step 03, alignment |
| **SAMtools** | 1.21 | Steps 03 and 06, sorting, indexing and depth |
| **Picard** | 2.18.29 | Steps 04, 05 and 06, read groups, merging and duplicate removal |
| **GATK** | 4.4 and 4.6 | Steps 07 to 11, and the HS metrics QC |
| **BCFtools** | 1.6 | Steps 11 and 12, concatenation, tags and indexing |
| **Ensembl VEP** | 113 | Step 12, functional annotation, GRCh38 offline cache |
| **Singularity** | 2.4.2 | Step 12, runs the VEP image |
| **Python** | 3.10.13 and 3.12.6 | QC plots and downstream analysis |
| **Hail** | 0.2.134-952ae203dbbe | Post-annotation QC, outside this repository |
| **Apache Spark** | 3.5.5 | Backend for Hail |

## Notes

**GATK.** Two versions were in use. `CollectHsMetrics` was run with the cluster
module `gatk/4.4.0.0`; the BQSR step called GATK 4.6 directly from
`/home/ceromova/software/gatk-4.6.0.0/gatk`. The remaining GATK steps loaded
the `gatk` module, so their version depends on what the module pointed to at
the time of the run.

**Reference and resources.** GRCh38 with decoy contigs
(`Homo_sapiens_assembly38.fasta`), the GATK resource bundle (HapMap 3.3,
1000 Genomes Omni 2.5, 1000 Genomes phase 1 high-confidence SNPs, dbSNP 146,
Mills and 1000 Genomes gold standard indels) and the IDT xGen Exome
Hybridisation Panel v2 capture design.

**Hail and Spark.** These belong to the post-annotation QC branches shown in
the workflow diagram (sample identity QC, variant QC and hard filters), which
are not scripted in this repository.

**BCFtools 1.6.** This release is considerably older than the rest of the
toolchain, and two calls in the current scripts may not run under it: the
`TYPE` tag of `+fill-tags` in step 12 and the `--threads` option of
`bcftools concat` in step 11. Worth checking against the version actually
loaded by the `biotools` module before quoting 1.6 in the methods section.
