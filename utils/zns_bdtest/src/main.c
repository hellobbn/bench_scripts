#include <argp.h>
#include <bits/types/error_t.h>
#include <errno.h>
#include <fcntl.h>
#include <helper.h>
#include <libzbd/zbd.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#ifdef DEBUG
void dbg_dump_zinfo(struct zbd_info *zinfo) {
  printf("Device info:\n");
  printf("  vendor_id:            %s\n", zinfo->vendor_id);
  printf("  nr_sectors: (512B)    %llu\n", zinfo->nr_sectors);
  printf("  nr_lblocks:           %llu\n", zinfo->nr_lblocks);
  printf("  nr_pblocks:           %llu\n", zinfo->nr_pblocks);
  printf("  zone_size: (bytes)    %llu\n", zinfo->zone_size);
  printf("  zone_sectors:         %u\n", zinfo->zone_sectors);
  printf("  lblock_size:          %u\n", zinfo->lblock_size);
  printf("  pblock_size:          %u\n", zinfo->pblock_size);
  printf("  nr_zones:             %u\n", zinfo->nr_zones);
  printf("  max_nr_open_zones:    %u\n", zinfo->max_nr_open_zones);
  printf("  max_nr_active_zones:  %u\n", zinfo->max_nr_active_zones);
  printf("  model:                %d\n", zinfo->model);
}

char *zone_cond_parse(unsigned int cond) {
  switch (cond) {
  case BLK_ZONE_COND_NOT_WP:
    return "NOT_WP";
  case BLK_ZONE_COND_EMPTY:
    return "EMPTY";
  case BLK_ZONE_COND_IMP_OPEN:
    return "IMP_OPEN";
  case BLK_ZONE_COND_EXP_OPEN:
    return "EXP_OPEN";
  case BLK_ZONE_COND_CLOSED:
    return "CLOSED";
  case BLK_ZONE_COND_FULL:
    return "FULL";
  case BLK_ZONE_COND_READONLY:
    return "READ_ONLY";
  case BLK_ZONE_COND_OFFLINE:
    return "OFFLINE";
  default:
    return "UNKNOWN";
  }
}

char *zone_parse_type(unsigned int type) {
  switch (type) {
  case BLK_ZONE_TYPE_CONVENTIONAL:
    return "CONVENTIONAL";
  case BLK_ZONE_TYPE_SEQWRITE_REQ:
    return "SEQUENTIAL_REQ";
  case BLK_ZONE_TYPE_SEQWRITE_PREF:
    return "SEQUENTIAL_PREF";
  default:
    return "UNKNOWN";
  }
}
static inline void print_zone_info(int idx, struct zbd_zone *zone) {
  verbose("Zone %-4d: START: 0x%-11llx LEN: 0x%-11llx CAP: 0x%-11llx WP: "
          "0x%-11llx COND: %-10s TYPE: %-15s FLAGS: %x\n",
          idx, zone->start, zone->len, zone->capacity, zone->wp,
          zone_cond_parse(zone->cond), zone_parse_type(zone->type),
          zone->flags);
}

static inline void dbg_dump_zone(int idx, int fd) {
  struct zbd_zone *zones;
  unsigned int nr_zones;
  zbd_list_zones(fd, 0, 0, ZBD_RO_ALL, &zones, &nr_zones);
  print_zone_info(idx, zones + idx);
  free(zones);
}

static inline void dbg_dump_zones(unsigned int fd) {
  struct zbd_zone *zones;
  unsigned int nr_zones;
  znsinfo("Got %d zones\n", nr_zones);
  zbd_list_zones(fd, 0, 0, ZBD_RO_ALL, &zones, &nr_zones);
  for (int i = 0; i < nr_zones; i++) {
    print_zone_info(i, zones + i);
  }
  free(zones);
}
#else
#define dbg_dump_zinfo(zinfo)
#define dbg_dump_zones(fd)
#define dbg_dump_zone(idx, fd)
#endif

double total_throughput = 0;
int test_times = 0;

static int write_to_zone(int fd, int idx, struct zbd_zone *zone, char *buf,
                         ssize_t buf_size) {
  znsinfo("--------------------------------------------------------------------"
          "\n");
  znsinfo("==> Open zone: %d: 0x%llx len 0x%llx\n", idx, zbd_zone_start(zone),
          zbd_zone_len(zone));
  int ret = zbd_zones_operation(fd, ZBD_OP_OPEN, zbd_zone_start(zone),
                                zbd_zone_len(zone));
  if (ret == -1) {
    dbg_dump_zones(fd);
    znserror("cannot open zone %d\n", idx);
    return -1;
  }
  dbg_dump_zone(idx, fd);

  znsinfo("==> Trying to write to zone %d, wp at %llx\n", idx,
          zbd_zone_wp(zone));
  if (lseek(fd, zbd_zone_wp(zone), SEEK_SET) == -1) {
    znserror("cannot seek to zone %d wp %llx\n", idx, zbd_zone_wp(zone));
    return -1;
  }

  // monitor the time written
  struct timespec start, end;
  clock_gettime(CLOCK_MONOTONIC, &start);
  ssize_t bytes_written = write(fd, buf, buf_size);
  if (bytes_written == -1) {
    znserror("cannot write to zone %d, error: %s\n", idx, strerror(errno));
    return -1;
  }
  if (fsync(fd) == -1) {
    znserror("fsync error, error: %s\n", strerror(errno));
    return -1;
  };
  clock_gettime(CLOCK_MONOTONIC, &end);
  double time_taken = (end.tv_sec - start.tv_sec) * 1e9;
  time_taken = (time_taken + (end.tv_nsec - start.tv_nsec)) * 1e-9;
  znsinfo("==> Write took %f seconds\n", time_taken);

  // Calculate the throughput
  double throughput = buf_size / time_taken;
  verbose("==> Throughput: %f MB/s\n", throughput / 1024 / 1024);
  total_throughput = total_throughput + throughput / 1024 / 1024;
  test_times += 1;

  znsinfo("<== Wrote %ld bytes to zone %d\n", bytes_written, idx);
  dbg_dump_zone(idx, fd);

  znsinfo("==> Close zone: %d: 0x%llx len 0x%llx\n", idx, zbd_zone_start(zone),
          zbd_zone_len(zone));
  ret = zbd_zones_operation(fd, ZBD_OP_CLOSE, zbd_zone_start(zone),
                            zbd_zone_len(zone));
  dbg_dump_zone(idx, fd);
  if (ret == -1) {
    znserror("cannot close zone %d\n", idx);
    return -1;
  }
  znsinfo("--------------------------------------------------------------------"
          "\n");
  return 0;
}

const char *argp_program_version = "zns_bdtest 0.1";
const char *argp_program_bug_address = "<clfbbn@gmail.com>";
static char doc[] = "zns_bdtest -- test bw of zoned block device";
static char args_doc[] = "DEVICE ...";

static struct argp_option options[] = {
    {"buffer_size", 'b', "SIZE", 0, "Size of buffer to write to each zone"},
    {"num_writes", 'n', "NUM", 0, "Number of writes to each zone"},
    {"mode", 'm', "MODE", 0, "Mode of operation (seq, rand)"},
    {0}};

struct arguments {
  char *args[1];
  unsigned int buf_size;
  unsigned int num_writes;
  enum { MODE_SEQ, MODE_RAND, MODE_ALL } mode;
};

static error_t parse_opt(int key, char *arg, struct argp_state *state) {
  struct arguments *arguments = state->input;
  switch (key) {
  case 'b':
    arguments->buf_size = atoi(arg);
    break;
  case 'n':
    arguments->num_writes = atoi(arg);
    break;
  case 'm':
    if (strcmp(arg, "seq") == 0) {
      arguments->mode = MODE_SEQ;
    } else if (strcmp(arg, "rand") == 0) {
      arguments->mode = MODE_RAND;
    } else if (strcmp(arg, "all") == 0) {
      arguments->mode = MODE_ALL;
    } else {
      argp_usage(state);
    }
    break;
  case ARGP_KEY_ARG:
    if (state->arg_num >= 1) {
      argp_usage(state);
    }
    arguments->args[state->arg_num] = arg;
    break;
  case ARGP_KEY_END:
    if (state->arg_num < 1) {
      argp_usage(state);
    }
    break;
  default:
    return ARGP_ERR_UNKNOWN;
  }
  return 0;
}

static struct argp argp = {options, parse_opt, args_doc, doc};

int main(int argc, char *argv[]) {
  struct arguments arguments;
  arguments.args[0] = "";
  arguments.buf_size = 4096;
  arguments.num_writes = 1;
  arguments.mode = MODE_ALL;
  argp_parse(&argp, argc, argv, 0, 0, &arguments);

  char *dev_name = arguments.args[0];
  unsigned int buf_size = arguments.buf_size;
  unsigned int num_writes = arguments.num_writes;
  int mode = arguments.mode;

  printf("Writing to %s, buffer size: %d, num writes: %d, mode: %d\n", dev_name,
         buf_size, num_writes, mode);

  int is_zoned = zbd_device_is_zoned(dev_name);
  if (is_zoned == 0) {
    znserror("device %s is not zoned\n", dev_name);
    return 1;
  }

  znsinfo("Opening %s\n", dev_name);
  struct zbd_info *zinfo = malloc(sizeof(struct zbd_info));
  int fd = zbd_open(dev_name, O_RDWR, zinfo);
  dbg_dump_zinfo(zinfo);
  if (fd < 0) {
    znserror("zbd_open failed: %s\n", strerror(-fd));
    return 1;
  }

  struct zbd_zone *zones;
  unsigned int nr_zones;
  zbd_list_zones(fd, 0, 0, ZBD_RO_ALL, &zones, &nr_zones);

  // Initialize the buffer
  char *buf = malloc(buf_size);
  for (int i = 0; i < buf_size; i++) {
    buf[i] = 'a';
  }

  // Initialize the zone index
  int *zone_allowed = malloc(sizeof(int) * zinfo->max_nr_active_zones);
  srand(time(NULL));
  for (int i = 0; i < zinfo->max_nr_active_zones; i++) {
    zone_allowed[i] = rand() % nr_zones;
  }
  int *zone_idx = malloc(sizeof(int) * num_writes);
  for (int i = 0; i < num_writes; i++) {
    zone_idx[i] = zone_allowed[rand() % zinfo->max_nr_active_zones];
  }

  if (mode != MODE_SEQ) {
    // Random writes, write randomly to the max allowed zoned
    for (int i = 0; i < num_writes; i++) {
      zbd_list_zones(fd, 0, 0, ZBD_RO_ALL, &zones, &nr_zones);
      int idx = zone_idx[i];
      znsinfo("Writing to idx %d\n", idx);
      int ret = write_to_zone(fd, idx, zones + idx, buf, buf_size);
      if (ret == -1) {
        znserror("cannot write to zone %d\n", idx);
        dbg_dump_zones(fd);
        goto out;
      }
    }

    printf("Average throughput (Random): %f MB/s\n",
           total_throughput / test_times);
    // Reset all zones
    for (int i = 0; i < zinfo->max_nr_active_zones; i++) {
      if (zbd_zones_operation(fd, ZBD_OP_RESET,
                              zbd_zone_start(zones + zone_allowed[i]),
                              zbd_zone_len(zones + zone_allowed[i])) == -1) {
        znserror("cannot reset zone %d\n", i);
        dbg_dump_zones(fd);
        goto out;
      }
    }
  }

  if (mode != MODE_RAND) {
    // Now we choose a zone, write num_writes times to it
    total_throughput = 0;
    test_times = 0;
    int idx = zone_allowed[rand() % zinfo->max_nr_active_zones];
    for (int i = 0; i < num_writes; i++) {
      zbd_list_zones(fd, 0, 0, ZBD_RO_ALL, &zones, &nr_zones);
      znsinfo("Writing to idx %d\n", idx);
      int ret = write_to_zone(fd, idx, zones + idx, buf, buf_size);
      if (ret == -1) {
        znserror("cannot write to zone %d\n", idx);
        dbg_dump_zones(fd);
        goto out;
      }
    }
    printf("Average throughput (Sequential): %f MB/s\n",
           total_throughput / test_times);

    // reset the zone
    zbd_zones_operation(fd, ZBD_OP_RESET, zbd_zone_start(zones + idx),
                        zbd_zone_len(zones + idx));
  }

out:
  free(buf);
  free(zone_allowed);
  free(zone_idx);
  znsinfo("Closing %s\n", dev_name);
  zbd_close(fd);
  return 0;
}
