#include <helper.h>
#include <libzbd/zbd.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void dump_zinfo(struct zbd_info *zinfo) {
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

void dump_zones(struct zbd_zone *zones, unsigned int nr_zones) {
  info("Got %d zones\n", nr_zones);
  for (int i = 0; i < nr_zones; i++) {
    info("Zone %-4d: START: 0x%-11llx LEN: 0x%-11llx CAP: 0x%-11llx WP: "
         "0x%-11llx COND: %-10s TYPE: %-15s FLAGS: %x\n",
         i, zones[i].start, zones[i].len, zones[i].capacity, zones[i].wp,
         zone_cond_parse(zones[i].cond), zone_parse_type(zones[i].type),
         zones[i].flags);
  }
}

int main(int argc, char *argv[]) {
  if (argc < 2) {
    printf("Usage: %s <device>\n", argv[0]);
    return 1;
  }
  char *dev_name = argv[1];
  int is_zoned = zbd_device_is_zoned(dev_name);
  if (is_zoned == 0) {
    error("device %s is not zoned\n", dev_name);
    return 1;
  }

  info("Opening %s\n", dev_name);
  struct zbd_info *zinfo = malloc(sizeof(struct zbd_info));
  int fd = zbd_open(dev_name, 0, zinfo);
  if (fd < 0) {
    error("zbd_open failed: %s\n", strerror(-fd));
    return 1;
  }

  struct zbd_zone *zones;
  unsigned int nr_zones;
  zbd_list_zones(fd, 0, 0, ZBD_RO_ALL, &zones, &nr_zones);

#ifdef DEBUG
  dump_zones(zones, nr_zones);
#endif

  int zone_idx[] = {1, 20, 45};
  for (int i = 0; i < 3; i++) {
    int idx = zone_idx[i];
    info("Open zone: %d: 0x%llx len 0x%llx\n", idx, zbd_zone_start(zones + idx), zbd_zone_len(zones + idx));
    int ret = zbd_zones_operation(fd, ZBD_OP_OPEN, zbd_zone_start(zones + idx),
                                  zbd_zone_len(zones + idx));
    if (ret == -1) {
      error("cannot open zone %d\n", idx);
      goto out;
    }
  }

out:
  info("Closing %s\n", dev_name);
  zbd_close(fd);
  return 0;
}
