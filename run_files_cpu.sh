#!/bin/bash
#SBATCH --job-name=semantic_ratings_ollama_gpu
#SBATCH --account=zhanglp-vwendler-core
#SBATCH --qos=bbgpu
#SBATCH --gres=gpu:a100:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=logs/%x.%j.out
#SBATCH --error=logs/%x.%j.err
#SBATCH --mail-type=END,FAIL
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

cd /rds/projects/z/zhanglp-vwendler-core/
unset APPTAINER_BIND

# persistent cache on RDS
mkdir -p /rds/projects/z/zhanglp-vwendler-core/ollama_models
mkdir -p ~/.ollama
ln -sfn /rds/projects/z/zhanglp-vwendler-core/ollama_models ~/.ollama/models

# container present?
if [ ! -f ollama_latest.sif ]; then
  apptainer pull docker://ollama/ollama
fi

# start ollama WITH GPU passthrough
apptainer exec --nv ollama_latest.sif ollama serve > ollama_server.log 2>&1 &
OLLAMA_PID=$!

cleanup() { kill $OLLAMA_PID 2>/dev/null || true; }
trap cleanup EXIT

# wait until ready
for i in {1..60}; do
  if curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "[FATAL] Ollama server did not start." >&2
  tail -n 50 ollama_server.log || true
  exit 1
fi

# Pull model only if missing
MODEL="llama2:7b"
if ! apptainer exec --nv ollama_latest.sif ollama list | awk '{print $1}' | grep -qx "$MODEL"; then
  apptainer exec --nv ollama_latest.sif ollama pull "$MODEL"
fi

cd ~/projects/Mapping_Behav_RL
python Mapping_landscape_ABM/2.1_semantic_ratings.py
