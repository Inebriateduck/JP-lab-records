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
