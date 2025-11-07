#!/bin/bash

# Configuration
SIF_FILE="/scratch/fry/quackers_v1.0.5.sif"
GTDBTK_DB_HOST="/scratch/fry/gtdbtk_db/release226" 
GTDBTK_DB_CONTAINER_TARGET="/quackers_tools/gtdbtk_data" 
BASE_DIR="/scratch/fry/child_mgx_out/Anathema.out"
BIN_SUBDIR="bin_refinement/metawrap_70_10_bins"
SCRATCH_DIR="/scratch/fry"
MAX_CONCURRENT_JOBS=2
USERNAME="fry"

# Function to count running/pending jobs
count_jobs() {
    squeue -u ${USERNAME} -h -t PENDING,RUNNING -n gtdbtk_classify 2>/dev/null | wc -l
}

echo "Starting GTDB-Tk classification job submission..."
echo "Host Database path: $GTDBTK_DB_HOST"
echo "Container Target path: $GTDBTK_DB_CONTAINER_TARGET"
echo "Will maintain ${MAX_CONCURRENT_JOBS} concurrent jobs"
echo "----------------------------------------------------"

submitted=0
total=0

# Count total valid directories first
for BIN_DIR in "$BASE_DIR"/*/"$BIN_SUBDIR"; do
    if [ -d "$BIN_DIR" ]; then
        ((total++))
    fi
done

if [ $total -eq 0 ]; then
    echo "Error: No valid bin directories found matching pattern: $BASE_DIR/*/$BIN_SUBDIR"
    exit 1
fi

echo "Found ${total} samples to process"
echo ""

# Process each bin directory
for BIN_DIR in "$BASE_DIR"/*/"$BIN_SUBDIR"; do
    
    if [ ! -d "$BIN_DIR" ]; then
        continue
    fi
    
    PARENT_DIR=$(dirname $(dirname "$BIN_DIR"))
    OUTPUT_DIR="$PARENT_DIR/gtdbtk_out"
    SAMPLE_NAME=$(basename "$PARENT_DIR")
    
    # Skip if already processed
    if [ -d "${OUTPUT_DIR}" ] && [ -n "$(ls -A ${OUTPUT_DIR} 2>/dev/null)" ]; then
        echo "INFO: Skipping ${SAMPLE_NAME} - output directory already exists and is not empty"
        continue
    fi
    
    # Check if bin directory has any .fa files
    if [ -z "$(ls -A ${BIN_DIR}/*.fa 2>/dev/null)" ]; then
        echo "WARNING: Skipping ${SAMPLE_NAME} - no .fa files found in bin directory"
        continue
    fi
    
    # Wait until we have a slot BEFORE preparing job
    current_jobs=$(count_jobs)
    while [ ${current_jobs} -ge ${MAX_CONCURRENT_JOBS} ]; do
        echo "[$(date '+%H:%M:%S')] ${current_jobs}/${MAX_CONCURRENT_JOBS} jobs active. Waiting for a slot..."
        sleep 30
        current_jobs=$(count_jobs)
    done
    
    echo "Preparing job for: $SAMPLE_NAME"
    echo "  Bins: $BIN_DIR"
    echo "  Output: $OUTPUT_DIR"
    
    # Create output directory
    mkdir -p "${OUTPUT_DIR}"
    
    # Create SLURM script for this sample
    cat > "/tmp/submit_gtdbtk_${SAMPLE_NAME}.sh" << EOF
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --cpus-per-task=192
#SBATCH --time=1:00:00
#SBATCH --job-name=gtdbtk_classify
#SBATCH --output=${SCRATCH_DIR}/gtdbtk_classify_${SAMPLE_NAME}.out
#SBATCH --error=${SCRATCH_DIR}/gtdbtk_classify_${SAMPLE_NAME}.err

echo "Starting GTDB-Tk classification for ${SAMPLE_NAME}"
echo "Bins directory: ${BIN_DIR}"
echo "Output directory: ${OUTPUT_DIR}"
echo "----------------------------------------------------"

singularity exec \\
    --bind "${BIN_DIR}":/bins \\
    --bind "${GTDBTK_DB_HOST}":"${GTDBTK_DB_CONTAINER_TARGET}" \\
    --bind "${OUTPUT_DIR}":/gtdbtk_out \\
    --env GTDBTK_DATA_PATH="${GTDBTK_DB_CONTAINER_TARGET}" \\
    "${SIF_FILE}" gtdbtk classify_wf \\
    --genome_dir /bins \\
    --out_dir /gtdbtk_out \\
    --cpus 192 \\
    --extension fa \\
    --skip_ani_screen \\
    --force \\
    --scratch_dir /tmp/gtdbtk_scratch

if [ \$? -eq 0 ]; then
    echo "Successfully completed GTDB-Tk for ${SAMPLE_NAME}"
else
    echo "!! ERROR during GTDB-Tk for ${SAMPLE_NAME} !!"
    exit 1
fi
EOF

    # Submit the job
    job_output=$(sbatch "/tmp/submit_gtdbtk_${SAMPLE_NAME}.sh" 2>&1)
    if [ $? -eq 0 ]; then
        job_id=$(echo ${job_output} | awk '{print $NF}')
        ((submitted++))
        echo "[$(date '+%H:%M:%S')] Submitted ${SAMPLE_NAME} (Job ID: ${job_id}) - Total submitted: ${submitted}/${total}"
    else
        echo "ERROR: Failed to submit job for ${SAMPLE_NAME}: ${job_output}"
    fi
    
    # Small delay to let squeue update
    sleep 2
done

echo ""
echo "Job submission complete!"
echo "Total jobs submitted: ${submitted}"
echo "Check job status with: squeue -u ${USERNAME}"
echo "Monitor progress with: watch -n 30 'squeue -u ${USERNAME}'"
