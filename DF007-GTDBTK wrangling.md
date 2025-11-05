Using GTDBTK to examine our datasets because I am desperate for data at this point. Created a script that operates within the quackers apptainer to loop through and process all the bins from the metawrap out (run at 70, 10 cutoffs) and dump the results into the corresponding directory. Script is call ```Brimstone.sh```
```
#!/bin/bash

# Configuration
SIF_FILE="/scratch/fry/quackers_v1.0.5.sif"
GTDBTK_DB_HOST="/scratch/fry/gtdbtk_db/release226"
GTDBTK_DB_CONTAINER_TARGET="/quackers_tools/gtdbtk_data"
BASE_DIR="/scratch/fry/child_mgx_out/Anathema.out"
BIN_SUBDIR="bin_refinement/metawrap_70_10_bins"
SCRATCH_DIR="/scratch/fry"
MAX_CONCURRENT_JOBS=2
USERNAME="fry"

# Function to count running/pending jobs
count_jobs() {
    squeue -u ${USERNAME} -h -t PENDING,RUNNING -n gtdbtk_classify 2>/dev/null | wc -l
}

echo "Starting GTDB-Tk classification job submission..."
echo "Host Database path: $GTDBTK_DB_HOST"
echo "Container Target path: $GTDBTK_DB_CONTAINER_TARGET"
echo "Will maintain ${MAX_CONCURRENT_JOBS} concurrent jobs"
echo "----------------------------------------------------"

submitted=0
total=0

# Count total valid directories first
for BIN_DIR in "$BASE_DIR"/*/"$BIN_SUBDIR"; do
    if [ -d "$BIN_DIR" ]; then
        ((total++))
    fi
done

if [ $total -eq 0 ]; then
    echo "Error: No valid bin directories found matching pattern: $BASE_DIR/*/$BIN_SUBDIR"
    exit 1
fi

echo "Found ${total} samples to process"
echo ""

# Process each bin directory
for BIN_DIR in "$BASE_DIR"/*/"$BIN_SUBDIR"; do

    if [ ! -d "$BIN_DIR" ]; then
        continue
    fi

    PARENT_DIR=$(dirname $(dirname "$BIN_DIR"))
    OUTPUT_DIR="$PARENT_DIR/gtdbtk_out"
    SAMPLE_NAME=$(basename "$PARENT_DIR")

    # Skip if already processed
    if [ -d "${OUTPUT_DIR}" ] && [ -n "$(ls -A ${OUTPUT_DIR} 2>/dev/null)" ]; then
        echo "INFO: Skipping ${SAMPLE_NAME} - output directory already exists and is not empty"
        continue
    fi

    # Check if bin directory has any .fa files
    if [ -z "$(ls -A ${BIN_DIR}/*.fa 2>/dev/null)" ]; then
        echo "WARNING: Skipping ${SAMPLE_NAME} - no .fa files found in bin directory"
        continue
    fi

    # Wait until we have a slot BEFORE preparing job
    current_jobs=$(count_jobs)
    while [ ${current_jobs} -ge ${MAX_CONCURRENT_JOBS} ]; do
        echo "[$(date '+%H:%M:%S')] ${current_jobs}/${MAX_CONCURRENT_JOBS} jobs active. Waiting for a slot..."
        sleep 30
        current_jobs=$(count_jobs)
    done

    echo "Preparing job for: $SAMPLE_NAME"
    echo "  Bins: $BIN_DIR"
    echo "  Output: $OUTPUT_DIR"

    # Create output directory
    mkdir -p "${OUTPUT_DIR}"

    # Create SLURM script for this sample
    cat > "/tmp/submit_gtdbtk_${SAMPLE_NAME}.sh" << EOF
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --cpus-per-task=192
#SBATCH --time=1:00:00
#SBATCH --job-name=gtdbtk_classify
#SBATCH --output=${SCRATCH_DIR}/gtdbtk_classify_${SAMPLE_NAME}.out
#SBATCH --error=${SCRATCH_DIR}/gtdbtk_classify_${SAMPLE_NAME}.err

echo "Starting GTDB-Tk classification for ${SAMPLE_NAME}"
echo "Bins directory: ${BIN_DIR}"
echo "Output directory: ${OUTPUT_DIR}"
echo "----------------------------------------------------"

singularity exec \\
    --bind "${BIN_DIR}":/bins \\
    --bind "${GTDBTK_DB_HOST}":"${GTDBTK_DB_CONTAINER_TARGET}" \\
    --bind "${OUTPUT_DIR}":/gtdbtk_out \\
    --env GTDBTK_DATA_PATH="${GTDBTK_DB_CONTAINER_TARGET}" \\
    "${SIF_FILE}" gtdbtk classify_wf \\
    --genome_dir /bins \\
    --out_dir /gtdbtk_out \\
    --cpus 192 \\
    --extension fa \\
    --skip_ani_screen \\
    --force \\
    --scratch_dir /tmp/gtdbtk_scratch

if [ \$? -eq 0 ]; then
    echo "Successfully completed GTDB-Tk for ${SAMPLE_NAME}"
else
    echo "!! ERROR during GTDB-Tk for ${SAMPLE_NAME} !!"
    exit 1
fi
EOF

    # Submit the job
    job_output=$(sbatch "/tmp/submit_gtdbtk_${SAMPLE_NAME}.sh" 2>&1)
    if [ $? -eq 0 ]; then
        job_id=$(echo ${job_output} | awk '{print $NF}')
        ((submitted++))
        echo "[$(date '+%H:%M:%S')] Submitted ${SAMPLE_NAME} (Job ID: ${job_id}) - Total submitted: ${submitted}/${total}"
    else
        echo "ERROR: Failed to submit job for ${SAMPLE_NAME}: ${job_output}"
    fi

    # Small delay to let squeue update
    sleep 2
done
```
I then extract the desired taxa with ```Gehenna.py``` (which also generates a binary presence / absence matrix) 

```
#!/usr/bin/env python3
"""
Generate a presence/absence matrix from GTDB-Tk classification results.
Rows = taxonomic classifications, Columns = samples
"""

import os
import sys
import glob
from collections import defaultdict
import argparse

def parse_gtdbtk_taxonomy(taxonomy_string, level):
    """
    Extract taxonomic rank from GTDB taxonomy string.

    Args:
        taxonomy_string: Full GTDB taxonomy (e.g., "d__Bacteria;p__Bacillota;...")
        level: Taxonomic level (domain, phylum, class, order, family, genus, species)

    Returns:
        Taxonomic name at specified level
    """
    level_map = {
        'domain': 'd__',
        'phylum': 'p__',
        'class': 'c__',
        'order': 'o__',
        'family': 'f__',
        'genus': 'g__',
        'species': 's__'
    }

    if level not in level_map:
        raise ValueError(f"Invalid taxonomic level: {level}")

    prefix = level_map[level]

    # Split taxonomy string by semicolon
    ranks = taxonomy_string.split(';')

    # Find the rank with the matching prefix
    for rank in ranks:
        if rank.startswith(prefix):
            # Remove prefix and return
            taxon = rank.replace(prefix, '').strip()
            # Return full taxonomy up to this level for context
            return taxon if taxon else f"Unclassified_{level}"

    return f"Unclassified_{level}"

def read_gtdbtk_summary(file_path, taxonomic_level):
    """
    Read GTDB-Tk summary file and extract taxonomic classifications.

    Args:
        file_path: Path to gtdbtk.bac120.summary.tsv
        taxonomic_level: Which taxonomic level to extract

    Returns:
        Set of taxonomic classifications found in this sample
    """
    taxa = set()

    try:
        with open(file_path, 'r') as f:
            for line in f:
                # Skip header
                if line.startswith('user_genome'):
                    continue

                fields = line.strip().split('\t')
                if len(fields) < 2:
                    continue

                # Second column contains the classification
                classification = fields[1]

                # Extract taxonomic level
                taxon = parse_gtdbtk_taxonomy(classification, taxonomic_level)
                taxa.add(taxon)

        return taxa

    except FileNotFoundError:
        print(f"Warning: File not found: {file_path}", file=sys.stderr)
        return set()
    except Exception as e:
        print(f"Error reading {file_path}: {e}", file=sys.stderr)
        return set()

def main():
    parser = argparse.ArgumentParser(
        description='Generate presence/absence matrix from GTDB-Tk results',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Species-level matrix
  python gtdbtk_taxonomy_matrix.py -i /scratch/fry/child_mgx_out/Anathema.out -o species_matrix.tsv -l species

  # Genus-level matrix
  python gtdbtk_taxonomy_matrix.py -i /scratch/fry/child_mgx_out/Anathema.out -o genus_matrix.tsv -l genus
        """
    )

    parser.add_argument('-i', '--input', required=True,
                        help='Base directory containing sample subdirectories (e.g., Anathema.out)')
    parser.add_argument('-o', '--output', required=True,
                        help='Output TSV file for presence/absence matrix')
    parser.add_argument('-l', '--level', required=True,
                        choices=['domain', 'phylum', 'class', 'order', 'family', 'genus', 'species'],
                        help='Taxonomic level to extract')

    args = parser.parse_args()

    base_dir = args.input
    output_file = args.output
    taxonomic_level = args.level

    print(f"Scanning directory: {base_dir}")
    print(f"Taxonomic level: {taxonomic_level}")
    print("-" * 60)

    # Dictionary to store presence/absence data
    # Key: taxon name, Value: dict of {sample: 1}
    taxon_matrix = defaultdict(lambda: defaultdict(int))

    # Find all sample directories
    pattern = os.path.join(base_dir, '*', 'gtdbtk_out', 'gtdbtk.bac120.summary.tsv')
    summary_files = glob.glob(pattern)

    if not summary_files:
        print(f"Error: No GTDB-Tk summary files found matching pattern: {pattern}")
        sys.exit(1)

    print(f"Found {len(summary_files)} samples")
    print()

    # Collect all samples
    samples = []

    # Process each sample
    for summary_file in sorted(summary_files):
        # Extract sample name from path
        # Path format: /path/to/Anathema.out/SAMPLE_NAME/gtdbtk_out/gtdbtk.bac120.summary.tsv
        sample_name = summary_file.split('/')[-3]
        samples.append(sample_name)

        print(f"Processing: {sample_name}")

        # Read taxa from this sample
        taxa = read_gtdbtk_summary(summary_file, taxonomic_level)

        print(f"  Found {len(taxa)} unique {taxonomic_level}-level taxa")

        # Mark presence (1) for each taxon in this sample
        for taxon in taxa:
            taxon_matrix[taxon][sample_name] = 1

    print()
    print("-" * 60)
    print(f"Total unique {taxonomic_level}-level taxa: {len(taxon_matrix)}")
    print(f"Total samples: {len(samples)}")

    # Write output matrix
    print(f"Writing output to: {output_file}")

    with open(output_file, 'w') as out:
        # Write header
        out.write(f"{taxonomic_level}\t" + "\t".join(samples) + "\n")

        # Write each taxon row
        for taxon in sorted(taxon_matrix.keys()):
            row = [taxon]

            # Add presence/absence for each sample (0 if not present, 1 if present)
            for sample in samples:
                row.append(str(taxon_matrix[taxon][sample]))

            out.write("\t".join(row) + "\n")

    print("Done!")
    print()
    print("Summary statistics:")
    print(f"  Rows (taxa): {len(taxon_matrix)}")
    print(f"  Columns (samples): {len(samples)}")

    # Calculate some basic stats
    total_presences = sum(sum(sample_dict.values()) for sample_dict in taxon_matrix.values())
    total_cells = len(taxon_matrix) * len(samples)
    sparsity = (1 - total_presences / total_cells) * 100 if total_cells > 0 else 0

    print(f"  Total presences: {total_presences}")
    print(f"  Matrix sparsity: {sparsity:.2f}% (cells with 0)")

if __name__ == '__main__':
    main()
```
I then generate a binary heatmap in R for visualization of presence / absence (I'm hoping something will pop out here). This step uses the script gtdbtk_heatmap.R (not shown). Generated heatmaps are labeled Genus, Family and Species matrices and are available in the matrices folder. 

================ RESULTS ============================
GTDBTK pulled up hits for B. infantis... I didn't even know the DB was up to date enough to be able to do that. 

Searching the generated samples for B. infantis confirms that they are in fact there 
```
(base) [fry@tri-login01 Anathema.out]$ awk -F'\t' '
> NR==1 { # Save header
>     for (i=2; i<=NF; i++) header[i]=$i
> }
> $1=="Bifidobacterium infantis" { # Find the row
>     printf "Columns with 1 for %s: ", $1
>     for (i=2; i<=NF; i++) {
>         if ($i==1) printf "%s ", header[i]
>     }
>     print ""
> }
> ' species_matrix.tsv
awk: fatal: cannot open file `species_matrix.tsv' for reading: No such file or directory
(base) [fry@tri-login01 Anathema.out]$ cd ..
(base) [fry@tri-login01 child_mgx_out]$ cd ..
(base) [fry@tri-login01 fry]$ awk -F'\t' '
> NR==1 { # Save header
>     for (i=2; i<=NF; i++) header[i]=$i
> }
> $1=="Bifidobacterium infantis" { # Find the row
>     printf "Columns with 1 for %s: ", $1
>     for (i=2; i<=NF; i++) {
>         if ($i==1) printf "%s ", header[i]
>     }
>     print ""
> }
> ' species_matrix.tsv
Columns with 1 for Bifidobacterium infantis: 7_048203 7_063632 7_127319 7_249526 7_258174 7_358160 7_358236
```
Performing further confirmation on one of the samples to ensure it wasnt an error in my initial grep pattern 

```
==== in 7_048203 ====
(base) [fry@tri-login01 gtdbtk_out]$ grep "s__Bifidobacterium infantis" gtdbtk.bac120.summary.tsv
bin.12  d__Bacteria;p__Actinomycetota;c__Actinomycetes;o__Actinomycetales;f__Bifidobacteriaceae;g__Bifidobacterium;s__Bifidobacterium infantis

===in 7_063632===
(base) [fry@tri-login01 gtdbtk_out]$ grep "s__Bifidobacterium infantis" gtdbtk.bac120.summary.tsv
bin.1   d__Bacteria;p__Actinomycetota;c__Actinomycetes;o__Actinomycetales;f__Bifidobacteriaceae;g__Bifidobacterium;s__Bifidobacterium infantis

=== in 7_127319 ===
(base) [fry@tri-login01 gtdbtk_out]$ grep "s__Bifidobacterium infantis" gtdbtk.bac120.summary.tsv
bin.1   d__Bacteria;p__Actinomycetota;c__Actinomycetes;o__Actinomycetales;f__Bifidobacteriaceae;g__Bifidobacterium;s__Bifidobacterium infantis  GCF_000269965.1 95.05   d__Bacteria;p__Actinomycetota;c__Actinomycetes;o__Actinomycetales;f__Bifidobacteriaceae;g__Bifidobacterium;s__Bifidobacterium infantis
```
Pattern checks out... that is B. infantis in several of our samples! 

Searching in the excel file sample_priority (which lists some of the sample IDs alongside the age at which the sample was taken). 
- 7_258174 is at 1 year
- 7_358236 is at 1 year
- The rest of the hits were not present in the document

This is very unexpected. For next steps I think we need to dig through the metadata to find out why this is happening, and also see how the rest of the samples differ. I need to generate relative abundance as well. 
