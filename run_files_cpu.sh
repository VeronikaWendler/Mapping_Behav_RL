#!/bin/bash
#SBATCH --job-name=sem_ratings_openai
#SBATCH --account=zhanglp-vwendler-core
#SBATCH --qos=bbdefault
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=logs/%x.%j.out
#SBATCH --error=logs/%x.%j.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=VAW508@student.bham.ac.uk

set -euo pipefail
mkdir -p logs

module purge
module load bear-apps/2024a/live

source ~/apps/miniforge3/etc/profile.d/conda.sh
conda activate mapping_abm

export OPENAI_API_KEY="$(cat /rds/projects/z/zhanglp-vwendler-core/SECRETS/openai_api_key.txt)"
export OPENAI_MODEL="gpt-4.1-mini"              
export OPENAI_URL="https://api.openai.com/v1/chat/completions"

export MAX_PAIRS=15000
export BATCH_SIZE=100
export WORKERS=6
export TIMEOUT=120
export RETRIES=6
export FORCE_START=7000

cd ~/projects/Mapping_Behav_RL
python Mapping_landscape_ABM/2.1_semantic_ratings.py