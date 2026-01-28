#!/bin/bash
#SBATCH --job-name=2_semantic_net                    # should be changed to whatever you are running, otherwise confusion 
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=6
#SBATCH --mem=128G
#SBATCH --output=logs/%x.%j.out
#SBATCH --error=logs/%x.%j.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=VAW508@student.bham.ac.uk

set -euo pipefail
mkdir -p logs

module purge
module load bear-apps/2024a/live
module load R/4.5.0-gfbf-2024a

export HF_HOME=$HOME/.cache/huggingface
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1

export MPLCONFIGDIR=${SLURM_TMPDIR:-/tmp}/mplcache
export PYTHONUNBUFFERED=1
export TOKENIZERS_PARALLELISM=false

# this is my project folder with code
cd ~/projects/Mapping_Behav_RL

source ~/apps/miniforge3/etc/profile.d/conda.sh
conda activate mapping_abm
Rscript Mapping_landscape_ABM/2_semantic_net.R         # or python or Rscript

