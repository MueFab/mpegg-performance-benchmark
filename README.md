# MPEG-G Performance Benchmark

This benchmark was tested on the following operating systems:

- Ubuntu 20.04.2 LTS

## Benchmark Execution

To execute the benchmark, run the following commands:

    git clone https://github.com/voges/mpegg-performance-benchmark.git
    cd mpegg-performance-benchmark
    ./install_dependencies.sh
    ./install_tools.sh
    ./run_simulations.sh 1 # argument is the number of threads

A list of result files will be stored in ``result_files.txt``.

Out of the box the simulations are performed with the files from the ``test`` folder.
To perform the 'real' benchmark, check whether the paths in the files ``fastq_files.txt``, ``sam_files.txt``, and ``ref_files.txt`` point to the correct local locations.
Then, comment lines 33-35 and uncomment lines 36-38 in ``run_simulations.sh``.

## Contact

Jan Voges <[voges@tnt.uni-hannover.de](mailto:voges@tnt.uni-hannover.de)>
