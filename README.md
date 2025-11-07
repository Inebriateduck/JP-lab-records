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

