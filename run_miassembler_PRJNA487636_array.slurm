#!/bin/bash
#SBATCH -A naiss2025-5-431
#SBATCH -p main
#SBATCH -J mia_PRJNA487636
#SBATCH --array=1-179%8
#SBATCH -t 12:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH -o logs/mia_%A_%a.out
#SBATCH -e logs/mia_%A_%a.err

set -euo pipefail


# ============================================================
# Environment
# ============================================================

source /cfs/klemming/home/x/xueyaw/xueyao/miniconda/etc/profile.d/conda.sh
conda activate miassembler_nf

ml PDC
ml singularity

# MIAssembler currently requires the legacy Nextflow parser
export NXF_SYNTAX_PARSER=v1


# ============================================================
# Paths
# ============================================================

REPO=/cfs/klemming/home/x/xueyaw/xueyao/miassembler

BASE=/cfs/klemming/home/x/xueyaw/xueyao/data/metagenomics/PRJNA487636
MASTER_SHEET="$BASE/miassembler_all.csv"

REF=/cfs/klemming/home/x/xueyaw/xueyao/reference/miassembler

OUT="$BASE/miassembler_output_tpa312"

WORK_ROOT=/cfs/klemming/scratch/x/xueyaw/miassembler_work_PRJNA487636

SHEET_ROOT=/cfs/klemming/scratch/x/xueyaw/miassembler_array_samplesheets

NXF_LOG_ROOT=/cfs/klemming/scratch/x/xueyaw/miassembler_nextflow_logs_PRJNA487636

DONE_ROOT=/cfs/klemming/scratch/x/xueyaw/miassembler_done_PRJNA487636

CACHE=/cfs/klemming/scratch/x/xueyaw/miassembler_singularity_cache

export NXF_SINGULARITY_CACHEDIR="$CACHE"


mkdir -p \
    "$OUT" \
    "$WORK_ROOT" \
    "$SHEET_ROOT" \
    "$NXF_LOG_ROOT" \
    "$DONE_ROOT" \
    "$CACHE"


# ============================================================
# Determine sample for this array element
#
# Array 0   -> CSV line 2
# Array 1   -> CSV line 3
# ...
# Array 179 -> CSV line 181
# ============================================================

LINE=$((SLURM_ARRAY_TASK_ID + 2))

HEADER=$(head -n 1 "$MASTER_SHEET")
ROW=$(sed -n "${LINE}p" "$MASTER_SHEET")

if [[ -z "$ROW" ]]; then
    echo "ERROR: No row found for array task ${SLURM_ARRAY_TASK_ID}"
    exit 1
fi


# Column 1 = study accession
# Column 2 = run accession

STUDY=$(printf '%s\n' "$ROW" | cut -d',' -f1 | tr -d '\r')
RUN=$(printf '%s\n' "$ROW" | cut -d',' -f2 | tr -d '\r')

if [[ -z "$STUDY" || -z "$RUN" ]]; then
    echo "ERROR: Could not determine study/run accession"
    exit 1
fi


# ============================================================
# Per-sample paths
# ============================================================

SAMPLE_SHEET="$SHEET_ROOT/${RUN}.csv"

RUN_ROOT="$WORK_ROOT/${RUN}"

# IMPORTANT:
# Each independent Nextflow process gets its own launch directory.
# This prevents .nextflow session-lock collisions.
LAUNCH="$RUN_ROOT/launch"

# Each sample also gets its own Nextflow work directory.
WORK="$RUN_ROOT/work"

# Each sample gets its own Nextflow log.
NXF_LOG="$NXF_LOG_ROOT/${RUN}.nextflow.log"

# Marker written only after the final assembly passes validation.
DONE="$DONE_ROOT/${RUN}.done"


mkdir -p "$LAUNCH"
mkdir -p "$WORK"


# ============================================================
# Make one-sample samplesheet
# ============================================================

printf '%s\n' "$HEADER" > "$SAMPLE_SHEET"
printf '%s\n' "$ROW" >> "$SAMPLE_SHEET"


# ============================================================
# Expected final assembly path
# ============================================================

STUDY_PREFIX=${STUDY:0:7}
RUN_PREFIX=${RUN:0:7}

CONTIG="$OUT/$STUDY_PREFIX/$STUDY/$RUN_PREFIX/$RUN/assembly/metaspades/3.12.0/contig.fa.gz"


# ============================================================
# Basic information
# ============================================================

echo "============================================================"
echo "Started:       $(date)"
echo "Host:          $(hostname)"
echo "Array job:     ${SLURM_ARRAY_JOB_ID}"
echo "Array task:    ${SLURM_ARRAY_TASK_ID}"
echo "Study:         $STUDY"
echo "Run:           $RUN"
echo "Samplesheet:   $SAMPLE_SHEET"
echo "Launch dir:    $LAUNCH"
echo "Work dir:      $WORK"
echo "Nextflow log:  $NXF_LOG"
echo "Output root:   $OUT"
echo "Expected file: $CONTIG"
echo "============================================================"


# ============================================================
# Skip an already completed sample
# ============================================================

if [[ -f "$DONE" ]]; then

    if [[ -s "$CONTIG" ]] && gzip -t "$CONTIG" 2>/dev/null; then

        echo "Already completed successfully: $RUN"
        echo "Validated existing assembly:"
        echo "$CONTIG"

        exit 0

    else

        echo "WARNING: .done marker exists but assembly is missing/invalid."
        echo "Removing stale marker and rerunning sample."

        rm -f "$DONE"

    fi
fi


# Also catch the case where the assembly was completed but the
# driver stopped before it could create the .done marker.

#if [[ -s "$CONTIG" ]]; then
#
#    if gzip -t "$CONTIG" 2>/dev/null; then
#
#        NSEQ=$(zgrep -c '^>' "$CONTIG")
#
#        echo "Existing valid assembly found:"
#        echo "  file:      $CONTIG"
#        echo "  sequences: $NSEQ"
#
#        touch "$DONE"
#
#        echo "Marked sample complete."
#
#        exit 0
#    fi
#
#fi


# ============================================================
# Check FASTQ files
# ============================================================

R1=$(printf '%s\n' "$ROW" | cut -d',' -f3 | tr -d '\r')
R2=$(printf '%s\n' "$ROW" | cut -d',' -f4 | tr -d '\r')

if [[ ! -s "$R1" ]]; then
    echo "ERROR: R1 missing or empty:"
    echo "$R1"
    exit 1
fi

if [[ ! -s "$R2" ]]; then
    echo "ERROR: R2 missing or empty:"
    echo "$R2"
    exit 1
fi

echo
echo "FASTQ inputs:"
echo "R1: $R1"
echo "R2: $R2"


# ============================================================
# Repository sanity checks
# ============================================================

BRANCH=$(git -C "$REPO" branch --show-current)

echo
echo "Git branch: $BRANCH"

if [[ "$BRANCH" != "micore-tpa-reconstruction" ]]; then
    echo "ERROR: Wrong Git branch."
    echo "Expected: micore-tpa-reconstruction"
    echo "Found:    $BRANCH"
    exit 1
fi


echo
echo "Nextflow version:"
nextflow -version

echo
echo "Singularity version:"
singularity --version


# ============================================================
# Run MIAssembler
# ============================================================

echo
echo "Starting Nextflow: $(date)"
echo

# IMPORTANT:
# Run Nextflow FROM the unique per-sample launch directory.
# Therefore each array task gets an independent:
#
#   launch/.nextflow/
#
# and cannot lock another sample's Nextflow session.

cd "$LAUNCH"


# Use -resume only if this particular sample already has
# Nextflow history from an earlier attempt.

RESUME_FLAG=""

if [[ -s "$LAUNCH/.nextflow/history" ]]; then
    RESUME_FLAG="-resume"

    echo "Previous Nextflow history found."
    echo "Running with -resume."
else
    echo "No previous Nextflow history for $RUN."
    echo "Starting a new Nextflow session."
fi


nextflow \
    -log "$NXF_LOG" \
    run "$REPO/main.nf" \
    -profile singularity \
    -c "$REPO/pdc.config" \
    --samplesheet "$SAMPLE_SHEET" \
    --reference_genomes_folder "$REF" \
    --outdir "$OUT" \
    -work-dir "$WORK" \
    $RESUME_FLAG


# ============================================================
# Validate final assembly
# ============================================================

echo
echo "Nextflow returned successfully."
echo "Checking final assembly..."

if [[ ! -s "$CONTIG" ]]; then
    echo "ERROR: Nextflow completed but contig.fa.gz was not found:"
    echo "$CONTIG"
    exit 1
fi


if ! gzip -t "$CONTIG"; then
    echo "ERROR: gzip integrity check failed:"
    echo "$CONTIG"
    exit 1
fi


NSEQ=$(zgrep -c '^>' "$CONTIG")

if [[ "$NSEQ" -eq 0 ]]; then
    echo "ERROR: contig.fa.gz contains zero FASTA sequences."
    exit 1
fi


echo
echo "Assembly validated:"
echo "  file:      $CONTIG"
echo "  sequences: $NSEQ"
echo "  size:      $(du -h "$CONTIG" | cut -f1)"


# ============================================================
# Mark this sample complete
# ============================================================

touch "$DONE"


echo
echo "============================================================"
echo "SUCCESS:  $RUN"
echo "Finished: $(date)"
echo "============================================================"