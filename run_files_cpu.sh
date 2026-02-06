#!/bin/bash
#SBATCH --job-name=ollama_gpu
#SBATCH --account=zhanglp-vwendler-core
#SBATCH --cpus-per-task=6
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

export MPLCONFIGDIR=${SLURM_TMPDIR:-/tmp}/mplcache
export PYTHONUNBUFFERED=1
export TOKENIZERS_PARALLELISM=false
export PYTHONNOUSERSITE=1

source ~/apps/miniforge3/etc/profile.d/conda.sh
conda activate mapping_abm

# cd /rds/projects/z/zhanglp-vwendler-core/
# unset APPTAINER_BIND

# # Sanity check: confirm Slurm gave you a GPU and it’s visible
# echo "SLURM_JOB_ID=${SLURM_JOB_ID:-}"
# echo "CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-}"
# nvidia-smi || true

# # persistent cache on RDS
# mkdir -p /rds/projects/z/zhanglp-vwendler-core/ollama_models
# mkdir -p ~/.ollama
# ln -sfn /rds/projects/z/zhanglp-vwendler-core/ollama_models ~/.ollama/models

# # pull container once (your check is fine, but this ensures a stable filename)
# if [ ! -f ollama_latest.sif ]; then
#   apptainer pull ollama_latest.sif docker://ollama/ollama
# fi

# # start ollama (GPU-capable via --nv)
# apptainer exec --nv ollama_latest.sif ollama serve > ollama_server.log 2>&1 &
# OLLAMA_PID=$!

# cleanup() { kill $OLLAMA_PID 2>/dev/null || true; }
# trap cleanup EXIT

# # wait until ready
# for i in {1..60}; do
#   if curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
#     break
#   fi
#   sleep 1
# done

# if ! curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
#   echo "[FATAL] Ollama server did not start." >&2
#   tail -n 80 ollama_server.log || true
#   exit 1
# fi

# # pull model only if missing
# MODEL="llama2:7b"
# if ! apptainer exec --nv ollama_latest.sif ollama list | awk '{print $1}' | grep -qx "$MODEL"; then
#   apptainer exec --nv ollama_latest.sif ollama pull "$MODEL"
# fi

cd ~/projects/Mapping_Behav_RL
Rscript Mapping_landscape_ABM/6_map.R
