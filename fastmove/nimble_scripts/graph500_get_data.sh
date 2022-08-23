#!/bin/bash

# Generate graph 500 cycles

# Argument 1: Directory
# Argument 2: formatted output?

pushd $1

if [[ -z $2 ]] || [[ $2 -eq 0 ]]; then
for i in 4 8 12 16 20; do
	echo $i 
	grep -nr 'real time(ms)' result-graph500-omp-${i}* | cut -d ' ' -f 3 | tr -d ","  | awk 'NR == 3 { print "non-thp: " $0; print "dma: " delay_0; print "fastmove: " delay_1 } NR == 1{ delay_0 = $0 } NR == 2 { delay_1 = $0 } NR == 4 { print "opt: " $0 } NR == 5 { print "thp: " $0 }'
done
else
	for i in 4 8 12 16 20; do
	echo ${i}GB
	grep -nr 'real time(ms)' result-graph500-omp-${i}* | cut -d ' ' -f 3 | tr -d ","  | awk 'NR == 3 { print $0; print delay_0; print delay_1 } NR == 1{ delay_0 = $0 } NR == 2 { delay_1 = $0 } NR == 4 { print $0 } NR == 5 { print $0 }'
done
fi

popd
