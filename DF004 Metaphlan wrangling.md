Loggin how I installed metphlan4 as well as the specialized set of B infantis markers and merged the 2 DBS. This will be done in a venv due to limitations on Trillium. 

Venv creation: 
```
virtualenv --no-download Astaroth #<------------- venv name 

source Astaroth/bin/activate 
```
venv is now active. I will now load modules and install desired programs 

```
module load python3.10
```
installing metaphlan4 
```
pip install metaphlan
```
installing dependencies once complete 
```
metaphlan --install
```
Once this is done all metaphlan dependices should be present in the venv except for bt2 - this will need to be activated since it is a module, and will be done later. 
Before that, the modified *B. infantis* markers need to be installed. 

```
git clone https://github.com/yassourlab/MetaPhlAn-B.infantis/
```

Setting up the DB was a real pain and required updating some of the keys since the infantis markers were built with an older version of metaphlan. I used Sed to find and replace the key locations in the infantis script since the locations were hardcoded in. 

Old key
```
k__Bacteria|p__Actinobacteria|c__Actinomycetia|o__Bifidobacteriales|f__Bifidobacteriaceae|g__Bifidobacterium|s__Bifidobacterium_longum|t__SGB17248
```
New key
```
k__Bacteria|p__Actinomycetota|c__Actinomycetes|o__Bifidobacteriales|f__Bifidobacteriaceae|g__Bifidobacterium|s__Bifidobacterium_longum|t__SGB17248
```
Merging the DBs
```
python3 metaphlan_longum_markers.py --mpa-db-directory /scratch/fry/Astaroth/lib/python3.10/site-packages/metaphlan/metaphlan_databases

output location: /scratch/fry/Astaroth/bin/MetaPhlAn-B.infantis/mpa_vJan25_CHOCOPhlAnSGB_lon_subsp
```

Now I need to test that the new DB actually works. I'm going to be using the data from [Ennis et al.](https://www.nature.com/articles/s41467-024-45209-y) who also made the infantis markers. Their Bioproject has 80 different reads and they collected 80 stool samples so I should be able to just pick and assemble a single fastQ file and run that as a test. 

Using ENA to download a select sample 
```
wget -nc ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR252/030/SRR25256430/SRR25256430.fastq.gz
```

Running through my established workflow. Anathema_infantis.sh is a modified version of Anathema.sh made to accept just a single read since there is no reverse read in the Ennis DB. 

```
mass_cleaner.sh -> Anathema_infantis -> metawrap -> metaphlan
```

... Ennis et al. didn't use paired end reads, it's just single direction as far as I can tell. They didn't even assemble MAGs... I cannot use this as a control. John has reached out to Aline who originally modified the DB for use on a bangladeshi cohort - we're going to see if I can use some of their data as a control. 

Downloading Alines data from 
```
wget -nc ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR140/062/ERR14043662/ERR14043662_1.fastq.gz
wget -nc ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR140/062/ERR14043662/ERR14043662_2.fastq.gz
```
The data is then run through the Anathema.sh script to complete the first 3 steps of the quackers pipeline, and Helios.sh to complete metawrap. 

