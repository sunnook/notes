

<think>
The user is asking three questions:
1. From a professional perspective, how should we understand the Linux source code through layering and modularization?
2. Where are the C++20 new features reflected? Has the STL been modified? Can we view the libc++ source code? Does glibc have anything worth learning?

Let me analyze this carefully.

First, the user has shown me the Linux kernel 7.1.2 source code tree. This is a very recent version (Linux 7.1.2). Wait, actually Linux kernel versions don't go that high yet - the latest stable as of my knowledge is around 6.x. But the user says it's 7.1.2, so maybe this is a newer version. Actually, looking at the directory structure, it has `io_uring` as a top-level directory which was added in kernel 5.x, and `rust` directory which was added in kernel 6.x. So this could be a very new version. Let me not question the version and just analyze what's there.

Actually, wait - the system time says 2026-07-01, so Linux 7.1.2 could be a real version by then. Let me proceed with the analysis.

Now let me address the questions:

**Question 1: How to understand Linux source code through layering and modularization?**

The Linux kernel has a well-defined architecture. Let me think about this from a professional perspective:

Layers (from bottom to top):
1. Hardware Abstraction Layer (arch/)
2. Core kernel services (kernel/, mm/, sched/)
3. Subsystems (fs/, net/, block/, crypto/)
4. Device drivers (drivers/)
5. System call interface (the boundary to userspace)

Modules:
- arch/ - Architecture-specific code
- kernel/ - Core kernel (scheduling, IPC, signals, etc.)
- mm/ - Memory management
- fs/ - Filesystems (VFS + specific filesystems)
- net/ - Networking stack
- drivers/ - Device drivers
- block/ - Block I/O layer
- crypto/ - Crypto API
- security/ - Security frameworks (SELinux, AppArmor, etc.)
- sound/ - Sound subsystem (ALSA)
- include/ - Header files
- lib/ - Utility libraries
- init/ - Boot/init code
- ipc/ - System V IPC
- virt/ - Virtualization (KVM)
- io_uring/ - io_uring subsystem (relatively new, was promoted to top-level)
- certs/ - Certificate handling
- Documentation/ - Documentation
- scripts/ - Build scripts
- tools/ - Userspace tools
- usr/ - initramfs generation
- rust/ - Rust support (new)

**Question 2: C++20 new features, STL changes, libc++ source, glibc learning**

Wait, this question seems to be mixing C++ with Linux kernel. The Linux kernel is written in C (and some assembly, and now some Rust). It does NOT use C++. So I need to clarify this.

However, the user might be asking about C++20 in a general context, not specifically related to the Linux kernel. Let me re-read the question.

"2.c++20新特性体现在哪里，stl有改动吗？libc++源码是不是能看？glibc有没有值得学习的地方"

This seems like a separate question about C++20, not specifically about the Linux kernel. The user might be asking:
- Where are C++20 new features reflected (in general, or in some codebase)?
- Has STL been modified?
- Can we view libc++ source code?
- Does glibc have anything worth learning?

Since the user is looking at the Linux kernel source, they might be confused about the relationship between:
- Linux kernel (C code, no C++)
- glibc (GNU C Library - userspace C library, not in the kernel)
- libc++ (C++ standard library implementation, not in the kernel)

Let me provide a comprehensive answer that clarifies these distinctions.

Actually, let me reconsider. The user might be asking these as separate questions - the first about Linux kernel source code, and the second about C++20/STL/libc++/glibc in general (perhaps related to their Android development work, since Android uses bionic, not glibc, and libc++ for C++ support).

Let me structure my answer:

1. Linux kernel source code analysis (layering and modularization)
2. C++20 features, STL, libc++, glibc discussion

For the C++20 part:
- C++20 major features: concepts, ranges, coroutines, modules, `<=>` spaceship operator, `std::format`, `std::span`, `std::jthread`, `consteval`, `constinit`, designated initializers, etc.
- STL changes in C++20: new headers like `<concepts>`, `<ranges>`, `<format>`, `<coroutine>`, `<numbers>`, `<source_location>`, `<syncstream>`, etc. Many existing components got constexpr additions.
- libc++ (LLVM's C++ standard library) source is open source and available at https://github.com/llvm/llvm-project/tree/main/libcxx. Yes, you can read it.
- glibc (GNU C Library) is the C standard library for Linux userspace. It's open source and definitely worth studying for things like: memory allocation (ptmalloc), thread implementation (NPTL), locale handling, dynamic linking, etc.

Let me also note that in the context of Android development:
- Android uses bionic (not glibc) as its C library
- Android uses libc++ (from LLVM) as its C++ standard library
- The Linux kernel itself is pure C + assembly + some Rust

Let me write a comprehensive answer.
</think># 一、Linux 内核源码的分层与分模块分析

## 1. 分层架构（自底向上）

Linux 内核的分层不像 Android 那样有严格的 API 墙，但存在清晰的**依赖方向**：

```
┌─────────────────────────────────────────────┐
│  系统调用接口层  ← 用户空间的边界            │
│  (sys_xxx, 在各子系统入口处)                 │
├─────────────────────────────────────────────┤
│  子系统层                                    │
│  fs/  net/  block/  sound/  crypto/  ...    │
├─────────────────────────────────────────────┤
│  内核核心层                                  │
│  kernel/  mm/  sched/  ipc/  time/          │
├─────────────────────────────────────────────┤
│  硬件抽象层                                  │
│  arch/  drivers/  include/                  │
├─────────────────────────────────────────────┤
│  硬件                                       │
└─────────────────────────────────────────────┘
```

### 第一层：硬件抽象层

| 目录 | 职责 |
|------|------|
| `arch/` | 每种 CPU 架构的特定代码。`arch/arm64/` 是你 RK 平台最相关的。包含页表设置、中断向量、原子操作、上下文切换等 |
| `drivers/` | 设备驱动，内核中**体量最大**的目录。但驱动代码只调用内核提供的框架接口，不直接碰硬件寄存器之外的内核核心 |
| `include/` | 全局头文件。`include/linux/` 是内核的"公共 API" |

**关键理解：** `arch/` 定义了"CPU 怎么跑"，`drivers/` 定义了"外设怎么用"。两者通过内核核心层提供的框架间接交互。

### 第二层：内核核心层

| 目录 | 职责 |
|------|------|
| `kernel/` | 进程管理（`fork.c`、`exit.c`）、调度器（`sched/`）、信号（`signal.c`）、中断管理、时间管理、cgroup |
| `mm/` | 内存管理。`page_alloc.c`（伙伴系统）、`slub.c`（slab 分配器）、`mmap.c`（虚拟内存映射）、`vmscan.c`（页面回收）|
| `ipc/` | System V IPC（消息队列、共享内存、信号量）|

**关键理解：** 这一层是内核的"操作系统原理"教科书实现。`mm/` 和 `kernel/sched/` 是理解 Linux 运行机制的核心。

### 第三层：子系统层

| 目录 | 职责 |
|------|------|
| `fs/` | VFS（虚拟文件系统）框架 + 具体文件系统实现（ext4, f2fs, fuse...）|
| `net/` | 网络协议栈。`net/core/`（socket 核心）、`net/ipv4/`、`net/ipv6/`、`net/sched/`（流量控制）|
| `block/` | 块设备 I/O 层。`blk-mq.c`（多队列块设备）、I/O 调度器（`mq-deadline.c`, `bfq-iosched.c`）|
| `crypto/` | 内核加密 API。提供对称/非对称加密、哈希、压缩的统一接口 |
| `sound/` | ALSA 音频子系统。`sound/soc/`（ASoC，嵌入式音频核心）|
| `security/` | 安全框架。SELinux、AppArmor、Landlock 等 LSM（Linux Security Module）|
| `io_uring/` | 新一代异步 I/O 框架（5.x 引入，6.x/7.x 提升为顶级目录）|

### 第四层：系统调用接口

系统调用是用户空间和内核的**唯一合法通道**。以 ARM64 为例：

```
用户调用 open()
    → libc 的 syscall 包装（用户空间）
    → svc #0 指令触发异常（硬件层）
    → el0_sync 异常处理（arch/arm64/kernel/entry.S）
    → invoke_syscall（kernel/syscall.c）
    → sys_openat → do_sys_open（fs/open.c）
```

## 2. 分模块理解

### 模块间的通信机制

内核模块之间**不直接函数调用**（除了同模块内部），而是通过：

1. **注册-回调模式**：驱动向子系统注册 `struct xxx_ops`，子系统在适当时机回调
   ```c
   // drivers/usb/core/driver.c
   // 驱动注册一个 usb_driver，USB 子系统在设备插入时回调 probe()
   ```
2. **VFS 接口**：一切皆文件。`/proc`、`/sys` 都是 VFS 的具体实现
3. **通知链**：`notifier_chain` 机制，模块间事件通知
4. **内核线程 + 等待队列**：异步通信

### 以你的 RK 音视频场景为例

```
APP: open("/dev/video0")
  → fs/ (VFS 层路由)
    → drivers/media/ (V4L2 框架)
      → drivers/media/platform/rockchip/ (RK 摄像头驱动)
        → 哪个 ISP? 哪个 Sensor?
```

### 编译系统的模块化

每个目录都有 `Kconfig`（配置选项）和 `Makefile`（编译规则）：

```
make menuconfig
  → 读取所有 Kconfig，生成 .config
    → Makefile 根据 CONFIG_XXX=y 决定编译哪些文件
      → 最终链接成 vmlinux（或独立的 .ko 模块）
```

## 3. 阅读路径建议

```
第一步：启动流程
  arch/arm64/kernel/head.S  →  start_kernel()  →  init/main.c
  
第二步：进程与调度
  kernel/fork.c  →  kernel/sched/core.c  →  kernel/exit.c

第三步：内存管理
  mm/page_alloc.c  →  mm/slub.c  →  mm/mmap.c  →  mm/vmscan.c

第四步：你的专业方向
  drivers/media/  +  fs/  +  block/  (根据需要)
```

---

# 二、libc++、glibc 的关系与分析

## 首先澄清一个关键事实

**Linux 内核源码里没有 C++。** 内核是纯 C + 汇编 + 少量 Rust（7.x 新增）。你看到的 `linux-7.1.2` 源码树里不存在任何 C++ 代码。

C++20、STL、libc++、glibc 都是**用户空间**的东西：

```
┌──────────────────────────────────┐
│  你的 C++ 应用程序               │
├──────────────────────────────────┤
│  C++ 标准库  │  C 标准库          │
│  libc++ / libstdc++  │  glibc / bionic │
├──────────────────────────────────┤
│  Linux 内核（你正在看的源码）    │
└──────────────────────────────────┘
```

| 库 | 语言 | 用途 | Android 中用吗 |
|----|------|------|----------------|
| **glibc** | C | Linux 桌面/服务器的 C 标准库 | ❌ Android 用 bionic |
| **bionic** | C | Android 的 C 标准库 | ✅ |
| **libstdc++** | C++ | GCC 的 C++ 标准库实现 | ❌ |
| **libc++** | C++ | LLVM 的 C++ 标准库实现 | ✅ Android 用这个 |



## glibc 有没有值得学习的地方

**绝对有。** glibc 是 Linux 生态中最成熟的 C 库实现，虽然 Android 不用它，但它的设计思想值得深入学习：

### 1. 内存分配器——ptmalloc

```
glibc: malloc/malloc.c
```

- 学习 `ptmalloc` 的 arena、chunk、bin 设计
- 理解 fastbin、smallbin、largebin、unsorted bin 的分级策略
- 对比 `jemalloc`、`tcmalloc`、`mimalloc` 的差异
- **与你的工作直接相关**：理解内存分配器有助于排查内存碎片、OOM 问题

### 2. 线程实现——NPTL

```
glibc: nptl/
```

- `pthread_create` 底层如何 `clone()` 系统调用
- TLS（Thread Local Storage）的实现机制
- futex 的用户态封装
- 线程取消、线程局部存储的细节

### 3. 动态链接器——ld.so

```
glibc: elf/
```

- PLT/GOT 的工作原理
- 延迟绑定
- 符号解析顺序
- `dlopen`/`dlsym` 的实现

### 4. IO 层

```
glibc: libio/  (旧) / stdio-common/
```

- `FILE*` 的内部结构（`_IO_FILE`）
- 缓冲区管理
- `printf` 的格式化解析（非常精巧的状态机）

### 5. 与 bionic 的对比

| 维度 | glibc | bionic |
|------|-------|--------|
| 设计目标 | 性能优先，功能完整 | 体积小、启动快、BSD 许可 |
| malloc | ptmalloc（多 arena） | scudo（更注重安全） |
| 线程 | NPTL（重量级） | 基于 futex 的轻量实现 |
| DNS 解析 | 复杂，支持多种后端 | 简化版 |
| locale | 完整实现 | 极简，几乎不用 |

**如果你做 Android 底层开发，建议同时看 bionic 源码**（在 AOSP 的 `bionic/` 目录下），对比 glibc 能获得更深的理解。

---

## 总结

```
Linux 内核源码 (C 语言)
  ├── 分层：arch → kernel/mm → fs/net/block → syscall
  ├── 分模块：每个子系统独立 Kconfig + Makefile
  └── 入口：arch/arm64/kernel/head.S → init/main.c

C++ 生态 (用户空间)
  ├── C++20：concepts, ranges, coroutines, modules, format...
  ├── STL：libc++ (Android) / libstdc++ (桌面)
  └── C 库：glibc (桌面) / bionic (Android)

值得阅读的源码优先级（针对你的方向）：
  1. Linux 内核 drivers/media/ + sound/soc/  ← 直接相关
  2. bionic/  ← Android 底层必读
  3. libc++ include/__memory/  ← C++ 进阶
  4. glibc malloc/ + nptl/  ← 系统级理解
```





<think>
1.  **Analyze the User's Request:**
    *   **Task 1:** Translate the provided English text about Linux kernel layers and modules into Chinese.
    *   **Task 2:** Answer whether `net/` contains the networking stack.
    *   **Task 3:** Provide a prioritized learning path for an audio/video (A/V) engineer transitioning from junior to mid/senior level, specifically regarding: Linux kernel, Android kernel, bionic, libc++, glibc.
    *   **Task 4:** Answer whether the difference between libc and bionic is significant.
    *   **Task 5:** Answer whether reading glibc is a good way to understand system calls.

2.  **Task 1: Translation**
    *   Translate the provided structure accurately into Chinese.
    *   *Layers (from bottom to top)* -> 分层架构（自底向上）
    *   *Hardware Abstraction Layer (arch/)* -> 硬件抽象层 (arch/)
    *   *Core kernel services (kernel/, mm/, sched/)* -> 内核核心服务 (kernel/, mm/, sched/)
    *   *Subsystems (fs/, net/, block/, crypto/)* -> 子系统层 (fs/, net/, block/, crypto/)
    *   *Device drivers (drivers/)* -> 设备驱动层 (drivers/)
    *   *System call interface (the boundary to userspace)* -> 系统调用接口（通往用户空间的边界）
    *   *Modules:* -> 模块划分：
    *   Translate each module description clearly.

3.  **Task 2: Is `net/` the networking stack?**
    *   Yes, it is. Explain briefly what it contains (socket layer, TCP/IP, Netfilter, etc.).

4.  **Task 3: Priorities for an A/V Engineer (Junior to Mid/Senior)**
    *   *Context:* User is doing A/V on (presumably) Android (based on previous RK/Android mentions and the mention of bionic). Wants to know what to study: Linux kernel, Android kernel, bionic, libc++, glibc.
    *   *A/V Specifics:* A/V involves heavy I/O (zero-copy, io_uring), memory management (dma-buf, ion, hugepages), multimedia frameworks (V4L2, ALSA, MediaController), and hardware acceleration (VPU, GPU).
    *   *Priority Ranking:*
        1.  **Linux Kernel (A/V specific subsystems)**: V4L2 (`drivers/media/`), ALSA (`sound/soc/`), DMA-BUF (`drivers/dma-buf/`), Memory Management (`mm/` specifically for I/O and buffers). This is the absolute core for A/V performance.
        2.  **Android Framework & Kernel Features**: Binder, ashmem/memfd, lowmemorykiller (lmkd), SCHED_FIFO/DEADLINE (for real-time A/V).
        3.  **libc++ (or libstdc++)**: For user-space A/V frameworks (like Stagefright/MediaCodec in Android, or FFmpeg C++ wrappers). Understanding threading, atomics, and memory management in C++ is crucial for high-performance A/V apps.
        4.  **Bionic**: Understanding how Android handles threads, memory (scudo), and syscalls. Important for debugging crashes and performance issues in Android A/V.
        5.  **glibc**: Good for conceptual understanding, but lower priority for daily Android A/V work. Better as a reference for "how standard Linux does it" vs "how Android does it".

5.  **Task 4: Is the difference between libc (glibc) and bionic significant?**
    *   Yes, quite significant in design philosophy.
    *   *glibc*: Feature-rich, POSIX compliant, heavy, optimized for server/desktop. Large memory footprint.
    *   *bionic*: Lightweight, fast startup, BSD license (historical reason for Android), smaller size, custom malloc (Scudo for security), simplified TLS and pthread implementation. Not fully POSIX compliant (intentionally drops obscure features).

6.  **Task 5: Can glibc help understand system calls?**
    *   Yes, absolutely. glibc is essentially a massive wrapper around Linux syscalls.
    *   Reading glibc source (e.g., `sysdeps/unix/sysv/linux/`) shows exactly how user-space arguments are marshaled into registers for the kernel.
    *   It's an excellent bridge between C library functions (like `malloc`, `pthread_create`, `open`) and kernel behavior (like `brk`/`mmap`, `clone`, `openat`).
    *   However, note that for Android, Bionic does the same thing, so reading Bionic is equally valid and more directly applicable to Android.

7.  **Drafting the Response (Iterative refinement):**
    *   Keep the tone professional and encouraging.
    *   Use clear formatting (lists, bold text).
    *   Ensure the A/V context is tightly integrated into the priority recommendations. (Mention V4L2, ALSA, DMA-BUF, zero-copy).

8.  **Final Review against User constraints:**
    *   Chinese language? Yes.
    *   Addressed all 5 points? Yes.
    *   Accurate technical details? Yes.

**(Self-Correction during drafting):** Make sure to clarify that "Android kernel" is basically Linux kernel + Android-specific patches (like Binder, ashmem historically, different schedulers). So "Linux Kernel" and "Android Kernel" aren't entirely separate codebases, but the same base with different configs and features. Emphasize *why* an A/V engineer needs to care about these things (e.g., memory copying is the enemy of A/V, so `dma-buf` and `mm/` are critical).
</think>### 1. 英文内容中文翻译

**分层架构（自底向上）：**

*   **硬件抽象层 (`arch/`)**：不同 CPU 架构的特定代码。
*   **内核核心服务 (`kernel/`, `mm/`, `sched/`)**：进程调度、内存管理、IPC 等核心功能。
*   **子系统层 (`fs/`, `net/`, `block/`, `crypto/`)**：文件系统、网络协议栈、块设备 I/O、加密框架等。
*   **设备驱动层 (`drivers/`)**：各种外设的具体驱动程序。
*   **系统调用接口**：内核与用户空间的唯一合法边界。

**模块划分：**

*   `arch/` - 架构相关代码
*   `kernel/` - 内核核心（调度、IPC、信号等）
*   `mm/` - 内存管理
*   `fs/` - 文件系统（VFS 虚拟文件系统 + 具体文件系统）
*   `net/` - 网络协议栈
*   `drivers/` - 设备驱动
*   `block/` - 块 I/O 层
*   `crypto/` - 加密 API
*   `security/` - 安全框架（SELinux, AppArmor 等）
*   `sound/` - 音频子系统（ALSA）
*   `include/` - 内核头文件
*   `lib/` - 内核内部使用的通用工具库
*   `init/` - 内核启动与初始化代码
*   `ipc/` - System V 进程间通信
*   `virt/` - 虚拟化（KVM）
*   `io_uring/` - io_uring 子系统（较新，已被提升为顶级目录）
*   `certs/` - 证书处理
*   `Documentation/` - 官方文档
*   `scripts/` - 编译与构建脚本
*   `tools/` - 用户空间辅助工具
*   `usr/` - initramfs（早期用户空间）生成
*   `rust/` - Rust 语言支持（新增）

---

### 2. `net/` 下是网络协议栈吗？

**是的，完全是。** `net/` 目录包含了 Linux 网络协议栈的完整实现。
*   `net/core/` 是网络栈的核心（Socket 缓冲区、收发包总控）。
*   `net/ipv4/` 和 `net/ipv6/` 是 TCP/IP 协议层。
*   `net/sched/` 是流量控制（QoS）。
*   协议栈底层对接 `drivers/net/` 下的网卡驱动，顶层对接用户空间的 `socket()` 系统调用。

---

### 3. 音视频开发（初转中高）的学习优先级

作为音视频开发，你的核心痛点是：**高吞吐、低延迟、零拷贝、硬解码、同步机制**。基于此，我为你排定以下学习优先级（1最紧急，5最后）：

#### 优先级 1：Linux 内核中的“音视频相关子系统”
不要一上来就去啃 `mm/` 或 `sched/`，而是**从直接相关的子系统切入**：
*   **V4L2 框架 (`drivers/media/`)**：这是摄像头和视频采集的基石。必须懂 `open/ioctl/mmap` 在 V4L2 里的流转。
*   **ALSA 框架 (`sound/soc/`)**：音频驱动的核心，尤其是 ASoC（嵌入式音频）的 Machine/Platform/Codec 划分。
*   **内存与零拷贝 (`mm/`, `drivers/dma-buf/`)**：音视频最怕拷贝。重点看 `dma-buf` 框架（如何把硬件解码器的输出直接喂给显示器）、`mmap` 的底层实现、以及 `ion` / `dma-heap`（连续内存分配器）。
*   **异步 I/O (`io_uring/`)**：这是未来高并发音视频服务的杀手级特性，比 `epoll` 性能更高，必学。

#### 优先级 2：Android 内核特性与 Bionic
既然你做安卓，必须懂 Android 在 Linux 基础上做了什么魔改：
*   **Android 专用驱动**：Binder（进程通信）、ashmem/memfd（匿名共享内存，音视频数据传输核心）、lowmemorykiller（内存回收机制）。
*   **Bionic**：见第 4 点详解。

#### 优先级 3：C++ 标准库
音视频框架（如 FFmpeg C 接口封装、Android Stagefright/NdkMediaCodec）大量使用 C++。
*   重点学习：C++11/20 的并发（`std::thread`, `std::atomic`）、智能指针（内存防泄漏）、`std::span`（C++20，用于替代裸指针传递 Buffer）。

#### 优先级 4：glibc（作为理解系统调用的参考）
见第 5 点详解。

#### 优先级 5：Linux 内核核心机制
等你的业务代码遇到瓶颈了（比如线程调度抖动导致音画不同步、内存碎片导致分配大块 Buffer 失败），再回头深入：
*   `kernel/sched/`（CFS 调度器，实时优先级）
*   `mm/page_alloc.c`（伙伴系统，大页内存）

---

### 4. libc 和 bionic 差别会很大吗？

**差别很大，设计哲学完全不同。**

| 维度 | glibc (标准 Linux) | bionic (Android) |
| :--- | :--- | :--- |
| **设计目标** | 功能全面、性能极致、支持各种老旧标准 | 体积小、启动快、适合移动设备、BSD开源协议 |
| **代码体积** | 庞大（几 MB） | 极小（几百 KB） |
| **内存分配** | ptmalloc（多 arena，吞吐量大，但容易产生内存碎片） | Scudo（极度注重安全，防堆溢出，体积小） |
| **线程** | NPTL (重量级，功能全) | 基于 futex 的轻量级实现，为了省内存砍了很多边缘特性 |
| **POSIX 兼容性** | 几乎 100% 兼容 | 部分兼容，很多不常用的 POSIX 接口被直接删掉 |
| **DNS解析** | 复杂，支持各种配置文件 | 简化版，适配移动网络切换 |

**对你的影响**：如果你在 Android 上做音视频，分配大块内存的行为和普通 Linux 完全不一样。Bionic 的分配器对大块内存的处理策略不同，排查 OOM 或内存踩踏问题时，不能用 glibc 的经验生搬硬套。

---

### 5. 是不是可以通过 glibc 更好理解系统调用？

**非常正确，这是一个极佳的切入点。**

系统调用是用户空间进入内核的门槛。你写 C/C++ 代码调用的 `open()`, `read()`, `malloc()`, `pthread_create()`，其实都不是系统调用本身，而是 **glibc/Bionic 提供的包装函数**。

通过看 glibc 源码，你能清楚地看到：
1.  **参数如何传递**：glibc 会把你的参数放入特定的 CPU 寄存器。
2.  **如何触发陷入**：glibc 会调用 `svc #0` (ARM) 或 `syscall` 指令，从用户态切到内核态。
3.  **返回值如何处理**：glibc 会检查内核返回的错误码，并设置 `errno`。

**举个音视频相关的例子：`mmap`**
你可以去 glibc 源码里找 `sysdeps/unix/sysv/linux/mmap.c`：
```c
// glibc 的 mmap 包装大概长这样
void * __mmap (void *addr, size_t len, int prot, int flags, int fd, off_t offset) {
    // 一些参数校验和偏移量对齐处理...
    // 调用内部的 syscall 宏，触发 svc 指令陷入内核
    return (void *) INLINE_SYSCALL (mmap, 6, addr, len, prot, flags, fd, offset);
}
```
看完这层，你再跳到 Linux 内核源码的 `mm/mmap.c` 里的 `sys_mmap` 函数，就能完美闭环：**从你写的代码 -> glibc 包装 -> 硬件陷入 -> 内核实际分配内存**。

**建议**：虽然看 glibc 能很好地理解系统调用，但如果你在 Android 平台，**看 Bionic 源码会更对口**。Bionic 的代码比 glibc 简洁得多，非常适合阅读。路径在 AOSP 的 `bionic/libc/` 目录下。







