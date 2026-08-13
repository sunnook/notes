// get_cycle_count.h
#ifndef GET_CYCLE_COUNT_H
#define GET_CYCLE_COUNT_H

#include <stdint.h>

#if defined(__aarch64__)
static inline uint64_t Get_Dsp_Cycle_Count(void) {
    uint64_t cycles;
    asm volatile("mrs %0, cntvct_el0" : "=r" (cycles));
    return cycles;
}
#elif defined(__x86_64__)
#include <x86intrin.h>
static inline uint64_t Get_Dsp_Cycle_Count(void) {
    return __rdtsc();
}
#elif defined(__ARM_ARCH_7A__)
static inline uint64_t Get_Dsp_Cycle_Count(void) {
    uint32_t cycles;
    asm volatile("mrc p15, 0, %0, c9, c13, 0" : "=r" (cycles));
    return cycles;
}
#else
#error "Unsupported platform - please implement Get_Dsp_Cycle_Count"
#endif

#endif // GET_CYCLE_COUNT_H
