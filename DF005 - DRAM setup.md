Setting up DRAM since John suggested I use it. 

Initially I tried to set it up with Conda since it looked easier and was recommended. Big mistake - trillum (and comput canada in general) does not like it when you do that because it 
"creates a lot of files which degrades the performance of the file system and also interferes with your Python environment". IDK sounds like a skill issue from whoever designed the 
architecture, but I barely know how to code so what do I know. Proper installation with PIP can be done with the following steps. 

```
module load StdEnv/2023 python/3.11.5 scipy-stack/2025a
virtualenv ~/.virtualenvs/dramenv
source ~/.virtualenvs/dramenv/bin/activate
pip install DRAM-bio

DRAM-setup.py prepare_databases --output_dir DRAM_data
```

The download times are extremely long, in excess of an hour. I suggest running it in a screen on your local node so you can multitask. 
