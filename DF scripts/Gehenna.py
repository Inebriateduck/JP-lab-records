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
