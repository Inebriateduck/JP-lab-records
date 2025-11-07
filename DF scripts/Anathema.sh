#!/bin/bash
set -x  # Enable debug mode
INPUT_DIR="/scratch/fry/split_child_mgx_deep_data/Bin_2_child_mgx_deep_data"
OUTPUT_BASE="/scratch/fry/child_mgx_out/Anathema.out"
CONFIG_TEMPLATE="/scratch/fry/Anathema.config"
SIF_FILE="/scratch/fry/quackers_v1.0.5.sif"
PREV_JOB_ID=""

echo "Starting script..."
echo "INPUT_DIR: $INPUT_DIR"
echo "OUTPUT_BASE: $OUTPUT_BASE"

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "ERROR: INPUT_DIR does not exist: $INPUT_DIR"
    exit 1
fi

if [[ ! -f "$CONFIG_TEMPLATE" ]]; then
    echo "ERROR: CONFIG_TEMPLATE does not exist: $CONFIG_TEMPLATE"
    exit 1
fi

if [[ ! -f "$SIF_FILE" ]]; then
    echo "ERROR: SIF_FILE does not exist: $SIF_FILE"
    exit 1
fi

echo "All required files/dirs found. Starting loop..."

for R1_FILE in "${INPUT_DIR}"/*_paired_1_cleaned.fastq; do
    echo "Processing: $R1_FILE"

    if [[ ! -f "$R1_FILE" ]]; then
        echo "R1_FILE does not exist, skipping: $R1_FILE"
        continue
    fi

    BASENAME=$(basename "${R1_FILE}")
    JOBNAME=$(echo "${BASENAME}" | cut -d'_' -f1,2)
    echo "JOBNAME: $JOBNAME"

    R2_FILE=$(echo "${R1_FILE}" | sed 's/_paired_1_cleaned/_paired_2_cleaned/')
    echo "R2_FILE: $R2_FILE"

    if [[ ! -f "${R2_FILE}" ]]; then
        echo "Skipping ${JOBNAME}, pair2 not found: $R2_FILE"
        continue
    fi

    OUTDIR="${OUTPUT_BASE}/${JOBNAME}"
    
    # Skip if already processed
    if [[ -d "${OUTDIR}" ]]; then
        echo "Skipping ${JOBNAME}, already processed"
        continue
    fi
    
    echo "Creating OUTDIR: $OUTDIR"
    mkdir -p "${OUTDIR}" || { echo "Failed to create OUTDIR"; exit 1; }

    CONFIG_FILE="${OUTDIR}/${JOBNAME}_config.ini"
    cp "${CONFIG_TEMPLATE}" "${CONFIG_FILE}" || { echo "Failed to copy config"; exit 1; }

    sed -i "s|FILE1|${R1_FILE}|g" "${CONFIG_FILE}"
    sed -i "s|FILE2|${R2_FILE}|g" "${CONFIG_FILE}"
    sed -i "s|PIPEOUTDIR|${OUTDIR}|g" "${CONFIG_FILE}"

    SLURM_SCRIPT="${OUTDIR}/${JOBNAME}_quackers.sbatch"
    echo "Creating SLURM_SCRIPT: $SLURM_SCRIPT"

    # Create SLURM script with monitoring and cleanup
    cat > "${SLURM_SCRIPT}" <<'EOFSLURM'
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --cpus-per-task=192
#SBATCH --time=3:00:00
#SBATCH --job-name=JOBNAME_PLACEHOLDER
#SBATCH --output=OUTDIR_PLACEHOLDER/JOBNAME_PLACEHOLDER.out
#SBATCH --error=OUTDIR_PLACEHOLDER/JOBNAME_PLACEHOLDER.err

# Trap to ensure complete cleanup on exit
cleanup() {
    echo "Starting cleanup at $(date)"

    # Kill the main pipeline process
    if [ ! -z "$PIPELINE_PID" ]; then
        kill -TERM $PIPELINE_PID 2>/dev/null
        sleep 2
        kill -KILL $PIPELINE_PID 2>/dev/null
    fi

    # Kill all child processes of this script
    pkill -TERM -P $$ 2>/dev/null
    sleep 2
    pkill -KILL -P $$ 2>/dev/null

    # Kill any remaining background jobs
    jobs -p | xargs -r kill -KILL 2>/dev/null

    # Wait for all processes to finish
    wait 2>/dev/null

    echo "Cleanup complete at $(date)"
}

trap cleanup EXIT SIGTERM SIGINT

export OPENBLAS_NUM_THREADS=48
export OMP_NUM_THREADS=48


# Clear any temp files
rm -rf /tmp/tmp* /tmp/metawrap* /tmp/checkm* 2>/dev/null

echo "Starting job at $(date)"

# Run pipeline in background
singularity exec -B /home -B /scratch SIF_PLACEHOLDER python3 /quackers_pipe/quackers_pipe.py \
-1 R1_PLACEHOLDER -2 R2_PLACEHOLDER -o OUTDIR_PLACEHOLDER -c CONFIG_PLACEHOLDER --stop 3c_metabat2_binning &

PIPELINE_PID=$!
echo "Pipeline started with PID: $PIPELINE_PID at $(date)"

# Create empty single.fastq if it doesn't exist (workaround for missing unpaired reads)
sleep 10
if [ ! -f "OUTDIR_PLACEHOLDER/1_host_filter/export/single.fastq" ]; then
    mkdir -p OUTDIR_PLACEHOLDER/1_host_filter/export
    touch OUTDIR_PLACEHOLDER/1_host_filter/export/single.fastq
    echo "Created empty single.fastq as workaround"
fi

# Track completion of all three binning steps
STEP_3A_DONE=false
STEP_3B_DONE=false
STEP_3C_DONE=false

# Monitor for all three binning steps to complete, then kill at step 4
while kill -0 $PIPELINE_PID 2>/dev/null; do
    # Check which steps have completed
    if grep -q "running: 3a_concoct_binning" OUTDIR_PLACEHOLDER/JOBNAME_PLACEHOLDER.out 2>/dev/null; then
        if [ "$STEP_3A_DONE" = false ]; then
            echo "Step 3a detected at $(date)"
            STEP_3A_DONE=true
        fi
    fi

    if grep -q "running: 3b_maxbin2_binning" OUTDIR_PLACEHOLDER/JOBNAME_PLACEHOLDER.out 2>/dev/null; then
        if [ "$STEP_3B_DONE" = false ]; then
            echo "Step 3b detected at $(date)"
            STEP_3B_DONE=true
        fi
    fi

    if grep -q "running: 3c_metabat2_binning" OUTDIR_PLACEHOLDER/JOBNAME_PLACEHOLDER.out 2>/dev/null; then
        if [ "$STEP_3C_DONE" = false ]; then
            echo "Step 3c detected at $(date)"
            STEP_3C_DONE=true
        fi
    fi

    # If all three steps are done and step 4 starts, kill immediately
    if [ "$STEP_3A_DONE" = true ] && [ "$STEP_3B_DONE" = true ] && [ "$STEP_3C_DONE" = true ]; then
        if grep -q "running: 4_mwrap_bin_r" OUTDIR_PLACEHOLDER/JOBNAME_PLACEHOLDER.out 2>/dev/null; then
            echo "All binning steps (3a, 3b, 3c) complete. Step 4 detected at $(date). Killing pipeline..."
            kill -TERM $PIPELINE_PID 2>/dev/null
            sleep 3
            kill -KILL $PIPELINE_PID 2>/dev/null
            pkill -KILL -P $PIPELINE_PID 2>/dev/null
            echo "Pipeline stopped after completing all binning steps at $(date)"
            break
        fi
    fi

    sleep 3
done

# Explicit cleanup call
cleanup

# Clean temp directories
rm -rf /tmp/tmp* /tmp/metawrap* /tmp/checkm* 2>/dev/null

# Clear any singularity cache
rm -rf ~/.singularity/cache/tmp/* 2>/dev/null

# Give filesystem extra time to sync
sleep 10

echo "Job completed at $(date). Pipeline stopped after steps 3a, 3b, 3c."
exit 0
EOFSLURM

    # Replace placeholders with actual values
    sed -i "s|JOBNAME_PLACEHOLDER|${JOBNAME}|g" "${SLURM_SCRIPT}"
    sed -i "s|OUTDIR_PLACEHOLDER|${OUTDIR}|g" "${SLURM_SCRIPT}"
    sed -i "s|R1_PLACEHOLDER|${R1_FILE}|g" "${SLURM_SCRIPT}"
    sed -i "s|R2_PLACEHOLDER|${R2_FILE}|g" "${SLURM_SCRIPT}"
    sed -i "s|SIF_PLACEHOLDER|${SIF_FILE}|g" "${SLURM_SCRIPT}"
    sed -i "s|CONFIG_PLACEHOLDER|${CONFIG_FILE}|g" "${SLURM_SCRIPT}"

    echo "Script content:"
    cat "${SLURM_SCRIPT}"

    echo "Submitting job..."
    if [[ -z "$PREV_JOB_ID" ]]; then
        # First job - no dependency, submit immediately
        JOB_OUTPUT=$(sbatch "${SLURM_SCRIPT}")
        PREV_JOB_ID=$(echo "$JOB_OUTPUT" | awk '{print $NF}')
        echo "First job submitted for $JOBNAME with ID: $PREV_JOB_ID at $(date)"
    else
        # Wait for previous job to complete before submitting next one
        echo "Waiting for previous job $PREV_JOB_ID to complete before submitting next..."
        
        # Keep checking until job disappears from queue
        while true; do
            JOB_STATUS=$(squeue -j $PREV_JOB_ID -h -o "%T" 2>/dev/null)
            if [[ -z "$JOB_STATUS" ]]; then
                echo "Previous job $PREV_JOB_ID has completed at $(date)"
                break
            fi
            echo "Job $PREV_JOB_ID status: $JOB_STATUS - waiting 30 seconds..."
            sleep 30
        done
        
        # Extra sleep to ensure complete cleanup
        echo "Waiting 30 seconds for complete cleanup..."
        sleep 30
        
        echo "Submitting next job for $JOBNAME at $(date)"
        
        # Now submit the next job
        JOB_OUTPUT=$(sbatch "${SLURM_SCRIPT}")
        PREV_JOB_ID=$(echo "$JOB_OUTPUT" | awk '{print $NF}')
        echo "Job submitted for $JOBNAME with ID: $PREV_JOB_ID"
    fi
done

echo "All jobs submitted and completed. Script finished."
