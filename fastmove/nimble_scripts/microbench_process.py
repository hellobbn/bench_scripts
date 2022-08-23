#!/usr/bin/python3

import os.path
import sys
import re

if len(sys.argv) != 4:
    print("Please give a file name")

if not os.path.exists(sys.argv[1]):
    print(sys.argv[1] + " not found!")

cycles_dict = {}
bd_dict = {}

def fill_dict(dicti, key_line, val_line):
    key_spl_line = key_line.split(' ')
    for keys in key_spl_line:
        if keys not in dicti:
            dicti[keys] = 0

    val_spl_line = val_line.split(' ')
    line_size = len(val_spl_line)
    assert(line_size == len(dicti))
    for i in range(line_size):
        dicti[key_spl_line[i]] = dicti[key_spl_line[i]] + int(val_spl_line[i])

with open(sys.argv[1]) as f:
    config_line = f.readline().replace('\n', '').split('-')
    print(config_line)
    method = config_line[0]
    if method == "fm" or method == "fm_nonthp":
        mt = config_line[1]
        ck = config_line[2]
        cc = config_line[3]
        pg_shift = config_line[4]
    else:
        mt = config_line[1]
        pg_shift = config_line[2]

    # print(method + ", " + mt + ", " + pg_shift)

    curr_line_num = 0
    epoch_num = 0
    for line in f:
        line = line.replace('\n', '')

        if curr_line_num == 0:
            epoch_num = epoch_num + 1
            curr_line_num = curr_line_num + 1
            continue

        if curr_line_num == 1:
            curr_line_num = curr_line_num + 2
            key_line = line
            val_line = f.readline()
            fill_dict(cycles_dict, key_line, val_line)
            continue

        if curr_line_num == 3:
            curr_line_num = 0
            key_line = line
            val_line = f.readline()
            fill_dict(bd_dict, key_line, val_line)
            continue

    print("epoch num = " + str(epoch_num))
    for k, v in cycles_dict.items():
        cycles_dict[k] = float(cycles_dict[k]) / epoch_num

    for k, v in bd_dict.items():
        bd_dict[k] = float(bd_dict[k]) / epoch_num

if not os.path.exists(sys.argv[2]):
    mode = "w"
else:
    mode = "a"

if method == "fm" or method == "fm_nonthp":
    fname = method + "-" + ck + "-" + cc + "-" + pg_shift
else:
    fname = method + "-" + mt + "-" + pg_shift

with open(sys.argv[2], mode=mode) as f:
    if mode == "w":
        f.write("#\t")
        for k, _ in cycles_dict.items():
            f.write(k + '\t')
        f.write('\n')
    f.write(fname + "\t")
    for k, _ in cycles_dict.items():
        f.write(str(cycles_dict[k]) + '\t')
    f.write('\n')

with open(sys.argv[3], mode=mode) as f:
    if mode == "w":
        f.write("#\t")
        for k, _ in bd_dict.items():
            f.write(k + '\t')
        f.write('\n')
    f.write(fname + "\t")
    for k, _ in bd_dict.items():
        f.write(str(bd_dict[k]) + '\t')
    f.write('\n')
