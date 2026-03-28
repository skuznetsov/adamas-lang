/* Benchmark: Nested loops — equivalent to bench_loop.cr
 * Pure compute, no allocations. Tests loop/arithmetic codegen.
 * Scaled up: matrix_sum(30000) for measurable runtime.
 */
#include <stdio.h>
#include <stdint.h>

int32_t matrix_sum(int32_t n) {
    int32_t sum = 0;
    for (int32_t i = 0; i < n; i++) {
        for (int32_t j = 0; j < n; j++) {
            sum = sum + i * j;
        }
    }
    return sum;
}

int main(void) {
    /* Run 100 iterations of matrix_sum(10000) for ~10B ops */
    int32_t total = 0;
    for (int k = 0; k < 100; k++) {
        total += matrix_sum(10000);
    }
    printf("%d\n", total);
    return 0;
}
