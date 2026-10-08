#!/bin/bash
#SBATCH -A naiss2025-5-431
#SBATCH -p main
#SBATCH -J miassembler_driver
#SBATCH -t 22:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH -o logs/miassembler_driver_%j.out
#SBATCH -e logs/miassembler_driver_%j.err

set -euo pipefail

echo "=== Job started ==="
date
hostname

# Environment
source /cfs/klemming/home/x/xueyaw/xueyao/miniconda/etc/profile.d/conda.sh
conda activate miassembler_nf

ml PDC
ml singularity

export NXF_SYNTAX_PARSER=v1

# Paths
BASE=/cfs/klemming/home/x/xueyaw/xueyao/data/metagenomics/PRJNA487636
REF=/cfs/klemming/home/x/xueyaw/xueyao/reference/miassembler
WORK=/cfs/klemming/scratch/x/xueyaw/miassembler_work
CACHE=/cfs/klemming/scratch/x/xueyaw/miassembler_singularity_cache
OUT="$BASE/miassembler_output_test1_tpa312"

export NXF_SINGULARITY_CACHEDIR="$CACHE"

mkdir -p "$WORK" "$CACHE" "$OUT"

cd /cfs/klemming/home/x/xueyaw/xueyao/miassembler

echo "Branch:"
git branch --show-current

echo "Nextflow:"
nextflow -version

echo "Singularity:"
singularity --version

echo "Starting workflow:"
date

nextflow run main.nf \
    -profile singularity \
    -c pdc.config \
    --samplesheet "$BASE/miassembler_test1.csv" \
    --reference_genomes_folder "$REF" \
    --outdir "$OUT" \
    -work-dir "$WORK" \
    -resume

echo "=== Workflow finished ==="
date
