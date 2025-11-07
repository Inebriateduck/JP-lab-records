#!/bin/bash

# Configuration
INPUT_DIR="/scratch/fry/child_mgx_out/Anathema.out"
SCRATCH_DIR="/scratch/fry"
MAX_CONCURRENT_JOBS=20
USERNAME="fry"

# Function to count running/pending jobs
count_jobs() {
    squeue -u ${USERNAME} -h -t PENDING,RUNNING 2>/dev/null | grep -c "bin_refinement"
}

# Check if input directory exists
if [ ! -d "${INPUT_DIR}" ]; then
    echo "Error: Input directory ${INPUT_DIR} does not exist!"
    exit 1
fi

# Get all sample directories
samples=($(ls -d ${INPUT_DIR}/*/ 2>/dev/null | xargs -n 1 basename))

if [ ${#samples[@]} -eq 0 ]; then
    echo "Error: No sample directories found in ${INPUT_DIR}"
    exit 1
fi

echo "Found ${#samples[@]} samples in ${INPUT_DIR}"
echo "Will maintain ${MAX_CONCURRENT_JOBS} concurrent jobs"
echo "Starting job submission..."
echo ""

submitted=0
for sample in "${samples[@]}"; do
    # Create sample-specific paths
    OUTPUT_DIR="${INPUT_DIR}/${sample}/bin_refinement"
    A_PATH="${INPUT_DIR}/${sample}/3a_concoct_binning/bins"
    B_PATH="${INPUT_DIR}/${sample}/3b_maxbin2_binning/maxbin2/maxbin2_bins"
    C_PATH="${INPUT_DIR}/${sample}/3c_metabat2_binning/metabat2/metabat2_bins"

    # Check if required input directories exist
    if [ ! -d "${A_PATH}" ] || [ ! -d "${B_PATH}" ] || [ ! -d "${C_PATH}" ]; then
        echo "WARNING: Skipping ${sample} - missing required input directories"
        continue
    fi

    # Skip if already processed
    if [ -d "${OUTPUT_DIR}" ] && [ -n "$(ls -A ${OUTPUT_DIR} 2>/dev/null)" ]; then
        echo "INFO: Skipping ${sample} - output directory already exists and is not empty"
        continue
    fi

    # Create output directory
    mkdir -p "${OUTPUT_DIR}"

    # Create SLURM script for this sample
    cat > "/tmp/submit_${sample}.sh" << EOF
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --cpus-per-task=192
#SBATCH --time=1:00:00
#SBATCH --job-name=bin_refinement_${sample}
#SBATCH --output=${SCRATCH_DIR}/bin_refinement_${sample}.out
#SBATCH --error=${SCRATCH_DIR}/bin_refinement_${sample}.err

# Singularity container
singularity exec -B /home -B /scratch ${SCRATCH_DIR}/quackers_v1.0.5.sif bash << 'EOFINNER'
unset -f which
export PATH="/quackers_tools/metaWRAP-1.3/bin:\$PATH"

# Create wrapper that intercepts python2.7 calls
mkdir -p /tmp/python_wrapper_\$\$
cat > /tmp/python_wrapper_\$\$/python2.7 << 'PYWRAP'
#!/bin/bash
script="\$1"
# If it's binning_refiner.py (CheckM step), use python3
if [[ "\$script" == *"binning_refiner.py"* ]]; then
    exec /opt/conda/bin/python3 "\$@"
else
    # Everything else uses real python2.7 with its own packages
    export PYTHONPATH=/usr/local/lib/python2.7/site-packages
    exec /usr/local/bin/python2.7 "\$@"
fi
PYWRAP
chmod +x /tmp/python_wrapper_\$\$/python2.7
export PATH="/tmp/python_wrapper_\$\$:\$PATH"

# CheckM path correction
export CHECKM_DATA_PATH=/opt/conda/checkm_data
checkm data setRoot /opt/conda/checkm_data

# Matplotlib config directory (avoid conflicts)
export MPLCONFIGDIR=/tmp/matplotlib_config_\$\$
mkdir -p \$MPLCONFIGDIR

# Running function
metawrap bin_refinement \\
  -o ${OUTPUT_DIR} \\
  -t 192 \\
  -m 100 \\
  -c 70 \\
  -x 10 \\
  -A ${A_PATH} \\
  -B ${B_PATH} \\
  -C ${C_PATH}
EOFINNER
EOF

    # Submit the job
    job_output=$(sbatch "/tmp/submit_${sample}.sh" 2>&1)
    if [ $? -eq 0 ]; then
        job_id=$(echo ${job_output} | awk '{print $NF}')
        ((submitted++))
        echo "[$(date '+%H:%M:%S')] Submitted ${sample} (Job ID: ${job_id}) - Total submitted: ${submitted}/${#samples[@]}"
    else
        echo "ERROR: Failed to submit job for ${sample}: ${job_output}"
    fi

    # Wait until we have a slot before submitting next job
    current_jobs=$(count_jobs)
    while [ ${current_jobs} -ge ${MAX_CONCURRENT_JOBS} ]; do
        echo "[$(date '+%H:%M:%S')] ${current_jobs}/${MAX_CONCURRENT_JOBS} jobs active. Waiting for a slot..."
        sleep 30
        current_jobs=$(count_jobs)
    done
done

echo ""
echo "Job submission complete!"
echo "Total jobs submitted: ${submitted}"
echo "Check job status with: squeue -u ${USERNAME}"
echo "Monitor progress with: watch -n 30 'squeue -u ${USERNAME}'"
