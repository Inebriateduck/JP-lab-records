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

Wrapper 

```
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

    # Use unquoted EOT so variables expand immediately
    cat > "${SLURM_SCRIPT}" <<EOT
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --cpus-per-task=192
#SBATCH --time=20:00:00
#SBATCH --job-name=${JOBNAME}
#SBATCH --output=${OUTDIR}/${JOBNAME}.out
#SBATCH --error=${OUTDIR}/${JOBNAME}.err

export OPENBLAS_NUM_THREADS=100
export OMP_NUM_THREADS=100
export MKL_NUM_THREADS=100
export NUMEXPR_NUM_THREADS=100
export BLIS_NUM_THREADS=100

singularity exec -B /home -B /scratch ${SIF_FILE} python3 /quackers_pipe/quackers_pipe.py \
-1 ${R1_FILE} -2 ${R2_FILE} -o ${OUTDIR} -c ${CONFIG_FILE} --stop 3c_metabat2_binning
EOT

    echo "Script content:"
    cat "${SLURM_SCRIPT}"

    echo "Submitting job..."
    if [[ -z "$PREV_JOB_ID" ]]; then
        # First job - no dependency
        JOB_OUTPUT=$(sbatch "${SLURM_SCRIPT}")
    else
        # Subsequent jobs - depend on previous job completion
        JOB_OUTPUT=$(sbatch --dependency=afterok:${PREV_JOB_ID} "${SLURM_SCRIPT}")
    fi

    # Extract job ID from sbatch output
    PREV_JOB_ID=$(echo "$JOB_OUTPUT" | awk '{print $NF}')
    echo "Job submitted for $JOBNAME with ID: $PREV_JOB_ID"
done
```
