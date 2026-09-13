# GStreamer 流水线调用链分析

> 基于 `gstreamer-1.29.2` 源码，记录从用户层 API 到底层实现的真实调用链。
> 所有行号均为实际源码位置，已逐一核对。

---

## 一、项目结构速览

| 目录 | 说明 |
|------|------|
| `gst/` | 核心库源码：glib-compat、gstbin、gstbuffer、gstbus、gstelement、gstpad 等基础组件 |
| `libs/gst/base/` | 基础库：BaseSrc、BaseSink、BaseTransform、BaseParse、Aggregator 等基类 |
| `plugins/` | 插件系统（核心元素和追踪器） |
| `tools/` | 工具：gst-inspect、gst-launch、gst-stats、gst-typefind |
| `tests/` | 测试：benchmarks、check、examples |
| `docs/` | 文档 |
| `scripts/` | 构建辅助脚本 |
| `data/` | 数据文件 |

### 核心架构
- `Object → Element → Bin/Pipeline` 是基本的对象层次
- `Pad` 连接元素之间的数据流
- `Buffer / Sample / Memory` 承载数据
- `Bus` 传递消息/事件
- `Plugin` 机制注册元素

---

## 二、gst/ 与 libs/gst/base/ 的关系

### gst/ —— 全部是 GObject

看 `gst/gst.h`，整个 `gst/` 目录就是围绕 GObject 构建的一整套框架：

```c
#include <glib.h>          // 基础
```

所有核心类型都是 GObject：

| GObject 类型 | 职责 |
|--------------|------|
| `GstObject` | 所有 GStreamer 对象的基类 |
| `GstElement` | 可组合的功能单元 |
| `GstPad` | 元素之间的连接点（sink/src） |
| `GstBin / GstPipeline` | 容纳其他元素的容器 |
| `GstBus` | 消息/事件通道 |
| `GstBuffer / GstMemory` | 数据载体 |
| `GstCaps / GstStructure` | 媒体格式描述 |
| `GstSample` | Buffer + Caps + Segment + Meta 的组合 |
| `GstEvent / GstMessage / GstQuery` | 控制流/状态/查询 |

此外还有一些非对象的底层工具，比如 `gstpoll.c`（I/O 多路复用）、`gstatomicqueue.c`（线程安全队列）、`gstandroid.c`（Android 适配）等。

### libs/gst/base/ —— 元素的基类（抽象元素骨架）

这是给插件开发者用的脚手架。如果要写一个具体的插件，不需要从零实现 `GstElement` 的所有虚函数，而是继承这些基类：

| 基类 | 作用 | 你需要实现 |
|------|------|-----------|
| `GstBaseSrc` | 数据源（文件读取、摄像头采集等） | `read()` / `is_seekable()` |
| `GstBaseSink` | 数据接收端（视频显示、音频播放等） | `render()` / `start()` / `stop()` |
| `GstBaseTransform` | 帧到帧的转换（编解码、缩放等） | `transform_frame()` |
| `GstBaseParse` | 解析压缩格式（mp4/h264 等流） | `parse_frame()` + 格式识别 |
| `GstAggregator` | 多路数据聚合同步（音视频同步） | `aggregator_frame()` |

底层还有工具类：
- `GstCollectPads` —— 多 pad 数据收集复用
- `GstAdapter` —— 数据缓冲/peek/advance
- `GstDataQueue` —— pad 间的数据队列

**一句话总结：**
- `gst/` = 骨架和内脏（整个 GObject 类型体系、数据结构、调度机制）
- `libs/gst/base/` = 骨架的模具（常见插件类型的抽象父类，写插件时直接继承，不用从头实现）

---

## 三、GObject 与 GStreamer 的关系

### GObject 是独立的外部库

`gst/gst.h` 里只有一行：
```c
#include <glib.h>
```
而 `gst/gstobject.h` 里写的是：
```c
#include <glib-object.h>
```

这里的 `<>` 尖括号表示它不是项目自带的文件，而是系统安装的库。`glib` 和 `glib-object` 是一套独立的基础库（`libs/glib-2.0/`），GStreamer 是链接到它上面用的。可以用 `pkg-config --cflags glib-2.0` 看它装在哪。

而 `gstobject.h` 是 GStreamer 自己写的，它定义了 `GstObject` 类型，作为所有 GStreamer 对象的基类。看它的宏定义：

```c
#define GST_TYPE_OBJECT       (gst_object_get_type ())   // GObject 的类型注册
#define GST_OBJECT(obj)       (G_TYPE_CHECK_INSTANCE_CAST ((obj), GST_TYPE_OBJECT, GstObject))
```

这些都是 GObject 的机制（`G_TYPE_CHECK_INSTANCE_CAST` 等），`gstobject.h` 只是在 `glib-object.h` 的基础上包装了一层。

---

## 四、三个关键函数的真实位置

之前凭直觉找不到，是因为它们分散在不同文件里：

| 函数 | 文件 | 行号 |
|------|------|------|
| `gst_init()` | `gst/gst.c` | 451 |
| `gst_pipeline_new()` | `gst/gstpipeline.c` | 348 |
| `gst_element_link()` | `gst/gstutils.c` | 2276 |

### 为什么 `gst_element_link` 不在 `gstelement.c`？

GStreamer 的代码组织有个容易误导人的地方：
- `gstelement.c` / `gstelement.h` 是 `GstElement` 这个**类型**的定义（类结构、虚函数、属性）
- 但操作 element 的**便捷 API**（`link`、`link_many`、`seek`、`get_state` 等）大量被放进了 `gstutils.c`

所以"元素相关函数都在 `gstelement.c`"这个直觉是错的。`gstutils.c` 有 4000+ 行，是 GStreamer 最大的工具文件之一，很多日常调用的 API 都在那。

---

## 五、五个关键问题

### 问题1：`g_option_context_new("- GStreamer initialization")` 这种传字符串符号，是固定的吗？有符号表吗？容易出错吗？

这个字符串**不是符号，只是给人看的显示文字**。真正的"符号表"是另一回事。GStreamer 里有两类字符串：

**A. 显示用的字符串（随便写，错了只是显示难看）**

`g_option_context_new("- GStreamer initialization")` 这个参数只是 `--help` 时打印的标题。写 `"- xxx"` 也能编译运行，只是 help 输出难看。这类没有符号表，也不需要。

**B. 工厂名（有"符号表"，错了会运行失败）**

`gst_element_factory_make("pipeline", name)` 里的 `"pipeline"` 是**工厂名**，是真正的符号。它对应一个注册表。看 `gst/gst.c:614`：

```c
static gboolean
gst_register_core_elements (GstPlugin * plugin)
{
  /* register some standard builtin types */
  if (!gst_element_register (plugin, "bin", GST_RANK_PRIMARY,
          GST_TYPE_BIN) ||
      !gst_element_register (plugin, "pipeline", GST_RANK_PRIMARY,
          GST_TYPE_PIPELINE)
      )
    g_assert_not_reached ();

  return TRUE;
}
```

这就是"符号表"的注册过程。每个插件在 `gst_init()` 时通过 `gst_element_register(名字, 排名, GType)` 把自己注册进一个全局的 **registry（注册表）**。`gst_element_factory_make("pipeline", ...)` 就是去这个 registry 里按名字查工厂，查不到就返回 NULL（看 `gstelementfactory.c:749-766`）：

```c
factory = gst_element_factory_find (factoryname);   // 按名字查注册表
if (factory == NULL)
  goto no_factory;                                  // → "no such element factory!"
```

**容易出错吗？** 会的，但有两道防线：
1. 编译期：`GST_TYPE_PIPELINE` 这种是宏，类型错就编译不过
2. 运行期：名字拼错 → `gst_element_factory_find` 返回 NULL → 打 warning，不会崩

可以用 `gst-inspect-1.0` 命令看完整的注册表（所有可用工厂名）。

### 问题2：我在哪里找实现？

直觉"函数名 → 同名 .c 文件"在 GStreamer 里不成立。规律是：

| 类型 | 去哪找 |
|------|--------|
| `gst_xxx_new()` 等构造 | 通常在 `gstxxx.c`，但很多只是薄包装 |
| 操作元素的便捷函数（`link`/`seek`/`state`） | **`gstutils.c`**（不在 `gstelement.c`） |
| pad 相关 | `gstpad.c` |
| 工厂/创建 | `gstelementfactory.c` |

**最快的方法不是猜文件，而是直接 grep：**

```bash
grep -rn "^gst_element_link (" gst/
```

注意 `^` 锚定行首 + `(` 紧跟函数名，能精确匹配**定义**（定义都是顶格写、返回类型在上一行），过滤掉注释和调用点。

### 问题3：`gst_pipeline_new` 有必要深入进去看吗？里面大概什么样？

第一层没必要深看，但往下两层值得看一眼。它是个三层洋葱：

```
gst_pipeline_new("my")                          // gstpipeline.c:348  ← 薄包装
  └─ gst_element_factory_make("pipeline", "my") // gstelementfactory.c:819
       └─ gst_element_factory_make_full(...)     // :791
            └─ gst_element_factory_make_valist   // :738  ← 这里开始有干货
                 ├─ gst_element_factory_find("pipeline")  // 查注册表，拿到工厂
                 └─ gst_element_factory_create_valist     // :556  ← 真正创建
                      ├─ gst_plugin_feature_load(factory)  // 按需加载插件(.so)
                      └─ gst_element_factory_create_with_properties  // g_object_new 实例化
```

关键点在第 5、6 层（`gstelementfactory.c:556-602`）：

```c
gst_element_factory_create_valist (factory, first, properties)
{
  // 1. 确保插件代码已加载进内存（动态插件才需要 dlopen）
  newfactory = GST_ELEMENT_FACTORY(gst_plugin_feature_load(factory));

  // 2. 检查类型有效
  if (factory->type == G_TYPE_INVALID) goto no_type;

  // 3. 用 GObject 机制实例化对象（传属性）
  element = gst_element_factory_create_with_properties(factory, n, names, values);
}
```

**一句话：`gst_pipeline_new` = "去注册表里查名叫 pipeline 的工厂 → 加载它的插件 → 用 GObject `g_object_new` 造一个实例"。** 看到这一层就够了，再往下就是 GObject 的 `g_object_new`，那是 GLib 的事，不是 GStreamer 的。

### 问题4：`gst_element_link_pads` 里面是什么

也是洋葱，但这一层有真正的逻辑。`gstutils.c:2160`：

```c
gst_element_link_pads(src, NULL, dest, NULL)
  └─ gst_element_link_pads_full(src, NULL, dest, NULL, GST_PAD_LINK_CHECK_DEFAULT)
```

`gst_element_link_pads_full`（`gstutils.c:1844`）干三件事：

1. **找 src pad**（1866-1902）：传了 pad 名字就按名字找（`gst_element_get_static_pad`），没传就取第一个可用的 pad
2. **找 dest pad**（1905-1945）：同上，找 sink 方向的 pad
3. **连起来**（1951）：调 `pad_link_maybe_ghosting(srcpad, destpad, flags)`

再往下一层 `pad_link_maybe_ghosting`（`gstutils.c:1732`）→ `gst_pad_link_full`（`gstpad.c:2552`），这里才是真正建立连接的地方，核心几行：

```c
gst_pad_link_full (srcpad, sinkpad, flags)
{
  result = gst_pad_link_prepare(srcpad, sinkpad, flags);  // 检查方向、caps 兼容性

  GST_PAD_PEER(srcpad) = sinkpad;    // ← 互相记下对方，这就是"连接"
  GST_PAD_PEER(sinkpad) = srcpad;

  schedule_events(srcpad, sinkpad);   // 安排 sticky 事件重发

  srcfunc = GST_PAD_LINKFUNC(srcpad); // 调用 pad 自定义的 link 回调
  sinkfunc = GST_PAD_LINKFUNC(sinkpad);
  ...
}
```

**所谓"连接"的本质，就是两个 pad 互相在 `GST_PAD_PEER` 里存了对方的指针。** 之后 src pad 往下推数据时，就是通过这个 peer 指针找到 sink pad，调它的 chain 函数。

### 问题5：示例的底层调用展开（缩进展开）

把典型示例的每一行 API 往下展开到底层：

```
gst_init(&argc, &argv)
└─ gst_init_check(&argc, &argv, &err)              // gst.c:455 真正的初始化
   ├─ _priv_gst_init_seed()                          // 随机数种子
   ├─ gst_init_get_option_group()                    // 注册命令行选项
   ├─ gst_registry_init()                            // 建全局注册表
   ├─ gst_plugin_load_file(core插件)                  // 扫描/加载插件 .so
   └─ gst_register_core_elements()                   // gst.c:608 注册内置元素
      └─ gst_element_register("bin", GST_TYPE_BIN)
      └─ gst_element_register("pipeline", GST_TYPE_PIPELINE)   ← "pipeline"这个名字在这里进注册表

gst_pipeline_new("my-pipeline")
└─ gst_element_factory_make("pipeline", "my-pipeline")         // gstelementfactory.c:819
   └─ gst_element_factory_make_full("pipeline","name","my-pipeline",NULL) // :791
      └─ gst_element_factory_make_valist(...)                   // :738
         ├─ gst_element_factory_find("pipeline")                // 在注册表里查工厂
         └─ gst_element_factory_create_valist(factory,...)     // :556
            ├─ gst_plugin_feature_load(factory)                 // 确保插件已加载
            └─ gst_element_factory_create_with_properties       // → g_object_new(GST_TYPE_PIPELINE)
               └─ g_object_new(GType)                           // GLib 造对象(分配内存+设属性)

gst_element_factory_make("filesrc", "source")        // 同上流程,工厂名换成"filesrc"
└─ ... → gst_element_factory_find("filesrc") → g_object_new(GST_TYPE_FILESRC)

gst_bin_add_many(GST_BIN(pipeline), src, decodec, sink, NULL)
└─ gst_bin_add(GST_BIN(pipeline), src)              // 把元素挂到 pipeline 下做子元素
   └─ ... (decodec, sink 同理)

gst_element_link(src, decodec)                      // gstutils.c:2276
└─ gst_element_link_pads(src, NULL, decodec, NULL)  // :2160
   └─ gst_element_link_pads_full(src, NULL, decodec, NULL, ...)  // :1844
      ├─ 找 src 的 src-pad (取第一个可用的)
      ├─ 找 decodec 的 sink-pad (取第一个可用的)
      └─ pad_link_maybe_ghosting(srcpad, destpad, flags)         // :1732
         └─ gst_pad_link_full(srcpad, sinkpad, flags)            // gstpad.c:2552  ← 真正连接
            ├─ gst_pad_link_prepare()    // 检查方向+caps 兼容
            ├─ GST_PAD_PEER(srcpad) = sinkpad   // ← 互相记下对方
            ├─ GST_PAD_PEER(sinkpad) = srcpad
            ├─ schedule_events()          // 安排 sticky 事件
            └─ 调 src/sink pad 的 LINKFUNC 回调

gst_element_link(decodec, sink)                     // 同上,把 decodec→sink 也连上

gst_element_set_state(pipeline, GST_STATE_PLAYING)  // 状态切换,开始调度
└─ (触发各元素 state change → 数据开始通过上面建立的 peer 指针流动)

GstBus *bus = gst_pipeline_get_bus(pipeline)        // 拿总线
└─ gst_bus_timed_pop_filtered(bus, ...)             // 阻塞等消息(错误/结束)
```

**三个关键点：**

1. **`gst_init`** → 建注册表 + 把 `"pipeline"`/`"bin"` 这些名字注册进去（这就是"符号表"，确实存在，叫 registry）
2. **`gst_element_factory_make`** → 查注册表 → `g_object_new` 造对象。所有 `make("xxx")` 都是这套流程
3. **`gst_element_link`** → 找两个 pad → `GST_PAD_PEER` 互指。**数据流动就是靠这个 peer 指针**，之后 src 推数据时顺着 peer 找到 sink 的 chain 函数往下传

---

## 六、数据到底怎么流动：`set_state(PLAYING)` 之后的 push/chain 链路

前面只画到 `set_state(PLAYING)`，那之后数据是怎么从 src 一路流到 sink 的？核心在 `gst_pad_push` / `gst_pad_chain` 这一对函数。

### `gst_element_set_state` —— 触发状态切换

`gstelement.c:2922`：

```c
gst_element_set_state (GstElement * element, GstState state)
{
  oclass = GST_ELEMENT_GET_CLASS (element);
  if (oclass->set_state)
    result = (oclass->set_state) (element, state);   // 调用类虚函数
  return result;
}
```

它调用 `oclass->set_state`（默认实现 `gst_element_set_state_func`，`gstelement.c:2946`），后者计算状态转换（如 `NULL→READY→PAUSED→PLAYING`），对每个子元素递归调用 `change_state`。状态到 `PLAYING` 后，数据源（如 `filesrc`）的 task 线程被启动，开始调用 `gst_pad_push` 往下游推数据。

### `gst_pad_push` —— src pad 推数据

`gstpad.c:5008`：

```c
gst_pad_push (GstPad * pad, GstBuffer * buffer)
{
  res = gst_pad_push_data (pad,
      GST_PAD_PROBE_TYPE_BUFFER | GST_PAD_PROBE_TYPE_PUSH, buffer);
  return res;
}
```

### `gst_pad_push_data` —— 真正的推数据核心

`gstpad.c:4840`，这是数据流动的**心脏**。关键几行：

```c
gst_pad_push_data (GstPad * pad, GstPadProbeType type, void *data)
{
  GST_OBJECT_LOCK (pad);
  if (G_UNLIKELY (GST_PAD_IS_FLUSHING (pad))) goto flushing;   // 检查是否 flushing
  if (G_UNLIKELY (GST_PAD_IS_EOS (pad)))     goto eos;          // 检查是否 EOS
  if (G_UNLIKELY (GST_PAD_MODE (pad) != GST_PAD_MODE_PUSH)) goto wrong_mode;

  if ((ret = check_sticky (pad, NULL)) != GST_FLOW_OK) goto events_error;  // sticky 事件检查

  PROBE_HANDLE (pad, type | GST_PAD_PROBE_TYPE_BLOCK, data, ...);  // block probe
  PROBE_HANDLE (pad, type, data, ...);                              // 普通 probe

  if (G_UNLIKELY ((peer = GST_PAD_PEER (pad)) == NULL))           // ← 取出连接时存的 peer
    goto not_linked;

  gst_object_ref (peer);
  GST_OBJECT_UNLOCK (pad);

  ret = gst_pad_chain_data_unchecked (peer, type, data);          // ← 把数据交给 peer 的 chain
  ...
}
```

**核心就是两步（`gstpad.c:4890` 和 `4898`）：**
1. `peer = GST_PAD_PEER(pad)` —— 取出 link 时存的对端 pad 指针
2. `gst_pad_chain_data_unchecked(peer, type, data)` —— 调对端 pad 的 chain 函数，数据就这么传过去了

### `gst_pad_chain` —— sink pad 接数据

`gstpad.c:4749`：

```c
gst_pad_chain (GstPad * pad, GstBuffer * buffer)
{
  return gst_pad_chain_data_unchecked (pad,
      GST_PAD_PROBE_TYPE_BUFFER | GST_PAD_PROBE_TYPE_PUSH, buffer);
}
```

`gst_pad_chain_data_unchecked` 最终会调用 sink pad 上注册的 chain 函数（`GST_PAD_CHAINFUNC`），也就是下游元素（如 decoder）处理这帧数据的逻辑。处理完后，下游元素再用自己的 src pad 调 `gst_pad_push`，把数据继续往更下游推——如此递归，直到 sink 元素（如 `autovideosink`）渲染。

### 完整的数据流动闭环

```
[filesrc 元素] 启动 task 线程, 读取一帧
   │
   └─ gst_pad_push(srcpad, buffer)                    // gstpad.c:5008
      └─ gst_pad_push_data(srcpad, ...)                // gstpad.c:4840
         ├─ 检查 flushing / EOS / mode / sticky 事件
         ├─ 跑 probe (block + 普通)
         ├─ peer = GST_PAD_PEER(srcpad)                // 取出 link 时存的对端 ← 关键
         └─ gst_pad_chain_data_unchecked(peer, ...)    // 调对端的 chain  ← 数据跨元素
            └─ GST_PAD_CHAINFUNC(peer)(peer, buffer)   // = decoder 的处理函数
               │
               [decoder 元素] 解码这一帧
               │
               └─ gst_pad_push(decoder的srcpad, decoded)   // 解码完,继续往下游推
                  └─ gst_pad_push_data(...)
                     ├─ peer = GST_PAD_PEER(...)
                     └─ gst_pad_chain_data_unchecked(peer, ...)
                        └─ GST_PAD_CHAINFUNC(peer)(...)     // = sink 的处理函数
                           │
                           [sink 元素] render() 渲染/播放
```

**所以"流水线"的本质就是：**
- **link 阶段**：两个 pad 互相在 `GST_PAD_PEER` 里存对方指针（`gstpad.c:2589-2590`）
- **运行阶段**：上游 `gst_pad_push` → 取 peer → 调 peer 的 chain → 下游处理 → 下游再 push 自己的 src → 取 peer → ... 一路递归到最终 sink

数据不是被某个中央调度器搬运的，而是**每个元素主动 push，顺着 peer 指针一站站往下传**。这就是 GStreamer "pipeline" 真正跑起来的机制。

---

## 附：关键函数索引（按调用顺序）

| 阶段 | 函数 | 文件:行号 |
|------|------|-----------|
| 初始化 | `gst_init` | `gst/gst.c:451` |
| 初始化 | `gst_init_check` | `gst/gst.c` |
| 注册 | `gst_register_core_elements` | `gst/gst.c:608` |
| 注册 | `gst_element_register` | `gst/gstelementfactory.c` |
| 创建 | `gst_pipeline_new` | `gst/gstpipeline.c:348` |
| 创建 | `gst_element_factory_make` | `gst/gstelementfactory.c:819` |
| 创建 | `gst_element_factory_make_full` | `gst/gstelementfactory.c:791` |
| 创建 | `gst_element_factory_make_valist` | `gst/gstelementfactory.c:738` |
| 创建 | `gst_element_factory_create_valist` | `gst/gstelementfactory.c:556` |
| 连接 | `gst_element_link` | `gst/gstutils.c:2276` |
| 连接 | `gst_element_link_pads` | `gst/gstutils.c:2160` |
| 连接 | `gst_element_link_pads_full` | `gst/gstutils.c:1844` |
| 连接 | `pad_link_maybe_ghosting` | `gst/gstutils.c:1732` |
| 连接 | `gst_pad_link_full` | `gst/gstpad.c:2552` |
| 状态 | `gst_element_set_state` | `gst/gstelement.c:2922` |
| 状态 | `gst_element_set_state_func` | `gst/gstelement.c:2946` |
| 数据流 | `gst_pad_push` | `gst/gstpad.c:5008` |
| 数据流 | `gst_pad_push_data` | `gst/gstpad.c:4840` |
| 数据流 | `gst_pad_chain` | `gst/gstpad.c:4749` |
| 数据流 | `gst_pad_chain_data_unchecked` | `gst/gstpad.c` |
