Installing, setting up and running BAKTA

first, I'm making a new venv so it can work seperately. Venv is called Balam. Then I'm installing Bakta

```
python3 pip install bakta
```
module spider shows that most packages are contained in StdEnv/2023. Those that aren't can be installed via pip. The one exception to that is AMRfinderPLUS. The version on stdENV is deprecated and hasn't been updated for 
some reason - consequently, I had to compile it from the source manually and added it to my PATH. fun stuff. Directions to do so can be found [here](https://github.com/ncbi/amr/wiki/Compile-from-source). Once that was done I installed the bakta db

```
bakta_db download --output /scratch/fry/Balam/bin/Bakta/ --type full
```

