# MPEG-G Performance Benchmark

This benchmark was tested on the following operating systems:

- Ubuntu 20.04.2 LTS

## Installation

Clone the repository and ``cd`` into it:

    git clone https://github.com/voges/mpegg-performance-benchmark.git
    cd mpegg-performance-benchmark

Install required system libraries:

    bash install_dependencies.sh

Install compression tools:

    bash install_tools.sh

## Test

Perform a test run:

    bash run_simulations.sh --test_run

Upon completion the newly created directory ``tmp`` will contain all results.

With the ``--test_run`` option the simulations are performed with the files from the ``test`` folder.

## Execution

To perform the 'real' benchmark, set the path to the local copy of the MPEG-G Genomic Information Database:

    bash set_mpegg_gidb_prefix.sh /path/to/local/copy/of/the/mpegg/gidb

Then, check whether the paths in the file ``ref_files.txt`` point to the correct local locations.

Finally, run the benchmark:

    bash run_simulations.sh

Run ``bash run_simulations.sh --help`` for more options.

## Contact

Jan Voges <[voges@tnt.uni-hannover.de](mailto:voges@tnt.uni-hannover.de)>
