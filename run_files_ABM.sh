#!/bin/bash
#SBATCH --job-name=ABM_code                   # should be changed to whatever you are running, otherwise confusion 
#SBATCH --account=zhanglp-vwendler-core
#SBATCH --qos=bbdefault
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=6:00:00
#SBATCH --output=logs/%x.%j.out
#SBATCH --error=logs/%x.%j.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=VAW508@student.bham.ac.uk

set -euo pipefail
mkdir -p logs

module purge
module load bear-apps/2024a/live

unset HF_HUB_OFFLINE
unset TRANSFORMERS_OFFLINE

export MPLCONFIGDIR=${SLURM_TMPDIR:-/tmp}/mplcache
export PYTHONUNBUFFERED=1
export TOKENIZERS_PARALLELISM=false

# this is my project folder with code #
source ~/apps/miniforge3/etc/profile.d/conda.sh
conda activate mapping_abm
export RETICULATE_PYTHON=$(which python)
export RENVIRON_USER=/dev/null
export PYTHONNOUSERSITE=1


cd ~/projects/Mapping_Behav_RL

Rscript Mapping_landscape_ABM/4_clustering.R     # or python or Rscript ##

