#!/bin/bash

# Generate genie numbers on TNT cluster

#SBATCH --mail-user=muenteferi@tnt.uni-hannover.de
#SBATCH --mail-type=ALL
#SBATCH --job-name=genie_roundtrips
#SBATCH --output=slurm-%j-out.txt

#SBATCH --time=336:00:00
#SBATCH --partition=cpu_long_stud

#SBATCH --nodes=16           
#SBATCH --nodelist=nox
#SBATCH --tasks-per-node=1
#SBATCH --mem=96G

NUM_CORES=`nproc --all`
MAX_THREADS="16"
NUM_THREADS=`echo $((NUM_CORES<MAX_THREADS ? NUM_CORES : MAX_THREADS))`

echo "Start of SLURM script"
working_dir=/home/muenteferi/simulation_genie/mpegg-performance-benchmark
cd $working_dir
srun hostname

echo "Start of multi-threaded simulations with $NUM_THREADS threads."
bash ./run_simulations.sh -@ $NUM_THREADS -g -n
mv ./tmp ./results_${NUM_THREADS}_threads

echo "Start of single-threaded simulations."
bash ./run_simulations.sh -@ 1 -g -n
mv ./tmp ./results_1_threads
