#include <stdint.h>
struct adamas_out_local_pair { int read_end; int write_end; };
int adamas_out_local_fill_pair(struct adamas_out_local_pair *pair) {
  pair->read_end = 65;
  pair->write_end = 66;
  return 0;
}

int32_t adamas_out_contract_scalar(int32_t value) { return value; }
int32_t adamas_out_contract_opaque(void *value) { return value != 0; }
int32_t adamas_out_contract_variadic(int32_t prefix, ...) { return prefix; }
int32_t adamas_out_contract_fill_u32(uint32_t *value) { *value = 65; return 0; }
