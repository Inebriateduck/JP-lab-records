Goal here is to get the quackers pipeline to work. It's currently crashing at step 3 (concoct) and I don't know why. Initial analysis of the available modules on trillium shows that concot is not an 
available module. I'm wondering if thats the issue. Maybe I can install it in a VENV and call it for the pipeline?

===== Fix? =====

I dug through the error logs and got this:

```
Up and running. Check /scratch/fry/child_mgx_out/7_116980_1_2/3a_concoct_binning/data/concoct_run_log.txt for progress
Setting 192 OMP threads
Generate input data
OpenBLAS warning: precompiled NUM_THREADS exceeded, adding auxiliary array for thread metadata.
To avoid this warning, please rebuild your copy of OpenBLAS with a larger NUM_THREADS setting
or set the environment variable OPENBLAS_NUM_THREADS to 128 or lower
Segmentation fault (core dumped)
Process Process-10:
Traceback (most recent call last):
  File "/opt/conda/lib/python3.10/multiprocessing/process.py", line 314, in _bootstrap
    self.run()
  File "/opt/conda/lib/python3.10/multiprocessing/process.py", line 108, in run
    self._target(*self._args, **self._kwargs)
  File "/quackers_pipe/MetaPro_utilities_v2.py", line 296, in create_and_launch_v2
    sp.check_output(["sh", job_path])#, stderr = sp.STDOUT)
  File "/opt/conda/lib/python3.10/subprocess.py", line 421, in check_output
    return run(*popenargs, stdout=PIPE, timeout=timeout, check=True,
  File "/opt/conda/lib/python3.10/subprocess.py", line 526, in run
    raise CalledProcessError(retcode, process.args,
subprocess.CalledProcessError: Command '['sh', '/scratch/fry/child_mgx_out/7_116980_1_2/3a_concoct_binning/cct.sh']' returned non-zero exit status 139
```
Maybe the number of threads that the process is using is causing concot to crash since the script calls all 192 available cores. I'm going to try limiting them. 

==== Thread limiting ====

Before the singularity line I've inserted a limiter (it can likely be fine tuned in the future...)

```
export OPENBLAS_NUM_THREADS=64
export OMP_NUM_THREADS=64
```

128 threads seems to fail, but 100 threads works fine... idk why. 

===== Results =====

Running 
```
sbatch 7_116980_1_2.sh
```

Job request is complete. Tailing the logs file outputs:

```
tail -f /scratch/fry/child_mgx_out/7_116980_1_2/bypass_log.txt

3c_metabat2_binning

3b_maxbin2_binning

4_mwrap_bin_r

5_gtdbtk_classify

6_metawrap_quant_bins
```
I'm assuming the process is done, but I want to validate the data before I push the entire set of CHILD samples through. The data outputs do look good, but there is a large amount of NA, I'm wondering if thats just a quirk of the pipeline. Anyways, there are hits for certain bacteria in there, so it should be usable, espeically since they have linked identities. 

==== Bfifidobacteria hunt ====
```
awk -F'\t' '$2 ~ /Bifidobacterium/' gtdbtk.bac120.summary.tsv > Bifido_7_116980_1_2.tsv
```
```
User_genome	classification	closest_genome_reference  (I ain't pasting the whole thing) 
Refined_1088	d__Bacteria;p__Actinomycetota;c__Actinomycetes;o__Actinomycetales;f__Bifidobacteriaceae;g__Bifidobacterium;s__	N/A
Refined_366	d__Bacteria;p__Actinomycetota;c__Actinomycetes;o__Actinomycetales;f__Bifidobacteriaceae;g__Bifidobacterium;s__Bifidobacterium dentium	GCF_001042595.1
Refined_368	d__Bacteria;p__Actinomycetota;c__Actinomycetes;o__Actinomycetales;f__Bifidobacteriaceae;g__Bifidobacterium;s__Bifidobacterium breve	GCF_001025175.1
Refined_375	d__Bacteria;p__Actinomycetota;c__Actinomycetes;o__Actinomycetales;f__Bifidobacteriaceae;g__Bifidobacterium;s__Bifidobacterium longum	GCF_000196555.1
Refined_376	d__Bacteria;p__Actinomycetota;c__Actinomycetes;o__Actinomycetales;f__Bifidobacteriaceae;g__Bifidobacterium;s__Bifidobacterium longum	GCF_000196555.1
```
According to NJ this is actually a really high yield. We now know that the pipeline works - next step is figuring out how to batch the files properly so that I don't light the cluster on fire.

======================== EDIT ===================================

PYSCH! pipeline's cooked. See DF002 for more information. 

```
                            Pipeline's Closed
                                                                 
                               ░░░░░░░░░░░░░                             
                             ░░░░░░░▒░▒▒▒▒▒░░░░░░░                       
                         ░░░░░░░░░░░░░░░░░░░░░▒▒▒░░░░                    
                      ░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒░░░                  
                     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒░░░░░░             
                    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒░░░            
                  ░░▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒░░           
                  ░░▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒░░          
                 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒░░░        
                 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒░░░       
                ░░░▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒░░       
                ░░░▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░       
               ░░▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░     
               ░░▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░     
               ░░▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░     
               ░░▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░      
                ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░       
                ░░░▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░        
                ░░░░░░░░▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░        
                 ░░░░░▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒░░          
                 ░░░░▒░░░░▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           
                    ░▒███▓░▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░▒░░░░           
                    ░▒░▒██░▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░▒░░░            
                    ░▒▒░░█░▒▒▒██▓▒░▒▒▒░░░░░░░░░░░░░░░░░░░░░░             
                    ░▒▒▒▒░▒▒▒▒░██▓░▒▒▒▒▒░░░░░░░░░░░░░░░░░                
                    ░▒▒░░▒▒▒▒▒▒░██▒▒▒▒▒▒▒░▒▒░░░░░░░░░                    
                    ░▒▒░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░                      
                    ░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░                        
                     ░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░▒░░░░                          
                    ░░░▒▒▒░░░░▒▒▒▒▒▒▒▒░░▒▒░██░░                          
                  ░░░▓░░▒▒▒▒▒▒▒▒▒▒▒▒▒░░▒▒░███░░░░                        
                 ░░▓▓▓▒▒▒░░▒▒▒▒▒▒░░░▒▒░▒██░▒▒▓▓▓▓▒░                      
                ░░▒▓▓▓▒▒▒░▒░░░░░░░▒▒░░███░▒▓▓▓▓▓▓▒▒░                     
                ░▒▓▓▓▒▓▒░██░░▒▒▒░░▒███▓░▒▓▓▓▓▓▓▓▓▓▓▒░                    
                ░▒▓▓▓▒▓▒░███▓░░░█████░▒▒▓▒▓▓▓▓▓▓▓▓▓▒░                    
                ░▒▒░▓▒▓▒░░▒▓██▒████░▒▓▒▒▓▓▓▓▓▓▓▓▓▓▓▒░                    
                ░▒▒░▒▓▒▒░█░██▓▒░█▓░▒▓▒▒▓▓▓▓▓▓▓▓▓▓▓▓▒░                    
                ░▒▒░▒▓▒▒░██░▒▓░█░▒▒▒▒▓▓▓▒▓▒░▒▓▓▓▓▓▓▒░                    
                ░▒▒░▒▓▒▒░█░██▓░█░▒▒▒▓▓▒▒▓▒▒░░▒▓▓▓▓▓▒░                    
                ░▒▒░▒▓▓▒▒░▓██▓░░▒▒▒▒▓▓▒▒▓▒▒░░▒▓▓▓▓▓▒░                    
                ░▒▒░▒▓▓▒▒░▓▓▓▓░░▓▒▓█▒▓▓▒▒▒▒░░▒▓▓▓▓▓▒░                    
                ░▒▒░▒▓▓▓▓▒░▒▒░▒▓▒▓▓▒█▓▓▒▒▒▒░░▒▓▓▓▓▓▒░                    
                ░██░▒▓▓▓▓▓░▒░░▓▓▓▓▓▓▒░▒▒▓▒▒░░▒▓▓▓▓▓▒░                    
                ░▒▒░▒▓▓▓▓▓▓░░▒▓▓▓▓▓▓▓▓▒▒▒▒▒░░▒▓▓▓▓▓▒░                    
                ░▒░░▒▓▓▓▓▓▓░▒▓▓▓▓▓▓▓▓▓▓▒▒▒▒░░▒▓▓▓▓▓▒░                    
                ░▒░░▒▓▓▓▓▓▓░░▒▓▓▓▓▓▓▓▓▓▒▒▒▒░░▒▓▓▓▒▒▒░                    
                ░░▒▒░▒▓▓▓▓▓░▒▓▒▓▓▓▓▓▓▓▒▒▓▒▒░░▒▓▒░███░                    
                 ░░░░░░░░▒░░░▒▓▓▓▓▓▓▓▓▒▒▒▒▒░▒██████▓░                    
                      ░░▒▒▒▒░░▒▓▓▓▓▓▓▓▓▒▒▒▒░▓███░░░▒░                    
                     ░░▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓▒▒▒▒▒░░▓░░▒▒▒▒░                    
                     ░▒▒▒▒▒▒▒▒░▒░▒▒▓▓▓▒▒▓▒░░░▒▒▒▒░░▒░                    
                     ░▒▒▒▒▒▒▒▒░▒▒▒░░▒▒▒▒▒▒░▒▒░▒░▒░░░░                    
                    ░▒▒▒▒▒▒▒▒▒░▒▒▒▒▒▒▒▒▒░░░░░░▒░░░                       
                    ░▒▒▒▒▒▒▒▒▒░▒▒▒▒▒▒▒▒▒▒▒▒░░░░                          
                    ░▒▒▒▒▒▒▒▒▒░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░                          
                    ░▒▒▒▒▒▒▒▒▒░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░                         
                     ░▒▒▒▒▒▒░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░                        
                  ██░░░░░▒▒▒░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░                       
                  ░░▒▒▒▒▒▒▒░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░                       
                ░░▒▒▒▒▒▒▒▒▒▒▒▒░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░                       
                ░▒▒▓▓▓▓▒▒▒▒▒░░▒▒▒░░░▒▒▒▒▒▒▒▒▒▒░                          
                ░▒▒▒▒▒▒▒▒▒░░▒▒▒▒▒▒▒▒░░▒▒▒▒▒░░░░                          
                 ░░░▒▒▒▒▒░▒▓▓▓▓▒▒▒▒▒▓▒▒▒▒▒▒▒▒▒░                          
                    ░░░░░░▒▒▒▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒░░░                          
                          ░▒▒▒▒▒▒▒▒▒▒▒▒░░░                               
                           ░░░▒▒▒▒▒▒░░░░
``` 
