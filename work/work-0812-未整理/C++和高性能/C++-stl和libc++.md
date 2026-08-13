
# C++20、STL、libc++、glibc 的关系与分析

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

## C++20 新特性体现在哪里

### 编译器层面

| 特性 | 说明 | 示例 |
|------|------|------|
| **Concepts** | 编译期模板约束，替代 SFINAE | `template<std::integral T>` |
| **Modules** | 替代 `#include`，解决编译速度 | `import std;` |
| **Coroutines** | 协程，无栈协作式 | `co_await`, `co_yield`, `co_return` |
| **Ranges** | 函数式管道操作容器 | `v \| views::filter(...) \| views::transform(...)` |
| **`<=>` 飞船运算符** | 三路比较，自动生成 `<`, `<=`, `==` 等 | `auto operator<=>(const T&) = default;` |
| **`std::format`** | 类型安全的格式化，替代 `printf`/`sprintf` | `std::format("x={}", 42)` |
| **`std::span`** | 非拥有视图，替代裸指针+长度 | `void f(std::span<int> v)` |
| **`std::jthread`** | 自动 join 的线程 + 协作式取消 | `std::jthread t([](std::stop_token st){...})` |
| **`consteval`** | 强制编译期求值 | `consteval int sq(int x){return x*x;}` |
| **`constinit`** | 确保编译期初始化，阻止动态初始化 | `constinit int x = 42;` |
| **指派初始化** | C99 风格的结构体初始化 | `Point{.x=1, .y=2}` |
| **模板 lambda** | lambda 模板参数 | `[]<typename T>(T x){}` |
| **`requires` 子句** | 约束模板 | `template<typename T> requires std::integral<T>` |

### STL 的改动（C++20 新增头文件）

```
<concepts>        — 概念定义库
<ranges>          — 范式适配器与视图
<format>          — std::format
<coroutine>       — 协程支持
<numbers>         — 数学常量 (std::numbers::pi)
<source_location> — 编译期源码位置信息
<syncstream>      — 同步输出流
<bit>             — 位操作
<version>         — 实现版本信息
```

已有组件的大量增强：
- `constexpr` 大幅扩展——`std::string`、`std::vector` 现在可以在编译期使用
- `<algorithm>` 大量算法支持 constexpr
- 容器新增 `contains()` 方法
- `std::map` 支持 heterogenous lookup

## libc++ 源码能不能看

**完全可以，而且强烈推荐。**

```
LLVM 项目:  https://github.com/llvm/llvm-project/tree/main/libcxx
```

libc++ 是 LLVM/Apple 维护的 C++ 标准库实现，Android 官方使用它。源码质量很高，值得学习的点：

| 看什么 | 在哪里 | 学什么 |
|--------|--------|--------|
| `std::vector` 实现 | `include/vector` | SFINAE、placement new、异常安全 |
| `std::shared_ptr` | `include/__memory/shared_ptr.h` | 原子引用计数、控制块设计 |
| `std::function` | `include/__functional/function.h` | 类型擦除、小对象优化 |
| `std::tuple` | `include/tuple` | 可变参数模板的极致运用 |
| `std::ranges` | `include/__ranges/` | C++20 概念和范围的工业级实现 |
| `std::format` | `include/__format/` | 编译期格式字符串解析 |

**阅读建议：** 从 `include/__utility/move.h`、`include/__memory/unique_ptr.h` 这种小文件开始，逐步过渡到 `vector`、`string`。

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

