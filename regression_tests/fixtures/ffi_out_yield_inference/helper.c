#include <stdint.h>
struct adamas_ffi_yield_info { int64_t first; int64_t second; };
int32_t adamas_ffi_yield_fill(struct adamas_ffi_yield_info *info) {
  info->first = 65; info->second = 66; return 0;
}
int32_t adamas_ffi_yield_after(int32_t first, int64_t second, struct adamas_ffi_yield_info *info) {
  info->first = first; info->second = second; return 0;
}
int32_t adamas_ffi_yield_pointer(int64_t **value) {
  static int64_t payload = 67; *value = &payload; return 0;
}
int32_t adamas_ffi_yield_inspect(int64_t *value) { return (int32_t)*value; }
