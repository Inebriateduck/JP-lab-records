Installing, setting up and running BAKTA for enzyme analysis

first, I'm making a new venv so it can work seperately. Venv is called Balam. Then I'm installing Bakta

```
python3 pip install bakta
```
module spider shows that most packages are contained in StdEnv/2023. Those that aren't can be installed via pip. The one exception to that is AMRfinderPLUS. The version on stdENV is deprecated and hasn't been updated for 
some reason - consequently, I had to compile it from the source manually and added it to my PATH. fun stuff. Directions to do so can be found [here](https://github.com/ncbi/amr/wiki/Compile-from-source). Once that was done I installed the bakta db.

```
bakta_db download --output /scratch/fry/Balam/bin/Bakta/ --type full
```

So it's a complete shitshow with my source built version of AMRFinderPlus. I'm making a docker image instead. 
```
apptainer pull docker://oschwengers/bakta
```

The boot in with ```apptainer shell bakta.sif``` and check installation with ```bakta --version``` any ```bakta``` command shouldn't work outside of the apptainer. 

```
Apptainer> bakta --version
bakta 1.11.4
```
Looks good. (Spoiler alert - it was not). 

Change of plans, I'm switching to using Mamba as was recommended to me by Ryan. Following Mamba install I created an ENV with ```mamba create -n bakta_env -c conda-forge -c bioconda python=3.10 bakta```. I then activate it with ```conda activate bakta_env```. 

Installation of Bakta + AMRfinder and checks ensues. 
```
mamba install -c conda-forge -c bioconda bakta ncbi-amrfinderplus
(bakta_env) [fry@tri-login01 fry]$ bakta --version
bakta 1.11.4
(bakta_env) [fry@tri-login01 fry]$ amrfinder --version
4.0.23
```

Everything looks good for now. Let's see if it works this time. 
```
amrfinder_update --force_update --database $SCRATCH/amrfinderplus_db
Running: amrfinder_update --force_update --database /scratch/fry/amrfinderplus_db
                                                                                Looking up the published databases at https://ftp.ncbi.nlm.nih.gov/pathogen/Antimicrobial_resistance/AMRFinderPlus/database/
Looking for the target directory: /scratch/fry/amrfinderplus_db/2025-07-16.1/
Downloading AMRFinder database version 2025-07-16.1 into: /scratch/fry/amrfinderplus_db/2025-07-16.1/
Running: /home/fry/miniforge3/envs/bakta_env/bin/amrfinder_index /scratch/fry/amrfinderplus_db/2025-07-16.1/
Indexing
amrfinder_index took 3 seconds to complete
amrfinder_update took 7 seconds to complete

bakta_db download --output $SCRATCH/bakta_db --type full
Bakta software version: 1.11.4
Required database schema version: 6

Selected DB type: full

Fetch DB versions...
        ... compatible DB versions: 1
Download database: v6.0, type=full, 2025-02-24, DOI: 10.5281/zenodo.14916843, URL: https://zenodo.org/record/14916843/files/db.tar.xz...
```
Testing it in a debugnode worked. SLURM script works as well and is called ```Wormwood.sh```. 

========= Generation of circular plots =================
So bakta has a tool in it's pipeline that generates plots of the genome which display the predicted proteins and coding/noncoding regions. If you run it in [COG mode](https://bakta.readthedocs.io/en/latest/cli/genomeplots.html) it will colour them based on clustered orthologous genes (COG). Unfortunately, I configured ```Wormwood.sh``` to run it in default mode. Thus I'm going to have to generate the plots from the .JSON files myself. 






