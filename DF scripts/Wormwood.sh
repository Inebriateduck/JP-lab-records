#!/bin/bash

# Bakta SLURM Batch Processing Script
# Submits individual SLURM jobs for each bin, processes subdirectories sequentially

# Configuration
BASE_DIR="/scratch/fry/child_mgx_out/Anathema.out"
BAKTA_DB="/scratch/fry/bakta_db/db"
CONDA_ENV="bakta_env"

# SLURM parameters
ACCOUNT="rrg-jparkin-ac"

# Activate conda environment for verification
source ~/miniforge3/etc/profile.d/conda.sh
conda activate ${CONDA_ENV}

# Verify Bakta is available
if ! command -v bakta &> /dev/null; then
    echo "ERROR: Bakta not found in ${CONDA_ENV} environment"
    exit 1
fi

echo "Using Bakta version: $(bakta --version)"
echo ""

# Find all subdirectories containing bin_refinement/metawrap_70_10_bins
SUBDIRS=($(find ${BASE_DIR} -type d -path "*/bin_refinement/metawrap_70_10_bins" | sed 's|/bin_refinement/metawrap_70_10_bins||' | sort -u))

echo "Found ${#SUBDIRS[@]} subdirectories to process"
echo "Starting at: $(date)"
echo ""

# Process each subdirectory sequentially
for SUBDIR in "${SUBDIRS[@]}"; do
    SUBDIR_NAME=$(basename ${SUBDIR})
    BIN_DIR="${SUBDIR}/bin_refinement/metawrap_70_10_bins"
    OUTPUT_BASE="${SUBDIR}/bakta_results"
    
    echo "=========================================="
    echo "Processing subdirectory: ${SUBDIR_NAME}"
    echo "Bin directory: ${BIN_DIR}"
    echo "Started at: $(date)"
    echo "=========================================="
    
    # Check if bin directory exists
    if [ ! -d "${BIN_DIR}" ]; then
        echo "WARNING: Bin directory not found: ${BIN_DIR}"
        echo ""
        continue
    fi
    
    # Find all .fa files in the bin directory
    FA_FILES=($(find ${BIN_DIR} -maxdepth 1 -name "*.fa" -type f))
    
    if [ ${#FA_FILES[@]} -eq 0 ]; then
        echo "WARNING: No .fa files found in ${BIN_DIR}"
        echo ""
        continue
    fi
    
    echo "Found ${#FA_FILES[@]} bin files to process"
    echo ""
    
    # Create output directory
    mkdir -p ${OUTPUT_BASE}
    
    # Array to store job IDs
    JOB_IDS=()
    
    # Submit a SLURM job for each .fa file
    for FA_FILE in "${FA_FILES[@]}"; do
        BIN_NAME=$(basename ${FA_FILE} .fa)
        BIN_OUTPUT="${OUTPUT_BASE}/${BIN_NAME}"
        
        echo "  Submitting job for: ${BIN_NAME}"
        
        # Create SLURM script on-the-fly
        SLURM_SCRIPT=$(mktemp)
        cat > ${SLURM_SCRIPT} <<EOF
#!/bin/bash
#SBATCH --account=${ACCOUNT}
#SBATCH --time=00:15:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=192
#SBATCH --job-name=bakta_${SUBDIR_NAME}_${BIN_NAME}
#SBATCH --output=${OUTPUT_BASE}/${BIN_NAME}_slurm.out
#SBATCH --error=${OUTPUT_BASE}/${BIN_NAME}_slurm.err

# Load conda environment
source ~/miniforge3/etc/profile.d/conda.sh
conda activate ${CONDA_ENV}

# Run Bakta
echo "Starting Bakta annotation for ${BIN_NAME}"
echo "Input file: ${FA_FILE}"
echo "Output directory: ${BIN_OUTPUT}"
echo "Database: ${BAKTA_DB}"
echo "Started at: \$(date)"

bakta --db ${BAKTA_DB} \\
      --output ${BIN_OUTPUT} \\
      --prefix ${BIN_NAME} \\
      --threads 192 \\
      --verbose \\
      ${FA_FILE}

EXIT_CODE=\$?

if [ \${EXIT_CODE} -eq 0 ]; then
    echo "Bakta completed successfully for ${BIN_NAME}"
    echo "Finished at: \$(date)"
else
    echo "ERROR: Bakta failed for ${BIN_NAME} with exit code \${EXIT_CODE}"
    echo "Check log: ${BIN_OUTPUT}/${BIN_NAME}.log"
fi

exit \${EXIT_CODE}
EOF

        # Submit the job and capture job ID
        JOB_ID=$(sbatch --parsable ${SLURM_SCRIPT})
        JOB_IDS+=($JOB_ID)
        echo "    Job ID: ${JOB_ID}"
        
        # Clean up temporary script
        rm ${SLURM_SCRIPT}
    done
    
    # Wait for all jobs in this subdirectory to complete
    echo ""
    echo "Waiting for ${#JOB_IDS[@]} jobs to complete for ${SUBDIR_NAME}..."
    
    for JOB_ID in "${JOB_IDS[@]}"; do
        # Wait for job to finish
        while squeue -j ${JOB_ID} 2>/dev/null | grep -q ${JOB_ID}; do
            sleep 30
        done
        echo "  Job ${JOB_ID} completed"
    done
    
    echo "All jobs completed for ${SUBDIR_NAME} at: $(date)"
    echo ""
    
    # Generate summary report for this subdirectory
    echo "Summary for ${SUBDIR_NAME}:" > ${OUTPUT_BASE}/summary.txt
    echo "Total bins processed: ${#FA_FILES[@]}" >> ${OUTPUT_BASE}/summary.txt
    echo "Completed at: $(date)" >> ${OUTPUT_BASE}/summary.txt
    
done

echo "=========================================="
echo "All subdirectories processed!"
echo "Finished at: $(date)"
echo "=========================================="
