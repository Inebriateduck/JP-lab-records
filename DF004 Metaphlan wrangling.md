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
```
Old key
k__Bacteria|p__Actinobacteria|c__Actinomycetia|o__Bifidobacteriales|f__Bifidobacteriaceae|g__Bifidobacterium|s__Bifidobacterium_longum|t__SGB17248

New key
k__Bacteria|p__Actinomycetota|c__Actinomycetes|o__Bifidobacteriales|f__Bifidobacteriaceae|g__Bifidobacterium|s__Bifidobacterium_longum|t__SGB17248
```
Merging the DBs
```
python3 metaphlan_longum_markers.py --mpa-db-directory /scratch/fry/Astaroth/lib/python3.10/site-packages/metaphlan/metaphlan_databases
```







