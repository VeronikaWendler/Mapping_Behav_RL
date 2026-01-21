#!/bin/bash
#SBATCH --job-name=2.1_semantic_ratings                      # should be changed to whatever you are running, otherwise confusion 
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

source ~/apps/miniforge3/etc/profile.d/conda.sh
conda activate mapping_abm
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"                # to prefer conda's module
unset LD_PRELOAD


export HF_HOME=$HOME/.cache/huggingface
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export MPLCONFIGDIR=${SLURM_TMPDIR:-/tmp}/mplcache
export PYTHONUNBUFFERED=1
export TOKENIZERS_PARALLELISM=false

cd ~/projects/Mapping_Behav_RL

# This  is for a test ...

echo "CONDA_PREFIX=$CONDA_PREFIX"
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
echo "which python3: $(which python3)"
python3 -c "import ssl,sys; print('py:',sys.executable); print('openssl:',ssl.OPENSSL_VERSION)"

echo "---- ldd _ssl ----"
ldd "$CONDA_PREFIX/lib/python3.10/lib-dynload/_ssl.cpython-310-x86_64-linux-gnu.so" | egrep "crypto|ssl|not found" || true

# End of test 


Rscript Mapping_landscape_ABM/3_taxonomy.R        # change to Rscript or python 


