The way that the Quackers pipeline was originially set up means that metawrap doesnt actually select for the best bins. It just dumps all of them. Which is extreamly fucking bad if you're dealing with the amount of data that I am. 
What I'm going to do instead is to attempt to manually run metawrap and get the best bins that way, then run them through the rest of the pipeline. 

==== Manual access of mwrap ====

```
singularity shell quackers_v1.0.5.sif
cd /
cd quackers_tools
```

Attempting to run mwrap however, gives the following

```
Apptainer> metawrap --help
Illegal option --
/quackers_tools/metaWRAP-1.3/bin/metawrap: line 33: Usage:: No such file or directory
cannot find config-metawrap file - something went wrong with the installation!
```

Peeking into the execution code for mwrap shows that this is the block thats going wrong 

```
config_file=$(which config-metawrap)      <----- This line is causing the error
source $config_file
if [[ $? -ne 0 ]]; then
        echo "cannot find config-metawrap file - something went wrong with the installation!"
        exit 1
```

Possible fix (still confirming)

```
Apptainer> unset -f which
Apptainer> export PATH="/quackers_tools/metaWRAP-1.3/bin:$PATH"
Apptainer> metawrap assembly --help
```
Testing fix 

```
metawrap bin_refinement \
  -o /scratch/fry/child_mgx_out/7_116980_1_2/bin_refinement \
  -t 8 \
  -m 40 \
  -c 70 \
  -x 10 \
  -A /scratch/fry/child_mgx_out/7_116980_1_2/3a_concoct_binning/bins \
  -B /scratch/fry/child_mgx_out/7_116980_1_2/3b_maxbin2_binning/maxbin2/maxbin2_bins
```

Testing with a batch submission (cluster go brrrrrr)

```
#!/bin/bash 
#SBATCH --nodes=1
#SBATCH --cpus-per-task=192
#SBATCH --time=10:00:00
#SBATCH --job-name=bin_refinement_7_116980_1_2
#SBATCH --output=/scratch/fry/bin_refinement.out
#SBATCH --error=/scratch/fry/bin_refinement.err

mkdir -p /scratch/fry/bin_refinement

# Singularity container
singularity exec -B /home -B /scratch /scratch/fry/quackers_v1.0.5.sif bash << 'EOF'

# "which" fix
unset -f which

export PATH="/quackers_tools/metaWRAP-1.3/bin:$PATH"

# Python override (don't ask)
mkdir -p /tmp/python_override
ln -sf /opt/conda/bin/python3 /tmp/python_override/python2.7
ln -sf /opt/conda/bin/python3 /tmp/python_override/python
export PATH="/tmp/python_override:$PATH"

# CheckM path correction (again, don't ask)
export CHECKM_DATA_PATH=/opt/conda/checkm_data
echo "/opt/conda/checkm_data" > /tmp/checkm_data_path.txt
checkm data setRoot /opt/conda/checkm_data

# Running function
metawrap bin_refinement \
  -o /scratch/fry/bin_refinement \
  -t 192 \
  -m 100 \
  -c 70 \
  -x 10 \
  -A /scratch/fry/child_mgx_out/7_116980_1_2/3a_concoct_binning/bins \
  -B /scratch/fry/child_mgx_out/7_116980_1_2/3b_maxbin2_binning/maxbin2/maxbin2_bins \
  -C /scratch/fry/child_mgx_out/7_116980_1_2/3c_metabat2_binning/metabat2/metabat2_bins

EOF
```

The above script did workn initially, but failed to call the CheckM DB, which resulted in a failure to bin based on the best results. reworked it a bit.

```
#!/bin/bash 
#SBATCH --nodes=1
#SBATCH --cpus-per-task=192
#SBATCH --time=10:00:00
#SBATCH --job-name=bin_refinement_7_116980_1_2
#SBATCH --output=/scratch/fry/bin_refinement.out
#SBATCH --error=/scratch/fry/bin_refinement.err

mkdir -p /scratch/fry/bin_refinement

singularity exec -B /home -B /scratch /scratch/fry/quackers_v1.0.5.sif bash << 'EOF'

unset -f which
export PATH="/quackers_tools/metaWRAP-1.3/bin:$PATH"

# Create wrapper that intercepts python2.7 calls
mkdir -p /tmp/python_wrapper
cat > /tmp/python_wrapper/python2.7 << 'PYWRAP'
#!/bin/bash
script="$1"
# If it's binning_refiner.py (CheckM step), use python3
if [[ "$script" == *"binning_refiner.py"* ]]; then
    exec /opt/conda/bin/python3 "$@"
else
    # Everything else uses real python2.7 with its own packages
    export PYTHONPATH=/usr/local/lib/python2.7/site-packages
    exec /usr/local/bin/python2.7 "$@"
fi
PYWRAP
chmod +x /tmp/python_wrapper/python2.7

export PATH="/tmp/python_wrapper:$PATH"

export CHECKM_DATA_PATH=/opt/conda/checkm_data
checkm data setRoot /opt/conda/checkm_data

export MPLCONFIGDIR=/tmp/matplotlib_config_$$
mkdir -p $MPLCONFIGDIR

metawrap bin_refinement \
  -o /scratch/fry/bin_refinement \
  -t 192 \
  -m 100 \
  -c 70 \
  -x 10 \
  -A /scratch/fry/child_mgx_out/7_116980_1_2/3a_concoct_binning/bins \
  -B /scratch/fry/child_mgx_out/7_116980_1_2/3b_maxbin2_binning/maxbin2/maxbin2_bins \
  -C /scratch/fry/child_mgx_out/7_116980_1_2/3c_metabat2_binning/metabat2/metabat2_bins

EOF
```

Wrapper to run the initial processing automatically. This version also allows you to load the OPENBLAS threads variable up to 192 threads (jut don't touch the OMP threads)


```
#!/bin/bash
set -x  # Enable debug mode
INPUT_DIR="/scratch/fry/premature_stop_and_loop_test"
OUTPUT_BASE="/scratch/fry/child_mgx_out"
CONFIG_TEMPLATE="/scratch/fry/quackers.config.template"
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
#SBATCH --time=20:00:00
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

export OPENBLAS_NUM_THREADS=100
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=100
export NUMEXPR_NUM_THREADS=100
export BLIS_NUM_THREADS=100

echo "Starting job at $(date)"

# Run pipeline in background
singularity exec -B /home -B /scratch SIF_PLACEHOLDER python3 /quackers_pipe/quackers_pipe.py \
-1 R1_PLACEHOLDER -2 R2_PLACEHOLDER -o OUTDIR_PLACEHOLDER -c CONFIG_PLACEHOLDER --stop 3c_metabat2_binning &

PIPELINE_PID=$!
echo "Pipeline started with PID: $PIPELINE_PID at $(date)"

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
        # First job - no dependency
        JOB_OUTPUT=$(sbatch "${SLURM_SCRIPT}")
    else
        # Subsequent jobs - depend on previous job completion
        JOB_OUTPUT=$(sbatch --dependency=afterany:${PREV_JOB_ID} "${SLURM_SCRIPT}")
    fi
    
    # Extract job ID from sbatch output
    PREV_JOB_ID=$(echo "$JOB_OUTPUT" | awk '{print $NF}')
    echo "Job submitted for $JOBNAME with ID: $PREV_JOB_ID"
done

echo "Script completed"
```

I wonder if I can throttle up the threads to 192 now... (turns out you cant). 

Running some timing tests - for a pair of 4.4gb files the runtime stats are as follows 

```
JobID           JobName    Account    Elapsed  MaxVMSize     MaxRSS  SystemCPU    UserCPU ExitCode
------------ ---------- ---------- ---------- ---------- ---------- ---------- ---------- --------
258487         7_195178 rrg-jpark+   00:31:56                         00:00:00   00:00:00      0:0
```

multiply by 350 (approx) and you get 8 days to run the entire set. I think it might be worth submitting in multiple smaller batches. 

```
[fry@tri-login05 child_mgx_deep_data]$ find /scratch/fry/child_mgx_deep_data -maxdepth 1 -type f -name '*cleaned.fastq' | wc -l
778
```
There's 778 total cleaned files, so 389 sets of complete reads total. I'm going to split them into bins of ~25 because that would give the jobs some leeway in terms of the max runtime on the cluster. 
