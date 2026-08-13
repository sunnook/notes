# GStreamer 1.29 设计分析

> 本文档对 GStreamer 1.29.2 核心库进行深度架构分析，覆盖入口点、整体架构、
> 核心类体系、数据流、控制流等维度。面向有 C/C++ 基础的开发者。

---

## 1. 项目概述与构建系统

### 1.1 GStreamer 整体定位

GStreamer 是一个**开源多媒体框架**，核心理念是：
将音视频处理拆解为一系列**处理单元（Element）**，
通过**接口（Pad）**将单元**连接（Link）**起来，
形成一条**处理流水线（Pipeline）**。

数据以 **Buffer** 的形式在 Pipeline 中流动，
每个 Element 对 Buffer 中的数据进行解码、编码、滤镜、复用、解复用等操作。

```
[文件源] ─→ [解复用] ─→ [H.264 解码] ─→ [渲染]
                  │
              [AAC 解码] ─→ [音频输出]
```

这种**管道模型（Pipeline Model）**是 GStreamer 最核心的抽象。

### 1.2 目录结构一览

```
gstreamer-1.29.2/
├── gst/                      # 核心库源代码（gst/libgstreamer-1.0.so）
│   ├── gst.c                 #   gst_init / gst_deinit — 入口
│   ├── gst.h                 #   主头文件（包含所有公开 API）
│   ├── gstelement.[ch]       #   GstElement — 基本处理单元
│   ├── gstbin.[ch]           #   GstBin — 可容纳其他 Element 的容器
│   ├── gstpipeline.[ch]      #   GstPipeline — 顶层容器
│   ├── gstpad.[ch]           #   GstPad — 元素间的连接接口
│   ├── gstbuffer.[ch]        #   GstBuffer — 数据载体
│   ├── gstbus.[ch]           #   GstBus — 事件/消息通信通道
│   ├── gstcaps.[ch]          #   GstCaps — 数据格式描述
│   ├── gstevent.[ch]         #   GstEvent — 控制事件（seek, flush...）
│   ├── gstquery.[ch]         #   GstQuery — 查询请求（duration, position...）
│   ├── gstmessage.[ch]       #   GstMessage — 异步通知
│   ├── gstminiobject.[ch]    #   轻量引用计数基类
│   ├── gstobject.[ch]        #   命名引用计数基类
│   ├── gstpadtemplate.[ch]   #   Pad 模板
│   ├── gstelementfactory.[ch]#   Element 工厂
│   ├── gstplugin.[ch]        #   插件管理
│   ├── gstregistry.[ch]      #   插件注册表
│   ├── gstparse.[ch]         #   Pipeline 描述字符串解析器
│   ├── gstclock.[ch]         #   时钟抽象
│   ├── gsttask.[ch]          #   后台任务线程
│   ├── gstbufferpool.[ch]    #   Buffer 池管理
│   ├── gstmemory.[ch]        #   内存元数据
│   ├── gststructure.[ch]     #   键值对结构体
│   ├── gstvalue.[ch]         #   通用值类型（GValue）
│   └── parse/                #   .y / .l 词法语法分析
│
├── libs/                     # 扩展库
│   └── gst/
│       ├── base/             #   GstBaseSink, GstBaseSrc 等基类
│       ├── check/            #   测试基础设施
│       ├── controller/       #   属性动态控制（GstController）
│       ├── helpers/          #   工具函数库
│       └── net/              #   网络相关元素
│
├── plugins/                  # 核心插件
│   ├── elements/             #   基础元素：fakesrc, queue, tee, concat...
│   └── tracers/              #   性能追踪器
│
├── tools/                    # 命令行工具
│   ├── gst-launch.c          #   管道启动器（示例应用）
│   ├── gst-inspect.c         #   插件检查工具
│   ├── gst-stats.c           #   性能统计工具
│   └── gst-typefind.c        #   类型探测工具
│
├── tests/                    # 测试套件
│   ├── check/                #   单元测试
│   ├── examples/             #   示例代码
│   └── validate/             #   验证测试
│
├── docs/                     # 文档
├── meson.build               # 构建配置
└── README.md
```

### 1.3 构建系统：Meson

GStreamer 1.x 系列使用 **Meson** 作为构建系统（替代了旧的 autotools）。

核心构建文件 `meson.build` 定义了：
- **gst/** 目录编译为 `gstreamer-1.0` 共享库
- **libs/gst/base/** 等编译为独立库（`libgstbase-1.0.so`）
- **plugins/** 下的每个子目录编译为独立插件（`.so` 文件）

```
应用
 └── libgstreamer-1.0.so (gst/)
     ├── 核心运行时（元素管理、状态机、数据流）
     └── 动态加载插件
         ├── libgstcoreelements.so (plugins/elements/)
         └── ... (第三方插件)
```

> **注意**：本代码库仅包含 `gstreamer`（核心库），完整的 GStreamer 生态还包含
> `gst-plugins-base`、`gst-plugins-good/bad/ugly` 等插件仓库。
> 本分析聚焦于核心库的架构设计。

---

## 2. 入口点分析

### 2.1 `gst_init()` / `gst_deinit()` — 库入口

**文件**：`gst/gst.c`

这是开发者接触的第一个 API。调用流程如下：

```
gst_init(argc, argv)
 └── gst_init_check(argc, argv, &error)
      ├── ① 获取 GStreamer 专属的 GOptionGroup
      │      (gst_init_get_option_group())
      │      → 注册 --gst-debug, --gst-plugin-path 等参数
      │
      ├── ② g_option_context_parse() — 解析命令行
      │      在解析前后触发回调：
      │      ├── init_pre()  — 预解析（GOptionGroup 的 parse hook）
      │      │     ├── 初始化时钟子系统 (priv_gst_clock_init())
      │      │     ├── 获取可执行文件路径
      │      │     ├── 初始化调试系统 (_priv_gst_debug_init())
      │      │     └── 设置插件路径 (_priv_gst_plugin_paths)
      │      │
      │      └── init_post() — 后解析
      │            ├── 加载预定义插件
      │            ├── 更新插件注册表 (gst_update_registry())
      │            │     └── 扫描所有插件目录，重建 registry
      │            └── 注册核心元素 (fakesrc, fakesink, filesrc, filesink...)
      │
      └── 设置 gst_initialized = TRUE
```

**关键机制**：
- `init_lock` 是 `GRecMutex`（递归互斥锁），保证线程安全的初始化
- 注册表（Registry）机制：GStreamer 启动时扫描所有 `.so` 插件，
  将其中的 Element Factory 信息序列化存储到二进制注册表中，
  后续 `gst_element_factory_make()` 直接从注册表查找，无需重复扫描

```c
// 最简用法
int main(int argc, char *argv[]) {
  gst_init(&argc, &argv);   // 解析 GStreamer 参数 + 初始化
  // ... 构建 pipeline ...
  gst_deinit();              // 清理（主要用于 leak 检测）
  return 0;
}
```

### 2.2 `gst-launch.c` — 典型应用入口

**文件**：`tools/gst-launch.c`

这是 GStreamer 的命令行管道启动器，也是**最佳的学习入口**。
它展示了应用层使用 GStreamer 的完整生命周期：

```
main()
 │
 ├── ① 设置 locale 和程序名
 │
 ├── ② 解析应用参数 + GStreamer 参数
 │      g_option_context_add_group(gst_init_get_option_group())
 │
 ├── ③ 解析 pipeline 描述字符串
 │      gst_parse_launchv(argv, &error)   ← 核心！
 │         └── 将 "filesrc location=video.mp4 ! qtdemux ! h264parse ! avdec_h264 ! autovideosink"
 │             解析为 Element 对象图
 │
 ├── ④ 创建 GMainLoop（GLib 事件循环）
 │      loop = g_main_loop_new(NULL, FALSE)
 │
 ├── ⑤ 获取 Pipeline 的 Bus
 │      bus = gst_element_get_bus(pipeline)
 │      gst_bus_add_watch(bus, bus_handler, NULL)  ← 消息处理回调
 │      gst_bus_set_sync_handler(bus, bus_sync_handler, ...)  ← 同步消息回调
 │
 ├── ⑥ 设置 Pipeline 到 PAUSED 状态（ preroll）
 │      gst_element_set_state(pipeline, GST_STATE_PAUSED)
 │         └── 各 Element 逐级从 NULL → READY → PAUSED
 │
 ├── ⑦ 安装信号处理器 (SIGINT/SIGHUP)
 │
 ├── ⑧ 运行事件循环
 │      g_main_loop_run(loop)    ← 阻塞直到 EOS 或错误
 │         │
 │         └── bus_handler() 回调被 GMainLoop 触发
 │               处理 GST_MESSAGE_EOS → g_main_loop_quit()
 │               处理 GST_MESSAGE_ERROR → 打印错误 + quit
 │               处理 GST_MESSAGE_BUFFERING → 自动暂停/恢复
 │
 ├── ⑨ 设置 Pipeline 到 NULL
 │      gst_element_set_state(pipeline, GST_STATE_NULL)
 │
 └── ⑩ 释放资源
       gst_object_unref(pipeline)
       gst_deinit()
```

**Bus 消息处理**是应用层的核心交互方式：

| 消息类型 | 含义 | 典型处理 |
|---------|------|---------|
| `GST_MESSAGE_EOS` | 流结束 | 退出事件循环 |
| `GST_MESSAGE_ERROR` | 发生错误 | 打印错误信息 |
| `GST_MESSAGE_STATE_CHANGED` | 状态变更 | 打印状态/自动进入 PLAYING |
| `GST_MESSAGE_BUFFERING` | 缓冲进度 | 缓冲不足时暂停，100% 时恢复 |
| `GST_MESSAGE_TAG` | 元数据 | 打印音画信息 |
| `GST_MESSAGE_LATENCY` | 需要重新分配延迟 | 通知 Bin 重新计算 |

### 2.3 `gst-inspect.c` — 插件检查工具

**文件**：`tools/gst-inspect.c`

用于枚举所有已注册的 Element Factory 及其属性：
1. `gst_init()` 初始化
2. 从注册表加载所有 ElementFactory
3. 遍历打印每个 Element 的名称、类、描述、Pad 模板、属性等

### 2.4 Plugin 注册入口

每个插件（`.so`）包含一个标准入口函数：

```c
// 插件注册约定：gst_plugin_register_<plugin_name>
// 例如 plugins/elements/gstcoreelementsplugin.c 中的注册
gst_plugin_register (plugin, "fakesrc", GST_RANK_NONE,
                     GST_TYPE_FAKE_SRC, ...);
```

注册时，ElementFactory 被存入全局注册表，后续通过名称查找。

---

## 3. 整体架构设计

### 3.1 分层架构

GStreamer 从架构上可分为四层：

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 4: Application（应用层）                               │
│  gst-launch, 自定义 C 应用, Python(gi.repository.Gst)         │
│  职责：构建 Pipeline, 监听 Bus 消息, 响应控制命令              │
└─────────────────────────────────────────────────────────────┘
                            │
              gst_element_set_state()
              gst_element_send_event()
              gst_pad_push()
                            │
┌─────────────────────────────────────────────────────────────┐
│  Layer 3: Pipeline Management（管道管理层）                    │
│  GstPipeline → GstBin → GstElement                           │
│  职责：状态机传播, 时钟分发, 延迟计算, Pad 拓扑管理             │
│  实现：gstbin.c, gstpipeline.c                                │
└─────────────────────────────────────────────────────────────┘
                            │
              gst_pad_push() / gst_pad_pull_range()
              gst_event_new_seek() / gst_query_new_duration()
                            │
┌─────────────────────────────────────────────────────────────┐
│  Layer 2: Element Processing（元素处理层）                     │
│  各种 Element（解码器、编码器、滤镜、源、宿）                   │
│  职责：对 Buffer 中的数据进行实际处理                          │
│  实现：插件中的具体 Element 类（外部仓库提供）                  │
│       核心插件：fakesrc, queue, tee, concat, identity...      │
└─────────────────────────────────────────────────────────────┘
                            │
              Buffer, Caps, Memory
                            │
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: Data Transport（数据传输层）                         │
│  GstPad (chain/push/pull) → GstBuffer → GstMemory             │
│  职责：在 Pad 之间传递数据，管理 Buffer 内存与引用计数          │
│  实现：gstpad.c, gstbuffer.c, gstmemory.c                     │
└─────────────────────────────────────────────────────────────┘
```

**关键设计原则**：
1. **Push 模式优先**：上游元素主动 push 数据到下游，下游决定是否接受
2. **分层职责清晰**：Pipeline 管状态，Element 管处理，Pad 管传输
3. **异步消息驱动**：Bus 消息与事件循环解耦，不阻塞数据流

### 3.2 插件化架构

GStreamer 的核心库只提供**基础设施**和**基础元素**，
绝大多数编解码器元素以**插件**形式存在：

```
                     ┌──────────────────────┐
                     │   Plugin Loader       │
                     │   (gstpluginloader.c)  │
                     └──────────┬───────────┘
                                │ dlopen()/dlsym()
              ┌─────────────────┼─────────────────┐
              │                 │                 │
     ┌────────▼──────┐ ┌───────▼──────┐ ┌────────▼──────┐
     │ libgstcore    │ │ libgstvideo  │ │ libgstaudio   │
     │ elements.so   │ │ .so          │ │ .so           │
     │               │ │              │ │               │
     │ fakesrc       │ │ videoconvert │ │ audioconvert  │
     │ fakesink      │ │ videoscale   │ │ audioresample │
     │ filesrc       │ │              │ │               │
     │ filesink      │ │              │ │               │
     │ queue         │ │              │ │               │
     │ tee           │ │              │ │               │
     └───────────────┘ └──────────────┘ └───────────────┘
```

**插件加载流程**：
1. `gst_init()` 扫描插件路径
2. `dlopen()` 每个 `.so`，调用 `gst_plugin_load()`
3. 插件内部调用 `gst_element_register()` 注册 ElementFactory
4. ElementFactory 存入注册表
5. 用户通过 `gst_element_factory_make("name", NULL)` 创建实例

### 3.3 GObject 面向对象体系（C 语言的 OOP）

GStreamer 完全用 C 编写，但通过 **GLib/GObject** 实现了完整的面向对象体系：

```
GType 类型系统（运行时 RTTI）
   │
   ├── 类层次（Class Hierarchy）
   │     GObject → GstMiniObject（数据基类）
   │            → GstObject（命名对象基类）
   │                  ├── GstElement（处理单元）
   │                  │        ├── GstBin（容器元素）
   │                  │        │        └── GstPipeline（顶层容器）
   │                  │        └── 用户自定义 Element
   │                  │
   │                  ├── GstPad（接口）
   │                  └── GstBus（消息通道）
   │
   ├── 信号机制（Signal）
   │     "pad-added", "pad-removed", "no-more-pads"
   │
   └── 属性系统（Property）
         GObject 的 get/set 机制，支持通知监听
```

GStreamer 在此基础上构建了自己的语义层：
- **GstMiniObject**：轻量引用计数对象（Buffer 等数据用）
- **GstObject**：GObject + 名称 + parentage（带名字的引用计数对象）
- **GstElement**：GObject 子类 + 状态机 + Pad 管理 + Bus
- **GstPad**：GstObject 子类 + 数据流函数指针（chain/push/getrange）

---

## 4. 核心类体系与类图

### 4.1 GObject 类型系统速览（C++ 背景读者参考）

GStreamer 基于 GLib/GObject 实现 OOP，这是理解源码的关键。
下面将 GObject 概念与 C++ 做类比：

| C++ 概念 | GObject 对应 | 说明 |
|---------|-------------|------|
| `class Foo` | `gchar const foo_get_type(void)` | 类型定义 |
| `class Foo { virtual void bar(); }` | `struct _FooClass { ... void (*bar)(Foo*); }` | 虚函数 = 函数指针 |
| `Foo* p = new Foo()` | `g_object_new(FOO_TYPE, ...)` | 构造 |
| `delete p` | `g_object_unref(p)` | 引用计数析构 |
| `dynamic_cast<Foo*>(obj)` | `G_TYPE_CHECK_INSTANCE_TYPE(obj, FOO_TYPE)` | 运行时类型检查 |
| `static_cast<Base*>(p)` | `G_TYPE_CHECK_INSTANCE_CAST(obj, BASE_TYPE, Base)` | 安全强转 |
| `obj->signal.connect(callback)` | `g_signal_connect(obj, "signal", ...)` | 信号连接 |
| `obj->property = val` | `g_object_set(obj, "property", val, NULL)` | 属性设置 |

**核心模式**：

```c
// 1. 类型宏定义（类似 C++ 的 class 声明）
#define MY_TYPE_FOO (my_foo_get_type())
#define MY_IS_FOO(obj) (G_TYPE_CHECK_INSTANCE_TYPE((obj), MY_TYPE_FOO))
#define MY_FOO(obj) (G_TYPE_CHECK_INSTANCE_CAST((obj), MY_TYPE_FOO, MyFoo))

// 2. 实例结构体 = 基类实例 + 私有成员（类似 C++ 的成员变量）
struct _MyFoo {
  GObject parent_instance;    // 必须放在第一个！
  gchar *name;                // 自己的成员
};

// 3. 类结构体 = 基类类 + 虚函数（类似 C++ 的 virtual 函数表）
struct _MyFooClass {
  GObjectClass parent_class;
  void (*named_changed) (MyFoo *foo, gchar *new_name);  // 信号
  gboolean (*process) (MyFoo *foo, const gchar *data);   // 虚函数
};
```

**为什么用宏而非指针**？GObject 的宏（`G_TYPE_CHECK_*`）在 debug 模式下做类型校验，
在 release 模式下编译为直接内存访问，零开销。

### 4.2 对象继承体系

GStreamer 定义了**两条并行的继承链**：

```
                              GObject (GLib)
                                 │
                   ┌─────────────┼─────────────┐
                   │             │             │
           ┌───────▼──────┐ ┌───▼────┐  ┌─────▼──────┐
           │   GTypeClass  │ │ GValue │  │ GBoxed     │
           │ (元数据类)    │ │ (值类型)│  │ (拷贝封装) │
           └──────────────┘ └────────┘  └────────────┘
                   │
         ┌─────────┴─────────┐
         │                     │
  ┌──────▼───────┐    ┌───────▼──────────┐
  │ GstMiniObject│    │   GstObject       │◄─── 这个分支被 gst 使用
  │ (数据对象)    │    │ (命名对象)        │
  │ refcount     │    │ name + parent    │
  │ 可拷贝/dispose│   │ refcount         │
  └──────┬───────┘    └───────┬──────────┘
         │                    │
    ┌────┴────┐     ┌────────┴────────┐
    │         │     │                 │
┌───▼───┐ ┌──▼──────────┐   ┌────────▼────────┐
│Buffer│ │Caps         │   │   GstElement     │◄── 核心抽象
│Event │ │Query        │   │ state: NULL/    │
│Message│ │Structure   │   │   READY/PAUSED/ │
│Meta  │ │TagList     │   │   PLAYING       │
└──────┘ └────────────┘   │ pads: list      │
                          │ bus, clock      │
                          └────────┬────────┘
                                   │
                          ┌────────▼────────┐
                          │    GstBin       │◄── 容器元素
                          │  child_elements │
                          │  latency calc   │
                          └────────┬────────┘
                                   │
                          ┌────────▼────────┐
                          │  GstPipeline    │◄── 顶层容器
                          │  auto clock     │
                          │  bus (own)      │
                          └─────────────────┘
```

**两条链路的区分**：
- **GstMiniObject 链**：管理**数据对象**（Buffer、Caps、Event 等），侧重轻量、可拷贝、COW
- **GstObject 链**：管理**控制对象**（Element、Pad、Bus 等），侧重命名、parentage、信号

### 4.3 类图（UML 表示）

以下是核心类的详细 UML 类图。`+` 表示 public，`-` 表示 private，`--->` 表示关联关系。

```
┌─────────────────────────────────────────────────────────────────┐
│                        GObject (GLib)                            │
├─────────────────────────────────────────────────────────────────┤
│ - GType g_type                                                    │
│ - GInitiallyUnowned...*                                           │
├─────────────────────────────────────────────────────────────────┤
│ + g_object_new(type, ...)                                         │
│ + g_object_get(obj, "prop", &val, NULL)                           │
│ + g_object_set(obj, "prop", val, NULL)                            │
│ + g_signal_connect(obj, "signal", callback, user_data)           │
└────────────────────────┬────────────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ GstMiniObject│ │  GstObject    │ │   GValue      │
│--------------│ │--------------│ │--------------│
│ GType type   │ │ GObject      │ │ GType f_type  │
│ gint refcount│ │ gchar* name  │ │ union value  │
│ gint lockstate││ gpointer     │ │              │
│ guint flags  │ │ parent       │ │              │
│ copy func    │ │ refcount     │ │              │
│ dispose func │ │ flags        │ │              │
│ free func    │ │              │ │              │
└──────────────┘ └──────────────┘ └──────────────┘
     │               │
     │  (数据对象)    │  (控制对象)
     │               │
     ├───→ GstBuffer ──→ GstMemory
     ├───→ GstCaps
     ├───→ GstEvent
     ├───→ GstQuery
     ├───→ GstMessage
     ├───→ GstStructure
     └───→ GstTagList
               │
               └──→ GstSample (Buffer + Caps)

     │
     └───→ GstPad (独立分支，见下方)

┌─────────────────────────────────────────────────────────────────┐
│                        GstElement                                │
├─────────────────────────────────────────────────────────────────┤
│ + GstObject object                                                │
│ + GRecMutex state_lock                                            │
│ + GCond state_cond                                                │
│ + GstState target_state           ---> NULL/READY/PAUSED/PLAYING │
│ + GstState current_state                                          │
│ + GstState next_state                                             │
│ + GstState pending_state                                          │
│ + GstStateChangeReturn last_return                                │
│ + GstBus *bus          ---> 消息通道                              │
│ + GstClock *clock        ---> 时钟                                │
│ + gint64 base_time           ---> 时间基准                        │
│ + GstClockTime start_time    ---> PAUSED 时的 running_time        │
│ + GList *pads              ---> [GstPad] 双向链表                 │
│ + guint32 pads_cookie      ---> pad 列表变更计数器                │
├─────────────────────────────────────────────────────────────────┤
│ + gst_element_set_state(elem, state)                              │
│ + gst_element_get_state(elem, &state, ...)                        │
│ + gst_element_add_pad(elem, pad)                                  │
│ + gst_element_remove_pad(elem, pad)                               │
│ + gst_element_get_static_pad(elem, name)                          │
│ + gst_element_request_pad_simple(elem, templ)                     │
│ + gst_element_send_event(elem, event)                             │
│ + gst_element_query(elem, query)                                  │
│ + gst_element_post_message(elem, message)                         │
│ + gst_element_provide_clock(elem)                                 │
└─────────────────────────────────────────────────────────────────┘
           │ 虚函数 (在 ElementClass 中)
           │
    ┌──────┴──────┐
    │ change_state │  ◄── 元素实现的核心钩子
    │ get_state    │
    │ set_state    │
    │ provide_clock│
    │ send_event   │
    │ query        │
    └─────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                        GstPad                                    │
├─────────────────────────────────────────────────────────────────┤
│ + GstObject object                                                │
│ + gpointer element_private   ---> 元素自定义数据                   │
│ + GstPadTemplate *padtemplate   ---> Pad 模板                     │
│ + GstPadDirection direction  ---> SRC 或 SINK                    │
├─────────────────────────────────────────────────────────────────┤
│ /* 私有 */                                                       │
│ + GRecMutex stream_rec_lock  ---> 数据流锁                       │
│ + GstTask *task              ---> 后台任务                       │
│ + GCond block_cond           ---> 阻塞等待条件变量                 │
│ + GHookList probes           ---> Pad Probe 回调列表             │
│ + GstPadMode mode            ---> NONE / PUSH / PULL             │
│                                                                 │
│ /* 数据流函数指针（虚函数）*/                                     │
│ + GstPad *peer               ---> 对端 Pad (链接时设置)            │
│ + GstPadChainFunction chainfunc      ---> 接收 buffer             │
│ + GstPadChainListFunction chainlistfunc → 接收 buffer list       │
│ + GstPadGetRangeFunction getrangefunc → 拉取 buffer              │
│ + GstPadEventFunction eventfunc      → 处理事件                   │
│ + GstPadQueryFunction queryfunc      → 处理查询                   │
│ + GstPadLinkFunction linkfunc        → 链接回调                   │
├─────────────────────────────────────────────────────────────────┤
│ + gst_pad_link(srcpad, sinkpad)                                   │
│ + gst_pad_unlink(srcpad, sinkpad)                                 │
│ + gst_pad_push(srcpad, buffer)   ◄── 主流                        │
│ + gst_pad_push_list(srcpad, list)                                 │
│ + gst_pad_pull_range(sinkpad, offset, size, &buffer)             │
│ + gst_pad_push_event(srcpad, event)                               │
│ + gst_pad_chain(sinkpad, buffer)   ◄── 元素内部调用              │
│ + gst_pad_add_probe(pad, mask, callback, ...)                    │
│ + gst_pad_activate_mode(pad, mode, TRUE)  ◄── READY→PAUSED 时调用 │
└─────────────────────────────────────────────────────────────────┘
```

**类间关系总结**：

```
GstElement "has-a" → GList<GstPad>       (每个元素有 0..N 个 Pad)
GstPad "has-a"   → GstPad *peer         (链接后指向对端 Pad)
GstElement "has-a" → GstBus *bus         (通过 Bus 收发消息)
GstElement "has-a" → GstClock *clock     (由 Pipeline 分配)
GstBin "has-a"   → GList<GstElement>     (容器包含子元素)
GstElement "is-owned-by" → ElementFactory (每个实例关联一个工厂)
```

### 4.4 数据对象体系

除了控制对象链，GStreamer 还有庞大的**数据对象体系**：

```
GstMiniObject (最底层引用计数基类)
    │
    ├── GstBuffer         数据缓冲区
    │   ├── 实际数据由 GstMemory 承载
    │   ├── 元数据列表 (GstMeta)
    │   └── 时间戳、偏移、标志
    │
    ├── GstCaps           格式能力描述
    │   ├── 包含多个 GstStructure
    │   └── 如: video/x-raw,format=RGBA,width=1920,height=1080
    │
    ├── GstEvent          控制事件
    │   ├── NEWSEGMENT    播放速率/时间范围
    │   ├── EOS           流结束
    │   ├── FLUSH_START/STOP  刷新
    │   ├── SEEK          跳转
    │   ├── CAPS          格式协商结果
    │   └── CUSTOM        自定义事件
    │
    ├── GstQuery          查询请求
    │   ├── DURATION      获取总时长
    │   ├── POSITION        获取当前位置
    │   ├── SEEKING         查询是否支持 seek
    │   ├── FORMAT          查询支持的格式
    │   ├── ALLOCATION      查询内存分配策略
    │   └── ...
    │
    ├── GstMessage         异步通知
    │   ├── ERROR           错误
    │   ├── WARNING         警告
    │   ├── INFO            信息
    │   ├── STATE_CHANGED   状态变化
    │   ├── EOS             流结束 (由 Element 发)
    │   ├── TAG             元数据
    │   ├── BUFFERING       缓冲进度
    │   ├── LATENCY         延迟重分配
    │   └── ...
    │
    ├── GstStructure       键值对容器
    │   └── name + field[] (每个 field: name + GValue)
    │
    ├── GstTagList         标签列表 (GMessage 的子集)
    ├── GstBufferList       Buffer 集合
    ├── GstMeta            Buffer 元数据
    └── GstSample          Buffer + Caps 组合 (携带格式信息)
```

**Buffer 内存模型**：

```
GstBuffer
  ├── data: guint8*          → 实际内存起始指针
  ├── size: guint64           → 数据大小
  └── memory: GstMemory*      → 底层内存管理
       │
       ├── GstMemory (实际内存持有者)
       │   ├── data: gpointer      → 内存起始
       │   ├── size: gsize         → 内存大小
       │   ├── allocator: GstAllocator*  → 分配器
       │   └── meta: GstMeta*      → 附加元数据 (Dermatogram/HDR/DRM...)
       │
       └── 支持共享内存：
           - 同一块内存可被多个 Buffer 共享 (COW 写时复制)
           - gst_mini_object_make_writable() → 不共享时自动 copy
```


## 5. 数据流分析

### 5.1 Push 模式数据流（主流）

GStreamer 默认采用 **Push 模式**：上游元素主动将 Buffer 推向下游。

```
[ Element A ] ──push()──▶ [ Element B ] ──push()──▶ [ Element C ]
    srcpad  ────────  sinkpad      srcpad  ────────  sinkpad

数据流路径：
① Element A 的 chain 函数中：
   gst_pad_push(srcpad_A, buffer)

② gst_pad_push() 内部：
   a. 检查 peer pad (sinkpad_B)
   b. 如果 sinkpad_B 有 caps 未协商 → 自动协商
   c. 调用 sinkpad_B 的 chainfunc(buffer)

③ Element B 的 sinkpad chainfunc 中：
   a. 处理 buffer（解码/转换/传递）
   b. gst_pad_push(srcpad_B, processed_buffer)
   c. 推给下一个 Element

④ 重复...
```

**gst_pad_push() 的完整流程**：

```
gst_pad_push(GstPad *pad, GstBuffer *buffer)
 │
 ├── ① 检查 pad 状态 (flushing? linked? caps negotiated?)
 │
 ├── ② 发送 GST_PAD_PROBE_TYPE_PUSH probes
 │
 ├── ③ 调用 peer sinkpad 的 chainfunc(buffer)
 │       └── 这是用户自定义的 Element 逻辑入口
 │
 └── ④ 返回 GstFlowReturn
         └── GST_FLOW_OK / GST_FLOW_EOS / GST_FLOW_ERROR / ...
```

**链式处理的典型 Element 代码模式**：

```c
// 一个"透传"元素（如 identity）的 chain 函数示例
static GstFlowReturn
my_element_chain (GstPad *pad, GstObject *parent, GstBuffer *buffer)
{
  MyElement *elem = MY_ELEMENT (parent);

  // 1. 处理 buffer（可修改、可丢弃、可转换）
  if (elem->do_processing) {
    buffer = my_process_buffer (elem, buffer);
  }

  // 2. 推给下游
  GstPad *outpad = gst_element_get_static_pad (elem, "src");
  GstFlowReturn ret = gst_pad_push (outpad, buffer);
  gst_object_unref (outpad);

  return ret;
}
```

### 5.2 Pull 模式数据流

用于需要下游主动拉取数据的场景（如 file source、网络流）：

```
[ Element A (Decoder) ]  ◀──pull_range()──  [ Element B (FileSrc) ]
     sinkpad                     srcpad

① Decoder 调用 gst_pad_pull_range(srcpad, offset, size, &buffer)
② 内部转发到 peer (FileSrc 的 sinkpad)
③ FileSrc 的 getrangefunc 被调用
④ FileSrc 从文件读取数据填入 buffer
⑤ 返回给调用方
```

**Push vs Pull 的选择**：
| 模式 | 适用场景 | 示例 |
|------|---------|------|
| Push | 实时流、缓冲区可控 | 网络流 → 解码 → 渲染 |
| Pull | 需要精确控制读取时机 | 文件源、seek 后的随机读取 |
| 混合 | 源元素用 Pull，处理链用 Push | filesrc(queue) decoder (default push) |

### 5.3 Buffer 生命周期与引用计数

Buffer 的生命周期由**引用计数**管理：

```
创建 Buffer                    传递 Buffer                    销毁 Buffer
    │                              │                              │
    ├── gst_buffer_new()           ├── gst_pad_push(pad, buf)   ├── gst_buffer_unref(buf)
    ├── gst_buffer_new_allocate()  │   → ref++                   │   ref--
    ├── gst_buffer_new_wrapped()   ├── gst_pad_push_list()      │   → free()
    └── gst_buffer_copy()          └── gst_buffer_replace()      └── allocator->free()
                                     │                              (或 gst_memory_free())
                                     ├── gst_buffer_ref(buf)    ← COW 写时复制
                                     │   → ref++ (共享数据)
                                     └── gst_buffer_make_writable(buf)
                                         → 需要写时 copy
```

**关键规则**：
1. `gst_pad_push()` 会**转移所有权**：调用方不再持有该 buffer 的引用
2. 下游的 `chainfunc` 收到 buffer 后拥有一个引用，用完后需 `gst_buffer_unref()`
3. 如果下游丢弃 buffer，直接 `gst_buffer_unref()` 即可
4. **写时复制**：`gst_mini_object_make_writable()` 在 buffer 被共享时自动创建副本

### 5.4 Caps 协商流程

在数据开始流动前，上下游 Pad 必须协商**数据格式**（Caps = Capabilities）：

```
Pad Link 时自动协商：

Element A (srcpad)                    Element B (sinkpad)
     │                                      │
     │  ① gst_pad_link(srcpad, sinkpad)     │
     │                                      │
     │  ② 检查 srcpad 的 current caps        │
     │     (如有)                           │
     │                                      │
     │  ③ 询问 sinkpad 的 query_caps()      │
     │     → "你能接收什么格式？"            │
     │                                      │
     │  ④ 取交集，如果为空 → 失败             │
     │                                      │
     │  ⑤ 如果 srcpad 无 fixed caps:         │
     │     → 发送 CAPS event 给下游          │
     │     → 下游回复确认                     │
     │                                      │
     │  ⑥ 双方都设置 current caps            │
     │  ✅ 协商完成，数据开始流动              │
```

**Caps 格式示例**：
```
video/x-raw, format=(string)RGBA, width=(int)1920, height=(int)1080, framerate=(fraction)30/1
audio/x-raw, format=(string)F32, rate=(int)48000, channels=(int)2
```

### 5.5 Event / Query 流

**Event（事件）**：带方向的控制指令，沿 Pad 链传递

```
方向：DOWNSTREAM (上游 → 下游)         UPSTREAM (下游 → 上游)

NEWSEGMENT    │──▶│                  │◀──│     通知下游播放速率/范围
EOS           │──▶│                  │     流结束信号
FLUSH_START   │──▶│                  │     开始刷新
FLUSH_STOP    │──▶│                  │     刷新完成
SEEK          │──▶│                  │     跳转请求
CAPS          │──▶│                  │     格式确认
```

**Query（查询）**：沿 Pad 链反向传播的请求

```
                    │
          POSITION  │◀──│  询问"当前位置在哪？"
          DURATION  │◀──│  询问"总时长多少？"
          SEEKING   │◀──│  询问"支持 seek 吗？"
          FORMAT    │◀──│  询问"支持哪些时间格式？"
          ALLOCATION│◀──│  询问"内存怎么分配？"
                    │
```

**Event 与 Query 的区别**：
| | Event | Query |
|--|-------|-------|
| 方向 | 单向 (DOWNSTREAM/UPSTREAM) | 反向传播 (下游→上游) |
| 语义 | "请做这件事" | "请告诉我这个信息" |
| 传递 | 沿 Pad 链转发 | 沿 Pad 链回传结果 |
| 示例 | EOS, SEEK, NEWSEGMENT | POSITION, DURATION, SEEKING |

---

## 6. 控制流分析

### 6.1 状态机模型

GstElement 是一个**有限状态机（FSM）**，有 4 个有效状态：

```
                  gst_element_set_state(NULL)
                  (重置到初始状态)
                         │
                         ▼
              ┌─── GST_STATE_NULL (初始) ─────────┐
              │ · 资源未分配                        │
              │ · 元素未初始化                      │
              │ · 设备未打开                        │
              └──┬─────────────────────────────────┘
                 │ gst_element_set_state(READY)
                 │
                 ▼
         ┌── GST_STATE_READY (就绪) ────────────────┐
         │ · 资源已分配                             │
         │ · 元素已初始化                           │
         │ · 设备已打开 (视频/音频设备探测)          │
         │ · Pad 已创建                             │
         │ · **不能处理数据** (不推 buffer)          │
         └──┬──────────────────────────────────────┘
            │ gst_element_set_state(PAUSED)
            │
            ▼
    ┌── GST_STATE_PAUSED (暂停) ──────────────────┐
    │ · 数据可以进入元素                           │
    │ · 元素可以处理数据 (但 Sink 只接收不渲染)     │
    │ · 时钟已同步到 PAUSED 基准                   │
    │ · Buffer 被 preroll 缓冲                    │
    └──┬──────────────────────────────────────────┘
       │ gst_element_set_state(PLAYING)
       │
       ▼
 ┌── GST_STATE_PLAYING (播放) ─────────────────┐
 │ · 时钟开始运行                                │
 │ · 数据正常流动                                 │
 │ · Sink 开始渲染数据                           │
 │ · running_time 基于时钟计算                   │
 └─────────────────────────────────────────────┘
```

**向下的状态转换**（反向路径相同）：

```
PLAYING → PAUSED: 时钟仍在运行，但 Sink 停止渲染
PAUSED → READY:  停止数据流，Deactivate 所有 Pad，清空 Buffer
READY → NULL:    释放资源，关闭设备，清理状态
```

**关键设计：渐进式状态转换**：

```
GST_STATE_CHANGE_NULL_TO_READY    (0x12)
GST_STATE_CHANGE_READY_TO_PAUSED  (0x23)
GST_STATE_CHANGE_PAUSED_TO_PLAYING(0x34)
GST_STATE_CHANGE_PLAYING_TO_PAUSED(0x43)
GST_STATE_CHANGE_PAUSED_TO_READY  (0x32)
GST_STATE_CHANGE_READY_TO_NULL    (0x21)
```

每个转换是**原子且不可跳过的**。即使调用 `set_state(NULL → PLAYING)`，
内部也会依次执行 NULL→READY→PAUSED→PLAYING 三个转换。

### 6.2 状态转换的逐级传播

当 Pipeline 被设置新状态时，状态转换从**顶层向下传播**：

```
Pipeline (set_state(PLAYING))
 │
 ├── ① 选择/分配时钟
 │      gst_pipeline_auto_clock() → 从子元素中选一个 clock
 │      或通过 gst_pipeline_use_clock() 手动指定
 │
 ├── ② 通知所有子元素设置目标状态
 │      gst_element_set_state(child, PLAYING)
 │         │
 │         ├── gst_bin_set_state()   ← Bin 的特殊处理
 │         │     ├── 先设置子元素状态
 │         │     │     gst_element_set_state(each_child, PLAYING)
 │         │     │
 │         │     └── 等待所有子元素完成
 │         │           gst_element_get_state(child, &state, &pending, GST_CLOCK_TIME_NONE)
 │         │
 │         └── 自己的 change_state() 钩子
 │
 └── ③ 分发 base_time 和 running_time
        base_time = current_time - pipeline_start_time
```

**Bin 的特殊行为**：

```
GstBin 在状态转换中扮演"协调者"角色：

1. 它管理子元素的添加/移除
2. 它计算并重新分配 Pipeline 的 Latency：
   gst_bin_recalculate_latency()
   └── 收集所有 sink pad 的最小延迟
       → 设置 Pipeline 的 configured latency

3. 它收集子元素发出的 EOS 消息：
   - 只有当所有子元素都发送 EOS，Bin 才向上发送 EOS
   - EOS 消息暂存在 Bin 中排队

4. 它处理"热插拔"元素（在 PAUSED/PLAYING 时动态添加）
```

### 6.3 时钟与时间同步

时钟系统是 GStreamer 时间管理的核心：

```
                    GstPipeline
                        │
                    ┌───┴───┐
                    │clock  │  (GstClock, 如 GstSystemClock)
                    └───┬───┘
                        │ 通过 context 或 set_clock() 分发
                        │
          ┌─────────────┼─────────────┐
          │             │             │
     ┌────▼───┐   ┌─────▼───┐   ┌────▼───┐
     │Element1│   │Element2 │   │Element3│
     │clock    │   │clock    │   │clock   │
     └────────┘   └─────────┘   └────────┘

在 PLAYING 状态转换时：
  1. Pipeline 选定一个 master clock
  2. 设置 base_time（通常为当前时间）
  3. 每个元素的 running_time 计算：
     running_time = (clock_time - base_time) + start_time
```

**时钟同步**：

```
Element 在 PLAYING 状态下处理 buffer 时：
  timestamp (buffer 的时间戳)
    ── 对比 ──▶ 当前 running_time
    ── 如果 timestamp < running_time ──▶ wait (gst_clock_wait)
    ── 如果 timestamp > running_time ──▶ 直接处理
    ── 如果 timestamp ≈ running_time ──▶ 立即处理
```

### 6.4 Bus 消息机制

Bus 是 Element 与 Application 之间的**异步消息通道**：

```
Element A ──post_message(ERROR, ...)──▶ Bus
                                          │
                                          ├── gst_bus_add_watch() → 异步回调
                                          │     bus_handler(GstBus *bus, GstMessage *msg, ...)
                                          │
                                          └── gst_bus_set_sync_handler() → 同步回调
                                                bus_sync_handler(bus, msg, ...)
                                                (在 Element 线程中同步执行)
```

**消息的创建和传递流程**：

```
gst_element_post_message(element, message)
 │
 ├── ① 检查 Bus 是否存在
 │
 ├── ② 如果 Bin 有父 Bin，消息向上冒泡
 │       (每个 Bin 可以选择是否转发消息)
 │
 ├── ③ 到达 Pipeline 的 Bus
 │
 ├── ④ Bus 将消息放入异步队列
 │
 └── ⑤ Application 的 bus_handler() 被 GMainLoop 触发
```

**Bus 同步与异步模式对比**：

| 模式 | 函数 | 执行线程 | 适用场景 |
|------|------|---------|---------|
| 异步 | `gst_bus_add_watch()` | GMainLoop 线程 | 正常应用（更新 UI、退出循环） |
| 同步 | `gst_bus_set_sync_handler()` | Element 数据线程 | 需要立即响应的内部操作 |

**典型消息流**（从 Pipeline 启动到播放）：

```
Application                          Pipeline                      Elements
    │                                    │                              │
    │ set_state(PAUSED)                  │                              │
    │ ─────────────────▶                 │                              │
    │                                    │ state_change(NULL→READY)      │
    │                                    │ ─────────────────▶           │ filesrc open file
    │                                    │                              │
    │                                    │ state_change(READY→PAUSED)    │
    │                                    │ ─────────────────▶           │ src pad activate
    │                                    │                              │
    │ ◀── STATE_CHANGED message ──────── │                              │
    │                                    │ preroll 完成                  │
    │                                    │                              │
    │ set_state(PLAYING)                 │                              │
    │ ─────────────────▶                 │                              │
    │                                    │ state_change(PAUSED→PLAYING)  │
    │                                    │ clock selected                │
    │ ◀── STATE_CHANGED message ──────── │                              │
    │                                    │                              │
    │                                    │ data flows ▶                 │
    │                                    │                              │
    │ ◀── BUFFERING / TAG / ... ─────── │                              │
    │ ◀── EOS message ───────────────── │        EOS sent by src       │
    │ quit()                           │                              │
```


---

## 7. 各文件作用详解

### 7.1 gst/ 核心模块文件清单与职责

`gst/` 目录编译为 `libgstreamer-1.0.so`（在 pkg-config 中称为 `gstreamer-1.0`），
是 GStreamer 运行时的心脏。下面的分组按功能域而非字母序排列，便于理解架构全貌。

#### 7.1.1 初始化与运行时基础设施

| 文件 | 职责 | 类比 |
|------|------|------|
| `gst.c` | `gst_init()`/`gst_deinit()`，命令行参数解析，插件注册表扫描 | 程序的 `main()` 前的初始化 |
| `gstinfo.c` | 日志系统（`GST_DEBUG_*` 宏），调试等级、颜色输出 | 类似 `log4j` / `spdlog` |
| `gsterror.c` | 错误码定义与 `GError` 转换 | — |
| `gstutils.c` | 通用工具函数：内存 dump、字符串、线程辅助函数 | — |
| `gstpoll.c` | 跨平台 poll/epoll/kqueue 封装 | 文件描述符多路复用 |
| `gstatomicqueue.c` | 无锁环形队列，用于 Buffer 传递 | `moodycamel::ConcurrentQueue` |
| `gsttask.c` / `gsttaskpool.c` | 后台任务线程管理，Element 的独立执行线程 | 线程池/`std::jthread` |
| `gstcpuid.c` | CPU 特性检测（SSE/AVX/NEON） | — |

> **gstTask 的设计**：每个需要异步工作的 Element（如 src 元素的推数据线程、sink 元素的渲染线程）
> 都持有一个 `GstTask`。`GstTaskPool` 在所有 Element 间共享线程，避免了"一个 Element 一个线程"的浪费。
> 这类似于 C++ 中的 **工作窃取线程池（work-stealing pool）**。

#### 7.1.2 核心对象体系

| 文件 | 职责 | 关系 |
|------|------|------|
| `gstminiobject.c` | 最底层引用计数基类，提供 `ref`/`unref`/`copy`/`make-writable` | `GObject` 的兄弟类型（非 `GObject` 子类） |
| `gstobject.c` | 命名引用计数对象，`name` + `parent` + `refcount` | `GObject` 子类 |
| `gstobject.c` 的关键方法 | `gst_object_set_name()`, `gst_object_set_parent()`, `gst_object_replace()` | 用于对象图管理和 leak 检测 |

#### 7.1.3 元素管理系统

| 文件 | 职责 | 说明 |
|------|------|------|
| `gstelement.h/c` | **`GstElement`** — 框架的核心抽象，封装了状态机、Pad 管理、Bus、Clock | 每个编解码器、源、宿都是 `GstElement` 子类 |
| `gstbin.c` | **`GstBin`** — 可容纳子元素的容器，负责状态传播、延迟计算、Bus 转发 | `GstPipeline` 的直接父类 |
| `gstpipeline.c` | **`GstPipeline`** — 顶层容器，自动分配 Clock、持有自己的 Bus | 一个 Pipeline = 一个独立的多媒体会话 |
| `gstelementfactory.c` | **`GstElementFactory`** — 元素工厂，记录类名、Caps、插件来源 | 用户通过 `gst_element_factory_make()` 创建实例 |
| `gstpad.c` | **`GstPad`** — 元素间的连接接口，持有一组函数指针（chainfunc, eventfunc...） | 数据流动的实际通道 |
| `gstghostpad.c` | **`GstGhostPad`** — 指向 Bin 内部某个 Pad 的代理 | Bin 对外暴露的统一入口 |
| `gstpadtemplate.c` | **`GstPadTemplate`** — Pad 的模板（名称、方向、Caps 约束） | 决定元素"长什么样" |

#### 7.1.4 数据对象体系

| 文件 | 职责 | 类比 |
|------|------|------|
| `gstbuffer.c` | **`GstBuffer`** — 数据缓冲区，引用计数 + 写时复制 + 元数据 | `std::shared_ptr<uint8_t[]>` + 时间戳 |
| `gstbufferlist.c` | **`GstBufferList`** — Buffer 集合 | — |
| `gstmemory.c` | **`GstMemory`** — 实际内存持有者，支持共享/映射 | 内存池的抽象 |
| `gstallocator.c` | **`GstAllocator`** — 内存分配器接口 | `malloc`/`mmap`/`drmModeDumbMmap` 的统一接口 |
| `gstbufferpool.c` | **`GstBufferPool`** — Buffer 池管理，预先分配内存 | 对象的"池化"，避免频繁 malloc |
| `gstcaps.c` | **`GstCaps`** — 格式能力描述，支持 range/enum/str 通配 | 网络中的 `Content-Type` 协商 |
| `gststructure.c` | **`GstStructure`** — Caps 的内部结构：字段名→值的映射表 | `std::map<string, GValue>` |
| `gstvalue.c` | **`GValue`** — 通用值类型，可装 int/str/fraction/box/struct | `std::variant<int, string, ...>` |
| `gstevent.c` | **`GstEvent`** — 控制事件（SEEK/EOS/FLUSH/NEWSEGMENT） | — |
| `gstquery.c` | **`GstQuery`** — 查询请求（DURATION/POSITION/SEEKING） | — |
| `gstmessage.c` | **`GstMessage`** — 异步通知（ERROR/WARNING/STATE_CHANGED） | `Promise<Error>` |
| `gsttaglist.c` | **`GstTagList`** — 音轨信息、标题、艺术家等元数据 | ID3/ VorbisComment |
| `gstsegment.c` | **`GstSegment`** — 播放段描述（起始位置、速率、格式） | `std::pair<Position, Position>` |
| `gstsample.c` | **`GstSample`** — Buffer + Caps 组合（带格式信息的 Buffer） | — |
| `gstmeta.c` | **`GstMeta`** — Buffer/BufferList 上的附加元数据 | HDR/DRM/色彩空间标记 |

> **Buffer/Memory 的关系**：`GstBuffer` 是"上层视角"，包含时间戳、偏移、元数据；
> `GstMemory` 是"底层视角"，持有实际内存指针和分配器。**一个 Buffer 可以包含多个 Memory 块**，
> 这支持分散/聚合 I/O（scatter-gather）场景。

#### 7.1.5 时钟与同步

| 文件 | 职责 | 说明 |
|------|------|------|
| `gstclock.c` | **`GstClock`** 抽象基类，定义 `clock_get_time()` 接口 | — |
| `gstsystemclock.c` | **`GstSystemClock`** — 基于 `clock_gettime(CLOCK_MONOTONIC)` | 最常见的 Clock 实现 |
| `gstnet.c` (libs/) | 网络时间协议（NTP）时钟同步 | 分布式场景用 |

#### 7.1.6 动态控制

| 文件 | 职责 |
|------|------|
| `gstcontrolsource.c` | **`GstControlSource`** — 随时间变化的值源（如 LFO 波形） |
| `gstcontrolbinding.c` | **`GstControlBinding`** — 将控制源绑定到元素属性 |
| `gstargbcontrolbinding.c` | 针对 ARGB 属性的特殊绑定 |
| `gstinterpolationcontrolsource.c` | 插值控制源（线性/阶跃/贝塞尔） |
| `gstlfocontrolsource.c` | 低频振荡器（正弦波、方波等） |
| `gsttimedvaluecontrolsource.c` | 离散时间点-值序列 |

> 这是 GStreamer 的**动画系统**：你可以在时间轴上设定"音量从 0→1 用时 2 秒"，
> 框架自动在运行时插值并更新属性。类似 C++ 中的 `std::chrono` + 回调。

#### 7.1.7 插件与注册表

| 文件 | 职责 |
|------|------|
| `gstplugin.c` | **`GstPlugin`** — 已加载插件的运行时表示 |
| `gstpluginfeature.c` | 插件特性的基类（ElementFactory、TracerFactory 等都继承） |
| `gstpluginloader.c` | 动态加载 `.so` 插件：`dlopen` → `dlsym(gst_plugin_register_*)` |
| `gstregistry.c` | 注册表的 C 级操作：读写、合并 chunk |
| `gstregistrybinary.c` | 二进制注册表格式序列化/反序列化 |
| `gstregistrychunks.c` | 增量更新机制：只重写变更的 chunk，而非整个 registry |

> **注册表优化**：GStreamer 2 级优化 — 磁盘缓存 + 增量更新。
> 第一次启动时扫描所有插件，写入 `~/.cache/gstreamer-1.0/registry.json`；
> 后续启动直接从缓存加载，秒开。

#### 7.1.8 Pipeline 描述符解析器

| 文件 | 职责 |
|------|------|
| `gstparse.c` | 主解析逻辑，处理 `"filesrc ! queue ! filesink"` 风格的字符串 |
| `gstparse.h` | 公开 API：`gst_parse_launchv()` |
| `parse/grammar.y.in` | Bison 语法规则 |
| `parse/parse.l` | Flex 词法分析 |
| `parse/gen_grammar.py.in` | 在构建时生成 `grammar.y` |

> 这个解析器支持完整的 DSL：元素创建、属性赋值、Pad 链接、Bus 监听器、
> 信号处理器、甚至嵌套 Bin。`gst-launch-1.0` 就是靠它工作的。

#### 7.1.9 其他重要模块

| 文件 | 职责 |
|------|------|
| `gstbus.c` | **`GstBus`** — Element ↔ Application 的消息通道 |
| `gstcontext.c` | **`GstContext`** — Element 间的上下文共享（如 DRM device） |
| `gstdevice.[ch]` | 设备抽象（音频输出设备、视频捕获设备） |
| `gstdevicemonitor.c` | 设备热插拔监控 |
| `gstiterator.c` | GList 之上的类型安全迭代器 |
| `gstchildproxy.c` | 让 Bin 实现 `GChildProxy` 接口 |
| `gstpreset.c` | 预设管理（保存/加载 Element 属性组合） |
| `gsttypefind.[ch]` | 自动类型探测（文件魔数识别） |
| `gsturi.c` | URI 协议处理（`file://`, `http://`） |
| `gsttoc.[ch]` | TOC（Table of Contents） — 章节/曲目信息 |
| `gsttracer.[ch]` | 性能追踪器框架 |
| `gststreamcollection.c` / `gststreams.c` | 多流管理（多音轨、多字幕） |
| `gstprotection.c` | DRM 保护相关 |
| `gstasyncquery.c` / `gstasyncsignal.*` | 异步查询/信号（在后台线程执行查询） |
| `gstdate*.c` / `gstidstr.c` / `gstvecdeque.c` | 日期、ID字符串、动态数组等基础设施 |

### 7.2 libs/ 扩展库

libs/ 中的每个子目录编译为独立的共享库，核心库运行时可以可选地依赖它们。

#### 7.2.1 libs/gst/base/ — 基类库（`libgstbase-1.0.so`）

这是核心库提供的**最重要的抽象层**，绝大多数编解码器插件都基于这些基类实现：

| 文件 | 职责 | 说明 |
|------|------|------|
| `gstbasesrc.c` | **`GstBaseSrc`** — 源元素基类 | 子类只需实现 `is_seekable()` + `read()`/`get_range()` |
| `gstbasesink.c` | **`GstBaseSink`** — 接收元素基类 | 子类只需实现 `render()`（将 Buffer 送到屏幕/扬声器/文件） |
| `gstbasetransform.c` | **`GstBaseTransform`** — 转换元素基类 | 子类只需实现 `transform()`（输入→输出 Buffer） |
| `gstbaseparse.c` | **`GstBaseParse`** — 解析器基类 | 处理容器格式（MP4/AVI/WebM），提取 Elementary Stream |
| `gstaggregator.c` | **`GstAggregator`** — 聚合元素基类 | 从多个输入 Pad 收集 Buffer，汇聚成单输出 |
| `gstadapter.c` | **`GstAdapter`** — 数据适配器 | 将不定长输入缓冲区转为固定大小输出 |
| `gstcollectpads.c` | **`GstCollectPads`** — 多 Pad 收集器 | 管理多个输入 Pad 的 Buffer 队列 |
| `gstdataqueue.c` | **`GstDataQueue`** — 通用数据队列 | 带容量限制的 Buffer 队列（`queue` 元素的基础） |
| `gstpushsrc.c` | **`GstPushSrc`** — Push 模式源基类 | 比 `GstBaseSrc` 更简单的源实现 |
| `gsttypefindhelper.c` | 类型探测辅助函数 | 检查 Buffer 魔数 |
| `gstbitreader.[ch]` | 位流读取工具 | 从 Buffer 中逐 bit 解析（用于容器格式解析） |
| `gstbitwriter.[ch]` | 位流写入工具 | 构造封装好的数据包 |
| `gstbytereader.[ch]` | 字节流读取工具 | 按字节序读取（大端/小端） |
| `gstbytewriter.[ch]` | 字节流写入工具 | — |
| `gstflowcombiner.c` | FlowReturn 合并逻辑 | 多个操作返回不同 FlowReturn 时的合并策略 |
| `gstindex.c` | 索引管理 | 播放位置索引 |
| `gstmemindex.c` | 内存索引 | 基于内存的索引实现 |
| `gstqueuearray.c` | 快速数组队列 | 内部数据结构 |

> **GstBaseSrc / GstBaseSink / GstBaseTransform 三剑客**：
> 这三个基类覆盖了 95% 的元素类型。写一个自定义元素，通常只需要：
> 1. 继承对应基类
> 2. 实现 1-3 个虚函数（如 `render`、`transform`、`read`）
> 3. 在 `class_init` 中注册 Pad 模板
>
> 基类自动处理了状态机、Clock 同步、Preroll、Push/Pull 模式切换、
> Query 转发、Buffer 分配等繁琐细节。

#### 7.2.2 libs/gst/check/ — 测试基础设施（`libgstcheck-1.0.so`）

| 文件 | 职责 |
|------|------|
| `gstcheck.c` | 测试框架核心：创建测试元素、连接、运行 |
| `gstcheck.h` | 测试宏：`GST_START_TEST`、`assert_equal_buffers()` 等 |
| `gstbasetransform.c` (test 中) | BaseTransform 专用的 helper |
| `gstbufferstraw.c` | Buffer 捕获/检查工具 |
| `gstconsistencychecker.c` | 一致性检查器 |
| `gsttestclock.c` | 可操控的测试时钟 |
| `gstcachelack.c` | Harness — 轻量测试夹具 |

> 这是 GStreamer 单元测试的基石，基于 libcheck + 自定义宏。
> 测试中的元素只需几行代码即可连接和验证数据流。

#### 7.2.3 libs/gst/controller/ — 动态控制（`libgstcontroller-1.0.so`）

| 文件 | 职责 |
|------|------|
| `gstinterpolationcontrolsource.c` | 插值控制源（线性/阶跃/贝塞尔） |
| `gstlfocontrolsource.c` | 低频振荡器 |
| `gsttimedvaluecontrolsource.c` | 时间点→值映射 |
| `gsttriggercontrolsource.c` | 触发器控制源 |
| `gstproxycontrolbinding.c` | 代理绑定（代理另一个绑定） |
| `gstargbcontrolbinding.c` | ARGB 属性绑定 |
| `gstdirectcontrolbinding.c` | 直接绑定（无插值） |

#### 7.2.4 libs/gst/helpers/ — 辅助工具

| 文件 | 职责 |
|------|------|
| `gst-completion-helper.c` | 命令行补全辅助 |
| `gst-plugin-scanner.c` | 插件扫描工具 |

#### 7.2.5 libs/gst/net/ — 网络扩展（`libgstnet-1.0.so`）

| 文件 | 职责 |
|------|------|
| `gstnetclientclock.c` | NTP 网络时钟 — 从远程 NTP 服务器同步时间 |
| `gstnettimeprovider.c` | NTP 时间提供者 |
| `gstntppacket.c` | NTP 报文解析 |
| `gstnettimepacket.c` | 时间包 |
| `gstnetaddressmeta.c` | 网络地址元数据 |
| `gstnetcontrolmessagemeta.c` | 网络控制消息元数据 |

### 7.3 plugins/ 核心插件

这些插件编译为独立的 `.so` 文件，作为 `libgstreamer-1.0` 的补充：

#### 7.3.1 plugins/elements/ — 基础元素

| 元素 | 文件 | 作用 |
|------|------|------|
| `fakesrc` | `gstfakesrc.c` | 生成伪数据缓冲区（测试用） |
| `fakesink` | `gstfakesink.c` | 丢弃数据的接收端（测试用） |
| `filesrc` | `gstfilesrc.c` | 从文件读取数据 |
| `filesink` | `gstfilesink.c` | 写入数据到文件 |
| `queue` | `gstqueue.c` | **缓冲队列** — 解耦上下游速率，线程隔离 |
| `queue2` | `gstqueue2.c` | 改进版 queue（多 Pad 支持） |
| `tee` | `gsttee.c` | **分支节点** — 一份数据推向多个下游 |
| `identity` | `gstidentity.c` | 透传元素，不修改数据（调试用） |
| `concat` | `gstconcat.c` | 拼接多个媒体片段 |
| `funnel` | `gstfunnel.c` | 合并多个输入流 |
| `inputselector` | `gstinputselector.c` | 多输入选其一 |
| `outputselector` | `gstoutputselector.c` | 单输入选一切出 |
| `valve` | `gstvalve.c` | 阀门 — 控制数据是否通过 |
| `capsfilter` | `gstcapsfilter.c` | 强制 Caps 过滤 |
| `typefind` | `gsttypefindelement.c` | 自动类型探测 |
| `clocksync` | `gstclocksync.c` | 时钟同步 |
| `fdsrc` / `fdsink` | `gstfdsrc.c` / `gstfdsink.c` | 文件描述符 I/O |
| `dataurisrc` | `gstdataurisrc.c` | 从 `data:` URI 读取 |
| `downloadbuffer` | `gstdownloadbuffer.c` | 异步下载 Buffer |
| `streamiddemux` | `gststreamiddemux.c` | 基于 stream-id 解复用 |
| `sparsefile` | `gstsparsefile.c` | 稀疏文件支持 |

#### 7.3.2 plugins/tracers/ — 性能追踪器

| 追踪器 | 文件 | 作用 |
|--------|------|------|
| `dots` | `gstdots.c` | 在终端绘制状态机转换点图 |
| `latency` | `gstlatency.c` | 追踪每个 Buffer 的延迟 |
| `leaks` | `gstleaks.c` | Buffer 泄漏检测 |
| `log` | `gstlog.c` | 详细的事件/Buffer 日志 |
| `rusage` | `gstrusage.c` | 系统资源使用统计 |
| `stats` | `gststats.c` | 实时吞吐量/帧率统计 |
| `factories` | `gstfactories.c` | 元素工厂信息 |

### 7.4 tools/ 工具程序

| 工具 | 文件 | 作用 |
|------|------|------|
| `gst-launch-1.0` | `gst-launch.c` | 从命令行构建和运行 Pipeline，`filesrc ! queue ! fakesink` |
| `gst-inspect-1.0` | `gst-inspect.c` | 枚举插件信息：Element、Pad 模板、属性、信号 |
| `gst-stats-1.0` | `gst-stats.c` | 运行时性能统计工具 |
| `gst-typefind-1.0` | `gst-typefind.c` | 探测文件媒体类型 |

---

## 8. C++ 知识补充

> 本面向有 C/C++ 基础但未必熟悉高级特性的开发者，通过 C 和 C++ 的对比，
> 帮助理解 GStreamer 的设计选择。

### 8.1 GObject 类型系统 vs C++ 继承

#### 类型系统的本质差异

C++ 的类型系统在**编译期**完成绑定，而 GObject 的类型系统在**运行期**完成：

```cpp
// C++: 编译期多态 — 虚函数表在编译时确定
class Shape {
public:
    virtual ~Shape() = default;
    virtual double area() const = 0;  // 虚函数表 vtable
};

class Circle : public Shape {
    double radius_;
public:
    double area() const override { return 3.14 * radius_ * radius_; }
};
// Circle 的 vtable 在编译时生成，无法在运行时替换
```

```c
// GObject: 运行期多态 — 函数指针在初始化时设置
static guint32 circle_get_type (void) G_GNUC_CONST;

struct _Circle {
  GObject parent;          // 继承
  gdouble radius;          // 成员
};

struct _CircleClass {
  GObjectClass parent;     // 父类 class
  // 没有"虚函数"概念 — 所有方法通过函数指针调用
};

// 虚函数表 = CircleClass 中的函数指针
static void circle_area (Circle *self) {
  // 通过 self->class->area (self) 调用，运行期解析
}

// 子类可以完全替换某个方法
static void circle_class_init (CircleClass *klass) {
  klass->area = my_custom_area;  // 运行时替换！
}
```

#### 关键区别

| 维度 | C++ | GObject |
|------|-----|---------|
| 多态时机 | 编译期（vtable） | 运行期（函数指针） |
| 运行时类型检查 | `dynamic_cast` | `G_TYPE_CHECK_INSTANCE_TYPE` |
| 构造函数 | `new` 自动调用 | `g_object_new()` 两步（alloc → init） |
| 析构函数 | RAII（确定性） | 引用计数 + `finalize`（非确定性） |
| 多重继承 | 支持（interface） | 支持（`G_IMPLEMENT_INTERFACE`） |
| 异常 | `try/catch` | 返回 `GError**` |
| 泛型 | `template<T>` | `GValue`（运行期类型） |
| 内存管理 | `shared_ptr`/`unique_ptr` | `ref`/`unref` |

> **为什么 GStreamer 用 C 而不是 C++**？
> 1. **跨语言互操作**：Python (GIR/GObject-Introspection)、Java (GStreamer Java bindings)、
>    JavaScript (GStreamer.js) 都能直接绑定 C API
> 2. **运行时类型可替换**：动态插件可以在运行时"修改"一个类的虚函数表
> 3. **零成本抽象**：没有 C++ 虚函数表的 overhead，对实时多媒体很重要
> 4. **兼容性**：C  ABI 的稳定性远优于 C++（`std::vector<int>` 在不同编译器间 ABI 不兼容）

### 8.2 宏生成"类"的模式

GObject 使用大量宏来生成"类"代码。以下是核心宏展开后的真实形态：

```c
// ===== 标准 GObject 类的声明 =====

// 1. 类型函数声明
struct _MyClass;
guint32 my_class_get_type (void) G_GNUC_CONST;

// 2. 实例结构体
struct _MyClass {
  GObject parent;                 // 必须放在第一位
  gchar *name;                    // 自己的成员
  gint value;
  // 注意：没有 private 成员 — 所有成员都是 public 的
};

// 3. 类结构体
struct _MyClassClass {
  GObjectClass parent;
  void (*named_changed) (MyClass *, gchar *);  // 信号
  gboolean (*process) (MyClass *, const gchar *); // 虚函数
};

// 4. 类型注册宏（展开后是复杂的 static gsize __g_define_type__ = 0;）
//    它会在第一次调用时调用 _register() 函数，注册类型信息
G_DEFINE_TYPE (MyClass, my_class, G_TYPE_OBJECT)

// ===== 展开后等价于 =====
static guint32 my_class_get_type (void) {
  static gsize __g_define_type__ = 0;
  if (g_once_init_enter (&__g_define_type__)) {
    // 定义实例大小、类大小
    // 注册父类型、接口、信号、属性...
    // 定义 class_init 和 instance_init
    // 注册到 GTypeRegistry
    gsize __type__ = g_type_register_static (
        G_TYPE_OBJECT,
        "MyClass",
        &my_class_info,   // GTypeClassInfo + GTypeInfo
        0);
    g_once_init_leave (&__g_define_type__, __type__);
    return __type__;
  }
  return __g_define_type__;
}
```

> **G_DEFINE_TYPE 的好处**：
> 1. 只需一行代码注册类型
> 2. 自动创建 `my_class_init()` 和 `my_class_instance_init()`
> 3. 自动实现 `my_class_get_type()`（线程安全，`g_once_init_enter` 保证只执行一次）
>
> 对于 C++ 开发者来说，这相当于把 `class MyClass : public QObject` 的类型注册
> 用宏自动生成 — 只不过 GObject 需要在运行期也知道类型信息。

### 8.3 虚函数表在 C 中的实现

GObject 不使用 C++ vtable 机制，而是通过**结构体函数指针**实现多态：

```c
// C++ 虚函数
struct Shape {
    virtual double area() = 0;
    virtual ~Shape() = default;
};

// C 中 GObject 等效写法
struct ShapeClass {
  GObjectClass parent;
  // 虚函数 = 函数指针
  double (*area) (Shape *self);
  void (*dispose) (Shape *self);
};

// 使用：通过函数指针调用
static void shape_print_area (Shape *self) {
  // 注意：第一个参数总是实例自身 — "this" 是显式的
  double area = GST_CALL_WITH_TYPE (self, area, (self));
  // 等价于 C++ 的 self->area()
}

// 子类重写虚函数
struct CircleClass {
  ShapeClass parent;     // 继承父类
  // CircleClass 可以添加自己的"虚函数"
  void (*set_radius) (Circle *, gdouble);
};

// 调用时，实际上是 vtable[0].area(self)
// 如果子类重写了 area，vtable[0].area 指向子类实现
```

**对比**：

```cpp
// C++: this 指针隐藏，编译器插入
circle.area()
// 编译为: circle_vtable[0].area(circle)

// GObject: 完全一样，只是显式写出
circle_class->area (circle)
// 编译为: circle_vtable[0].area(circle)
```

> 本质上是同一个机制，只是 C++ 编译器帮你隐藏了函数指针的显式调用。

### 8.4 引用计数与智能指针类比

#### 引用计数机制

GStreamer 使用引用计数管理对象生命周期：

```c
// C++: std::shared_ptr
{
    auto p1 = std::make_shared<MyClass>("hello");  // ref = 1
    {
        auto p2 = p1;       // ref = 2（浅拷贝）
        // ...
    }                       // ref = 1（p2 析构）
}                           // ref = 0（p1 析构，对象被销毁）

// GObject: ref/unref
{
    MyClass *p1 = my_class_new ("hello");  // ref = 1 (constructor 返回强引用)
    {
        MyClass *p2 = g_object_ref (p1);   // ref = 2
        // ...
        g_object_unref (p2);               // ref = 1
    }
    g_object_unref (p1);                   // ref = 0，对象销毁
}
```

#### 等价映射表

| C++ | GObject | 说明 |
|-----|---------|------|
| `std::shared_ptr<T>` | `g_object_ref()/unref()` | 共享所有权 |
| `std::unique_ptr<T>` | 无直接对应 — C 无移动语义 | 需用手动所有权转移（如 `gst_buffer_replace()`） |
| `std::make_shared<T>` | `g_object_new(T_TYPE, ...)` | 创建 + 初始化 |
| `T* raw_ptr` | `T*` (未经 ref) | **借用引用（borrowing reference）** |
| `T& ref` | `T*` (确保非 NULL) | C 中没有引用类型 |
| `dynamic_cast<T*>(p)` | `G_TYPE_CHECK_INSTANCE_CAST(p, T_TYPE, T)` | 类型转换 |
| `dynamic_cast<T*>(&p)` | `G_TYPE_CHECK_INSTANCE_TYPE(p, T_TYPE)` | 类型检查 |
| `override` | 在 `class_init` 中赋值 | — |
| `virtual destructor` | `finalize` 信号 | — |

#### 写时复制（Copy-on-Write）

GStreamer 的 Buffer 支持 COW，类似于 C++ `std::shared_ptr` 但加了"可写性"检查：

```c
GstBuffer *buf1 = gst_buffer_new_allocate (NULL, 1024, NULL);

// 浅拷贝 — 共享同一内存
GstBuffer *buf2 = gst_buffer_ref (buf1);  // ref++

// buf2 想写入...
buf2 = gst_buffer_make_writable (buf2);  // 如果只有 1 个引用，返回 buf2
//                                      // 如果有多个引用，分配新内存并拷贝

// C++ 中需要类似机制，但没有内置支持 — 需要自己实现 `std::shared_ptr<T>` + 写锁
```

### 8.5 GValue — C 中的运行时类型安全容器

`GValue` 是 GObject 的类型安全通用值类型，类似于 C++ 的 `std::any` + `std::variant`：

```c
GValue val = G_VALUE_INIT;

// 存储 int
g_value_init (&val, G_TYPE_INT);
g_value_set_int (&val, 42);
gint v = g_value_get_int (&val);

// 存储字符串
g_value_unset (&val);  // 释放
g_value_init (&val, G_TYPE_STRING);
g_value_set_string (&val, "hello");
const gchar *s = g_value_get_string (&val);

// 存储 Fraction (分数，用于 framerate)
g_value_unset (&val);
g_value_init (&val, GST_TYPE_FRACTION);
g_value_set_fraction (&val, 30, 1);  // 30/1 = 30fps
gint num, den;
g_value_get_fraction (&val, &num, &den);

// C++ 对应
std::variant<int, std::string, Fraction> val_cpp;
// 但 GValue 的优势：类型是运行期决定的，可以存储任意 GType
// C++ 的 std::variant 需要在编译期知道所有类型
```

### 8.6 信号机制 vs C++ 信号槽

```cpp
// C++: Qt Signal/Slot
class MyClass : public QObject {
    Q_OBJECT
signals:
    void namedChanged(const QString &newName);
};
// 连接: QObject::connect(obj, &MyClass::namedChanged, this, &handleChanged);

// GObject
struct _MyClassClass {
  GObjectClass parent;
  gchar *signals[SIGNAL_LAST];
};

enum {
  SIGNAL_NAMED_CHANGED,
  SIGNAL_LAST
};

static void my_class_class_init (MyClassClass *klass) {
  klass->signals[SIGNAL_NAMED_CHANGED] =
    g_signal_new (
      "named-changed",
      G_TYPE_FROM_CLASS (klass),
      G_SIGNAL_RUN_LAST,    // 何时调用：构造后/析构前
      NULL,                 // 类虚函数偏移（无）
      NULL,                 // 累计器
      NULL,                 //  marshal 函数（自动）
      g_cclosure_marshal_VOID__STRING,  // 参数签名
      G_TYPE_NONE,          // 返回值类型
      1,                    // 参数数量
      G_TYPE_STRING);       // 第一个参数类型
}

// 连接信号
g_signal_connect (obj, "named-changed", G_CALLBACK (handle_changed), user_data);
```

> **RUN_LAST 的含义**：在信号链的最后调用回调 — 这意味着在信号的"默认处理器"之后执行。
> C++ 没有这个概念：C++ 信号直接调用槽函数，没有"默认处理器"阶段。

### 8.7 总结：GStreamer 的设计哲学

| C++ 惯用法 | GStreamer 等价 | 原因 |
|-----------|---------------|------|
| 虚函数继承 | GObject 子类 + class_init 函数指针 | 运行期可替换 |
| `shared_ptr` | `ref`/`unref` | 无所有权语义，全部平等 |
| `std::function` | GCallback + `g_signal_connect` | 类型安全的回调 |
| `std::variant` | `GValue` | 运行期类型 |
| RAII | 无 — 需要手动 `unref` | C 的限制，但可通过 GError 模式规避 |
| `std::move` | 所有权转移 API（如 `gst_element_get_static_pad` 返回借用，`gst_element_request_pad` 返回强引用） | C 无移动语义 |

GStreamer 在纯 C 中实现了极其接近 C++ OOP 的表达能力，
代价是更冗长的样板代码（每个类都需要类型宏、class_init、instance_init...）
和手动生命周期管理。