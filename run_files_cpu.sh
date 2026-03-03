#!/bin/bash
#SBATCH --job-name=1000_corrected_sem_ratings_
#SBATCH --account=zhanglp-vwendler-core
#SBATCH --qos=bbdefault
#SBATCH --cpus-per-task=8
#SBATCH --mem=128G
#SBATCH --time=24:00:00
#SBATCH --output=logs/%x.%j.out
#SBATCH --error=logs/%x.%j.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=VAW508@student.bham.ac.uk

set -euo pipefail
mkdir -p logs

module purge
module load bear-apps/2024a/live

# ---- Put Apptainer build/cache somewhere BIG (NOT HOME, NOT /tmp)
export APPTAINER_TMPDIR="/rds/projects/z/zhanglp-vwendler-core/apptainer_tmp"
export APPTAINER_CACHEDIR="/rds/projects/z/zhanglp-vwendler-core/apptainer_cache"
mkdir -p "$APPTAINER_TMPDIR" "$APPTAINER_CACHEDIR"

# ---- Use an RDS-backed "tmp" (big) for this job, NOT Linux /tmp (tiny on your logs)
SCRATCH="/rds/projects/z/zhanglp-vwendler-core/tmp/${USER}/slurm_${SLURM_JOB_ID}"
mkdir -p "$SCRATCH"

# ---- Python hygiene
export MPLCONFIGDIR="$SCRATCH/mplcache"
export PYTHONUNBUFFERED=1
export TOKENIZERS_PARALLELISM=false
export PYTHONNOUSERSITE=1

source ~/apps/miniforge3/etc/profile.d/conda.sh
conda activate mapping_abm

# ---- Container location on RDS
CONTAINERS_DIR="/rds/projects/z/zhanglp-vwendler-core/containers"
SIF="${CONTAINERS_DIR}/ollama_latest.sif"
mkdir -p "$CONTAINERS_DIR"

if [ ! -f "$SIF" ]; then
  echo "[INFO] Pulling Ollama container to: $SIF"
  apptainer pull "$SIF" docker://ollama/ollama
else
  echo "[INFO] Using existing container: $SIF"
fi

# ---- Ollama models go to RDS scratch (must have tens of GB free for 70B)
export OLLAMA_MODELS="$SCRATCH/ollama_models"
mkdir -p "$OLLAMA_MODELS"

echo "[INFO] SCRATCH=$SCRATCH"
echo "[INFO] OLLAMA_MODELS=$OLLAMA_MODELS"
df -h "/rds/projects/z/zhanglp-vwendler-core" || true

# ---- Bind host paths into container
BIND="/rds:/rds,/tmp:/tmp"

export OLLAMA_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OLLAMA_NUM_THREADS=8
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
# ---- Start Ollama
LOG="$SCRATCH/ollama_server.${SLURM_JOB_ID}.log"
apptainer exec --bind "$BIND" "$SIF" ollama serve > "$LOG" 2>&1 &
OLLAMA_PID=$!

cleanup() { kill "$OLLAMA_PID" 2>/dev/null || true; }
trap cleanup EXIT

# ---- Wait for Ollama
for i in {1..180}; do
  if curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "[FATAL] Ollama server did not start." >&2
  tail -n 200 "$LOG" || true
  exit 1
fi

# ---- Pull model (FIXED TAG)
# NOTE: your earlier tag llama3.3:70b-instruct does not exist in Ollama registry.
MODEL="${OLLAMA_MODEL:-qwen2.5:7b-instruct}"  
echo "[INFO] Pulling model (into $OLLAMA_MODELS): $MODEL"
apptainer exec --bind "$BIND" "$SIF" ollama pull "$MODEL"
apptainer exec --bind "$BIND" "$SIF" ollama list || true

# ---- Quick sanity check that GENERATE works (not only /api/tags)
echo "[TEST] quick generate"
curl -s http://127.0.0.1:11434/api/generate \
  -H 'Content-Type: application/json' \
  -d '{"model":"'"$MODEL"'","prompt":"Write exactly two lines.\nLine1: OK.\nLine2: Answer=[0]","stream":false,"options":{"num_predict":40,"temperature":0}}' \
  | head -c 400; echo

echo "[TEST] done"

# ---- Runtime settings for Python (minimal)
export OLLAMA_MODEL="$MODEL"   # ensures Python uses the same model you pulled
export MAX_PAIRS=10000

# Optional: not "bias", just stability/performance
export BATCH_SIZE=20
export OLLAMA_TIMEOUT=600
export OLLAMA_RETRIES=2
export OLLAMA_WORKERS=1

echo "[INFO] Runtime env:"
env | egrep "OLLAMA_|MAX_PAIRS|BATCH_SIZE" | sort

cd ~/projects/Mapping_Behav_RL
python Mapping_landscape_ABM/2.1_semantic_ratings.py