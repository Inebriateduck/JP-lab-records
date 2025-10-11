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
