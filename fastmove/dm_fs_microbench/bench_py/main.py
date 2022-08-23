import json
import subprocess
import re
import sys
import os
import time
import argparse

# This script automates the pattern creation and testing. Specifically,
# it will read files from a json file containing the following information
# for each pattern:
# - ptn_name: Name of the pattern
# - ptn_desc: The description of the pattern, in the following manner:
#   - desc: description string
#   - pattern: The pattern
#     - numa_node: the numa node
#     - number of splits here
# Example:
#
# {
#   "ptn_name": "LL",
#   "ptn_desc": {
#     "desc": "Two locally stripped devices",
#     "pattern": [
#       {
#         "numa_node": 0,
#         "num_split": 1
#       },
#       {
#         "numa_node": 1,
#         "num_split": 1
#       }
#     ]
#   }
# }
#
# The above will create a stripe across two numa_nodes: 0, 1 (full capacity)

# TODO: Use a class, for now, all things should be cached locally

setting_mountpoint = "/mnt/pmem"

def eprint(*args, **kwargs):
    """Print messages to stderr"""
    print(*args, file=sys.stderr, **kwargs)

def get_cpuinfo():
    """Get cpu info, the number of numa nodes

    Returns: The dictionary containing the following things:
        - "raw": The raw cpu info
        - "numa_num": The number of numa nodes, return -1 if fail
        - "numa_cpu": The cpus in each numa node
    """
    # Get cpu info
    cpuinfo = subprocess.check_output(["lscpu"]).decode('utf-8')

    # Get the number of NUMA
    numa_num = -1
    numa_list = {}
    for line in cpuinfo.split('\n'):
        numa_line = re.findall(r'NUMA node\(s\)', line)
        if (numa_line):
            numa_num = line.split(' ')[-1]
            numa_num = int(numa_num)
            break

    for i in range(0, numa_num):
        for line in cpuinfo.split('\n'):
            numa_cpu = re.findall(fr'NUMA node{i} CPU\(s\): ', line)
            if (numa_cpu):
                numa_list[i] = line.split(' ')[-1]

    return {
        "raw": cpuinfo,
        "numa_num": numa_num,
        "numa_cpu": numa_list
    }

def pm_get_info(numa_num):
    """
    Get the persistent memory info
    This function should be called each time when the table is altered

    Argument List:
        - numa_num: The number of numa nodes

    Returns: A dictionary containing the following things:
        - "numa%i": The pmem information of i'th numa node
        The returned dictionary has a structure of follows:
        {
            "numa0":    # The numa node
                {
                    0:  # The namespace count
                        {
                            "namespace"
                            "size"
                            "blkdev"
                        }
                }
        }
    """

    # Final dict
    ret_dict = {}
    if numa_num < 1:
        eprint("ERROR: expected a numa number larger than 0, got "
                   + str(numa_num))

    for i in range(0, numa_num):
        # Check i'th numa
        namespace_in_numa_i = 0
        curr_namespace = -1

        # Per-numa dict
        numa_i_dict = {}
        ret_dict["numa" + str(i)] = numa_i_dict

        info = subprocess.check_output(["ndctl", "list","-vc","--numa-node",
                                           str(i)]).decode("utf-8")

        size_found = False
        namespace_found = False
        blkdev_found = False
        state_found = False


        for line in info.split('\n'):
            size_find = re.findall("\"size\":", line)
            namespace_find = re.findall("\"dev\":", line)
            blkdev_find = re.findall("\"blockdev\":", line)
            state_find = re.findall("\"state\":", line)

            if (namespace_find):
                # A new namespace is found, initialize new dic for that
                if namespace_found:
                    eprint("BUG: new namespace found before the old namespace")
                    exit(1)

                # Per-namespace dict
                internal_dict = {}
                numa_i_dict[namespace_in_numa_i] = internal_dict
                curr_namespace = namespace_in_numa_i
                namespace_in_numa_i += 1

                # Fill the dict
                namespace = line.split(':')
                internal_dict["namespace"] = \
                    namespace[1].replace(',', '').replace('"', '')

                namespace_found = True

            if (size_find):
                if curr_namespace < 0 or namespace_found == False:
                    eprint("BUG: string \"size\" found before a namespace!")
                    exit(1)

                size = line.split(':')[1].replace(',', '')
                numa_i_dict[curr_namespace]["size"] = size

                size_found = True

            if (blkdev_find):
                if curr_namespace < 0 or namespace_found == False:
                    eprint("BUG: string \"blkdev\" found before a namespace!")
                    exit(1)

                blkdev = line.split(':')[1].replace(',', '').replace('"', '')
                numa_i_dict[curr_namespace]["blk"] = "/dev/" + blkdev

                blkdev_found = True

            if (state_find):
                if curr_namespace < 0 or namespace_found == False:
                    eprint("BUG: string \"blkdev\" found before a namespace!")
                    exit(1)

                # FIXME: for now we ignore this slot, because it does NOT
                #        handling of such inactive slots has not been
                #        implemented
                blkdev = ""
                numa_i_dict[curr_namespace]["blk"] = "_inactive"

                state_found = True
                eprint("ERROR: inactive slot found, not implemented")
                exit(1)


            if size_found and (blkdev_found or state_found) and namespace_found:
                size_found = False
                blkdev_found = False
                namespace_found = False
                state_found = False
    return ret_dict

def bench_init(setting_file):
    """Read settings and test patterns from json file

    Argument List:
        - setting_file: The file name of the json file

    Return:
        - A dictionary describing the pattern and setting, [setting, pattern]
    """
    json_opened = open(setting_file)
    data = json.load(json_opened)

    setting = data["bench_settings"]
    pattern = data["test_patterns"]

    return [setting, pattern]

def ndctl_create_namespace(numa_node, size="0"):
    sub_args = []
    if size != "0":
        sub_args.append("-m")
        sub_args.append("fsdax")
        sub_args.append("-s")
        sub_args.append(size)

    sub_args.append("--region=region" + str(numa_node))

    subprocess.check_output(["sudo", "ndctl", "create-namespace"] + sub_args)

def ndctl_destroy_namespace(ns):
    subprocess.check_output(["sudo", "ndctl", "disable-namespace", ns])
    subprocess.check_output(["sudo", "ndctl", "destroy-namespace", ns])

def pattern_init(pattern_detail, numa_num, dm_script="create_dm.pl"):
    """Initialize pattern based on the pattern detail

    Argument List:
        - pattern_detail: The pattern detail, read from json file
        - numa_num: The number of numa nodes
        - dm_script: The dm creation script

    Return: The created dev
    """

    # TODO: For now we do not implement fall back, instead, we rely on
    #       the user the recover from a in-consistent state
    pattern_info = pattern_detail["ptn_desc"]["pattern"]

    dm_device_list = []

    if len(pattern_info) == 1 and pattern_info[0]["num_split"] == 1:
        numa_node = pattern_info[0]["numa_node"]
        pmem_info = pm_get_info(numa_num)
        numa_op = pmem_info["numa" + str(numa_node)]
        return numa_op[0]["blk"]

    for ninfo in pattern_info:
        pmem_info = pm_get_info(numa_num)
        numa_node = ninfo["numa_node"]
        num_split = ninfo["num_split"]
        numa_op = pmem_info["numa" + str(numa_node)]

        if len(numa_op) != 1:
            eprint("ERR: expect 1 namespace in numa " + numa_node + ", got "
                   + len(numa_op))
        device = numa_op[0]
        print(device)

        # Get the namespace
        namespace_at_numa = device["namespace"]
        size_at_numa = int(device["size"])
        if num_split != 1:
            if ninfo["size"]:
                size_of_each_split = ninfo["size"]
        else:
            size_of_each_split = size_at_numa

        # Destroy the namespace, if viable
        ndctl_destroy_namespace(namespace_at_numa)

        if num_split > 1:
            for _ in range(0, num_split):
                subprocess.check_output(["sudo", "ndctl", "create-namespace",
                                            "-m", "fsdax", "-s",
                                            str(size_of_each_split)])
        else:
            subprocess.check_output(["sudo", "ndctl", "create-namespace"])

        # Update pmem list
        pmem_info = pm_get_info(numa_num)
        numa_op = pmem_info["numa" + str(numa_node)]
        for i in range(0, num_split):
            dm_device_list.append(numa_op[i]["blk"])

    # Now that every devices are set up, we now set up the device mapper, if
    # viable
    if os.path.isfile(dm_script) or os.path.islink(dm_script):
        subprocess.check_output(["sudo", "perl", dm_script] + dm_device_list)
    else:
        # Not a viable dm path
        eprint("ERROR: Failed to open the dm-stripe script")
        exit(1)

    return "/dev/mapper/stripe_dev"

def pattern_exit(pattern_detail, numa_num, dm_file="/dev/mapper/stripe_dev"):
    """De-initialize the pattern, return to original state

    Argument List:
        - pattern_detail: The pattern detail, read from json file
        - numa_num: The number of numa nodes
        - dm_file: The device mapper location

    Return: True if succeeded, False otherwise
    """

    # Remove the namespace
    pattern_info = pattern_detail["ptn_desc"]["pattern"]

    if len(pattern_info) == 1 and pattern_info[0]["num_split"] == 1:
        return True

    # Remove the stripe. The stripe should already be umounted
    subprocess.check_output(["sudo", "dmsetup", "remove", dm_file])

    for ninfo in pattern_info:
        pmem_info = pm_get_info(numa_num)
        numa_node = ninfo["numa_node"]
        num_split = ninfo["num_split"]
        numa_op = pmem_info["numa" + str(numa_node)]

        if int(num_split) == 1:
            continue

        for i in range(0, num_split):
            ns = numa_op[i]
            ns_name = ns["namespace"]
            print("deleting " + ns_name)
            ndctl_destroy_namespace(ns_name)

        ndctl_create_namespace(numa_node)


def do_mkfs(dev, fs):
    """Do filesystem formatting

    Argument List:
        - dev: The device to be formatted
        - fs: The filesystem to format

    Return:
        True if the filesystem is mounted (after formatting), False if not

    Note:
        Some file systems will automatically mount after formatting, for
        example, NOVA, will format the device while mounting it
    """

    if re.findall("stripe_dev", dev) or re.findall("pmem", dev):
        if fs == "nova":
            lsmod_out = subprocess.check_output(["lsmod"]).decode("utf-8")
            if not re.search("nova", lsmod_out):
                subprocess.check_output(["sudo", "modprobe", "nova"])
            subprocess.check_output(["sudo", "mount", "-t", "NOVA", "-o", "init", dev, setting_mountpoint])
            return True
        elif fs == "odinfs":
            lsmod_out = subprocess.check_output(["lsmod"]).decode("utf-8")
            if not re.search("odinfs", lsmod_out):
                subprocess.check_output(["sudo", "modprobe", "odinfs"])
            subprocess.check_output(["sudo", "mount", "-t", "odinfs", "-o", "init,dele_thrds=12", "/dev/pmem_ar0", setting_mountpoint])
            return True
        else:
            if fs == "ext4":
                mkfs_flags = "-F"
            elif fs == "xfs":
                mkfs_flags = "-f -m reflink=0"
            else:
                eprint("ERROR: unknown filesystem " + fs)
                exit(1)

            subprocess.check_output(["sudo", "mkfs." + fs] +
                                            mkfs_flags.split(' ') + [dev])
            return False
    else:
        eprint("Trying to format " + dev + ", does not support")
        exit(1)


def run_bench(pattern_datail, bench_pattern, bench_fs, bench_size,
            bench_engine, bench_thread, dev, numa_cpu,
              result_file="bench_result", group_reporting=True):
    print(
        f"{'Benchmark':<15}{pattern_detail['ptn_name']:>10}",
        f"\n{'--> '}{pattern_datail['ptn_desc']['desc']}",
        f"\n{'write pattern':<15}{bench_pattern:>10}",
        f"\n{'filesystem':<15}{bench_fs:>10}",
        f"\n{'chunk size':<15}{bench_size:>10}",
        f"\n{'fio engine':<15}{bench_engine:>10}",
        f"\n{'write thread':<15}{bench_thread:>10}",
    )

    # Initialize environment
    if do_mkfs(dev, bench_fs) ==  False:
        # Mount
        subprocess.check_output(["sudo", "mount", "-o", "dax", dev, setting_mountpoint])

    # Fio
    header = ("=================================\n"
              f"Benchmark: {pattern_datail['ptn_name']}"
              f"- {pattern_datail['ptn_desc']['desc']}\n"
              f"{bench_pattern}_{bench_fs}_{bench_size}"
              f"_{bench_engine}_{bench_thread}\n"
              "=================================\n")
    footer = "\n\n"

    add_opts = []
    if group_reporting:
        add_opts.append("--group_reporting")

    result = subprocess.check_output(["sudo", "numactl", "-m", "0", "-N", "0", "fio",
                                        "--name=benchmark",
                                        f"--rw={bench_pattern}",
                                        f"--numjobs={bench_thread}",
                                        f"--ioengine={bench_engine}",
                                        f"--bs={bench_size}",
                                        f"--cpus_allowed={numa_cpu[0]}"] +
                                        add_opts +
                                        ["--runtime=10",
                                        "--cpus_allowed_policy=split",
                                        "--time_based",
                                        "--direct=1",
                                        f"--directory={setting_mountpoint}",
                                        "--size=1G"]).decode('utf-8')

    with open(result_file, "a+") as f:
        f.write(header)
        f.write(result)
        f.write(footer)

    subprocess.check_output(["sudo", "umount", setting_mountpoint])

###################################################
# Main
###################################################
parser = argparse.ArgumentParser(description="FIO Bench for fs")

parser.add_argument('setting_file', metavar='FILE', type=str,
                    help='A json file describing the benchmark setting')
parser.add_argument('-d', '--disable_group_reporting', action='store_false',
                    help='Disable group reporting in fio', dest='group_reporting')
parser.add_argument('-y', '--ycsb', action="store_true",
                    help='Test YCSB instead of fio, if enabled, `-d` will not effect',
                    dest='use_ycsb')
args = vars(parser.parse_args())

gr = args['group_reporting']
ycsb = args['use_ycsb']

info = get_cpuinfo()
numa_num = info["numa_num"]
numa_cpu = info["numa_cpu"]

if numa_num == -1:
    eprint("ERROR: Failed to get number of numa nodes")
    exit(1)

pm_info = pm_get_info(numa_num)
[setting_data, pattern_data] = bench_init(args['setting_file'])

if "mountpoint" in setting_data.keys():   
    setting_mountpoint = setting_data["mountpoint"]

## YCSB
if ycsb == True:
    for pattern_detail in pattern_data:
        dev = pattern_init(pattern_detail, numa_num,
                            dm_script="/home/chenlf/create_dm.pl")

        os.sync()
        time.sleep(2)
        for fs in setting_data["fs"]:
            if do_mkfs(dev, fs) == False:
                subprocess.check_output(["sudo", "mount", "-o", "dax", dev, setting_mountpoint])
            subprocess.check_output(["sudo", "/home/chenlf/ycsb/ycsb_bench.sh", pattern_detail['ptn_name']])
            subprocess.check_output(["sudo", "umount", setting_mountpoint])

        pattern_exit(pattern_detail, numa_num)

else:
    bench_set_name = args['setting_file'].split("/")[-1].replace(".json", "")

    if args['group_reporting'] == False:
        bench_set_name = bench_set_name + '_ng'
    bench_file = "fio_" + bench_set_name + "_" + time.strftime("%Y%m%d-%H%M%S")

    with open(bench_file, "a+") as f:
        f.write("# BENCH SET: " + bench_set_name + "\n")

    for pattern_detail in pattern_data:
        dev = pattern_init(pattern_detail, numa_num,
                            dm_script="/home/chenlf/create_dm.pl")
        os.sync()
        time.sleep(2)
        for bench_fs in setting_data["fs"]:
            for bench_pattern in setting_data["pattern"]:
                for bench_size in setting_data["size"]:
                    for bench_engine in setting_data["engine"]:
                        for bench_thread in setting_data["thread"]:
                            run_bench(pattern_detail, bench_pattern, bench_fs, bench_size, bench_engine,
                                                    bench_thread, dev, numa_cpu, bench_file, gr)
        pattern_exit(pattern_detail, numa_num)

