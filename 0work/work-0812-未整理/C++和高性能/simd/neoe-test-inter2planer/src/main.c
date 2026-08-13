#include <stdlib.h>
#include <stdint.h>
#include <arm_neon.h>
#include <stdio.h> // printf requires stdio.h, not stdlib.h


#include "inter2planer.h"
#include "cycle_cnt.h"



// 2. Read timer frequency (cycles per second)
static inline uint64_t Get_Timer_Freq(void) {
    uint64_t val;
    // read CNTFRQ_EL0 register
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r" (val));
    return val;
}

// Benchmark function
#include <string.h> // for memset

void banchMark(void)
{
    // 1. Increase iterations to reduce scheduling interference (at least 1000)
    const int iterations = 1000; 
    uint64_t start, end;
    INT32 len = 640;  
    INT32 uBitWidth = 16;

    INT8* dst = malloc(len*2);
    INT8* src = malloc(len*2);

    // 2. Initialize memory to prevent page faults and fill with data
    memset(src, 0xAB, len*2);
    memset(dst, 0x00, len*2);

    // 3. Use volatile sink variable to prevent dead code elimination
    volatile INT32 sink = 0; 

    // warmup
    priv_ao_copy_inter2plan0(src, len, uBitWidth, dst);

    // --- Benchmark inter2plan0 ---
    start = Get_Dsp_Cycle_Count();
    for (int i = 0; i < iterations; i++) {
        priv_ao_copy_inter2plan0(src, len, uBitWidth, dst);
    // force read dst to prevent compiler from optimizing away the copy
    }
    end = Get_Dsp_Cycle_Count();
    printf("[inter2plan0] Average cycles: %llu\n", 
           (unsigned long long)((end - start) / iterations));

    // --- Benchmark inter2plan1 ---
    start = Get_Dsp_Cycle_Count();
    for (int i = 0; i < iterations; i++) {
        priv_ao_copy_inter2plan1(src, len, uBitWidth, dst);
        sink += dst[0];
    }
    end = Get_Dsp_Cycle_Count();
    printf("[inter2plan1] Average cycles: %llu\n", 
           (unsigned long long)((end - start) / iterations));

    // --- Benchmark inter2plan2 ---
    start = Get_Dsp_Cycle_Count();
    for (int i = 0; i < iterations; i++) {
        priv_ao_copy_inter2plan2(src, len, uBitWidth, dst);
        sink += dst[0];
    }
    end = Get_Dsp_Cycle_Count();
    printf("[inter2plan2] Average cycles: %llu\n", 
           (unsigned long long)((end - start) / iterations));

    // --- Benchmark inter2plan3 (NEON) ---
    start = Get_Dsp_Cycle_Count();
    for (int i = 0; i < iterations; i++) {
        priv_ao_copy_inter2plan3(src, len, uBitWidth, dst);
        sink += dst[0];
    }
    end = Get_Dsp_Cycle_Count();
    printf("[inter2plan3] Average cycles: %llu\n", 
           (unsigned long long)((end - start) / iterations));

    // 4. Print sink to prevent entire test block from being optimized away
    printf("Test finished. Sink: %d\n", sink);

    free(dst);
    free(src);

    return ;
}


void banchMark2(void)
{
    const int iterations = 1000; 
    uint64_t start, end, total_cycles;
    INT32 len = 640;  
    INT32 uBitWidth = 16;

    INT8* dst = malloc(len*2);
    INT8* src = malloc(len*2);

    memset(src, 0xAB, len*2);
    memset(dst, 0x00, len*2);

    volatile INT32 sink = 0; 

    // get system timer frequency
    uint64_t freq = Get_Timer_Freq();
    printf("System Timer Frequency: %llu Hz\n", (unsigned long long)freq);

    // warmup
    priv_ao_copy_inter2plan0(src, len, uBitWidth, dst);

    // --- Benchmark inter2plan0 ---
    start = Get_Dsp_Cycle_Count();
    for (int i = 0; i < iterations; i++) {
        priv_ao_copy_inter2plan0(src, len, uBitWidth, dst);
        sink += dst[0]; 
    }
    end = Get_Dsp_Cycle_Count();
    total_cycles = end - start;
    // calculate average time per call (microseconds): (total cycles / frequency) * 1000000 / iterations
    double avg_us = (double)total_cycles * 1000000.0 / (double)freq / iterations;
    printf("[inter2plan0] Avg cycles: %llu, Avg time: %.2f us\n", 
           (unsigned long long)(total_cycles / iterations), avg_us);

    // --- Benchmark inter2plan1 ---
    start = Get_Dsp_Cycle_Count();
    for (int i = 0; i < iterations; i++) {
        priv_ao_copy_inter2plan1(src, len, uBitWidth, dst);
        sink += dst[0];
    }
    end = Get_Dsp_Cycle_Count();
    total_cycles = end - start;
    avg_us = (double)total_cycles * 1000000.0 / (double)freq / iterations;
    printf("[inter2plan1] Avg cycles: %llu, Avg time: %.2f us\n", 
           (unsigned long long)(total_cycles / iterations), avg_us);

    // --- Benchmark inter2plan2 ---
    start = Get_Dsp_Cycle_Count();
    for (int i = 0; i < iterations; i++) {
        priv_ao_copy_inter2plan2(src, len, uBitWidth, dst);
        sink += dst[0];
    }
    end = Get_Dsp_Cycle_Count();
    total_cycles = end - start;
    avg_us = (double)total_cycles * 1000000.0 / (double)freq / iterations;
    printf("[inter2plan2] Avg cycles: %llu, Avg time: %.2f us\n", 
           (unsigned long long)(total_cycles / iterations), avg_us);

    // --- Benchmark inter2plan3 (NEON) ---
    start = Get_Dsp_Cycle_Count();
    for (int i = 0; i < iterations; i++) {
        priv_ao_copy_inter2plan3(src, len, uBitWidth, dst);
        sink += dst[0];
    }
    end = Get_Dsp_Cycle_Count();
    total_cycles = end - start;
    avg_us = (double)total_cycles * 1000000.0 / (double)freq / iterations;
    printf("[inter2plan3] Avg cycles: %llu, Avg time: %.2f us\n", 
           (unsigned long long)(total_cycles / iterations), avg_us);

    printf("Test finished. Sink: %d\n", sink);

    free(dst);
    free(src);

    return ;
}




int main(void)
{
    banchMark();

    banchMark2();
    return 0;
}
