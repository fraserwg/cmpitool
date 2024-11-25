#!/usr/bin/bash
#SBATCH --job-name=noncmore_preprocess_ICON-ESM-ER
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --mem=256G
#SBATCH --exclusive 
#SBATCH --time=06:00:00
#SBATCH --account=bk1377
#SBATCH --output=noncmore_preprocess_ICON-ESM-ER.%j.out

# limit stacksize ... adjust to your programs need
# and core file size
ulimit -s 204800
ulimit -c 0

module load cdo
module load parallel

set -e

./noncmore_preprocess_ICON-ESM-ER.sh
