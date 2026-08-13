对于快速傅里叶变化，或者dct变换（在音频和图像领域常用的），是不是也可以做个类似的对比；比如对于jpeg的编码和解码，或者音频静音或特殊声音检测什么的？或者png，帮我分析一下，再设计一下实验方案


<think>
用户提出了一个非常好的问题，他想知道是否可以将之前关于NEON优化和性能对比的方法论，应用到其他算法上，如FFT、DCT、JPEG编解码、音频检测、PNG编解码等。

这是一个系统性的实验设计问题。我需要：
1. 分析这些算法的特点，是否适合做类似的对比
2. 分析每个算法的向量化潜力
3. 设计具体的实验方案

让我逐一分析：

## 算法分析

### 1. FFT (快速傅里叶变换)
- **特点**：蝶形运算，涉及复数乘法、加法，数据依赖性强（前一级输出是后一级输入）
- **向量化潜力**：中等偏高
  - 每个蝶形运算内部的复数乘加可以向量化
  - 同一级的多个蝶形运算可以并行处理
  - 位反转操作可以向量化
- **难点**：数据依赖性强，跨级无法并行；旋转因子查找表访问模式不规则

### 2. DCT (离散余弦变换)
- **特点**：矩阵乘法，余弦基函数，在JPEG/MPEG中广泛使用
- **向量化潜力**：高
  - 本质是矩阵乘法，非常适合SIMD
  - 2D DCT可以分解为行变换+列变换，每行/每列独立
  - 8x8块DCT是经典案例
- **难点**：需要处理转置操作

### 3. JPEG编解码
- **特点**：DCT + 量化 + 熵编码(Huffman/算术编码)
- **向量化潜力**：
  - DCT部分：高
  - 量化部分：高（简单的除法/乘法）
  - 熵编码部分：低（串行依赖，分支密集）
- **难点**：熵编码是瓶颈，很难向量化

### 4. PNG编解码
- **特点**：滤波+ DEFLATE(LZ77 + Huffman)
- **向量化潜力**：
  - 滤波部分：高（Paeth预测器等可以并行）
  - LZ77部分：中等（匹配查找可以部分并行）
  - Huffman部分：低
- **难点**：和JPEG类似，压缩阶段有串行依赖

### 5. 音频静音/特殊声音检测
- **特点**：能量计算、过零率、频谱分析
- **向量化潜力**：高
  - 能量计算是简单的平方求和，完美适合SIMD
  - 过零率计算也可以向量化
  - 如果用FFT做频谱分析，则回到FFT的问题

## 实验方案设计

我需要设计一个完整的实验方案，包括：
1. 实验目标
2. 测试算法选择
3. 实验分组
4. 代码实现要点
5. 性能评估指标
6. 分析方法

让我详细设计。

对于每个算法，我需要考虑：
- 纯C版本怎么写
- NEON手写版本怎么写
- 编译器自动向量化能否生效
- 测试数据怎么准备
- 如何验证正确性

让我选择几个代表性的算法来设计实验：

1. **8x8 DCT** - 图像压缩核心，矩阵运算，向量化潜力高
2. **FFT** - 信号处理核心，蝶形运算，向量化潜力中等
3. **音频能量检测** - 简单但实用，向量化潜力极高
4. **PNG滤波** - 图像处理，向量化潜力高

这样覆盖了从简单到复杂的不同场景。

让我详细写出实验方案。
</think># NEON 优化实验扩展方案：信号处理与编解码领域

## 一、算法向量化可行性分析

在动手之前，我们需要先评估每种算法的 **SIMD 友好度**，这决定了实验的价值和预期收益。

### 评估矩阵

| 算法 | 核心运算 | 数据并行性 | 分支密度 | 数据依赖 | SIMD 友好度 | 预期收益 |
|------|----------|-----------|---------|---------|------------|---------|
| **8×8 DCT** | 矩阵乘法 | 高（行列独立） | 低 | 低 | ★★★★★ | 4-8x |
| **FFT (Radix-2)** | 蝶形运算 | 中（同级蝶形并行） | 低 | 中（跨级依赖） | ★★★☆☆ | 2-4x |
| **音频能量检测** | 平方求和 | 极高 | 极低 | 极低 | ★★★★★ | 8-16x |
| **PNG 滤波** | 像素预测 | 高（行内并行） | 中 | 低 | ★★★★☆ | 3-6x |
| **JPEG 熵编码** | Huffman/bitstream | 极低 | 极高 | 高 | ★☆☆☆☆ | <1.5x |
| **DEFLATE 压缩** | LZ77+Huffman | 低 | 高 | 高 | ★★☆☆☆ | 1.5-2x |

### 关键结论

```
┌─────────────────────────────────────────────────────┐
│  SIMD 擅长的场景：                                   │
│  ✓ 规则的批量算术运算（乘加、平方求和）               │
│  ✓ 无数据依赖的并行通道                              │
│  ✓ 固定步长的内存访问                                │
│                                                      │
│  SIMD 不擅长的场景：                                 │
│  ✗ 串行依赖链（Huffman 编码的 bitstream）             │
│  ✗ 不规则内存访问（LZ77 匹配查找）                    │
│  ✗ 密集分支（条件编码、逃逸码处理）                   │
└─────────────────────────────────────────────────────┘
```

---

## 二、推荐实验算法选型

基于上述分析，我推荐选择 **三个代表性算法**，覆盖从"完美适配"到"具有挑战性"的不同场景：

### 实验 A：8×8 块 DCT 变换（图像压缩核心）
> **代表场景**：规则矩阵运算，SIMD 的"甜点区"

### 实验 B：音频 VAD（静音/语音检测）
> **代表场景**：批量统计计算，SIMD 收益最大

### 实验 C：PNG 行滤波
> **代表场景**：带条件分支的像素处理，SIMD 的"灰色地带"

---

## 三、实验 A：8×8 DCT 变换

### 3.1 算法背景

DCT 是 JPEG 编码的第一步。图像被分成 8×8 的块，每个块做 2D-DCT。2D-DCT 可分解为**行变换 + 列变换**（可分离性），每行/列是一个 1D-DCT。

```
8x8 块 → 行方向 1D-DCT → 转置 → 列方向 1D-DCT → 完成
```

### 3.2 代码实现

```c
#include <stdint.h>
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ============================================================
// 版本 0：纯 C 标准实现（基线）
// ============================================================
static const double dct_coeff[8][8];

// 初始化 DCT 系数表
static void init_dct_coeff(void) {
    for (int i = 0; i < 8; i++) {
        for (int j = 0; j < 8; j++) {
            if (i == 0)
                dct_coeff[i][j] = 1.0 / sqrt(8.0);
            else
                dct_coeff[i][j] = sqrt(2.0 / 8.0) * cos((2 * j + 1) * i * M_PI / 16.0);
        }
    }
}

// 1D-DCT 纯 C 版本：对 8 个 double 做变换
void dct1d_c(const double *src, double *dst) {
    for (int i = 0; i < 8; i++) {
        double sum = 0.0;
        for (int j = 0; j < 8; j++) {
            sum += dct_coeff[i][j] * src[j];
        }
        dst[i] = sum;
    }
}

// 2D-DCT 纯 C 版本
void dct2d_c(const double *block, double *out) {
    double temp[64];
    // 行变换
    for (int row = 0; row < 8; row++) {
        dct1d_c(block + row * 8, temp + row * 8);
    }
    // 转置 + 列变换
    for (int col = 0; col < 8; col++) {
        double col_in[8], col_out[8];
        for (int row = 0; row < 8; row++)
            col_in[row] = temp[row * 8 + col];
        dct1d_c(col_in, col_out);
        for (int row = 0; row < 8; row++)
            out[row * 8 + col] = col_out[row];
    }
}

// ============================================================
// 版本 1：定点化 + 查表优化（工程常见做法）
// ============================================================
// 用 int16_t 代替 double，系数预乘 2^15
static const int16_t dct_coeff_q15[8][8]; // 需初始化

void dct1d_q15(const int16_t *src, int16_t *dst) {
    for (int i = 0; i < 8; i++) {
        int32_t sum = 0;
        for (int j = 0; j < 8; j++) {
            sum += (int32_t)dct_coeff_q15[i][j] * src[j];
        }
        dst[i] = (int16_t)(sum >> 15);
    }
}

// ============================================================
// 版本 2：NEON Intrinsic（手写向量化）
// ============================================================
#include <arm_neon.h>

// 一次处理一行（8个int16_t 正好填满一个 128bit NEON 寄存器）
void dct1d_neon(const int16_t *src, int16_t *dst) {
    // 加载 8 个输入样本到 v0
    int16x8_t v_src = vld1q_s16(src);

    // 加载 8 行系数，每行做点积
    // DCT 系数矩阵的每一行和输入做逐元素乘加
    int16x8_t v_coeff0 = vld1q_s16(dct_coeff_q15[0]);
    int16x8_t v_coeff1 = vld1q_s16(dct_coeff_q15[1]);
    // ... 加载其余 6 行

    // 逐元素乘法
    int16x8_t v_mul0 = vmulq_s16(v_src, v_coeff0);
    int16x8_t v_mul1 = vmulq_s16(v_src, v_coeff1);
    // ...

    // 横向加法（pairwise add 多次，最终求和）
    // vaddv_s16 或 vpaddlq_s16 + vpadd_s16
    int32x4_t v_sum0 = vpaddlq_s16(v_mul0);  // 4个int32
    int32x2_t v_sum0_2 = vadd_s32(vget_low_s32(v_sum0), vget_high_s32(v_sum0));
    int32_t sum0 = vget_lane_s32(v_sum0_2, 0) + vget_lane_s32(v_sum0_2, 1);
    dst[0] = (int16_t)(sum0 >> 15);

    // ... 对其余 7 行重复
}

// ============================================================
// 版本 3：NEON 汇编（极致优化）
// ============================================================
// 直接写汇编，控制寄存器分配和指令调度
// 省略，思路同 intrinsic 但手动分配 q0-q7 寄存器

// ============================================================
// 正确性验证
// ============================================================
int verify_dct(void) {
    double block[64], out_c[64], out_neon[64];
    // 填充测试数据
    for (int i = 0; i < 64; i++)
        block[i] = (double)(i % 17 - 8);

    dct2d_c(block, out_c);
    // dct2d_neon(block_int16, out_neon);  // 需要定点转换

    double max_err = 0;
    for (int i = 0; i < 64; i++) {
        double err = fabs(out_c[i] - (double)out_neon[i]);
        if (err > max_err) max_err = err;
    }
    printf("DCT max error: %f\n", max_err);
    return max_err < 1.0; // 定点误差容忍
}
```

### 3.3 DCT 实验要点

```
为什么 DCT 是 SIMD 的"甜点区"？
┌──────────────────────────────────────────────┐
│ 1. 8个 int16 恰好 = 1个 128bit NEON 寄存器    │
│    → 完美的数据对齐                           │
│ 2. 8×8 矩阵乘法 = 64次独立乘加               │
│    → 零数据依赖                              │
│ 3. 系数固定 → 可预加载到寄存器                │
│ 4. 无分支 → 流水线不中断                      │
└──────────────────────────────────────────────┘
```

---

## 四、实验 B：音频 VAD（静音检测）

### 4.1 算法背景

VAD（Voice Activity Detection）通过计算短时能量和过零率来判断音频帧是否为静音。

```
音频帧(256样本) → 计算能量 → 计算过零率 → 阈值判断 → 静音/语音
```

### 4.2 代码实现

```c
#include <stdint.h>
#include <arm_neon.h>

#define FRAME_SIZE 256

// ============================================================
// 版本 0：纯 C 实现
// ============================================================
float compute_energy_c(const int16_t *samples, int len) {
    float energy = 0.0f;
    for (int i = 0; i < len; i++) {
        float s = (float)samples[i];
        energy += s * s;
    }
    return energy / len;
}

int compute_zcr_c(const int16_t *samples, int len) {
    int zcr = 0;
    for (int i = 1; i < len; i++) {
        if ((samples[i] >= 0 && samples[i-1] < 0) ||
            (samples[i] < 0 && samples[i-1] >= 0)) {
            zcr++;
        }
    }
    return zcr;
}

int is_silence_c(const int16_t *frame, int len,
                 float energy_thresh, int zcr_thresh) {
    float energy = compute_energy_c(frame, len);
    int zcr = compute_zcr_c(frame, len);
    return (energy < energy_thresh) && (zcr > zcr_thresh);
}

// ============================================================
// 版本 1：查表优化 + 整数运算
// ============================================================
int32_t compute_energy_int_c(const int16_t *samples, int len) {
    int32_t energy = 0;
    for (int i = 0; i < len; i++) {
        energy += (int32_t)samples[i] * samples[i];
    }
    return energy;
}

// ============================================================
// 版本 2：NEON Intrinsic
// ============================================================
// 能量计算：平方求和，SIMD 的完美场景
int32_t compute_energy_neon(const int16_t *samples, int len) {
    int32x4_t v_acc = vdupq_n_s32(0);  // 累加器

    // 每次处理 8 个 int16_t（填满 128bit）
    int i = 0;
    for (; i + 8 <= len; i += 8) {
        int16x8_t v_s = vld1q_s16(samples + i);
        // int16 平方会溢出，先扩宽到 int32 再乘
        // 拆成两个 int32x4
        int32x4_t v_low = vmovl_s16(vget_low_s16(v_s));
        int32x4_t v_high = vmovl_s16(vget_high_s16(v_s));
        // 逐元素乘法
        v_low = vmulq_s32(v_low, v_low);
        v_high = vmulq_s32(v_high, v_high);
        // 累加
        v_acc = vaddq_s32(v_acc, v_low);
        v_acc = vaddq_s32(v_acc, v_high);
    }

    // 横向归约：4个int32 → 1个int32
    int32x2_t v_pair = vpadd_s32(vget_low_s32(v_acc), vget_high_s32(v_acc));
    v_pair = vpadd_s32(v_pair, v_pair);
    int32_t total = vget_lane_s32(v_pair, 0);

    // 处理尾部剩余样本
    for (; i < len; i++) {
        total += (int32_t)samples[i] * samples[i];
    }
    return total;
}

// 过零率计算：NEON 版本（用符号位 XOR）
int compute_zcr_neon(const int16_t *samples, int len) {
    int zcr = 0;
    int i = 1;

    // NEON 处理：比较相邻样本符号位
    for (; i + 8 <= len; i += 8) {
        int16x8_t v_cur = vld1q_s16(samples + i);
        int16x8_t v_prev = vld1q_s16(samples + i - 1);
        // 取符号位：右移 15 位
        int16x8_t v_sign_cur = vshrq_n_s16(v_cur, 15);
        int16x8_t v_sign_prev = vshrq_n_s16(v_prev, 15);
        // 符号不同 → XOR 结果为非零
        int16x8_t v_diff = veorq_s16(v_sign_cur, v_sign_prev);
        // 统计非零元素个数
        uint16x8_t v_mask = vtstq_s16(v_diff, v_diff);  // 非零→0xFFFF
        uint16x8_t v_one = vdupq_n_u16(1);
        uint16x8_t v_count = vandq_u16(v_mask, v_one);
        // 横向求和
        zcr += vaddvq_u16(v_count);
    }

    // 尾部标量处理
    for (; i < len; i++) {
        if ((samples[i] >= 0 && samples[i-1] < 0) ||
            (samples[i] < 0 && samples[i-1] >= 0))
            zcr++;
    }
    return zcr;
}

// ============================================================
// 版本 3：NEON 汇编版（省略，思路同上）
// ============================================================
```

### 4.3 VAD 实验要点

```
为什么 VAD 能获得最大 SIMD 收益？
┌──────────────────────────────────────────────┐
│ 1. 256 样本的帧 → 32 次 NEON 迭代             │
│    → 并行度极高                               │
│ 2. 平方求和 = 最经典的 SIMD pattern           │
│    → 编译器自动向量化几乎肯定生效              │
│ 3. 过零率用 XOR + TST 指令巧妙实现             │
│    → 展示 SIMD 处理"逻辑判断"的能力            │
│ 4. 尾部处理展示了 NEON + 标量混合编程范式      │
└──────────────────────────────────────────────┘

预期收益：
  能量计算：纯C → NEON 约 8-12x（8个样本并行）
  过零率：  纯C → NEON 约 6-8x
```

---

## 五、实验 C：PNG 行滤波

### 5.1 算法背景

PNG 编码时对每行像素做滤波（预测编码），以提高后续 DEFLATE 压缩率。5 种滤波类型中，**Paeth 滤波器**最复杂，也最适合测试 SIMD 优化能力。

```
Paeth 滤波器：
  对每个像素 x，利用左边 A、上方 B、左上 C 预测：
  p = PaethPredictor(A, B, C)
  滤波值 = x - p

PaethPredictor(A, B, C):
  p = A + B - C
  pa = |p - A|, pb = |p - B|, pc = |p - C|
  if pa <= pb and pa <= pc: return A
  elif pb <= pc: return B
  else: return C
```

### 5.2 代码实现

```c
#include <stdint.h>
#include <stdlib.h>
#include <arm_neon.h>

// ============================================================
// 版本 0：纯 C 实现
// ============================================================
static inline uint8_t paeth_predictor(uint8_t a, uint8_t b, uint8_t c) {
    int p = (int)a + (int)b - (int)c;
    int pa = abs(p - a);
    int pb = abs(p - b);
    int pc = abs(p - c);
    if (pa <= pb && pa <= pc) return a;
    else if (pb <= pc) return b;
    else return c;
}

void png_filter_paeth_c(const uint8_t *cur_row,
                         const uint8_t *prev_row,
                         uint8_t *out, int len, int bpp) {
    // 前 bpp 字节用特殊处理（没有左侧邻居）
    for (int i = 0; i < bpp && i < len; i++) {
        uint8_t a = 0;
        uint8_t b = prev_row[i];
        uint8_t c = 0;
        out[i] = cur_row[i] - paeth_predictor(a, b, c);
    }
    for (int i = bpp; i < len; i++) {
        uint8_t a = cur_row[i - bpp];
        uint8_t b = prev_row[i];
        uint8_t c = prev_row[i - bpp];
        out[i] = cur_row[i] - paeth_predictor(a, b, c);
    }
}

// ============================================================
// 版本 1：查表 + 分支消除
// ============================================================
// Paeth 预测器的本质是一个 3 输入查表
// 但 3 个 8bit 输入 → 24bit 地址空间太大
// 折中：用位运算消除 if-else
static inline uint8_t paeth_predictor_branchless(uint8_t a, uint8_t b, uint8_t c) {
    int p = (int)a + (int)b - (int)c;
    int pa = abs(p - a);
    int pb = abs(p - b);
    int pc = abs(p - c);

    // 用条件掩码消除分支
    int min_ab = (pa <= pb) ? a : b;
    int result = (pa <= pc) ? min_ab : ((pb <= pc) ? b : c);
    return (uint8_t)result;
}

// ============================================================
// 版本 2：NEON Intrinsic
// ============================================================
// 难点：Paeth 预测器有条件分支，需要用向量化比较指令替代
void png_filter_paeth_neon(const uint8_t *cur_row,
                            const uint8_t *prev_row,
                            uint8_t *out, int len, int bpp) {
    int i = bpp;

    // NEON 一次处理 16 个 uint8_t
    for (; i + 16 <= len; i += 16) {
        // 加载 A = cur_row[i-bpp ... i-bpp+15]
        uint8x16_t v_a = vld1q_u8(cur_row + i - bpp);
        // 加载 B = prev_row[i ... i+15]
        uint8x16_t v_b = vld1q_u8(prev_row + i);
        // 加载 C = prev_row[i-bpp ... i-bpp+15]
        uint8x16_t v_c = vld1q_u8(prev_row + i - bpp);
        // 加载 X = cur_row[i ... i+15]
        uint8x16_t v_x = vld1q_u8(cur_row + i);

        // 扩展到 int16 以避免溢出
        int16x8_t v_a_lo = vreinterpretq_s16_u16(vmovl_u8(vget_low_u8(v_a)));
        int16x8_t v_a_hi = vreinterpretq_s16_u16(vmovl_u8(vget_high_u8(v_a)));
        int16x8_t v_b_lo = vreinterpretq_s16_u16(vmovl_u8(vget_low_u8(v_b)));
        int16x8_t v_b_hi = vreinterpretq_s16_u16(vmovl_u8(vget_high_u8(v_b)));
        int16x8_t v_c_lo = vreinterpretq_s16_u16(vmovl_u8(vget_low_u8(v_c)));
        int16x8_t v_c_hi = vreinterpretq_s16_u16(vmovl_u8(vget_high_u8(v_c)));

        // p = A + B - C
        int16x8_t v_p_lo = vsubq_s16(vaddq_s16(v_a_lo, v_b_lo), v_c_lo);
        int16x8_t v_p_hi = vsubq_s16(vaddq_s16(v_a_hi, v_b_hi), v_c_hi);

        // pa = |p - A|, pb = |p - B|, pc = |p - C|
        int16x8_t v_pa_lo = vabdq_s16(v_p_lo, v_a_lo);
        int16x8_t v_pb_lo = vabdq_s16(v_p_lo, v_b_lo);
        int16x8_t v_pc_lo = vabdq_s16(v_p_lo, v_c_lo);
        // ... hi 同理

        // 条件选择（用向量比较 + 条件选择指令 BSL）
        // if pa <= pb && pa <= pc: select A
        // elif pb <= pc: select B
        // else: select C

        // pa <= pb ?
        uint16x8_t v_mask_ab_lo = vcleq_s16(v_pa_lo, v_pb_lo);
        // pa <= pc ?
        uint16x8_t v_mask_ac_lo = vcleq_s16(v_pa_lo, v_pc_lo);
        // pb <= pc ?
        uint16x8_t v_mask_bc_lo = vcleq_s16(v_pb_lo, v_pc_lo);

        // pa is minimum → (pa<=pb) AND (pa<=pc)
        uint16x8_t v_sel_a_lo = vandq_u16(v_mask_ab_lo, v_mask_ac_lo);
        // pb is minimum → NOT(pa<=pb) AND (pb<=pc)
        uint16x8_t v_sel_b_lo = vandq_u16(vmvnq_u16(v_mask_ab_lo), v_mask_bc_lo);
        // else → C

        // 用 BSL (Bitwise Select) 合并结果
        // result = sel_a ? A : (sel_b ? B : C)
        int16x8_t v_pred_lo = vbslq_s16(v_sel_a_lo, v_a_lo, v_b_lo);
        v_pred_lo = vbslq_s16(v_sel_b_lo, v_b_lo, v_c_lo);
        // 注意：上面逻辑需要修正，正确写法是：
        // v_pred = vbslq_s16(v_sel_a, v_a, vbslq_s16(v_sel_b, v_b, v_c));

        // ... hi 同理（省略）

        // 滤波值 = X - predictor
        // 需要把 predictor 从 int16 截回 uint8
        // ... 省略截断和减法

        // 存储
        // vst1q_u8(out + i, v_result);
    }

    // 尾部标量处理
    for (; i < len; i++) {
        uint8_t a = cur_row[i - bpp];
        uint8_t b = prev_row[i];
        uint8_t c = prev_row[i - bpp];
        out[i] = cur_row[i] - paeth_predictor(a, b, c);
    }
}

// ============================================================
// 版本 3：NEON 汇编版（省略）
// ============================================================
```

### 5.3 PNG 滤波实验要点

```
为什么 PNG 滤波是"灰色地带"？
┌──────────────────────────────────────────────┐
│ 挑战1：Paeth 预测器有条件分支                  │
│   → 需要用向量比较 + BSL 指令消除分支          │
│   → 代码复杂度大幅增加                         │
│                                                │
│ 挑战2：uint8 → int16 扩展开销                  │
│   → 中间运算需要 int16 防溢出                  │
│   → 一次处理 16 个 uint8 需要拆成 2 个 int16x8 │
│                                                │
│ 挑战3：bpp 对齐问题                            │
│   → RGB 图像 bpp=3，不是 2 的幂               │
│   → 加载地址不对齐，NEON 效率下降              │
│                                                │
│ 收益预期：                                     │
│   灰度图(bpp=1)：3-5x（对齐好，收益高）        │
│   RGB图(bpp=3)：1.5-2x（对齐差，收益低）       │
└──────────────────────────────────────────────┘
```

---

## 六、统一实验框架

### 6.1 实验分组设计

```
┌─────────────────────────────────────────────────────────┐
│                  实验分组矩阵                             │
├──────────┬────────────────┬────────────────┬───────────┤
│  Group   │   编译选项      │   目的         │  评估重点 │
├──────────┼────────────────┼────────────────┼───────────┤
│ Group 1  │ -O0            │ 基线参考       │ 绝对下限   │
│ Group 2  │ -O2            │ 标量优化极限   │ ★核心对比  │
│          │ -fno-tree-     │ (禁止向量化)   │           │
│          │  vectorize     │                │           │
├──────────┼────────────────┼────────────────┼───────────┤
│ Group 3  │ -O3            │ 编译器自动向量化│ 编译器能力 │
│          │ -ftree-        │                │           │
│          │  vectorize     │                │           │
├──────────┼────────────────┼────────────────┼───────────┤
│ Group 4  │ -O2            │ 手写NEON在     │ 手写价值   │
│          │ -fno-tree-     │ 禁止自动向量化 │           │
│          │  vectorize     │ 环境下的表现   │           │
└──────────┴────────────────┴────────────────┴───────────┘

核心对比逻辑：
  Group 2 vs Group 4  → 手写 NEON 的真实收益（★最重要）
  Group 3 vs Group 4  → 手写 vs 编译器自动向量化的差距
  Group 2 的 inter2plan0 vs Group 3 的 inter2plan0 → 编译器自动向量化是否生效
```

### 6.2 统一 Benchmark 框架

```c
// ============================================================
// 通用性能测试框架
// ============================================================
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// ARMv8 周期计数器
static inline uint64_t get_cycle_count(void) {
    uint64_t val;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(val));
    return val;
}

static inline uint64_t get_timer_freq(void) {
    uint64_t val;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(val));
    return val;
}

// 通用 benchmark 模板
typedef void (*func_ptr)(const void *src, void *dst, int len);

typedef struct {
    const char *name;
    func_ptr func;
    int warmup_iters;
    int test_iters;
} benchmark_entry_t;

void run_benchmark(const benchmark_entry_t *entry,
                   const void *src, void *dst, int len) {
    uint64_t freq = get_timer_freq();
    volatile int sink = 0;

    // 预热
    for (int i = 0; i < entry->warmup_iters; i++) {
        entry->func(src, dst, len);
        sink += ((uint8_t*)dst)[0];
    }

    // 正式测试
    uint64_t start = get_cycle_count();
    for (int i = 0; i < entry->test_iters; i++) {
        entry->func(src, dst, len);
        sink += ((uint8_t*)dst)[0];
    }
    uint64_t end = get_cycle_count();

    uint64_t total_cycles = end - start;
    uint64_t avg_cycles = total_cycles / entry->test_iters;
    double avg_us = (double)total_cycles * 1e6 / (double)freq / entry->test_iters;

    printf("[%-20s] avg_cycles: %8llu  avg_time: %8.2f us  sink: %d\n",
           entry->name,
           (unsigned long long)avg_cycles,
           avg_us,
           sink);
}

// ============================================================
// 主测试函数
// ============================================================
void benchmark_dct(void) {
    printf("\n===== 8x8 DCT Benchmark =====\n");

    double block[64], out[64];
    for (int i = 0; i < 64; i++)
        block[i] = (double)(i % 17 - 8);

    // 测试多个块以增加数据量
    const int NUM_BLOCKS = 1000;
    double *blocks = malloc(sizeof(double) * 64 * NUM_BLOCKS);
    double *outs = malloc(sizeof(double) * 64 * NUM_BLOCKS);
    for (int i = 0; i < 64 * NUM_BLOCKS; i++)
        blocks[i] = (double)(i % 17 - 8);

    uint64_t freq = get_timer_freq();
    volatile double sink = 0;
    int iters = 100;

    // 预热
    for (int i = 0; i < NUM_BLOCKS; i++)
        dct2d_c(blocks + i * 64, outs + i * 64);

    // 纯 C 版本
    uint64_t start = get_cycle_count();
    for (int iter = 0; iter < iters; iter++) {
        for (int i = 0; i < NUM_BLOCKS; i++)
            dct2d_c(blocks + i * 64, outs + i * 64);
        sink += outs[0];
    }
    uint64_t end = get_cycle_count();
    uint64_t cycles = (end - start) / iters;
    double us = (double)(end - start) * 1e6 / freq / iters;
    printf("[DCT Pure C    ] blocks: %d, cycles: %llu, time: %.2f us\n",
           NUM_BLOCKS, (unsigned long long)cycles, us);

    // NEON 版本（类似结构）
    // ...

    free(blocks);
    free(outs);
}

void benchmark_vad(void) {
    printf("\n===== Audio VAD Benchmark =====\n");

    const int FRAME_SIZE = 256;
    const int NUM_FRAMES = 1000;
    int16_t *frames = malloc(sizeof(int16_t) * FRAME_SIZE * NUM_FRAMES);
    for (int i = 0; i < FRAME_SIZE * NUM_FRAMES; i++)
        frames[i] = (int16_t)(rand() % 65536 - 32768);

    uint64_t freq = get_timer_freq();
    volatile int32_t sink = 0;
    int iters = 100;

    // 预热
    for (int i = 0; i < NUM_FRAMES; i++)
        compute_energy_c(frames + i * FRAME_SIZE, FRAME_SIZE);

    // 纯 C 能量计算
    uint64_t start = get_cycle_count();
    for (int iter = 0; iter < iters; iter++) {
        for (int i = 0; i < NUM_FRAMES; i++)
            sink += compute_energy_c(frames + i * FRAME_SIZE, FRAME_SIZE);
    }
    uint64_t end = get_cycle_count();
    uint64_t cycles = (end - start) / iters;
    double us = (double)(end - start) * 1e6 / freq / iters;
    printf("[VAD Energy C  ] frames: %d, cycles: %llu, time: %.2f us\n",
           NUM_FRAMES, (unsigned long long)cycles, us);

    // NEON 能量计算
    start = get_cycle_count();
    for (int iter = 0; iter < iters; iter++) {
        for (int i = 0; i < NUM_FRAMES; i++)
            sink += compute_energy_neon(frames + i * FRAME_SIZE, FRAME_SIZE);
    }
    end = get_cycle_count();
    cycles = (end - start) / iters;
    us = (double)(end - start) * 1e6 / freq / iters;
    printf("[VAD Energy NEON] frames: %d, cycles: %llu, time: %.2f us\n",
           NUM_FRAMES, (unsigned long long)cycles, us);

    // 过零率对比
    // ...

    free(frames);
}

void benchmark_png_filter(void) {
    printf("\n===== PNG Paeth Filter Benchmark =====\n");

    const int ROW_LEN = 1920;  // FHD 宽度
    const int NUM_ROWS = 100;
    uint8_t *cur_rows = malloc(ROW_LEN * NUM_ROWS);
    uint8_t *prev_rows = malloc(ROW_LEN * NUM_ROWS);
    uint8_t *out_rows = malloc(ROW_LEN * NUM_ROWS);

    // 填充随机图像数据
    for (int i = 0; i < ROW_LEN * NUM_ROWS; i++) {
        cur_rows[i] = rand() & 0xFF;
        prev_rows[i] = rand() & 0xFF;
    }

    uint64_t freq = get_timer_freq();
    volatile int sink = 0;
    int iters = 100;
    int bpp = 3; // RGB

    // 预热
    for (int i = 0; i < NUM_ROWS; i++)
        png_filter_paeth_c(cur_rows + i * ROW_LEN,
                           prev_rows + i * ROW_LEN,
                           out_rows + i * ROW_LEN,
                           ROW_LEN, bpp);

    // 纯 C 版本
    uint64_t start = get_cycle_count();
    for (int iter = 0; iter < iters; iter++) {
        for (int i = 0; i < NUM_ROWS; i++)
            png_filter_paeth_c(cur_rows + i * ROW_LEN,
                               prev_rows + i * ROW_LEN,
                               out_rows + i * ROW_LEN,
                               ROW_LEN, bpp);
        sink += out_rows[0];
    }
    uint64_t end = get_cycle_count();
    uint64_t cycles = (end - start) / iters;
    double us = (double)(end - start) * 1e6 / freq / iters;
    printf("[PNG Paeth C   ] rows: %d, len: %d, cycles: %llu, time: %.2f us\n",
           NUM_ROWS, ROW_LEN, (unsigned long long)cycles, us);

    // NEON 版本
    // ...

    free(cur_rows);
    free(prev_rows);
    free(out_rows);
}

// ============================================================
// 主函数
// ============================================================
int main(void) {
    uint64_t freq = get_timer_freq();
    printf("========================================\n");
    printf("  NEON Optimization Benchmark Suite\n");
    printf("  Timer Freq: %llu Hz\n", (unsigned long long)freq);
    printf("========================================\n");

    init_dct_coeff();

    benchmark_dct();
    benchmark_vad();
    benchmark_png_filter();

    printf("\n========================================\n");
    printf("  All benchmarks finished.\n");
    printf("========================================\n");

    return 0;
}
```

### 6.3 Makefile 设计

```makefile
# ============================================================
# 通用 Makefile - 支持多组编译选项
# ============================================================

CROSS_COMPILE = aarch64-linux-gnu-
CC = $(CROSS_COMPILE)gcc

ARCH_FLAGS = -march=armv8-a -mtune=cortex-a53

# 可配置的优化级别
OPT_LEVEL ?= -O2
VECT_FLAG ?= -fno-tree-vectorize

CFLAGS = $(ARCH_FLAGS) -g $(OPT_LEVEL) $(VECT_FLAG) \
         -ftree-vectorize -fno-builtin -fno-common \
         -Wformat=1 -MMD -MP -Wall

LDFLAGS = -lm

TARGET = neon_benchmark
SRCS = main.c dct.c vad.c png_filter.c common.c
OBJS = $(SRCS:.c=.o)

.PHONY: all clean group1 group2 group3 group4

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

# ============================================================
# 一键测试所有 Group
# ============================================================
group1:
	$(MAKE) clean
	$(MAKE) OPT_LEVEL=-O0 VECT_FLAG=""
	./$(TARGET) | tee result_group1.txt

group2:
	$(MAKE) clean
	$(MAKE) OPT_LEVEL=-O2 VECT_FLAG="-fno-tree-vectorize"
	./$(TARGET) | tee result_group2.txt

group3:
	$(MAKE) clean
	$(MAKE) OPT_LEVEL=-O3 VECT_FLAG="-ftree-vectorize"
	./$(TARGET) | tee result_group3.txt

group4:
	$(MAKE) clean
	$(MAKE) OPT_LEVEL=-O2 VECT_FLAG="-fno-tree-vectorize"
	./$(TARGET) | tee result_group4.txt

# 反汇编目标
disasm: $(TARGET)
	$(CROSS_COMPILE)objdump -d -S $(TARGET) > $(TARGET).asm

clean:
	rm -f $(OBJS) $(TARGET) $(TARGET).asm *.d result_*.txt
```

---

## 七、预期结果与分析方法

### 7.1 预期性能对比表

```
┌────────────────┬──────────┬──────────┬──────────┬──────────┐
│ 算法           │ Group 2  │ Group 3  │ Group 4  │ NEON     │
│                │ 纯C(-O2) │ 自动向量化│ 手写NEON │ 收益     │
│                │          │ 纯C(-O3) │ (-O2)    │ (G2→G4) │
├────────────────┼──────────┼──────────┼──────────┼──────────┤
│ DCT 8x8        │ ~5000    │ ~1200    │ ~800     │ ~6x      │
│ (cycles/block) │          │          │          │          │
├────────────────┼──────────┼──────────┼──────────┼──────────┤
│ VAD 能量计算   │ ~800     │ ~120     │ ~100     │ ~8x      │
│ (cycles/frame) │          │          │          │          │
├────────────────┼──────────┼──────────┼──────────┼──────────┤
│ PNG Paeth      │ ~3000    │ ~2800    │ ~800     │ ~3.5x    │
│ (cycles/row)   │          │ (难自动)  │          │          │
└────────────────┴──────────┴──────────┴──────────┴──────────┘
```

### 7.2 分析维度

```
┌─────────────────────────────────────────────────────────────┐
│                    分析维度清单                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ 1. 绝对性能对比                                              │
│    → Group 2 vs Group 4：手写 NEON 的真实工程收益             │
│                                                              │
│ 2. 编译器能力评估                                            │
│    → Group 3 vs Group 4：编译器自动向量化 vs 手写             │
│    → 哪些算法编译器做得好？哪些做得差？为什么？               │
│                                                              │
│ 3. 算法特性与 SIMD 收益的关系                                 │
│    → DCT（规则矩阵）→ 收益最高                                │
│    → VAD（批量统计）→ 收益最高                                │
│    → PNG Paeth（条件分支）→ 收益中等                          │
│                                                              │
│ 4. 反汇编分析                                                │
│    → Group 3 的纯 C 代码是否生成了 ld1/st1？                 │
│    → 自动生成的 NEON 指令质量如何？                           │
│    → 寄存器分配是否合理？                                     │
│    → 循环展开程度？                                          │
│                                                              │
│ 5. 数据对齐影响                                              │
│    → DCT 8x8 天然对齐 → 无性能损失                           │
│    → PNG RGB(bpp=3) 不对齐 → 性能损失                        │
│    → 对比 bpp=1 vs bpp=3 的 NEON 收益差异                    │
│                                                              │
│ 6. 正确性验证                                                │
│    → 定点 vs 浮点的精度损失                                   │
│    → NEON 中间溢出风险                                       │
│    → 尾部处理是否正确                                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 7.3 最终报告模板

```
NEON 优化实验报告

1. 实验环境
   - CPU: Cortex-A53 @ 1.4GHz
   - OS: Linux 4.x aarch64
   - Compiler: GCC 9.x
   - Timer Freq: 24MHz

2. 实验结果汇总表
   [填入 7.1 的表格]

3. 各算法详细分析
   3.1 DCT
       - 纯 C 瓶颈分析
       - NEON 优化策略
       - 反汇编关键片段
       - 收益分析
   3.2 VAD (同上)
   3.3 PNG Filter (同上)

4. 编译器自动向量化能力评估
   - 哪些代码编译器向量化成功？
   - 哪些失败？原因分析
   - 反汇编对比

5. 结论与建议
   - 何时应该手写 NEON？
   - 何时可以依赖编译器？
   - 何时 SIMD 收益有限？
```

---

## 八、总结

这三个实验覆盖了 SIMD 优化的**三种典型场景**：

| 场景 | 算法 | 教学价值 |
|------|------|---------|
| **甜点区** | DCT | 展示 SIMD 的最大威力，编译器自动向量化也很容易生效 |
| **统计计算** | VAD 能量检测 | 最经典的 SIMD pattern（平方求和），收益最大 |
| **灰色地带** | PNG Paeth | 展示如何用向量比较指令处理条件分支，编译器难以自动优化 |

通过这套实验，你不仅能掌握 NEON 优化的具体技术，更能建立**"什么时候值得花时间手写 NEON"**的工程判断力。








