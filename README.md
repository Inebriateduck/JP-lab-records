# Simplified version of my workflow with the JP lab

This is designed to allow future use of my workflow until the quackers pipe is fully functional. All scripts in here are designed to be "fire and forget" - they can be run on an entire directory and will then iterate through the whole thing until completion. 

##  Step 1: Cleaning 
If you are using the same data that I was, the fastq files will need cleaning. This can be done via the mass_headercleaner.py and mass_headercleaner.sh scripts. once cleaned, move on to step 2. 

## Step 2: Segments 1-3c of quackers
Quackers is currently not capable of running step 4 (metawrap) properly due to what I suspect is differences in the versions of python used by the pipeline and checkM, which is required for metawrap. Consequently, I've had to truncate the pipeline. ```Anathema.sh``` is a script that iterates throuhgh a target directory, using a Regex to detect and process forward and reverse pairs. At the moment it can be manually run in parallel by renaming a copy of the script and providing a different directory. 

Prior to running, make your target directories by running splitter_config.slurm. and Make the appropriate modifications. 
```
#SBATCH --job-name=SAMPLEID_quackers <---- Insert job title here
#SBATCH --output=/scratch/fry/split_fastq_bins_%j.log <----\
#SBATCH --error=/scratch/fry/split_fastq_bins_%j.err  <---- Dump locations for error and .out files (change /fry/)
```
```
# Directories
INPUT_DIR="/scratch/fry/child_mgx_deep_data" <---- Swap /fry/ to your desired directory
OUTPUT_DIR="/scratch/fry/split_child_mgx_deep_data" <---- Swap /fry/ to your desired directory
mkdir -p "$OUTPUT_DIR"
```
```
# Number of bins
BINS=16 <---- Swap to desired bin number.
PAIRS_PER_BIN=$(( (TOTAL_PAIRS + BINS - 1) / BINS ))
```

Once you've split the pairs into your bins, you can run ```Anathema.sh``` with appropriate modifications. 
```
INPUT_DIR="/scratch/fry/split_child_mgx_deep_data/Bin_2_child_mgx_deep_data" <---- directory to your target bin
OUTPUT_BASE="/scratch/fry/child_mgx_out/Anathema.out" <---- directory to your output
CONFIG_TEMPLATE="/scratch/fry/Anathema.config" <---- location of config 
SIF_FILE="/scratch/fry/quackers_v1.0.5.sif" <---- location of quackers sif file
```

To run it in parallel, simply rename a copied version of the file and provide it a different input bin (ie, Bin2, Bin3, Bin4). 

## Step 3: Manual MetaWRAP
Since MetaWRAP is slightly (quite) jank, it calls the checkM DB in what is basically python for dinosaurs (python 2.7 came out in 2009 -_-) and the rest of the pipeline is called in more recent versions of python, there is a small (very large) disconnect in some of the functions and calling checkM fails. To bypass this, ```Samael.sh``` is a script that calls the checkM portions in a python 2.7 wrapper. It can be run on your output directory from step 2 to process all outputs in parallel automatically (The amount of parallel jobs can be set by you in the config section). It can be run with appropriate modifications. 
```
# Configuration
INPUT_DIR="/scratch/fry/child_mgx_out/Anathema.out" <---- path to output directory from step 2
SCRATCH_DIR="/scratch/fry" <---- top level bin
MAX_CONCURRENT_JOBS=20 <---- Job limit
USERNAME="fry" <----- your username here
```
```
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --cpus-per-task=192
#SBATCH --time=1:00:00
#SBATCH --job-name=bin_refinement_${sample} <----- job name
#SBATCH --output=${SCRATCH_DIR}/bin_refinement_${sample}.out <---- Dump sites for error and .out files (change /fry/)
#SBATCH --error=${SCRATCH_DIR}/bin_refinement_${sample}.err <-----/ 
```
```
echo "Monitor progress with: watch -n 30 'squeue -u ${USERNAME}'" <---- this is why you need your username
                                       ^--- Monitors every 30 seconds
```
## Step 4: GTDBTK run
GTDBTK is used to classify the MAGs generated in step 2 and binned in step 3 taxonomically. It can be run on the previously generated bins by running ```Brimstone.sh``` with appropriate modifactions
```
SIF_FILE="/scratch/fry/quackers_v1.0.5.sif" <----- quackers sif file location
GTDBTK_DB_HOST="/scratch/fry/gtdbtk_db/release226" <----- GTDBTK DB location
GTDBTK_DB_CONTAINER_TARGET="/quackers_tools/gtdbtk_data" 
BASE_DIR="/scratch/fry/child_mgx_out/Anathema.out" <----- Step 2 output
BIN_SUBDIR="bin_refinement/metawrap_70_10_bins" <------ Bins from Step 3
SCRATCH_DIR="/scratch/fry" <------- your scratch dir here
MAX_CONCURRENT_JOBS=2 <----- change to increase job number
USERNAME="fry" <------ your unsername
```
## Step 5: BAKTA run
Bakta is used to generate gene predictions for each MAG in each of the bins. Setting it up is a bit complicated - I would strongly reccommend first installing a mamba env or using mine which is preconfigured at /home/fry/miniforge3/envs/bakta_env (if you can access it). Installing in mamba is not that hard. 
```
##### ONCE MAMBA INSTALLED ###########
apptainer exec --cleanenv \
    --home /scratch/fry:/home/fry \ <---- your home dir
    bakta.sif /opt/conda/bin/bakta \ 
    --db /scratch/fry/bakta_db \ <------ where you want the db installed
    --output /scratch/fry/bakta_db <---- where you want the output of the db
```
Once installed, you can run Bakta on your MAG bins by running ```Wormwood.sh``` with appropriate modifications. 

```
BASE_DIR="/scratch/fry/child_mgx_out/Anathema.out" <--- output from step 3
BAKTA_DB="/scratch/fry/bakta_db/db" <--- bakta DB location
CONDA_ENV="bakta_env"
```
This step will take the longet due to how it queues up jobs and the large amount it needs to do, even if each one only takes 15 mins max. 


