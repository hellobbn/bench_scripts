#!/bin/bash

dir="$1"

if [[ -z $dir ]]; then
	error "Usage: $0 <dir>"
	exit 1
fi

if [[ ! -d $dir ]]; then
	error "Directory $dir does not exist"
	exit 1
fi

# Use the remaining arguments (if exist) for query
if [[ $# -gt 1 ]]; then
	query=(${@:2})
fi

grep_str=$(grep 'bw=' "$dir"/**/* | tr -s ' ' | sort -h)
for q in "${query[@]}"; do
	grep_str=$(echo "$grep_str" | grep -E "[_-]$q[-.]")
done

type=$(echo "$grep_str" | cut -d ' ' -f 1 | rev | cut -d '/' -f 1 | rev | sed 's/fio-//' | sed 's/\.log//' | sed 's/\://')
bw=$(echo "$grep_str" | cut -d ' ' -f 3 | sed 's/bw=//' | sed 's/MiB\/s//')

readarray -t type_arr <<<"$type"
readarray -t bw_arr <<<"$bw"

for i in "${!type_arr[@]}"; do
	printf "${type_arr[$i]}\t${bw_arr[$i]}\n"
done
