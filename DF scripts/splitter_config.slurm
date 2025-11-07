#!/bin/bash
#SBATCH --nodes=1
#SBATCH --cpus-per-task=192
#SBATCH --time=1:00:00
#SBATCH --job-name=SAMPLEID_quackers
#SBATCH --output=/scratch/fry/split_fastq_bins_%j.log
#SBATCH --error=/scratch/fry/split_fastq_bins_%j.err

echo "------------------------------------------------------------"
echo "Job started on $(date)"
echo "Running on node: $(hostname)"
echo "Using $SLURM_CPUS_PER_TASK CPUs"
echo "------------------------------------------------------------"

# Directories
INPUT_DIR="/scratch/fry/child_mgx_deep_data"
OUTPUT_DIR="/scratch/fry/split_child_mgx_deep_data"
mkdir -p "$OUTPUT_DIR"

echo "Looking for *_cleaned.fastq files in: $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo

# Collect all R1 cleaned files
mapfile -t R1_FILES < <(find "$INPUT_DIR" -maxdepth 1 -type f -name '*_1_cleaned.fastq' | sort)
TOTAL_PAIRS=${#R1_FILES[@]}
echo "Found $TOTAL_PAIRS paired samples."

# Number of bins
BINS=16
PAIRS_PER_BIN=$(( (TOTAL_PAIRS + BINS - 1) / BINS ))
echo "Splitting into $BINS bins of $PAIRS_PER_BIN pairs each."
echo

BIN_INDEX=1
PAIR_COUNT=0

# Prepare array of copy commands
COPY_CMDS=()

for R1 in "${R1_FILES[@]}"; do
    BASE_NAME="${R1%_1_cleaned.fastq}"
    R2="${BASE_NAME}_2_cleaned.fastq"

    if [[ ! -f "$R2" ]]; then
        echo "kipping: Missing R2 for $(basename "$R1")"
        continue
    fi

    BIN_DIR="${OUTPUT_DIR}/Bin_${BIN_INDEX}_child_mgx_deep_data"
    mkdir -p "$BIN_DIR"

    # Add copy commands for parallel execution
    COPY_CMDS+=("cp '$R1' '$BIN_DIR/'")
    COPY_CMDS+=("cp '$R2' '$BIN_DIR/'")
    echo "Queued pair: $(basename "$R1") and $(basename "$R2") → $BIN_DIR"

    ((PAIR_COUNT++))
    if (( PAIR_COUNT % PAIRS_PER_BIN == 0 && BIN_INDEX < BINS )); then
        ((BIN_INDEX++))
    fi
done

# Run copy commands in parallel using all available cores
echo
echo "Starting parallel copy using $SLURM_CPUS_PER_TASK cores..."
printf "%s\n" "${COPY_CMDS[@]}" | parallel -j "$SLURM_CPUS_PER_TASK"

echo
echo "Completed splitting into $BINS bins."
echo "Job finished on $(date)"
echo "------------------------------------------------------------"

