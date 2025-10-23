Here I'll be running data through the first 3 steps of the quackers pipeline, then manually running mWRAP and subsequent steps to identify bacterial species from the best bins. 

Wrapper to spawn SLURM jobs that iterates through provided paired .fasta files based on the provided input dir

```
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
```
Ran the script on bins 1-8

Integrity check 

```
[fry@tri-login01 7_047742]$ grep "broken" /scratch/fry/child_mgx_out/Anathema.out/*/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_049211/bypass_log.txt:2025-10-17 20:37:02.451092 broken at: 2_contig_assemble
/scratch/fry/child_mgx_out/Anathema.out/7_079615/bypass_log.txt:2025-10-18 06:34:48.396446 broken at: 2_contig_assemble

[fry@tri-login01 7_047742]$ grep -rin "3b" /scratch/fry/child_mgx_out/Anathema.out/*/bypass_log.txt | wc -l
167    <----- approx 30 samples broke / timed out before completing binning...

======== FILES WHICH DID NOT COMPLETE ============
[fry@tri-login01 fry]$ grep -L "3b" /scratch/fry/child_mgx_out/Anathema.out/*/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_047247/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_108600/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_116994/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_116999/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_117962/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_118064/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_140156/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_168158/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_171244/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_213951/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_217516/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_243107/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_245108/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_251244/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_256730/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_330410/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_341549/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_357113/bypass_log.txt
/scratch/fry/child_mgx_out/Anathema.out/7_400625/bypass_log.txt

====== FILES WITH NO bypass.log (also did not complete) =======
/scratch/fry/child_mgx_out/Anathema.out/7_116500/
/scratch/fry/child_mgx_out/Anathema.out/7_118011/
/scratch/fry/child_mgx_out/Anathema.out/7_118069/
/scratch/fry/child_mgx_out/Anathema.out/7_168216/
/scratch/fry/child_mgx_out/Anathema.out/7_177486/
/scratch/fry/child_mgx_out/Anathema.out/7_216362/
/scratch/fry/child_mgx_out/Anathema.out/7_219228/
/scratch/fry/child_mgx_out/Anathema.out/7_254324/
/scratch/fry/child_mgx_out/Anathema.out/7_256792/
/scratch/fry/child_mgx_out/Anathema.out/7_345150/
/scratch/fry/child_mgx_out/Anathema.out/7_357191/
/scratch/fry/child_mgx_out/Anathema.out/7_400707/
```

So thats a problem... I've removed those files for now, but will hopefully revist them to rerun them in the future. Final yield for the first half was 168 samples. 

Running that on the first 8 bins of samples (25 paired samples per bin) results in almost all the storage space on my scratch being used. I'm going to need to deleted the original bins 1-8 since they're taking up too much space. 

Running mWRAP post cleanup on every folder via a wrapper. The following script moves through all the output folders from the previous step and pulls the best bins. The amount of jobs it can spin up is adjustable, but don't make too many or the sysadmin will get mad. 

```
#!/bin/bash

# ====== Config ======
INPUT_DIR="/scratch/fry/child_mgx_out/Anathema.out"
SCRATCH_DIR="/scratch/fry"
MAX_CONCURRENT_JOBS=20
USERNAME="fry"

count_jobs() {
    squeue -u ${USERNAME} -h -t PENDING,RUNNING 2>/dev/null | grep -c "bin_refinement"
}

if [ ! -d "${INPUT_DIR}" ]; then
    echo "Error: Input directory ${INPUT_DIR} does not exist!"
    exit 1
fi

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

    if [ ! -d "${A_PATH}" ] || [ ! -d "${B_PATH}" ] || [ ! -d "${C_PATH}" ]; then
        echo "WARNING: Skipping ${sample} - missing required input directories"
        continue
    fi

    if [ -d "${OUTPUT_DIR}" ] && [ -n "$(ls -A ${OUTPUT_DIR} 2>/dev/null)" ]; then
        echo "INFO: Skipping ${sample} - output directory already exists and is not empty"
        continue
    fi

    mkdir -p "${OUTPUT_DIR}"

    cat > "/tmp/submit_${sample}.sh" << EOF
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --cpus-per-task=192
#SBATCH --time=1:00:00
#SBATCH --job-name=bin_refinement_${sample}
#SBATCH --output=${SCRATCH_DIR}/bin_refinement_${sample}.out
#SBATCH --error=${SCRATCH_DIR}/bin_refinement_${sample}.err

# ====== Singularity container =========
singularity exec -B /home -B /scratch ${SCRATCH_DIR}/quackers_v1.0.5.sif bash << 'EOFINNER'
unset -f which
export PATH="/quackers_tools/metaWRAP-1.3/bin:\$PATH"

# ======= Python 2.7 call interception ========

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

export CHECKM_DATA_PATH=/opt/conda/checkm_data
checkm data setRoot /opt/conda/checkm_data

export MPLCONFIGDIR=/tmp/matplotlib_config_\$\$
mkdir -p \$MPLCONFIGDIR

# ====== mWRAP params ======
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

# ========= Job Submission ==============
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
```

Once mWRAP is finished, I use a similar script to run GTDBTK to classify the samples. 

```
#!/bin/bash
# Submit GTDB-Tk classification jobs for all sample bins

# Configuration
INPUT_DIR="/scratch/fry/child_mgx_out/Anathema.out"
SCRATCH_DIR="/scratch/fry"
GTDBTK_DB="/scratch/fry/gtdbtk_db/release226"   # <-- adjust if different
MAX_CONCURRENT_JOBS=2
USERNAME="fry"

# ============= Counts running jobs =====================
count_jobs() {
    squeue -u ${USERNAME} -h -t PENDING,RUNNING 2>/dev/null | grep -c "gtdbtk_"
}

# ====== Input dir check ==============================
if [ ! -d "${INPUT_DIR}" ]; then
    echo "Error: Input directory ${INPUT_DIR} does not exist!"
    exit 1
fi

# ====== Gather sample directories ====================
samples=($(ls -d ${INPUT_DIR}/*/ 2>/dev/null | xargs -n 1 basename))
if [ ${#samples[@]} -eq 0 ]; then
    echo "No samples found under ${INPUT_DIR}"
    exit 1
fi

echo "Found ${#samples[@]} samples"
echo "Maintaining ${MAX_CONCURRENT_JOBS} concurrent GTDB-Tk jobs"
echo ""

submitted=0
for sample in "${samples[@]}"; do
    BIN_DIR="${INPUT_DIR}/${sample}/bin_refinement/metawrap_70_10_bins"
    OUT_DIR="${INPUT_DIR}/${sample}/gtdbtk_out"

    if [ ! -d "${BIN_DIR}" ]; then
        echo "WARNING: Skipping ${sample} (no bin_refinement/metawrap_70_10_bins folder)"
        continue
    fi

    if [ -d "${OUT_DIR}" ] && [ -n "$(ls -A ${OUT_DIR} 2>/dev/null)" ]; then
        echo "INFO: Skipping ${sample} (gtdbtk_out already populated)"
        continue
    fi

    mkdir -p "${OUT_DIR}"

# ====== SLURM script creation ================
    cat > "/tmp/gtdbtk_${sample}.sh" << EOF
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --cpus-per-task=192
#SBATCH --time=2:00:00
#SBATCH --job-name=gtdbtk_${sample}
#SBATCH --output=${SCRATCH_DIR}/gtdbtk_${sample}.out
#SBATCH --error=${SCRATCH_DIR}/gtdbtk_${sample}.err

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# @@ ===== GTDBTK - May need to be modified by user ======== @@
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
module load gtdbtk/2.3.2 || true
source /home/fry/Astaroth/bin/activate || true

echo "Running GTDB-Tk for ${sample} at \$(date)"
gtdbtk classify_wf \\
  --genome_dir ${BIN_DIR} \\
  --out_dir ${OUT_DIR} \\
  --data_dir ${GTDBTK_DB} \\
  --cpus 64

echo "GTDB-Tk completed for ${sample} at \$(date)"
EOF

# ===== Submit job ================================
    job_output=$(sbatch "/tmp/gtdbtk_${sample}.sh" 2>&1)
    if [ $? -eq 0 ]; then
        job_id=$(echo ${job_output} | awk '{print $NF}')
        ((submitted++))
        echo "[$(date '+%H:%M:%S')] Submitted ${sample} (Job ID: ${job_id}) - ${submitted}/${#samples[@]}"
    else
        echo "ERROR: Failed to submit ${sample}: ${job_output}"
    fi

 # ==== Wait for slots =============================
    current_jobs=$(count_jobs)
    while [ ${current_jobs} -ge ${MAX_CONCURRENT_JOBS} ]; do
        echo "[$(date '+%H:%M:%S')] ${current_jobs}/${MAX_CONCURRENT_JOBS} active jobs. Waiting..."
        sleep 60
        current_jobs=$(count_jobs)
    done
done

echo ""
echo "All GTDB-Tk classification jobs submitted!"
echo "Monitor with: squeue -u ${USERNAME} | grep gtdbtk"
```
