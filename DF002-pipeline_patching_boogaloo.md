The way that the Quackers pipeline was originially set up means that metawrap doesnt actually select for the best bins. It just dumps all of them. Which is extreamly fucking bad if you're dealing with the amount of data that I am. 
What I'm going to do instead is to attempt to manually run metawrap and get the best bins that way, then run them through the rest of the pipeline. 

==== Manual access of mwrap ====

```
singularity shell quackers_v1.0.5.sif
cd quackers_pipe/quackers_tools
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
