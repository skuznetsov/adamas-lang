/* Benchmark: Fibonacci(47) — C reference implementation
 * ~2.97 billion recursive calls
 * Equivalent to examples/bench_fib47_crystal.cr
 */
#include <stdio.h>
#include <stdint.h>

static uint32_t fib(int32_t n) {
    if (n <= 1) return (uint32_t)n;
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    uint32_t result = fib(47);
    printf("%u\n", result);
    return 0;
}
