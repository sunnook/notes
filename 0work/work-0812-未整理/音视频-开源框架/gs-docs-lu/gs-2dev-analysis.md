# GStreamer 1.29 二次开发分析

> 本文档面向"想基于 GStreamer 1.29.2 做定制化 / 二次开发"的工程师。
> 配套的 `gstream-design-analysis.md` 回答" GStreamer 是什么"，本文回答
> **"我要改/扩 GStreamer，该动哪里、怎么动、动哪些文件和类"**。
>
> 代码基线：`gstreamer-1.29.2`（核心库 `gst/` + `libs/gst/base` 等扩展库 +
> `plugins/elements` 核心元素 + `plugins/tracers` 追踪器）。本文不涉及
> `gst-plugins-base/good/bad` 等外部插件仓库，但会说明其边界。

---

## 目录
<!-- 行号为当前文档定位，锚点可点击跳转 -->

- [0. 文档定位与读者画像](#0-文档定位与读者画像) — L149
  - [0.1 你是谁](#01-你是谁) — L151
  - [0.2 本文档与已有文档的分工](#02-本文档与已有文档的分工) — L159
  - [0.3 阅读建议](#03-阅读建议) — L170
- [1. 二次开发全景图（扩展点矩阵）](#1-二次开发全景图扩展点矩阵) — L182
  - [1.1 扩展点总表](#11-扩展点总表) — L188
  - [1.2 侵入度分级](#12-侵入度分级) — L210
  - [1.3 选择扩展点的三条经验法则](#13-选择扩展点的三条经验法则) — L220
- [2. 入口与构建：如何把你的代码编进去](#2-入口与构建如何把你的代码编进去) — L229
  - [2.1 两种集成姿势](#21-两种集成姿势) — L231
  - [2.2 插件入口约定](#22-插件入口约定) — L240
  - [2.3 Element 注册宏族（1.20+ 推荐机制）](#23-element-注册宏族120+-推荐机制) — L269
  - [2.4 插件发现与加载链路](#24-插件发现与加载链路) — L292
  - [2.5 最小外部插件 meson.build 模板](#25-最小外部插件-mesonbuild-模板) — L310
  - [2.6 静态链接（特殊场景）](#26-静态链接特殊场景) — L335
- [3. 核心数据结构速查（二次开发必背）](#3-核心数据结构速查二次开发必背) — L343
  - [3.1 对象体系（GstObject 系，有名字、有父、有锁）](#31-对象体系gstobject-系有名字有父有锁) — L348
  - [3.2 GstElementClass 虚函数表 — `gst/gstelement.h:1040`](#32-gstelementclass-虚函数表-gstgstelementh1040) — L397
  - [3.3 Pad — `gst/gstpad.h:764`（数据传输核心）](#33-pad-gstgstpadh764数据传输核心) — L433
  - [3.4 数据对象体系（GstMiniObject 系，引用计数、COW）](#34-数据对象体系gstminiobject-系引用计数cow) — L467
  - [3.5 协商与控制对象](#35-协商与控制对象) — L528
  - [3.6 时钟与任务](#36-时钟与任务) — L539
  - [3.7 速查：开发时"只读 / 要写 / 要 override"](#37-速查开发时"只读-要写-要-override") — L549
- [4. 类图与继承体系（开发视角）](#4-类图与继承体系开发视角) — L564
  - [4.1 对象继承主树（GstObject 系）](#41-对象继承主树gstobject-系) — L569
  - [4.2 数据对象树（GstMiniObject 系）](#42-数据对象树gstminiobject-系) — L593
  - [4.3 基类选择决策表（核心！）](#43-基类选择决策表核心) — L608
  - [4.4 UML 风格类图（开发子树，标注 vfunc）](#44-uml-风格类图开发子树标注-vfunc) — L620
  - [4.5 继承的代码模式（GObject 标准三件套）](#45-继承的代码模式gobject-标准三件套) — L667
- [5. 数据流图（开发视角：数据经过你的代码时发生了什么）](#5-数据流图开发视角数据经过你的代码时发生了什么) — L712
  - [5.1 Push 模式（主流）：上游主动推](#51-push-模式主流上游主动推) — L716
  - [5.2 Pull 模式：下游主动拉](#52-pull-模式下游主动拉) — L745
  - [5.3 Buffer 生命周期与引用计数（开发必懂）](#53-buffer-生命周期与引用计数开发必懂) — L764
  - [5.4 Caps 协商流程（你的钩子在哪）](#54-caps-协商流程你的钩子在哪) — L782
  - [5.5 Event / Query 流（控制信息，非数据）](#55-event-query-流控制信息非数据) — L805
- [6. 分层控制流图（状态机 + 线程 + 内存）](#6-分层控制流图状态机-+-线程-+-内存) — L822
  - [6.1 状态机与你的 start/stop 时机](#61-状态机与你的-startstop-时机) — L824
  - [6.2 线程架构（关键：你的 vfunc 跑在哪个线程）](#62-线程架构关键你的-vfunc-跑在哪个线程) — L857
  - [6.3 内存架构（GstMemory → GstAllocator → GstBufferPool）](#63-内存架构gstmemory-→-gstallocator-→-gstbufferpool) — L904
  - [6.4 控制流分层总览](#64-控制流分层总览) — L947
- [7. 开发方向一：写一个 Transform Element（完整案例）](#7-开发方向一写一个-transform-element完整案例) — L965
  - [7.1 选父类：GstBaseTransform](#71-选父类gstbasetransform) — L970
  - [7.2 头文件 `myfilter.h`](#72-头文件-myfilterh) — L986
  - [7.3 源文件 `myfilter.c`（完整骨架）](#73-源文件-myfilterc完整骨架) — L1017
  - [7.4 插件入口 `myplugin.c`](#74-插件入口-mypluginc) — L1160
  - [7.5 meson.build](#75-mesonbuild) — L1177
  - [7.6 验证](#76-验证) — L1191
  - [7.7 涉及文件/类清单](#77-涉及文件类清单) — L1200
  - [7.8 踩坑清单](#78-踩坑清单) — L1211
- [8. 开发方向二：写一个 Src Element（完整案例）](#8-开发方向二写一个-src-element完整案例) — L1228
  - [8.1 选父类：GstBaseSrc vs GstPushSrc](#81-选父类gstbasesrc-vs-gstpushsrc) — L1232
  - [8.2 完整骨架 `mysrc.c`（产生递增计数测试流）](#82-完整骨架-mysrcc产生递增计数测试流) — L1242
  - [8.3 关键点说明](#83-关键点说明) — L1349
  - [8.4 涉及文件/类清单](#84-涉及文件类清单) — L1358
  - [8.5 踩坑](#85-踩坑) — L1367
- [9. 开发方向三：写一个 Sink Element（完整案例）](#9-开发方向三写一个-sink-element完整案例) — L1381
  - [9.1 选父类：GstBaseSink](#91-选父类gstbasesink) — L1385
  - [9.2 完整骨架 `mysink.c`（把数据写到自定义目标）](#92-完整骨架-mysinkc把数据写到自定义目标) — L1402
  - [9.3 同步渲染 vs 异步](#93-同步渲染-vs-异步) — L1488
  - [9.4 涉及文件/类清单](#94-涉及文件类清单) — L1497
  - [9.5 踩坑](#95-踩坑) — L1505
- [10. 开发方向四：多输入聚合 / 多输出分发](#10-开发方向四多输入聚合-多输出分发) — L1517
  - [10.1 何时用什么](#101-何时用什么) — L1519
  - [10.2 GstAggregator（推荐的多路合流基类）](#102-gstaggregator推荐的多路合流基类) — L1529
  - [10.3 骨架 `myaggregator.c`（双路拼接）](#103-骨架-myaggregatorc双路拼接) — L1548
  - [10.4 何时该用 Aggregator 而不是手搓](#104-何时该用-aggregator-而不是手搓) — L1600
  - [10.5 参考实现](#105-参考实现) — L1606
- [11. 开发方向五：自定义 GstMeta（给 Buffer 挂私有数据）](#11-开发方向五自定义-gstmeta给-buffer-挂私有数据) — L1615
  - [11.1 场景](#111-场景) — L1617
  - [11.2 两种注册方式](#112-两种注册方式) — L1628
  - [11.3 传统 GstMeta 完整骨架](#113-传统-gstmeta-完整骨架) — L1638
  - [11.4 Custom Meta（更简单）](#114-custom-meta更简单) — L1716
  - [11.5 与 BufferPool 的 clear_func 配合](#115-与-bufferpool-的-clearfunc-配合) — L1732
  - [11.6 踩坑](#116-踩坑) — L1737
- [12. 开发方向六：自定义 Allocator / BufferPool（内存架构定制）](#12-开发方向六自定义-allocator-bufferpool内存架构定制) — L1748
  - [12.1 场景](#121-场景) — L1750
  - [12.2 GstAllocator（`gst/gstallocator.h:160`）](#122-gstallocatorgstgstallocatorh160) — L1757
  - [12.3 完整骨架（包裹外部内存的 Allocator）](#123-完整骨架包裹外部内存的-allocator) — L1769
  - [12.4 GstBufferPool（`gst/gstbufferpool.c`）](#124-gstbufferpoolgstgstbufferpoolc) — L1808
  - [12.5 decide_allocation / propose_allocation 钩子](#125-decideallocation-proposeallocation-钩子) — L1833
  - [12.6 涉及文件/类清单](#126-涉及文件类清单) — L1842
  - [12.7 踩坑](#127-踩坑) — L1851
- [13. 开发方向七：自定义 Tracer（性能/行为追踪）](#13-开发方向七自定义-tracer性能行为追踪) — L1862
  - [13.1 场景](#131-场景) — L1864
  - [13.2 机制](#132-机制) — L1874
  - [13.3 可用钩子（部分，见 `plugins/tracers/gststats.c`）](#133-可用钩子部分见-pluginstracersgststatsc) — L1883
  - [13.4 完整骨架 `mytracer.c`](#134-完整骨架-mytracerc) — L1896
  - [13.5 激活方式](#135-激活方式) — L1934
  - [13.6 参考实现](#136-参考实现) — L1944
  - [13.7 踩坑](#137-踩坑) — L1952
- [14. 开发方向八：自定义时钟 / 控制源 / 设备提供 / TypeFind](#14-开发方向八自定义时钟-控制源-设备提供-typefind) — L1961
  - [14.1 自定义 GstClock（外部时钟同步）](#141-自定义-gstclock外部时钟同步) — L1965
  - [14.2 自定义 GstControlSource（属性动画）](#142-自定义-gstcontrolsource属性动画) — L1986
  - [14.3 自定义 GstDeviceProvider（设备发现）](#143-自定义-gstdeviceprovider设备发现) — L2005
  - [14.4 自定义 GstTypeFind（格式探测）](#144-自定义-gsttypefind格式探测) — L2036
- [15. 开发方向九：应用层定制（不碰核心）](#15-开发方向九应用层定制不碰核心) — L2060
  - [15.1 动态插拔 Pad](#151-动态插拔-pad) — L2064
  - [15.2 Pad Probe（拦截/改写/丢弃数据，不写 element）](#152-pad-probe拦截改写丢弃数据不写-element) — L2089
  - [15.3 Bus 消息处理](#153-bus-消息处理) — L2125
  - [15.4 launch 字符串 + 手动组合混合](#154-launch-字符串-+-手动组合混合) — L2148
  - [15.5 何时用应用层定制而非写插件](#155-何时用应用层定制而非写插件) — L2157
- [16. 修改核心库本身（高侵入，慎用）](#16-修改核心库本身高侵入慎用) — L2168
  - [16.1 何时该改 `gst/` 内部](#161-何时该改-gst-内部) — L2170
  - [16.2 改动点示例（仅说明，不鼓励）](#162-改动点示例仅说明不鼓励) — L2182
  - [16.3 ABI 兼容与维护](#163-abi-兼容与维护) — L2190
  - [16.4 替代方案优先级](#164-替代方案优先级) — L2198
- [17. 二次开发常见陷阱与最佳实践](#17-二次开发常见陷阱与最佳实践) — L2208
  - [17.1 线程](#171-线程) — L2212
  - [17.2 引用计数](#172-引用计数) — L2221
  - [17.3 Caps 协商](#173-caps-协商) — L2230
  - [17.4 状态机](#174-状态机) — L2238
  - [17.5 Buffer 可写性](#175-buffer-可写性) — L2246
  - [17.6 错误传播](#176-错误传播) — L2254
  - [17.7 日志](#177-日志) — L2261
  - [17.8 测试](#178-测试) — L2275
- [18. 开发决策树（我该选哪条路）](#18-开发决策树我该选哪条路) — L2284
- [19. 你可能没考虑到的（补充）](#19-你可能没考虑到的补充) — L2343
  - [19.1 国际化（i18n）](#191-国际化i18n) — L2347
  - [19.2 调试体系](#192-调试体系) — L2359
  - [19.3 插件版本与 registry 缓存](#193-插件版本与-registry-缓存) — L2369
  - [19.4 跨平台差异](#194-跨平台差异) — L2377
  - [19.5 与外部生态的边界](#195-与外部生态的边界) — L2389
  - [19.6 语言绑定（introspection）](#196-语言绑定introspection) — L2406
  - [19.7 安全](#197-安全) — L2413
  - [19.8 性能](#198-性能) — L2420
  - [19.9 许可证（LGPL vs GPL）](#199-许可证lgpl-vs-gpl) — L2430
  - [19.10 文档生成](#1910-文档生成) — L2438
- [20. 附录](#20-附录) — L2447
  - [20.1 核心文件 → 二次开发相关度速查](#201-核心文件-→-二次开发相关度速查) — L2449
  - [20.2 基类 vfunc 速查](#202-基类-vfunc-速查) — L2487
  - [20.3 环境变量速查](#203-环境变量速查) — L2511
  - [20.4 术语表](#204-术语表) — L2525
- [结语](#结语) — L2551

---

## 0. 文档定位与读者画像

### 0.1 你是谁

本文假设你：

1. 有 C 和 GObject 类型系统基础（知道 `G_DEFINE_TYPE`、虚函数表、引用计数）；
2. 已读过 `gstream-design-analysis.md`，理解 Element/Pad/Buffer/Caps/Pipeline/Bus 的概念；
3. 现在的目标是**动手**：要么写一个新 Element，要么改核心行为，要么在应用层做定制。

### 0.2 本文档与已有文档的分工

| 维度 | `gstream-design-analysis.md` | 本文 `gs-2dev-analysis.md` |
|------|------------------------------|----------------------------|
| 视角 | 架构通论（是什么） | 开发操作（怎么改） |
| 重点 | 类图、数据流、控制流 | 扩展点、父类选择、完整案例、踩坑 |
| 产出 | 理解 | 可运行的代码骨架 |
| 读者 | 学习者 | 实施者 |

两份文档互补：先读通论建立心智模型，再用本文落地。

### 0.3 阅读建议

- 想快速定位"我该动哪里" → 先读 §1 全景图与 §18 决策树；
- 想写一个 filter → §7；
- 想写一个源/宿 → §8 / §9；
- 想给 Buffer 挂私有数据 → §11；
- 想做零拷贝/硬件内存 → §12；
- 想做性能追踪 → §13；
- 只想在应用里加逻辑、不编译插件 → §15。

---

## 1. 二次开发全景图（扩展点矩阵）

GStreamer 的设计哲学是**"核心小、扩展点多"**。核心库 `gst/` 只提供基础设施，
几乎所有功能都通过插件/子类注入。下面这张矩阵是全文的索引——先建立
"需求 → 扩展点 → 涉及文件/类 → 侵入度"的直觉。

### 1.1 扩展点总表

| # | 扩展点 | 典型场景 | 主要父类/接口 | 涉及文件/类 | 侵入度 |
|---|--------|----------|---------------|-------------|--------|
| 1 | 新 Element（filter） | 视频滤镜、音频处理、数据打戳 | `GstBaseTransform` | `libs/gst/base/gstbasetransform.*` | 低（外部插件） |
| 2 | 新 Element（source） | 网络/硬件/共享内存取数据 | `GstBaseSrc`/`GstPushSrc` | `libs/gst/base/gstbasesrc.*`、`gstpushsrc.*` | 低 |
| 3 | 新 Element（sink） | 硬件显示、网络输出、自定义封装 | `GstBaseSink` | `libs/gst/base/gstbasesink.*` | 低 |
| 4 | 新 Element（多路聚合） | 多路视频合流、混音 | `GstAggregator` | `libs/gst/base/gstaggregator.*` | 低 |
| 5 | 新 Element（解析器） | 新容器格式解析 | `GstBaseParse` | `libs/gst/base/gstbaseparse.*` | 低 |
| 6 | 新 Plugin（打包） | 多个 Element 一起发布 | `GstPlugin` | `gst/gstplugin.*` + `GST_PLUGIN_DEFINE` | 低 |
| 7 | 自定义 Pad / Pad Probe | 拦截、改写、丢弃数据 | `GstPad` probes | `gst/gstpad.*` | 极低（应用层） |
| 8 | 自定义 GstMeta | AI 推理结果、硬件时间戳 | `GstMetaInfo` | `gst/gstmeta.*` | 低 |
| 9 | 自定义 GstAllocator | DMA-Buf、GPU 显存、物理内存 | `GstAllocator` | `gst/gstallocator.*`、`gstmemory.*` | 中 |
| 10 | 自定义 GstBufferPool | 缓冲池策略、预分配 | `GstBufferPool` | `gst/gstbufferpool.*` | 中 |
| 11 | 自定义 GstClock | 外部硬件时钟、PTP/自定义同步 | `GstClock` | `gst/gstclock.*`、`gstsystemclock.*` | 中 |
| 12 | 自定义 GstControlSource | 属性动画、自动化曲线 | `GstControlSource` | `libs/gst/controller/*` | 低 |
| 13 | 自定义 GstTracer | 吞吐/延迟/丢帧统计、自定义指标 | `GstTracer` | `gst/gsttracer.*`、`plugins/tracers/*` | 低 |
| 14 | 自定义 GstDeviceProvider | 设备热插拔发现 | `GstDeviceProvider` | `gst/gstdeviceprovider.*` | 中 |
| 15 | 自定义 GstTypeFind | 新容器/格式探测 | `GstTypeFind` | `gst/gsttypefind.*`、`libs/gst/base/gsttypefindhelper.*` | 低 |
| 16 | 修改核心库本身 | 协议级改动、核心性能瓶颈 | — | `gst/gstpad.c`、`gstbin.c` 等 | **高** |
| 17 | 应用层定制 | 动态插拔、消息处理、组合 | — | 只用公开 API | 极低 |

### 1.2 侵入度分级

- **极低**：只用公开 API，不编译任何东西，写在你的 `main()` 里（§15）。
- **低**：写一个外部插件 `.so`，通过 `GST_PLUGIN_PATH` 加载，核心库零修改（§7–§14 大部分）。
- **中**：仍可外部插件化，但需要较深理解核心机制（内存、时钟、设备）（§9–§11、§14）。
- **高**：直接改 `gst/` 内部源码并重新编译核心库，影响 ABI、维护成本高（§16）。

> **第一原则**：能用外部插件解决的，绝不改核心库。GStreamer 的全部设计都在
> 鼓励你把定制逻辑放在插件里。只有协议级语义改动或核心瓶颈才考虑动 `gst/`。

### 1.3 选择扩展点的三条经验法则

1. **处理数据 → 写 Element**。数据流过你的代码，就继承基类（§7–§10）。
2. **伴随数据但不改数据 → 写 Meta 或 Probe**。只想给 Buffer 贴标签或观察流量，
   用 GstMeta（§11）或 Pad Probe（§15），比写 Element 轻得多。
3. **不碰数据流，只做观测/控制 → 写 Tracer / ControlSource / Clock**（§13、§12、§11）。

---

## 2. 入口与构建：如何把你的代码编进去

### 2.1 两种集成姿势

| 姿势 | 说明 | 适用 |
|------|------|------|
| **外部插件仓库** | 独立 meson 项目，编译出 `libgst<name>.so`，靠 `GST_PLUGIN_PATH` 被发现 | 99% 的二次开发 |
| **核心 subproject** | 把你的代码作为 `gstreamer` 的子目录编进核心 | 需要改核心或随核心一起分发 |

绝大多数情况下选**外部插件**。下面以外部插件为主讲构建。

### 2.2 插件入口约定

每个插件 `.so` 必须导出一个 `plugin_init`，并用 `GST_PLUGIN_DEFINE` 声明元数据。
参考 `plugins/elements/gstcoreelementsplugin.c`：

```c
// plugins/elements/gstcoreelementsplugin.c
static gboolean
plugin_init (GstPlugin * plugin)
{
  gboolean ret = FALSE;
  ret |= GST_ELEMENT_REGISTER (capsfilter, plugin);
  ret |= GST_ELEMENT_REGISTER (fakesrc, plugin);
  ret |= GST_ELEMENT_REGISTER (queue, plugin);
  // ... 每个元素一个 GST_ELEMENT_REGISTER
  return ret;
}

GST_PLUGIN_DEFINE (GST_VERSION_MAJOR, GST_VERSION_MINOR, coreelements,
    "GStreamer core elements", plugin_init, VERSION, GST_LICENSE,
    GST_PACKAGE_NAME, GST_PACKAGE_ORIGIN);
```

要点：
- `GST_PLUGIN_DEFINE`（`gst/gstplugin.h:255`）展开为一个导出符号
  `gst_plugin_name_get_desc`，核心 registry 扫描时通过 `dlopen`+`dlsym` 找到它。
- `plugin_init` 在插件被加载时调用一次，负责把所有 Element 注册进 registry。
- `GST_VERSION_MAJOR/MINOR` 必须与核心库版本匹配，否则加载被拒绝（版本闸门）。

### 2.3 Element 注册宏族（1.20+ 推荐机制）

老写法是在 `plugin_init` 里直接调 `gst_element_register(plugin, name, rank, GType)`。
1.20 起推荐用宏族（`gst/gstelement.h:67–165`），把"定义注册函数"和"调用注册函数"分离：

```c
// 1) 在元素 .c 文件里定义注册函数（生成 gst_element_register_<name>）
GST_ELEMENT_REGISTER_DEFINE (my_filter, "my-filter", GST_RANK_NONE,
    GST_TYPE_MY_FILTER);

// 2) 在 plugin_init 里调用它
GST_ELEMENT_REGISTER (my_filter, plugin);
```

宏族成员：
- `GST_ELEMENT_REGISTER_DEFINE(e, e_n, rank, type)` — 定义 `gst_element_register_e()`；
- `GST_ELEMENT_REGISTER_DEFINE_WITH_CODE(...)` — 注册前插入自定义代码；
- `GST_ELEMENT_REGISTER_DECLARE(element)` — 在头文件声明注册函数；
- `GST_ELEMENT_REGISTER(element, plugin)` — 调用注册函数。

好处：一个插件里多个元素时，每个元素自包含注册逻辑，`plugin_init` 只需罗列
`GST_ELEMENT_REGISTER(x, plugin)`，与 `gstcoreelementsplugin.c` 的写法一致。

### 2.4 插件发现与加载链路

```
gst_init()
 └── gst_update_registry()
      └── gst_registry_scan_path()
           ├── 扫描 GST_PLUGIN_PATH / 默认目录下的 .so
           ├── dlopen() 每个 .so
           ├── dlsym("gst_plugin_name_get_desc")  ← GST_PLUGIN_DEFINE 生成
           ├── 版本/许可证检查
           └── plugin_init() → gst_element_register() → 写入 registry
```

- 注册表会被**二进制序列化**到 `~/.cache/gstreamer-1.0/registry-*.bin`
  （`gst/gstregistrybinary.c`），下次启动直接 mmap，不必重新扫描。
- 改了插件后若没生效，删掉 registry 缓存或设 `GST_REGISTRY_UPDATE=1`。
- `GST_PLUGIN_PATH` 追加你的插件目录；`GST_PLUGIN_SYSTEM_PATH` 覆盖默认路径。

### 2.5 最小外部插件 meson.build 模板

```meson
project('gst-my-plugins', 'c',
  version: '1.0.0',
  meson_version: '>= 0.63',
  default_options: ['c_std=gnu11'])

gst_dep = dependency('gstreamer-1.0', version: '>= 1.20')
gst_base_dep = dependency('gstreamer-base-1.0')

shared_library('gstmyplugins',
  sources: ['myfilter.c', 'mysrc.c', 'myplugin.c'],
  dependencies: [gst_dep, gst_base_dep],
  install: true,
  install_dir: gst_dep.get_variable('pluginsdir'),
  name_prefix: 'gst',  # 必须 gst 开头才会被扫描
)
```

关键点：
- `name_prefix: 'gst'` — 生成 `libgstmyplugins.so`，registry 只扫描 `gst*` 前缀；
- `install_dir` 用 `gst_dep.get_variable('pluginsdir')` 装到 GStreamer 插件目录；
- 依赖 `gstreamer-1.0`（核心）和 `gstreamer-base-1.0`（基类）。

### 2.6 静态链接（特殊场景）

若要把插件静态编进应用（嵌入式/闭源分发），参考 `README.static-linking`：
用 `GST_PLUGIN_STATIC_REGISTER` 宏在 `main` 里手动调用每个插件的
`gst_plugin_register_<name>`，跳过 dlopen 路径。代价是失去运行时换插件灵活性。

---

## 3. 核心数据结构速查（二次开发必背）

本章只列**开发时真正要碰的字段**，并标注你通常的角色：只读 / 要写 / 要 override。
完整字段见 `gstream-design-analysis.md` §4。结构体定义位置以 `gst/` 为根。

### 3.1 对象体系（GstObject 系，有名字、有父、有锁）

#### GstObject — `gst/gstobject.h:220`

```c
struct _GstObject {
  GInitiallyUnowned object;   // GObject 基类（floating ref）
  GMutex         lock;        // 对象锁（GST_OBJECT_LOCK）
  gchar         *name;        // 对象名
  GstObject     *parent;      // 弱引用父对象
  guint32        flags;        // GST_OBJECT_FLAGS
  GList         *control_bindings; // GstControlBinding 列表（属性动画）
  guint64        control_rate;
  guint64        last_sync;
};
```

- 你通常：**只读**。极少直接继承 GstObject（一般继承 GstElement）。
- 关键操作：`gst_object_ref/unref`（引用计数）、`GST_OBJECT_LOCK/UNLOCK`（锁）。

#### GstElement — `gst/gstelement.h:974`

```c
struct _GstElement {
  GstObject             object;
  GRecMutex             state_lock;   // 状态机递归锁
  GCond                 state_cond;   // 状态完成条件变量
  GstState              target_state, current_state, next_state, pending_state;
  GstBus               *bus;          // 消息总线
  GstClock             *clock;
  GstClockTimeDiff      base_time;    // PLAYING 时钟基准
  GstClockTime          start_time;
  guint16               numpads;      GList *pads;       // 所有 pad
  guint16               numsrcpads;   GList *srcpads;
  guint16               numsinkpads;  GList *sinkpads;
  guint32               pads_cookie;
  GList                *contexts;
};
```

- 你通常：**继承它**（通过基类），**override Class 的 vfunc**。
- 实例字段几乎不直接写；Class 的虚函数表才是你 override 的目标（见 §3.2）。

#### GstBin — `gst/gstbin.h:134` / GstPipeline — `gst/gstpipeline.c`

GstBin 在 GstElement 基础上加了 `children` 列表 + `child_bus`。
GstPipeline 在 GstBin 基础上加了顶层 `bus`、`clock`、`auto_flush_bus`。
- 你通常：**只组合**（`gst_bin_add/remove`），极少继承。自定义 Bin 仅当你要封装固定子拓扑。

### 3.2 GstElementClass 虚函数表 — `gst/gstelement.h:1040`

这是写 Element 时**最常 override 的地方**。关键 vfunc：

```c
struct _GstElementClass {
  GstObjectClass parent_class;
  gpointer       metadata;            // 元数据（作者、描述…）
  GstElementFactory *elementfactory; // 工厂指针
  GList         *padtemplates;        // Pad 模板列表

  // —— 信号（少用）——
  void (*pad_added)(GstElement*, GstPad*);
  void (*no_more_pads)(GstElement*);

  // —— 你会 override 的 vfunc ——
  GstPad* (*request_new_pad)(GstElement*, GstPadTemplate*, const gchar*, const GstCaps*);
  void    (*release_pad)(GstElement*, GstPad*);
  GstStateChangeReturn (*get_state)(...);
  GstStateChangeReturn (*set_state)(GstElement*, GstState);
  GstStateChangeReturn (*change_state)(GstElement*, GstStateChange); // ← 高频 override
  void    (*state_changed)(GstElement*, GstState, GstState, GstState);
  void    (*set_bus)(GstElement*, GstBus*);
  GstClock* (*provide_clock)(GstElement*);
  void      (*set_clock)(GstElement*, GstClock*);
  gboolean (*send_event)(GstElement*, GstEvent*);
  gboolean (*query)(GstElement*, GstQuery*);
  void     (*post_message)(GstElement*, GstMessage*);
  void     (*set_context)(GstElement*, GstContext*);
};
```

> **注意**：直接继承 GstElement 写 Element 是"原始"做法，要自己处理 pad、
> chain、状态机等大量细节。**90% 的情况应继承基类**（§4.2），基类已实现这些
> vfunc 的通用版本，你只 override 更细粒度的钩子。

### 3.3 Pad — `gst/gstpad.h:764`（数据传输核心）

```c
struct _GstPad {
  GstObject           object;
  gpointer            element_private;
  GstPadTemplate     *padtemplate;
  GstPadDirection     direction;       // SRC / SINK
  GRecMutex           stream_rec_lock; // streaming 线程递归锁
  GstTask            *task;            // pull 模式时挂的任务
  GCond               block_cond;      // pad 阻塞条件变量
  GHookList           probes;          // Pad Probe 钩子链
  GstPadMode          mode;            // NONE/PUSH/PULL
  GstPadActivateFunction       activatefunc;    // 激活
  GstPadActivateModeFunction   activatemodefunc; // 激活模式
  GstPad            *peer;             // 对端 pad
  GstPadLinkFunction           linkfunc;
  GstPadUnlinkFunction         unlinkfunc;
  // —— 数据传输函数（你常设这些）——
  GstPadChainFunction          chainfunc;     // push 模式接收
  GstPadChainListFunction      chainlistfunc; // 批量接收
  GstPadGetRangeFunction      getrangefunc;  // pull 模式产出
  GstPadEventFunction          eventfunc;     // 事件
  GstPadQueryFunction          queryfunc;     // 查询
  GstPadIterIntLinkFunction    iterintlinkfunc;
  gint64            offset;
  gint              num_probes, num_blocked;
};
```

- 你通常：**设函数指针**（通过基类的 `gst_pad_set_chain_function` 等）或
  **加 Probe**（`gst_pad_add_probe`）。
- `stream_rec_lock` + `task` 是理解线程架构的关键（§6）。

### 3.4 数据对象体系（GstMiniObject 系，引用计数、COW）

#### GstMiniObject — `gst/gstminiobject.h:210`（所有数据对象的基类）

```c
struct _GstMiniObject {
  GType   type;
  gint    refcount;      // 引用计数
  gint    lockstate;
  guint   flags;
  GstMiniObjectCopyFunction    copy;     // 写时复制钩子
  GstMiniObjectDisposeFunction dispose; // 释放前钩子
  GstMiniObjectFreeFunction    free;     // 释放钩子
};
```

- GstBuffer / GstEvent / GstQuery / GstMessage / GstCaps 都把 GstMiniObject 作第一个字段。
- **COW（Copy-On-Write）**：`gst_buffer_make_writable()` 在 refcount>1 时调 `copy` 复制一份。
- 你通常：**ref/unref 配对**，改写前先 `make_writable`。

#### GstBuffer — `gst/gstbuffer.h:283`

```c
struct _GstBuffer {
  GstMiniObject  mini_object;
  GstBufferPool *pool;       // 来源池（可空）
  GstClockTime   pts, dts, duration;  // 时间戳
  guint64        offset, offset_end; // 媒体偏移
  // 内存块列表 + Meta 列表是 private，通过 API 访问
};
```

- 你通常：**读 pts/dts**，**append GstMemory**（`gst_buffer_append_memory`），
  **add GstMeta**（`gst_buffer_add_meta`）。
- 一个 Buffer 可含**多块 GstMemory**（拼接、零拷贝切片）。

#### GstMemory — `gst/gstmemory.h:161`

```c
struct _GstMemory {
  GstMiniObject  mini_object;
  GstAllocator  *allocator;  // 分配器
  GstMemory     *parent;     // 切片时的父内存
  gsize          maxsize, align, offset, size;
};
```

- 你通常：**map/unmap** 读写数据（`gst_memory_map`），或**自定义 Allocator** 产出它（§12）。
- `parent` 字段支持零拷贝切片：一块大 Memory 切出多个子 Memory，共享底层，各自只改 offset/size。

#### GstMeta — `gst/gstmeta.h:117`

```c
struct _GstMeta {
  const GstMetaInfo *info;   // 类型信息（注册时生成）
};
```

- 你的自定义 Meta 结构：`{ GstMeta meta; <你的字段> }`，通过 `GstMetaInfo` 注册（§11）。
- `GstMetaInfo` 含 `init/transform/serialize/deserialize/clear` 等钩子。

### 3.5 协商与控制对象

| 对象 | 位置 | 角色 | 你通常 |
|------|------|------|--------|
| GstCaps | `gstcaps.h` | 格式描述（media type + fields） | transform_caps 协商时构造 |
| GstStructure | `gststructure.h` | 键值对（Caps/Event/Message 的载体） | 读写字段 |
| GstEvent | `gstevent.h` | 控制事件（seek/flush/caps/segment…） | sink_event/src_event 处理 |
| GstQuery | `gstquery.h` | 查询（duration/position/allocation…） | query vfunc 响应 |
| GstMessage | `gstmessage.h` | 异步通知（EOS/error/state…） | 应用层监听 Bus |
| GstSegment | `gstsegment.h` | 流位置/速率/累积时间 | do_seek 时维护 |

### 3.6 时钟与任务

#### GstClock — `gst/gstclock.h`
抽象时钟，`get_internal_time` vfunc 是核心。子类 `GstSystemClock`（`gstsystemclock.c`）
用 GLib 主循环时钟。自定义时钟见 §14。

#### GstTask — `gst/gsttask.h:134`
后台任务线程封装，驱动 pull 模式 pad 的数据拉取。`GstTaskPool`（`gsttaskpool.c`）管理线程复用。
- 你通常：不直接创建；基类（BaseSrc）在激活 pull 模式时自动创建。

### 3.7 速查：开发时"只读 / 要写 / 要 override"

| 结构 | 只读 | 要写（实例） | 要 override（Class vfunc） |
|------|------|--------------|---------------------------|
| GstObject | name/parent/flags | ref/unref, lock | (极少) deep_notify |
| GstElement | bus/clock/pads | (基类代劳) | change_state, request_new_pad, provide_clock, send_event, query |
| GstPad | direction/peer | set chain/getrange/event/query | (基类代劳) |
| GstBuffer | pts/dts/offset | append_memory, add_meta, make_writable | (无 vfunc，用 Meta) |
| GstMemory | size/offset | map/unmap | (自定义 Allocator 的 alloc/free) |
| GstMiniObject | refcount | ref/unref | copy/dispose/free (注册时设) |
| GstCaps | — | intersect/append/fixate | (无 vfunc) |
| GstClock | — | (子类 get_internal_time) | get_internal_time, wait_async |

---

## 4. 类图与继承体系（开发视角）

本章从"你要继承谁、override 哪些 vfunc"的角度画类图。完整类图见
`gstream-design-analysis.md` §4.3，这里聚焦**开发子树**。

### 4.1 对象继承主树（GstObject 系）

```
GObject                         ← GLib
  └─ GInitiallyUnowned          ← floating ref（自动归属父 Bin）
       └─ GstObject             gst/gstobject.c        有名/有锁/有父
            └─ GstElement       gst/gstelement.c       状态机/pad/时钟
                 ├─ GstBin      gst/gstbin.c           容器（children 列表）
                 │    └─ GstPipeline gst/gstpipeline.c  顶层（bus/clock）
                 │
                 └─ 【开发子树：基类】 libs/gst/base/
                      ├─ GstBaseSrc       gstbasesrc.c   源元素基类
                      │    └─ GstPushSrc  gstpushsrc.c   push 式源（最常用源）
                      ├─ GstBaseSink      gstbasesink.c  宿元素基类
                      ├─ GstBaseTransform gstbasetransform.c  滤镜基类
                      ├─ GstBaseParse     gstbaseparse.c 解析器基类
                      └─ GstAggregator    gstaggregator.c 多路聚合基类
                           (其 Pad 是 GstAggregatorPad)
```

> **关键认知**：你写的 Element 几乎不直接继承 `GstElement`，而是继承上面五个基类之一。
> 基类已经实现了 GstElement 的 `change_state`、pad 的 `chain`/`getrange`、
> Caps 协商、Buffer 分配等通用逻辑，你只 override 更细的钩子。

### 4.2 数据对象树（GstMiniObject 系）

```
GstMiniObject                   gst/gstminiobject.c    引用计数 + COW
  ├─ GstBuffer                   gstbuffer.c           数据载体（含 GstMemory 列表 + GstMeta 列表）
  ├─ GstEvent                    gstevent.c            控制事件（seek/flush/segment…）
  ├─ GstQuery                    gstquery.c            查询（duration/position/allocation…）
  ├─ GstMessage                  gstmessage.c         异步通知（EOS/error…）
  └─ GstCaps                     gstcaps.c             格式描述（含 GstStructure 列表）
       └─ GstCapsFeatures        gstcapsfeatures.c    特性（如 DMABuf）
```

这些**不继承 GstObject**，没有名字/父/信号，只有引用计数和 COW。开发时用 API 操作，
不继承。

### 4.3 基类选择决策表（核心！）

| 你要做的事 | 继承 | 关键 override 的 vfunc | 所在文件 |
|------------|------|------------------------|----------|
| 1 进 1 出，改数据（滤镜） | `GstBaseTransform` | `transform` 或 `transform_ip`、`transform_caps`、`set_caps` | `libs/gst/base/gstbasetransform.h` |
| 1 进 1 出，原地改（省拷贝） | `GstBaseTransform`（in-place 模式） | `transform_ip` | 同上 |
| 产生数据（源） | `GstBaseSrc` 或 `GstPushSrc` | `create`/`fill`、`is_seekable`、`do_seek`、`get_times`、`negotiate`、`start`/`stop` | `libs/gst/base/gstbasesrc.h` |
| 消费数据（宿） | `GstBaseSink` | `render`、`preroll`、`event`、`get_times`、`set_caps`、`start`/`stop` | `libs/gst/base/gstbasesink.h` |
| 多进 1 出（合流/混音） | `GstAggregator` | `aggregate`、`create_new_pad`、`sink_event`、`sink_query` | `libs/gst/base/gstaggregator.h` |
| 解析容器/流（输出帧/包） | `GstBaseParse` | `handle_frame`、`set_sink_caps`、`start`/`stop` | `libs/gst/base/gstbaseparse.h` |
| 容器/拓扑封装 | `GstBin` | (少 override，多组合) | `gst/gstbin.c` |

### 4.4 UML 风格类图（开发子树，标注 vfunc）

```
            ┌───────────────────┐
            │   GstElement      │  (gst/gstelement.h:1040)
            │───────────────────│
            │ +change_state()   │  ← 基类已实现通用状态机
            │ +request_new_pad()│
            │ +provide_clock()  │
            │ +send_event()     │
            │ +query()          │
            └─────────┬─────────┘
                      │ (abstract, 你不直接继承)
        ┌─────────────┼──────────────────────────────────┐
        │             │                                  │
┌───────▼────────┐ ┌──▼──────────────┐  ┌──────────────▼─────────┐
│ GstBaseSrc     │ │ GstBaseSink     │  │ GstBaseTransform       │
│ (源)           │ │ (宿)            │  │ (滤镜)                  │
│────────────────│ │─────────────────│  │────────────────────────│
│ *create()      │ │ *render()       │  │ *transform(in,out)     │
│ *fill()        │ │ *preroll()      │  │ *transform_ip(buf)      │
│ *is_seekable() │ │ *get_times()    │  │ *transform_caps()      │
│ *do_seek()     │ │ *set_caps()     │  │ *set_caps()            │
│ *get_times()   │ │ *event()        │  │ *decide_allocation()   │
│ *negotiate()   │ │ *start()/stop() │  │ *propose_allocation()  │
│ *start()/stop()│ └─────────────────┘  │ *start()/stop()        │
│ *unlock()      │                      │ *before_transform()    │
└───────┬────────┘                      └────────────────────────┘
        │
┌───────▼────────┐
│ GstPushSrc     │  (最常用源：push 式，只需 fill/create)
│────────────────│
│ *fill()         │
└────────────────┘

┌────────────────────────┐  ┌────────────────────────────┐
│ GstAggregator           │  │ GstBaseParse               │
│ (多路合流)              │  │ (流解析器)                  │
│─────────────────────────│  │────────────────────────────│
│ *aggregate()            │  │ *handle_frame()            │
│ *create_new_pad()       │  │ *set_sink_caps()           │
│ *sink_event()/query()   │  │ *start()/stop()            │
│ *find_best_sinkpad()    │  │ *get_duration()            │
│ *sink_pad_cloned()      │  │                            │
└────────────────────────┘  └────────────────────────────┘
```

### 4.5 继承的代码模式（GObject 标准三件套）

每个基类子类都用同一套宏生成"类"：

```c
// 头文件 myfilter.h
G_DECLARE_FINAL_TYPE (MyFilter, my_filter, MY, FILTER, GstBaseTransform)

// 源文件 myfilter.c
#define gst_my_filter_parent_class parent_class
G_DEFINE_TYPE (MyFilter, my_filter, GST_TYPE_BASE_TRANSFORM);

static void my_filter_class_init (MyFilterClass *klass) {
  GstElementClass *ec = GST_ELEMENT_CLASS (klass);
  GstBaseTransformClass *bc = GST_BASE_TRANSFORM_CLASS (klass);

  // 1. 元数据（gst-inspect 显示）
  gst_element_class_set_metadata (ec, "My Filter", "Filter/Effect",
      "Does X to data", "You <you@example.com>");

  // 2. Pad 模板
  gst_element_class_add_pad_template (ec,
      gst_pad_template_new ("sink", GST_PAD_SINK, GST_PAD_ALWAYS, ...));
  gst_element_class_add_pad_template (ec,
      gst_pad_template_new ("src", GST_PAD_SRC, GST_PAD_ALWAYS, ...));

  // 3. override 基类 vfunc
  bc->transform      = GST_DEBUG_FUNCPTR (my_filter_transform);
  bc->transform_ip   = GST_DEBUG_FUNCPTR (my_filter_transform_ip);
  bc->transform_caps = GST_DEBUG_FUNCPTR (my_filter_transform_caps);

  // 4. 属性（ GObject properties ）
  g_object_class_install_property (G_OBJECT_CLASS (klass), PROP_X, ...);
}

static void my_filter_init (MyFilter *self) {
  // 实例初始化
}
```

四个固定步骤：**元数据 → Pad 模板 → override vfunc → 安装属性**。后面每个完整案例
都是这个骨架的展开。

---

## 5. 数据流图（开发视角：数据经过你的代码时发生了什么）

本章把数据流和**你的 vfunc 调用时机**对齐。理解这张图，你就知道代码"挂在哪"。

### 5.1 Push 模式（主流）：上游主动推

```
[上游 Element]                [你的 BaseTransform]                 [下游 Element]
   src pad                       sink pad    src pad                  sink pad
     │                              │          │                          │
     │ gst_pad_push(buf)            │          │                          │
     │─────────────────────────────▶│          │                          │
     │                              │ chainfunc(基类实现)                  │
     │                              │   ↓                                  │
     │                              │ before_transform(buf)  ← 你的钩子(可选)
     │                              │   ↓                                  │
     │                              │ prepare_output_buffer(基类)            │
     │                              │   ↓                                  │
     │                              │ transform(in,out)  ← 你的核心          │
     │                              │   或 transform_ip(buf) ← 原地          │
     │                              │   ↓                                  │
     │                              │          │ gst_pad_push(outbuf)      │
     │                              │          │──────────────────────────▶│
     │                              │          │                          │ chainfunc(下游)
     │                              │          │                          │ ...
     │                              │          │◀─────────────────────────│ 返回 GstFlowReturn
     │◀─────────────────────────────│          │                          │
     │ (FlowReturn 向上游传播)        │          │                          │
```

**你的代码挂在 `transform` / `transform_ip`**。基类替你处理了：chain 接收、
输出 buffer 分配、metadata 拷贝、push 到下游、FlowReturn 传播。

### 5.2 Pull 模式：下游主动拉

```
[你的 BaseSrc]                 [下游 Element]
  src pad                         sink pad
     │                              │
     │◀─────────────────────────────│ gst_pad_pull_range(offset,size)
     │                              │
     │ getrangefunc(基类)            │
     │   ↓                          │
     │ create(offset,size,buf) ← 你的核心
     │   或 fill(offset,size,buf)   │
     │   ↓                          │
     │─────────────────────────────▶│ 返回 buf
```

Pull 模式由下游驱动。你的 BaseSrc 通过 `GstTask`（§6）在独立线程里响应 `getrangefunc`。
`is_seekable()` 返回 TRUE 时才支持 pull；否则只能 push（用 `GstPushSrc`）。

### 5.3 Buffer 生命周期与引用计数（开发必懂）

```
分配                  使用                      释放
gst_buffer_new()      gst_buffer_map(buf,&info,W)   gst_buffer_unref(buf)
gst_buffer_new_allocate()  gst_buffer_append_memory()   (refcount 减到 0 → free)
gst_buffer_pool_acquire()  gst_buffer_add_meta()
                      gst_buffer_make_writable()  ← refcount>1 时 COW 复制
```

**三条铁律**：
1. **写前必 writable**：`buf = gst_buffer_make_writable(buf)`。若 refcount>1，
   会复制一份；refcount==1 则原样返回。直接写非 writable buffer 是常见 bug。
2. **ref/unref 配对**：`gst_buffer_ref` 增引用，`gst_buffer_unref` 减。
   push 出去的 buffer 所有权转移给下游，**不要再用**（除非你 ref 了）。
3. **Meta 不自动跟随**：transform 到新 buffer 时，Meta 默认不拷贝，
   需在 `transform_meta` vfunc 里显式处理（§11）。

### 5.4 Caps 协商流程（你的钩子在哪）

```
[上游]                  [你的 BaseTransform]              [下游]
  │ propose caps            │                              │
  │────────────────────────▶│ transform_caps(dir,caps) ← 你的钩子
  │                         │ (把上游 caps 映射成你能输出的 caps)
  │                         │─────────────────────────────▶│ 查询下游接受什么
  │                         │◀─────────────────────────────│ 返回下游 caps
  │                         │ fixate_caps() ← 你的钩子(定值)
  │                         │ set_caps(incaps,outcaps) ← 你的钩子(确认)
  │                         │   ↓ (进入 PAUSED/PLAYING)
  │                         │ decide_allocation(query) ← 你的钩子(输出 buffer 池)
  │                         │ propose_allocation(query) ← 你的钩子(输入 buffer 池)
  │                         │   ↓
  │                         │ (数据流开始，transform 被反复调用)
```

- `transform_caps`：告诉框架"给我这种输入 caps，我能输出什么 caps"。
  简单 passthrough filter 可不实现（默认同 caps）。
- `set_caps`：双方 caps 确定后调用一次，你在此初始化编解码器/参数。
- `decide_allocation`：决定输出 buffer 用什么分配器/池（§12 关键钩子）。

### 5.5 Event / Query 流（控制信息，非数据）

```
Event（seek/flush/segment/eos，下游→上游 或 上游→下游）:
  gst_pad_send_event → eventfunc → 你的 sink_event/src_event vfunc
  （基类有默认实现，你 override 只为拦截特殊事件）

Query（duration/position/allocation，下游→上游）:
  gst_pad_query → queryfunc → 你的 query vfunc
  （BaseTransform 的 query vfunc 默认转发，你 override 只为回答特定查询）
```

- **Event 携带 GstStructure，可改写**；Query 是"请求-应答"模式。
- `decide_allocation`/`propose_allocation` 本质是响应 `GST_QUERY_ALLOCATION`。

---

## 6. 分层控制流图（状态机 + 线程 + 内存）

### 6.1 状态机与你的 start/stop 时机

GStreamer 四态：`NULL → READY → PAUSED → PLAYING`。`gst_element_set_state`
触发逐级传播，你的基类把状态变化映射成 vfunc 调用：

```
NULL → READY     : 分配资源、打开设备、创建 pad
                   BaseSrc/BaseSink/BaseTransform: start()  ← 你的钩子
READY → PAUSED   : 准备数据、preroll（首帧就绪）
                   BaseSink: preroll()
                   BaseSrc: negotiate()、decide_allocation()
PAUSED → PLAYING : 开始流动、启动时钟
                   (基类处理，你一般不 hook)
PLAYING → PAUSED : 暂停、停时钟
PAUSED → READY   : 释放数据流资源
                   BaseSrc/BaseSink/BaseTransform: stop()  ← 你的钩子
READY → NULL     : 关闭设备、释放全部资源
```

**对应关系**（开发时最常踩的对应表）：

| 转换 | 你的 vfunc | 典型动作 |
|------|-----------|----------|
| NULL→READY | `start()` | 打开文件/设备、分配编解码器上下文 |
| READY→PAUSED | `negotiate()`/`set_caps()`/`preroll()` | 协商格式、初始化处理状态 |
| PAUSED→PLAYING | (基类) | 启动时钟，无需你管 |
| PAUSED→READY | `stop()` | 释放编解码器、关闭设备 |
| READY→NULL | (基类释放) | — |

> `change_state` 是 GstElement 级 vfunc，基类已实现并调用上面的 `start/stop`。
> **只在需要细粒度控制（如 PAUSED→PLAYING 做特殊事）时才 override `change_state`**，
> 且必须 `chain up` 到父类。

### 6.2 线程架构（关键：你的 vfunc 跑在哪个线程）

GStreamer 是**多线程**框架，一个 pipeline 里通常有多个线程同时跑。理解"我的代码在
哪个线程"是写出正确 Element 的前提。

```
┌─────────────────────────────────────────────────────────────┐
│ ① 应用主线程 (main loop)                                      │
│   - gst_init / 构建 pipeline / set_state / 监听 Bus 消息       │
│   - 你的应用代码、Bus watch 回调在这里                          │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ ② Streaming 线程 (数据流线程，每个 push 链一条)                │
│   - 由上游 src pad 的 GstTask 或上游 push 触发                 │
│   - 持有 pad 的 stream_rec_lock (GRecMutex)                   │
│   - 你的 transform()/render()/chain 回调在这里跑 ★最常见★      │
│   - 多条 push 链 = 多个 streaming 线程（queue 之后是新线程）     │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ ③ Bus 线程 (GstBus 内部线程)                                   │
│   - 把 Element post 的 GstMessage 派发给应用                  │
│   - gst_bus_add_watch 的回调在这里（或主循环，取决于 watch）   │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ ④ Clock 线程 (GstSystemClock)                                 │
│   - 等待时钟等待者（wait_async）                               │
│   - BaseSink 用它做同步渲染                                     │
└─────────────────────────────────────────────────────────────┘
```

**线程安全清单**（开发时对照）：

| 你的 vfunc | 所在线程 | 共享数据保护 |
|-----------|----------|-------------|
| `transform`/`transform_ip` | streaming | 实例私有数据无需锁（单 pad单流）；多 pad 用 `GST_OBJECT_LOCK` |
| `render`/`preroll` | streaming | 同上 |
| `create`/`fill` (src) | src 的 GstTask 线程 | 同上 |
| `start`/`stop` | 应用线程 (set_state) | 与 streaming 并发，需锁保护共享状态 |
| `set_property`/`get_property` | 可任意线程 | 属性若被 streaming 读，需 `GST_OBJECT_LOCK` |
| `sink_event`/`src_event` | streaming | 同 transform |
| `change_state` | 应用线程 | 与 streaming 并发，用 `state_lock` |
| Bus watch 回调 | Bus 线程/主循环 | 跨线程访问 Element 用锁 |

> **最常见 bug**：在 `set_property`（应用线程）里改一个 `transform`（streaming 线程）
> 正在读的字段，没加锁 → 竞态。解法：用 `GST_OBJECT_LOCK` 保护，或用
> `gst_element_post_message` 把改动异步化。

### 6.3 内存架构（GstMemory → GstAllocator → GstBufferPool）

```
应用/Element 请求 buffer
   │ gst_buffer_new_allocate(allocator, size, params)
   │ 或 gst_buffer_pool_acquire_buffer(pool)
   ▼
┌──────────────────────────────────────────┐
│ GstBufferPool (gstbufferpool.c)            │
│  - 预分配一批 GstBuffer 复用               │
│  - 配置: caps, size, min/max buffers, allocator
│  - acquire/release 配对，避免反复分配       │
└───────────────┬────────────────────────────┘
                │ 首次分配时
                ▼
┌──────────────────────────────────────────┐
│ GstAllocator (gstallocator.c)              │
│  - alloc(size, params) → GstMemory         │
│  - free(mem)                               │
│  - 默认: sysmem (malloc)                   │
│  - 自定义: DMABuf/GPU/物理内存 (§12)        │
└───────────────┬────────────────────────────┘
                │
                ▼
┌──────────────────────────────────────────┐
│ GstMemory (gstmemory.c)                    │
│  - 一块内存的描述: offset/size/maxsize/align
│  - map(info, READ/WRITE) → 拿到指针        │
│  - 支持切片(parent 字段, 零拷贝)            │
└──────────────────────────────────────────┘
```

**零拷贝路径**（性能关键，§12 详述）：
1. **Allocator 级**：自定义 `GstAllocator` 让 `GstMemory` 包裹外部内存
   （DMA-Buf fd、GPU handle、mmap 区），`map` 返回的是外部指针，不拷贝。
2. **Memory 切片级**：一块大 `GstMemory` 用 `gst_memory_share` 切出子 Memory，
   共享底层，各自 offset/size，零拷贝。
3. **Buffer 级**：`gst_buffer_append_memory` 把多块 Memory 拼进一个 Buffer，
   `map` 时按需拼接或直接 scatter。

**BufferPool 的作用**：视频每秒几十帧，反复 `malloc/free` 开销大。Pool 预分配并
循环复用 buffer。你在 `decide_allocation` 里配置 pool（池大小、allocator、是否带 Meta）。

### 6.4 控制流分层总览

```
应用层  ──set_state──▶  Pipeline/Bin ──change_state 传播──▶  Element
   │                       │                                │
   │──send_event──▶        │──clock 分发──▶                 │──start/stop/transform
   │──query──▶             │──latency 计算─▶                │
   │                       ▼                                ▼
   │                    GstBus ◀──post_message── Element (streaming 线程)
   │                       │
   └──bus watch◀────────────┘ (异步消息)
```

- **控制流**（状态、事件、查询）从应用向下传播；**消息**从 Element 向上回流。
- **数据流**（buffer）在 streaming 线程里横向流动，与控制流解耦。

---

## 7. 开发方向一：写一个 Transform Element（完整案例）

Transform（滤镜）是最常见、最完整的二次开发场景。本节给出一个**可运行骨架**：
一个"给每个 buffer 打上处理时间戳元数据并透传"的 filter，演示 BaseTransform 全套用法。

### 7.1 选父类：GstBaseTransform

`GstBaseTransform`（`libs/gst/base/gstbasetransform.c`）是 1 进 1 出滤镜的基类。
两种工作模式：

| 模式 | override | 何时用 | buffer 分配 |
|------|----------|--------|-------------|
| **非 in-place** | `transform(in, out)` | 输出尺寸/格式与输入不同 | 基类分配新 outbuf |
| **in-place** | `transform_ip(buf)` | 原地改写，尺寸不变（如音量调节、灰度化） | 复用 inbuf（需 writable） |

设 in-place：`gst_base_transform_set_in_place(trans, TRUE)`，或在 class_init 里
不设 `transform` 只设 `transform_ip`。passthrough（不改数据，只观察）：
`gst_base_transform_set_passthrough(trans, TRUE)`。

本例用 **in-place + passthrough**：不改数据，只贴 Meta，零拷贝。

### 7.2 头文件 `myfilter.h`

```c
#pragma once
#include <gst/base/gstbasetransform.h>

G_BEGIN_DECLS
#define MY_TYPE_FILTER            (my_filter_get_type())
#define MY_FILTER(obj)            (G_TYPE_CHECK_INSTANCE_CAST((obj),MY_TYPE_FILTER,MyFilter))
#define MY_FILTER_CLASS(klass)    (G_TYPE_CHECK_CLASS_CAST((klass),MY_TYPE_FILTER,MyFilterClass))
#define MY_IS_FILTER(obj)         (G_TYPE_CHECK_INSTANCE_TYPE((obj),MY_TYPE_FILTER))
#define MY_IS_FILTER_CLASS(klass) (G_TYPE_CHECK_CLASS_TYPE((klass),MY_TYPE_FILTER))

typedef struct _MyFilter        MyFilter;
typedef struct _MyFilterClass    MyFilterClass;
typedef struct _MyFilterPrivate MyFilterPrivate;

struct _MyFilter {
  GstBaseTransform  parent;
  MyFilterPrivate  *priv;   // 私有数据（或直接放字段）
};

struct _MyFilterClass {
  GstBaseTransformClass parent_class;
};

GType my_filter_get_type (void);

G_END_DECLS
```

### 7.3 源文件 `myfilter.c`（完整骨架）

```c
#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif
#include "myfilter.h"
#include <gst/gst.h>
#include <gst/base/gstbasetransform.h>

GST_DEBUG_CATEGORY_STATIC (my_filter_debug);
#define GST_CAT_DEFAULT my_filter_debug

/* —— Pad 模板：ANY caps，表示接受任意格式 —— */
static GstStaticPadTemplate sinktemplate = GST_STATIC_PAD_TEMPLATE ("sink",
    GST_PAD_SINK, GST_PAD_ALWAYS, GST_STATIC_CAPS_ANY);
static GstStaticPadTemplate srctemplate = GST_STATIC_PAD_TEMPLATE ("src",
    GST_PAD_SRC, GST_PAD_ALWAYS, GST_STATIC_CAPS_ANY);

/* —— 属性 —— */
enum { PROP_0, PROP_SILENT, PROP_LAST };

#define DEFAULT_SILENT TRUE

/* —— GObject 标准三件套 —— */
#define my_filter_parent_class parent_class
G_DEFINE_TYPE_WITH_CODE (MyFilter, my_filter, GST_TYPE_BASE_TRANSFORM,
    GST_DEBUG_CATEGORY_INIT (my_filter_debug, "myfilter", 0, "my filter"));
GST_ELEMENT_REGISTER_DEFINE (my_filter, "my-filter", GST_RANK_NONE,
    MY_TYPE_FILTER);

static void my_filter_set_property (GObject *o, guint id, const GValue *v, GParamSpec *p);
static void my_filter_get_property (GObject *o, guint id, GValue *v, GParamSpec *p);
static GstFlowReturn my_filter_transform_ip (GstBaseTransform *trans, GstBuffer *buf);
static gboolean my_filter_start (GstBaseTransform *trans);
static gboolean my_filter_stop  (GstBaseTransform *trans);

static void
my_filter_class_init (MyFilterClass * klass)
{
  GObjectClass *gobject_class = G_OBJECT_CLASS (klass);
  GstElementClass *ec = GST_ELEMENT_CLASS (klass);
  GstBaseTransformClass *bc = GST_BASE_TRANSFORM_CLASS (klass);

  /* 1. 属性 */
  gobject_class->set_property = my_filter_set_property;
  gobject_class->get_property = my_filter_get_property;
  g_object_class_install_property (gobject_class, PROP_SILENT,
      g_param_spec_boolean ("silent", "Silent", "Don't print logs",
          DEFAULT_SILENT, G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));

  /* 2. 元数据（gst-inspect 显示） */
  gst_element_class_set_static_metadata (ec,
      "My Filter", "Filter/Effect",
      "Stamps each buffer with processing metadata",
      "You <you@example.com>");

  /* 3. Pad 模板 */
  gst_element_class_add_static_pad_template (ec, &sinktemplate);
  gst_element_class_add_static_pad_template (ec, &srctemplate);

  /* 4. override vfunc */
  bc->transform_ip = GST_DEBUG_FUNCPTR (my_filter_transform_ip);
  bc->start        = GST_DEBUG_FUNCPTR (my_filter_start);
  bc->stop         = GST_DEBUG_FUNCPTR (my_filter_stop);

  /* in-place + passthrough：不改数据，零拷贝 */
  bc->passthrough_on_same_caps = TRUE;
}

static void
my_filter_init (MyFilter *self)
{
  self->priv = G_TYPE_INSTANCE_GET_PRIVATE (self, MY_TYPE_FILTER, MyFilterPrivate);
  /* 让基类进入 in-place 模式 */
  gst_base_transform_set_in_place (GST_BASE_TRANSFORM (self), TRUE);
  gst_base_transform_set_passthrough (GST_BASE_TRANSFORM (self), TRUE);
}

static gboolean
my_filter_start (GstBaseTransform *trans)
{
  GST_INFO_OBJECT (trans, "start");
  return TRUE;
}

static gboolean
my_filter_stop (GstBaseTransform *trans)
{
  GST_INFO_OBJECT (trans, "stop");
  return TRUE;
}

static GstFlowReturn
my_filter_transform_ip (GstBaseTransform *trans, GstBuffer *buf)
{
  MyFilter *self = MY_FILTER (trans);

  /* in-place 模式下 buf 已被基类 make_writable，可直接改 */
  GST_LOG_OBJECT (self, "processing buffer pts=%" GST_TIME_FORMAT,
      GST_TIME_ARGS (GST_BUFFER_PTS (buf)));

  /* 这里可加 GstMeta（§11）、改时间戳、统计等 */
  if (!self->priv->silent) {
    GST_DEBUG_OBJECT (self, "buffer through, size=%u",
        (guint) gst_buffer_get_size (buf));
  }

  /* 返回 OK 表示继续；FLUSH 表示丢弃；ERROR 表示出错 */
  return GST_FLOW_OK;
}

static void
my_filter_set_property (GObject *o, guint id, const GValue *v, GParamSpec *p)
{
  MyFilter *self = MY_FILTER (o);
  switch (id) {
    case PROP_SILENT:
      GST_OBJECT_LOCK (self);   /* 跨线程：streaming 读，应用线程写 */
      self->priv->silent = g_value_get_boolean (v);
      GST_OBJECT_UNLOCK (self);
      break;
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (o, id, p);
  }
}

static void
my_filter_get_property (GObject *o, guint id, GValue *v, GParamSpec *p)
{
  MyFilter *self = MY_FILTER (o);
  switch (id) {
    case PROP_SILENT:
      GST_OBJECT_LOCK (self);
      g_value_set_boolean (v, self->priv->silent);
      GST_OBJECT_UNLOCK (self);
      break;
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (o, id, p);
  }
}
```

### 7.4 插件入口 `myplugin.c`

```c
#include <gst/gst.h>
GST_ELEMENT_REGISTER_DECLARE (my_filter)  /* 来自 myfilter.c 的宏 */

static gboolean
plugin_init (GstPlugin *plugin)
{
  return GST_ELEMENT_REGISTER (my_filter, plugin);
}

GST_PLUGIN_DEFINE (GST_VERSION_MAJOR, GST_VERSION_MINOR, myplugins,
    "My custom plugins", plugin_init, "1.0", "LGPL",
    "my-plugins", "https://example.com");
```

### 7.5 meson.build

```meson
project('gst-my-plugins', 'c', meson_version: '>= 0.63')
gst_dep = dependency('gstreamer-1.0', version: '>= 1.20')
gst_base_dep = dependency('gstreamer-base-1.0')
shared_library('gstmyplugins',
  ['myfilter.c', 'myplugin.c'],
  dependencies: [gst_dep, gst_base_dep],
  install: true,
  install_dir: gst_dep.get_variable('pluginsdir'),
  name_prefix: 'gst')
```

### 7.6 验证

```bash
meson setup build && ninja -C build && sudo ninja -C build install
GST_PLUGIN_PATH=$(pwd)/build gst-launch-1.0 \
  videotestsrc ! my-filter silent=false ! fakesink
GST_PLUGIN_PATH=$(pwd)/build gst-inspect-1.0 my-filter
```

### 7.7 涉及文件/类清单

| 文件/类 | 作用 | 你要做什么 |
|---------|------|-----------|
| `libs/gst/base/gstbasetransform.h` | 基类定义 | 继承，override vfunc |
| `gst/gstelement.h` | 元数据/Pad 模板宏 | class_init 里用 |
| `gst/gstplugin.h` | `GST_PLUGIN_DEFINE` | 插件入口 |
| `gst/gstelement.h` | `GST_ELEMENT_REGISTER_DEFINE` | 元素注册 |
| `gst/gstpadtemplate.h` | `GST_STATIC_PAD_TEMPLATE` | 声明 pad |
| `gst/gstinfo.h` | `GST_DEBUG_CATEGORY` | 日志分类 |

### 7.8 踩坑清单

1. **写 buffer 前没 writable**：in-place 模式基类会帮你 `make_writable`，
   非 in-place 模式你拿到的 outbuf 是新分配的，可直接写。**别直接写 inbuf**。
2. **passthrough 与 transform_ip 冲突**：passthrough=TRUE 时基类可能跳过
   `transform_ip`。若你既要 passthrough（不改数据）又要观察数据，用
   `before_transform` 钩子，或保持 passthrough=FALSE 但 transform_ip 只读不写。
3. **单元大小**：处理视频/音频时，`get_unit_size`/`transform_size` 要正确，
   否则 buffer 大小协商出错。passthrough 模式可忽略。
4. **Caps 协商**：若你的 filter 改变格式（如 RGB→GRAY），必须实现
   `transform_caps`，否则下游拿不到正确 caps。
5. **线程**：`transform_ip` 在 streaming 线程，`set_property` 在应用线程，
   共享字段（如 silent）必须 `GST_OBJECT_LOCK`。
6. **segment/pts**：改时间戳要同步更新 segment，否则同步错乱。passthrough 模式不动。

---

## 8. 开发方向二：写一个 Src Element（完整案例）

Src 元素产生数据。场景：从网络、共享内存、硬件、AI 推理输出产生流。

### 8.1 选父类：GstBaseSrc vs GstPushSrc

| 父类 | 模式 | override | 适用 |
|------|------|----------|------|
| `GstBaseSrc` | pull（可 seek） | `create`/`fill`、`is_seekable`、`do_seek`、`get_size` | 文件、可随机访问源 |
| `GstPushSrc` | push（不可 seek） | `fill`（最简） | 实时流、网络、硬件捕获 |

`GstPushSrc`（`libs/gst/base/gstpushsrc.c`）继承 `GstBaseSrc`，把 `create` 简化成
`fill`，适合"我有数据就推"的场景。本例用 **GstPushSrc**，最简。

### 8.2 完整骨架 `mysrc.c`（产生递增计数测试流）

```c
#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif
#include <gst/gst.h>
#include <gst/base/gstpushsrc.h>

GST_DEBUG_CATEGORY_STATIC (my_src_debug);
#define GST_CAT_DEFAULT my_src_debug

/* 输出 caps：application/octet-stream，每帧固定 4 字节 */
#define MY_SRC_CAPS \
  "application/x-my-src, " \
  "framerate = (fraction) [ 0, MAX ], " \
  "width = (int) [ 1, MAX ], height = (int) [ 1, MAX ]"

static GstStaticPadTemplate srctemplate = GST_STATIC_PAD_TEMPLATE ("src",
    GST_PAD_SRC, GST_PAD_ALWAYS,
    GST_STATIC_CAPS (MY_SRC_CAPS));

struct _MySrc { GstPushSrc parent; guint64 counter; guint fps_num, fps_den; };
struct _MySrcClass { GstPushSrcClass parent_class; };

#define my_src_parent_class parent_class
G_DEFINE_TYPE_WITH_CODE (MySrc, my_src, GST_TYPE_PUSH_SRC,
    GST_DEBUG_CATEGORY_INIT (my_src_debug, "mysrc", 0, "my src"));
GST_ELEMENT_REGISTER_DEFINE (my_src, "my-src", GST_RANK_NONE, MY_TYPE_SRC);

static gboolean my_src_start (GstBaseSrc *bsrc) {
  MySrc *self = MY_SRC (bsrc);
  self->counter = 0;
  /* live source：告诉基类这是实时流，需要时钟同步 */
  gst_base_src_set_live (bsrc, TRUE);
  /* 设置格式（时间/字节/帧） */
  gst_base_src_set_format (bsrc, GST_FORMAT_TIME);
  return TRUE;
}
static gboolean my_src_stop (GstBaseSrc *bsrc) { return TRUE; }

static GstCaps * my_src_get_caps (GstBaseSrc *bsrc, GstCaps *filter) {
  MySrc *self = MY_SRC (bsrc);
  GstCaps *caps = gst_caps_new_empty_simple ("application/x-my-src");
  /* 按 filter 交集 */
  if (filter) { GstCaps *i = gst_caps_intersect(caps, filter); gst_caps_unref(caps); caps = i; }
  return caps;
}

static gboolean my_src_is_seekable (GstBaseSrc *bsrc) { return FALSE; } /* push 不可 seek */

static void my_src_get_times (GstBaseSrc *bsrc, GstBuffer *buf,
    GstClockTime *start, GstClockTime *end) {
  /* live source：按 duration 同步 */
  *start = GST_BUFFER_PTS (buf);
  *end   = GST_BUFFER_PTS (buf) + GST_BUFFER_DURATION (buf);
}

static GstFlowReturn
my_src_fill (GstPushSrc *psrc, GstBuffer *buf)
{
  MySrc *self = MY_SRC (psrc);
  GstMapInfo map;
  guint32 val = (guint32)(self->counter++);

  if (!gst_buffer_map (buf, &map, GST_MAP_WRITE))
    return GST_FLOW_ERROR;
  *(guint32 *)map.data = val;   /* 写 4 字节计数 */
  gst_buffer_unmap (buf, &map);

  /* 时间戳：按帧率递增 */
  GST_BUFFER_PTS (buf) = self->counter *
      gst_util_uint64_scale (GST_SECOND, self->fps_den, self->fps_num);
  GST_BUFFER_DURATION (buf) =
      gst_util_uint64_scale (GST_SECOND, self->fps_den, self->fps_num);
  GST_BUFFER_OFFSET (buf) = self->counter;
  GST_BUFFER_OFFSET_END (buf) = self->counter + 1;

  GST_LOG_OBJECT (self, "pushed %u", val);
  return GST_FLOW_OK;
}

static void my_src_class_init (MySrcClass *klass) {
  GObjectClass *oc = G_OBJECT_CLASS (klass);
  GstElementClass *ec = GST_ELEMENT_CLASS (klass);
  GstBaseSrcClass *bc = GST_BASE_SRC_CLASS (klass);
  GstPushSrcClass *pc = GST_PUSH_SRC_CLASS (klass);

  gst_element_class_set_static_metadata (ec, "My Src", "Source",
      "Produces a counter test stream", "You <you@example.com>");
  gst_element_class_add_static_pad_template (ec, &srctemplate);

  bc->start       = GST_DEBUG_FUNCPTR (my_src_start);
  bc->stop        = GST_DEBUG_FUNCPTR (my_src_stop);
  bc->get_caps    = GST_DEBUG_FUNCPTR (my_src_get_caps);
  bc->is_seekable = GST_DEBUG_FUNCPTR (my_src_is_seekable);
  bc->get_times   = GST_DEBUG_FUNCPTR (my_src_get_times);
  pc->fill        = GST_DEBUG_FUNCPTR (my_src_fill);
  /* oc->set_property/get_property 省略，同 §7 */
}
static void my_src_init (MySrc *self) {
  self->fps_num = 25; self->fps_den = 1;
  /* blocksize 决定 fill 时 buf 的大小 */
  gst_base_src_set_blocksize (GST_BASE_SRC (self), 4);
}
```

### 8.3 关键点说明

- **live source**：`gst_base_src_set_live(TRUE)` 让基类知道这是实时流，
  `get_times` 用 buffer 时间戳做时钟同步（而非尽快推送）。
- **blocksize**：`gst_base_src_set_blocksize` 决定 `fill` 时 buffer 预分配大小。
  也可在 `decide_allocation` 里自定义池。
- **`get_caps`**：返回本源能输出的 caps。若支持多种格式，按 `filter` 交集返回。
- **`do_seek`**：仅 `is_seekable()==TRUE` 时需要实现，处理 seek 事件、更新 segment。

### 8.4 涉及文件/类清单

| 文件/类 | 作用 |
|---------|------|
| `libs/gst/base/gstbasesrc.h` | `GstBaseSrcClass` vfunc（start/stop/create/fill/get_caps/is_seekable/do_seek/get_times/decide_allocation） |
| `libs/gst/base/gstpushsrc.h` | `GstPushSrcClass`（fill，简化版 create） |
| `gst/gstclock.h` | live source 时钟同步 |
| `gst/gstsegment.h` | seek 时维护 segment |

### 8.5 踩坑

1. **discont 标志**：seek 后或首帧要设 `GST_BUFFER_FLAG_SET(buf, GST_BUFFER_FLAG_DISCONT)`，
   否则下游误判连续性。
2. **duration query**：若源有已知时长，实现 `query` 响应 `GST_QUERY_DURATION`，
   否则下游无法显示总时长。
3. **EOS**：数据耗尽时 `fill` 返回 `GST_FLOW_EOS`，基类自动发 EOS 事件。
4. **随机访问**：`is_seekable()==TRUE` 必须实现 `do_seek` 和 `get_size`，
   否则 seek 崩或无响应。
5. **线程**：`fill` 在 BaseSrc 的 GstTask 线程跑；`unlock`/`unlock_stop` 用于
   stop 时打断阻塞的 `fill`（如阻塞在 `read()`），务必实现。

---

## 9. 开发方向三：写一个 Sink Element（完整案例）

Sink 元素消费数据。场景：硬件显示、网络输出、自定义文件格式、AI 推理输入。

### 9.1 选父类：GstBaseSink

`GstBaseSink`（`libs/gst/base/gstbasesink.c`）已实现同步、preroll、segment、事件处理。
你只需 override 渲染相关 vfunc。

| vfunc | 何时调用 | 用途 |
|-------|----------|------|
| `start`/`stop` | NULL↔READY | 打开/关闭输出目标 |
| `set_caps` | 协商后 | 初始化输出格式 |
| `get_caps` | 协商前 | 返回能接受的 caps |
| `preroll` | PAUSED 首帧 | 预渲染（显示首帧） |
| `render` | PLAYING 每帧 | 实际渲染/输出 |
| `event` | 事件到达 | 处理 EOS/flush/seek |
| `get_times` | 同步前 | 返回 buffer 的同步起止时间 |
| `query` | 查询 | 响应 position/latency 等 |
| `unlock`/`unlock_stop` | 阻塞打断 | stop 时唤醒阻塞的 render |

### 9.2 完整骨架 `mysink.c`（把数据写到自定义目标）

```c
#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif
#include <gst/gst.h>
#include <gst/base/gstbasesink.h>

GST_DEBUG_CATEGORY_STATIC (my_sink_debug);
#define GST_CAT_DEFAULT my_sink_debug

static GstStaticPadTemplate sinktemplate = GST_STATIC_PAD_TEMPLATE ("sink",
    GST_PAD_SINK, GST_PAD_ALWAYS, GST_STATIC_CAPS_ANY);

struct _MySink { GstBaseSink parent; guint64 n_buf, n_bytes; FILE *fp; };
struct _MySinkClass { GstBaseSinkClass parent_class; };

#define my_sink_parent_class parent_class
G_DEFINE_TYPE_WITH_CODE (MySink, my_sink, GST_TYPE_BASE_SINK,
    GST_DEBUG_CATEGORY_INIT (my_sink_debug, "mysink", 0, "my sink"));
GST_ELEMENT_REGISTER_DEFINE (my_sink, "my-sink", GST_RANK_NONE, MY_TYPE_SINK);

static gboolean my_sink_start (GstBaseSink *bsink) {
  MySink *self = MY_SINK (bsink);
  self->n_buf = self->n_bytes = 0;
  self->fp = stdout;   /* 示例：写到 stdout，实际可换成设备/网络 */
  return self->fp != NULL;
}
static gboolean my_sink_stop (GstBaseSink *bsink) {
  MySink *self = MY_SINK (bsink);
  if (self->fp && self->fp != stdout) fclose (self->fp);
  self->fp = NULL;
  GST_INFO_OBJECT (self, "processed %llu buffers, %llu bytes",
      (unsigned long long)self->n_buf, (unsigned long long)self->n_bytes);
  return TRUE;
}

static GstFlowReturn
my_sink_render (GstBaseSink *bsink, GstBuffer *buf)
{
  MySink *self = MY_SINK (bsink);
  GstMapInfo map;
  if (!gst_buffer_map (buf, &map, GST_MAP_READ)) return GST_FLOW_ERROR;
  /* 实际输出：这里简单写文件，可换成硬件/网络/推理 API */
  if (self->fp) fwrite (map.data, 1, map.size, self->fp);
  gst_buffer_unmap (buf, &map);
  self->n_buf++; self->n_bytes += map.size;
  return GST_FLOW_OK;
}

/* preroll：首帧就绪，可显示/准备 */
static GstFlowReturn my_sink_preroll (GstBaseSink *bsink, GstBuffer *buf) {
  GST_DEBUG_OBJECT (bsink, "preroll buffer");
  return GST_FLOW_OK;
}

/* event：处理 EOS 等 */
static gboolean my_sink_event (GstBaseSink *bsink, GstEvent *event) {
  switch (GST_EVENT_TYPE (event)) {
    case GST_EVENT_EOS:  GST_INFO_OBJECT (bsink, "EOS"); break;
    case GST_EVENT_FLUSH_START: case GST_EVENT_FLUSH_STOP: break;
    default: break;
  }
  /* chain up 让基类处理（同步/segment 维护） */
  return GST_BASE_SINK_CLASS (my_sink_parent_class)->event (bsink, event);
}

static void my_sink_class_init (MySinkClass *klass) {
  GstElementClass *ec = GST_ELEMENT_CLASS (klass);
  GstBaseSinkClass *bc = GST_BASE_SINK_CLASS (klass);
  gst_element_class_set_static_metadata (ec, "My Sink", "Sink",
      "Writes data to a custom target", "You <you@example.com>");
  gst_element_class_add_static_pad_template (ec, &sinktemplate);
  bc->start   = GST_DEBUG_FUNCPTR (my_sink_start);
  bc->stop    = GST_DEBUG_FUNCPTR (my_sink_stop);
  bc->render  = GST_DEBUG_FUNCPTR (my_sink_render);
  bc->preroll = GST_DEBUG_FUNCPTR (my_sink_preroll);
  bc->event   = GST_DEBUG_FUNCPTR (my_sink_event);
  /* get_times 不实现：基类用 buffer pts/duration 同步 */
}
static void my_sink_init (MySink *self) {
  /* 默认开启同步；实时源可 gst_base_sink_set_sync(FALSE) */
}
```

### 9.3 同步渲染 vs 异步

- **默认同步**：基类用 `get_times` 返回的时间 + clock 做同步，到点才调 `render`。
  适合音视频显示（按 pts 对齐）。
- **关闭同步**：`gst_base_sink_set_sync(sink, FALSE)`，`render` 尽快调用。
  适合"只消费不显示"（如写文件、推理）。
- **异步渲染**：若 `render` 很慢（如网络 IO），用 `gst_base_sink_do_preroll` +
  自行管理时钟等待，避免阻塞 streaming 线程。

### 9.4 涉及文件/类清单

| 文件/类 | 作用 |
|---------|------|
| `libs/gst/base/gstbasesink.h` | `GstBaseSinkClass` vfunc |
| `gst/gstbuffer.h` | render 拿到的 buffer |
| `gst/gstevent.h` | event 处理 |

### 9.5 踩坑

1. **render 阻塞**：若 `render` 阻塞（慢 IO），会反压整个 pipeline。
   用 queue 隔离或异步化。`unlock` 必须能打断阻塞。
2. **EOS 后**：`render` 不再被调用，`event` 收到 EOS。资源在 `stop` 释放。
3. **preroll 阻塞**：PAUSED 状态基类等首帧 preroll 才完成状态转换。
   若源永不产生数据，pipeline 卡在 PAUSED。
4. **segment 外 buffer**：基类默认丢弃 segment 外 buffer，
   可 `gst_base_sink_set_drop_out_of_segment` 调整。

---

## 10. 开发方向四：多输入聚合 / 多输出分发

### 10.1 何时用什么

| 需求 | 用什么 |
|------|--------|
| 多进 1 出（合流/混音/拼图） | `GstAggregator`（推荐）或手搓多 sink pad |
| 1 进多出（分发） | `tee`（已有，`plugins/elements/gsttee.c`） |
| 多进 1 出选路 | `input_selector`（已有） |
| 1 进多出选路 | `outputselector`（已有） |
| 多进多出漏斗 | `funnel`（已有） |

### 10.2 GstAggregator（推荐的多路合流基类）

`GstAggregator`（`libs/gst/base/gstaggregator.c`）为多 sink pad 合流设计：
- 自动管理多个 `GstAggregatorPad`（请求式 pad，动态添加）。
- 内部 GstTask 驱动，你只需实现 `aggregate` 决定何时输出、怎么合。
- 处理了同步、segment、latency。

核心 vfunc：

| vfunc | 用途 |
|-------|------|
| `aggregate(timeout)` | 核心：从各 sink pad 取 buffer，合成输出 buffer 推出 |
| `create_new_pad(templ)` | 请求新 pad 时创建 `GstAggregatorPad` 子类 |
| `sink_event(pad, event)` | 每个 sink pad 的事件处理 |
| `sink_query(pad, query)` | 每个 sink pad 的查询处理 |
| `find_best_sinkpad()` | 决定以哪个 pad 为基准同步 |
| `src_event`/`src_query` | src pad 的事件/查询 |
| `start`/`stop` | 资源管理 |

### 10.3 骨架 `myaggregator.c`（双路拼接）

```c
#include <gst/gst.h>
#include <gst/base/gstaggregator.h>

struct _MyAgg { GstAggregator parent; };
struct _MyAggClass { GstAggregatorClass parent_class; };

G_DEFINE_TYPE (MyAgg, my_agg, GST_TYPE_AGGREGATOR);
GST_ELEMENT_REGISTER_DEFINE (my_agg, "my-agg", GST_RANK_NONE, MY_TYPE_AGG);

static GstStaticPadTemplate src_template = GST_STATIC_PAD_TEMPLATE ("src",
    GST_PAD_SRC, GST_PAD_ALWAYS, GST_STATIC_CAPS_ANY);
static GstStaticPadTemplate sink_template = GST_STATIC_PAD_TEMPLATE ("sink_%u",
    GST_PAD_SINK, GST_PAD_REQUEST, GST_STATIC_CAPS_ANY);

static GstFlowReturn
my_agg_aggregate (GstAggregator *agg, gboolean timeout)
{
  /* 遍历所有 sink pad，各取一个 buffer，拼接后推出 */
  GList *pads = GST_ELEMENT (agg)->sinkpads;
  GstBuffer *out = gst_buffer_new ();
  for (GList *l = pads; l; l = l->next) {
    GstAggregatorPad *apad = l->data;
    GstBuffer *in = gst_aggregator_pad_pop_buffer (apad);
    if (in) {
      GstBuffer *tmp = gst_buffer_append (out, in);  /* 拼接 */
      out = tmp;
    }
  }
  if (gst_buffer_get_size (out) == 0) {
    gst_buffer_unref (out);
    return GST_FLOW_OK;  /* 没数据，等下次 */
  }
  return gst_aggregator_finish_buffer (agg, out);
}

static void my_agg_class_init (MyAggClass *klass) {
  GstElementClass *ec = GST_ELEMENT_CLASS (klass);
  GstAggregatorClass *ac = GST_AGGREGATOR_CLASS (klass);
  gst_element_class_set_static_metadata (ec, "My Agg", "Generic",
      "Concatenates multiple inputs", "You");
  gst_element_class_add_static_pad_template_with_gtype (ec, &src_template,
      GST_TYPE_AGGREGATOR_PAD);
  gst_element_class_add_static_pad_template_with_gtype (ec, &sink_template,
      GST_TYPE_AGGREGATOR_PAD);
  ac->aggregate = GST_DEBUG_FUNCPTR (my_agg_aggregate);
}
static void my_agg_init (MyAgg *self) {}
```

### 10.4 何时该用 Aggregator 而不是手搓

- **用 Aggregator**：多路同步合流、需要 latency 对齐、pad 动态增减。
- **手搓多 sink pad**：极简场景（如只要轮询各 pad，无同步需求），但你要自己处理
  pad 激活、同步、segment，工作量远大于用 Aggregator。

### 10.5 参考实现

- `plugins/elements/gstconcat.c` — 简单顺序拼接
- `plugins/elements/gstfunnel.c` — 多进一出漏斗
- `plugins/elements/gstinputselector.c` — 输入选择
- `libs/gst/base/gstaggregator.c` — 基类本身

---

## 11. 开发方向五：自定义 GstMeta（给 Buffer 挂私有数据）

### 11.1 场景

你想给每个 buffer 附加自定义元数据，且数据不参与"数据流"本身：
- AI 推理结果（检测框、类别）
- 硬件时间戳、采集序号
- 自定义对齐/stride 信息
- 帧来源标识（多路摄像头）

GstMeta 比"在 buffer 里塞私有结构"更规范：有类型注册、引用计数随 buffer、
支持 transform/serialize。

### 11.2 两种注册方式

| 方式 | API | 适用 |
|------|-----|------|
| **传统 GstMeta** | `gst_meta_register(api, impl, init, free, transform, serialize, deserialize, clear)` | 完全自定义结构 |
| **Custom Meta**（1.20+） | `gst_meta_register_custom(name, tags, transform, ...)` | 只需键值对（基于 GstStructure），更简单 |

Custom Meta 内部用 `GstStructure` 存字段，省去自己定义结构体。传统方式更灵活、
性能更好（固定结构，无字符串查表）。

### 11.3 传统 GstMeta 完整骨架

```c
/* mymeta.h */
#include <gst/gst.h>

typedef struct {
  GstMeta  meta;        /* 必须第一个字段 */
  guint64  frame_id;    /* 你的私有字段 */
  GstClockTime capture_time;
} MyMeta;

GType my_meta_api_get_type (void);
#define MY_META_API_TYPE (my_meta_api_get_type())

const GstMetaInfo * my_meta_get_info (void);
#define MY_META_INFO (my_meta_get_info())

/* 便捷宏：add/get */
#define my_buffer_add_meta(buf)  ((MyMeta*)gst_buffer_add_meta(buf, MY_META_INFO, NULL))
#define my_buffer_get_meta(buf)  ((MyMeta*)gst_buffer_get_meta(buf, MY_META_API_TYPE))
```

```c
/* mymeta.c */
G_DEFINE_BOXED_TYPE (MyMeta, my_meta, my_meta_copy, my_meta_free)  /* 若需 boxed */
/* 实际上 Meta 用 gst_meta_register，不走 G_DEFINE_BOXED；上面仅示意 */

static gboolean my_meta_init (GstMeta *m, gpointer params, GstBuffer *buf) {
  MyMeta *meta = (MyMeta *)m;
  meta->frame_id = 0;
  meta->capture_time = GST_CLOCK_TIME_NONE;
  return TRUE;
}
static void my_meta_free (GstMeta *m, GstBuffer *buf) {
  /* 释放私有资源（如指针字段） */
}
static gboolean my_meta_transform (GstBuffer *transbuf, GstMeta *m,
    GstBuffer *buf, GQuark type, gpointer data) {
  MyMeta *meta = (MyMeta *)m;
  if (GST_META_TRANSFORM_IS_COPY(type)) {
    /* buffer 被复制时，把 meta 也复制到 transbuf */
    MyMeta *new = my_buffer_add_meta (transbuf);
    new->frame_id = meta->frame_id;
    new->capture_time = meta->capture_time;
    return TRUE;
  }
  /* 其他 transform 类型（如 scale）默认不跟随 */
  return FALSE;  /* FALSE 表示不自动拷贝，你已手动处理或不需跟随 */
}

static GType my_meta_api_get_type (void) {
  static GType type = 0;
  static const gchar *tags[] = { "my-meta", NULL };
  if (!type)
    type = gst_meta_api_type_register ("MyMetaAPI", tags);
  return type;
}
static const GstMetaInfo * my_meta_get_info (void) {
  static const GstMetaInfo *info = NULL;
  if (!info)
    info = gst_meta_register (MY_META_API_TYPE, "MyMeta",
        sizeof(MyMeta), my_meta_init, my_meta_free, my_meta_transform,
        NULL /*serialize*/, NULL /*deserialize*/, NULL /*clear*/);
  return info;
}
```

使用：
```c
MyMeta *m = my_buffer_add_meta (buf);
m->frame_id = 42;
m->capture_time = gst_clock_get_time (clock);
/* 读取 */
MyMeta *r = my_buffer_get_meta (buf);
if (r) g_print ("frame %llu\n", (unsigned long long)r->frame_id);
```

### 11.4 Custom Meta（更简单）

```c
const GstMetaInfo *info = gst_meta_register_custom_simple ("MyCustomMeta");
GstCustomMeta *cm = gst_buffer_add_custom_meta (buf, "MyCustomMeta");
GstStructure *s = gst_custom_meta_get_structure (cm);
gst_structure_set (s, "frame-id", G_TYPE_UINT64, (guint64)42, NULL);
gst_structure_set (s, "confidence", G_TYPE_DOUBLE, 0.95, NULL);
/* 读取 */
GstCustomMeta *r = gst_buffer_get_custom_meta (buf, "MyCustomMeta");
if (r) {
  GstStructure *rs = gst_custom_meta_get_structure (r);
  guint64 fid; gst_structure_get_uint64 (rs, "frame-id", &fid);
}
```

### 11.5 与 BufferPool 的 clear_func 配合

BufferPool 复用 buffer 时，`clear_func`（注册时设）会被调用，清空 meta 私有状态，
避免上一帧数据泄漏到下一帧。传统 Meta 在 `gst_meta_register` 的 `clear_func` 参数里设。

### 11.6 踩坑

1. **Meta 默认不跟随 transform**：`transform_func` 返回 FALSE 时，新 buffer 不带该 meta。
   若需跟随，在 `transform_func` 里手动 `add_meta` 到 transbuf 并拷贝字段（见 11.3）。
2. **serialize/deserialize**：若 buffer 要序列化（如 splitfilesrc、网络传输），
   必须实现这两个钩子，否则 meta 丢失。
3. **线程**：meta 随 buffer 在 streaming 线程流动，读写无需额外锁（buffer 引用计数保护）。
4. **类型注册时机**：在 `plugin_init` 或 `gst_init` 后注册一次，全局共享。

---

## 12. 开发方向六：自定义 Allocator / BufferPool（内存架构定制）

### 12.1 场景

- **DMA-Buf / GPU 显存**：硬件编解码要求 buffer 在特定内存，零拷贝传递。
- **固定物理内存**：某些硬件要求连续物理地址。
- **预分配大池**：减少运行时分配抖动。
- **mmap 区**：直接包裹文件/共享内存映射，避免拷贝。

### 12.2 GstAllocator（`gst/gstallocator.h:160`）

只需 override 两个 vfunc：

```c
struct _GstAllocatorClass {
  GstObjectClass object_class;
  GstMemory *(*alloc) (GstAllocator *allocator, gsize size, GstAllocationParams *params);
  void       (*free) (GstAllocator *allocator, GstMemory *memory);
};
```

### 12.3 完整骨架（包裹外部内存的 Allocator）

```c
struct _MyAllocator { GstAllocator parent; };
struct _MyAllocatorClass { GstAllocatorClass parent_class; };

G_DEFINE_TYPE (MyAllocator, my_allocator, GST_TYPE_ALLOCATOR);

static GstMemory *
my_allocator_alloc (GstAllocator *allocator, gsize size, GstAllocationParams *params)
{
  /* 实际分配：这里用 malloc 示例，可换成 DMA-Buf/GPU/mmap */
  gsize align = params ? params->align : 0;
  gsize maxsize = size + align;
  gpointer data = g_malloc (maxsize);   /* 你的硬件分配 */
  /* 用 gst_memory_new_wrapped 把外部内存包成 GstMemory，零拷贝 */
  GstMemory *mem = gst_memory_new_wrapped_full (
      GST_MEMORY_FLAG_NO_SHARE, data, maxsize, 0, size,
      data, g_free);   /* data 释放时调 g_free */
  return mem;
}
static void
my_allocator_free (GstAllocator *allocator, GstMemory *mem)
{
  /* 若用 gst_memory_new_wrapped_full，free 由 notify 处理；这里可不实现 */
}
static void my_allocator_class_init (MyAllocatorClass *klass) {
  GstAllocatorClass *ac = GST_ALLOCATOR_CLASS (klass);
  ac->alloc = GST_DEBUG_FUNCPTR (my_allocator_alloc);
  ac->free  = GST_DEBUG_FUNCPTR (my_allocator_free);
}
static void my_allocator_init (MyAllocator *self) {}

/* 注册成命名 allocator，供 decide_allocation 查找 */
void my_allocator_register (void) {
  gst_allocator_register ("MyAllocator", g_object_new (MY_TYPE_ALLOCATOR, NULL));
}
```

### 12.4 GstBufferPool（`gst/gstbufferpool.c`）

BufferPool 预分配并复用 buffer。自定义 pool 通常继承 `GstBufferPool`，override：
- `default_acquire_buffer`：从池取 buffer（默认实现够用，可 override 加策略）
- `default_release_buffer`：归还 buffer（可 override 触发 clear_meta）
- `default_free`：池销毁时释放

多数情况**不需自定义 pool**：在 Element 的 `decide_allocation` 里配置默认 pool：
```c
static gboolean my_filter_decide_allocation (GstBaseTransform *trans, GstQuery *query) {
  GstCaps *caps; GstBufferPool *pool = NULL; guint size, min, max;
  gst_query_parse_allocation (query, &caps, NULL);
  /* 查看下游是否已提供 pool */
  if (gst_query_get_n_allocation_pools (query) > 0)
    pool = gst_buffer_pool_new ();   /* 或用下游的 */
  GstStructure *config = gst_buffer_pool_get_config (pool);
  gst_buffer_pool_config_set_params (config, caps, size, min, max);
  gst_buffer_pool_config_set_allocator (config, my_allocator, NULL);  /* 你的 allocator */
  gst_buffer_pool_set_config (pool, config);
  gst_query_add_allocation_pool (query, pool, size, min, max);
  gst_object_unref (pool);
  return TRUE;
}
```

### 12.5 decide_allocation / propose_allocation 钩子

- **decide_allocation**（输出端，BaseTransform/BaseSrc）：决定输出 buffer 用什么
  pool/allocator，写入 `GST_QUERY_ALLOCATION` 回复给下游。
- **propose_allocation**（输入端，BaseTransform/BaseSink）：向上游建议输入 buffer
  用什么 pool/allocator。

这是零拷贝链路的关键：上游用你提议的 allocator 分配，下游直接用，不拷贝。

### 12.6 涉及文件/类清单

| 文件/类 | 作用 |
|---------|------|
| `gst/gstallocator.h` | `GstAllocatorClass`（alloc/free） |
| `gst/gstmemory.h` | `gst_memory_new_wrapped_full`（包裹外部内存） |
| `gst/gstbufferpool.h` | `GstBufferPool` + config API |
| `gst/gstquery.h` | `GST_QUERY_ALLOCATION` 协商 |

### 12.7 踩坑

1. **对齐**：硬件常要求特定对齐（如 16/32 字节），用 `GstAllocationParams.align` 传达。
2. **GST_MEMORY_FLAG_NO_SHARE**：不可共享的内存（如 GPU 上下文相关）要设此 flag，
   否则被切片共享会出错。
3. **pool 水位**：min/max buffers 设太小会卡顿，太大会占内存。视频一般 min=2/4。
4. **生命周期**：wrapped 内存的 `notify`（如 `g_free`）在 memory 释放时调用，
   确保外部资源随 buffer 释放。

---

## 13. 开发方向七：自定义 Tracer（性能/行为追踪）

### 13.1 场景

你想观测 pipeline 运行时的行为，但不想改数据流：
- 统计每个 element 的吞吐量、延迟、丢帧
- 记录每次 pad push/pull 的耗时
- 自定义指标（如 AI 推理帧率、缓冲区水位）
- 导出为 Prometheus/自定义格式

Tracer 是**观测者模式**：挂在核心数据路径上，只读不改，开销极小。

### 13.2 机制

`GstTracer`（`gst/gsttracer.h:309`）继承 `GstObject`。核心 API：
```c
void gst_tracing_register_hook (GstTracer *tracer, const gchar *detail, GCallback func);
```
`detail` 是钩子名（如 `"pad-push-pre"`），核心在对应位置埋了调用点。
注册后，每次核心执行到该点就调你的 `func`。

### 13.3 可用钩子（部分，见 `plugins/tracers/gststats.c`）

| 钩子 | 触发时机 |
|------|----------|
| `pad-push-pre` / `pad-push-post` | `gst_pad_push` 前/后 |
| `pad-push-list-pre` / `pad-push-list-post` | `gst_pad_push_list` 前/后 |
| `pad-pull-range-pre` / `pad-pull-range-post` | `gst_pad_pull_range` 前/后 |
| `pad-push-event-pre` | push event 前 |
| `pad-query-pre` / `pad-query-post` | pad query 前/后 |
| `element-new` | element 创建 |
| `element-post-message-pre` | post message 前 |
| `element-query-pre` | element query 前 |

### 13.4 完整骨架 `mytracer.c`

```c
#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif
#include <gst/gst.h>

struct _MyTracer { GstTracer parent; guint64 push_count; };
struct _MyTracerClass { GstTracerClass parent_class; };

#define my_tracer_parent_class parent_class
G_DEFINE_TYPE (MyTracer, my_tracer, GST_TYPE_TRACER);
GST_TRACER_REGISTER_DEFINE (my_tracer, "my-tracer");  /* 1.20+ 宏 */

/* 钩子回调：签名要匹配钩子（见 gsttracerutils.h 的 typedef） */
static void
do_push_pre (GstTracer *tracer, GstClockTime ts, GstPad *pad)
{
  MyTracer *self = MY_TRACER (tracer);
  self->push_count++;
  if (self->push_count % 100 == 0)
    GST_INFO_OBJECT (tracer, "pushed %llu buffers", (unsigned long long)self->push_count);
}

static void
my_tracer_init (MyTracer *self)
{
  GstTracer *tracer = GST_TRACER (self);
  self->push_count = 0;
  gst_tracing_register_hook (tracer, "pad-push-pre", G_CALLBACK (do_push_pre));
  /* 可注册多个钩子 */
}
static void my_tracer_class_init (MyTracerClass *klass) {}
```

插件入口同 §7.4，用 `GST_TRACER_REGISTER(my_tracer, plugin)` 在 `plugin_init` 里注册。

### 13.5 激活方式

```bash
GST_TRACERS="my-tracer" gst-launch-1.0 videotestsrc ! fakesink
# 多个 tracer 用分号或逗号分隔
GST_TRACERS="my-tracer;stats" gst-launch-1.0 ...
```

环境变量 `GST_TRACERS` 在 `gst_init` 时被解析，实例化列出的 tracer。

### 13.6 参考实现

- `plugins/tracers/gststats.c` — 统计吞吐/延迟，输出 `gst-stats` 工具格式
- `plugins/tracers/gstlatency.c` — 端到端延迟测量
- `plugins/tracers/gstleaks.c` — 对象泄漏检测
- `plugins/tracers/gstrusage.c` — CPU/内存资源使用
- `plugins/tracers/gstdots.c` — 生成 pipeline dot 图

### 13.7 踩坑

1. **性能**：钩子在热路径，回调必须极快（无锁、无 IO、无分配）。重活异步化。
2. **线程**：钩子在 streaming 线程调用，计数器用原子操作或接受近似值。
3. **钩子签名**：每个钩子的回调签名不同（参数数量/类型），必须精确匹配，
   参考 `gst/gsttracerutils.h` 的 typedef，否则栈错乱。

---

## 14. 开发方向八：自定义时钟 / 控制源 / 设备提供 / TypeFind

四个较小但实用的扩展点，各给精简骨架。

### 14.1 自定义 GstClock（外部时钟同步）

场景：硬件时钟、PTP 主时钟、自定义同步源。继承 `GstClock`，override `get_internal_time`：

```c
struct _MyClock { GstClock parent; };
G_DEFINE_TYPE (MyClock, my_clock, GST_TYPE_CLOCK);

static GstClockTime my_clock_get_internal_time (GstClock *clock) {
  /* 返回你的硬件时钟当前纳秒值 */
  return read_hardware_clock_ns ();
}
static void my_clock_class_init (MyClockClass *klass) {
  GstClockClass *cc = GST_CLOCK_CLASS (klass);
  cc->get_internal_time = GST_DEBUG_FUNCPTR (my_clock_get_internal_time);
}
```

参考：`gst/gstsystemclock.c`（系统时钟）、`libs/gst/net/gstnetclientclock.c`（网络时钟）、
`libs/gst/net/gstptpclock.c`（PTP）。把你的 clock 通过 `gst_pipeline_use_clock` 设给 pipeline。

### 14.2 自定义 GstControlSource（属性动画）

场景：让某属性随时间按曲线变化（音量淡入、参数扫描）。最简方式：用已有的
`GstInterpolationControlSource`（`libs/gst/controller/`），插入控制点绑定到属性：

```c
GstInterpolationControlSource *cs = gst_interpolation_control_source_new ();
gst_timed_value_control_source_set (GST_TIMED_VALUE_CONTROL_SOURCE (cs),
    0 * GST_SECOND, 0.0);
gst_timed_value_control_source_set (GST_TIMED_VALUE_CONTROL_SOURCE (cs),
    5 * GST_SECOND, 1.0);
GstControlBinding *cb = gst_direct_control_binding_new (element, "volume",
    GST_CONTROL_SOURCE (cs));
gst_object_add_control_binding (GST_OBJECT (element), cb);
```

自定义 source 继承 `GstControlSource`（`gst/gstcontrolsource.h`），参考
`libs/gst/controller/gstlfocontrolsource.c`（LFO 波形）。

### 14.3 自定义 GstDeviceProvider（设备发现）

场景：摄像头、声卡、采集卡热插拔。继承 `GstDeviceProvider`（`gst/gstdeviceprovider.h:169`），
override `probe` / `start` / `stop`：

```c
struct _MyProvider { GstDeviceProvider parent; };
G_DEFINE_TYPE (MyProvider, my_provider, GST_TYPE_DEVICE_PROVIDER);

static GList * my_provider_probe (GstDeviceProvider *provider) {
  GList *devices = NULL;
  devices = g_list_append (devices, my_device_new ("dev0"));  /* 枚举设备 */
  return devices;
}
static gboolean my_provider_start (GstDeviceProvider *provider) {
  /* 开始监控热插拔，发现时调 gst_device_provider_device_add */
  return TRUE;
}
static void my_provider_stop (GstDeviceProvider *provider) { /* 停止监控 */ }
static void my_provider_class_init (MyProviderClass *klass) {
  GstDeviceProviderClass *pc = GST_DEVICE_PROVIDER_CLASS (klass);
  pc->probe = GST_DEBUG_FUNCPTR (my_provider_probe);
  pc->start = GST_DEBUG_FUNCPTR (my_provider_start);
  pc->stop  = GST_DEBUG_FUNCPTR (my_provider_stop);
  gst_device_provider_class_set_metadata (pc, "My Devices",
      "Source/Video", "My hardware devices", "You");
}
```

应用层用 `GstDeviceMonitor`（`gst/gstdevicemonitor.c`）发现并创建 element。

### 14.4 自定义 GstTypeFind（格式探测）

场景：新容器/文件格式，让 GStreamer 能识别。用 `GST_TYPE_FIND_REGISTER` 宏
（`gst/gsttypefind.h:80`）注册一个 `GstTypeFindFunction`：

```c
static void
my_type_find (GstTypeFind *tf, gpointer data)
{
  guint8 *d = gst_type_find_peek (tf, 0, 4);
  if (d && d[0]==0xAB && d[1]==0xCD) {  /* 你的 magic */
    gst_type_find_suggest (tf, GST_TYPE_FIND_MAXIMUM,
        gst_caps_new_empty_simple ("application/x-my-format"));
  }
}
GST_TYPE_FIND_REGISTER_DEFINE (my_type_find, "my-format",
    GST_RANK_PRIMARY, my_type_find, "my", GST_CAPS_ANY, NULL, NULL);
/* plugin_init 里: GST_TYPE_FIND_REGISTER (my_type_find, plugin); */
```

参考 `libs/gst/base/gsttypefindhelper.c` 和外部 `gst-plugins-base` 的 typefind 实现。

---

## 15. 开发方向九：应用层定制（不碰核心）

不想编译插件，只在应用 `main()` 里加逻辑。用公开 API 即可，侵入度最低。

### 15.1 动态插拔 Pad

场景：运行时增删分支、接新源。用 `gst_element_link`/`unlink` + `pad-added` 信号：

```c
GstElement *pipe = gst_pipeline_new ("pipe");
GstElement *src = gst_element_factory_make ("uridecodebin", "src");
GstElement *conv = gst_element_factory_make ("videoconvert", "conv");
GstElement *sink = gst_element_factory_make ("autovideosink", "sink");
gst_bin_add_many (GST_BIN (pipe), src, conv, sink, NULL);
gst_element_link (conv, sink);

/* uridecodebin 动态产生 src pad，连上时再 link */
g_signal_connect (src, "pad-added", G_CALLBACK (on_pad_added), conv);
g_signal_connect (src, "no-more-pads", G_CALLBACK (on_no_more_pads), NULL);

static void on_pad_added (GstElement *e, GstPad *new_pad, gpointer data) {
  GstElement *conv = GST_ELEMENT (data);
  GstPad *sinkpad = gst_element_get_static_pad (conv, "sink");
  if (gst_pad_can_link (new_pad, sinkpad))
    gst_pad_link (new_pad, sinkpad);
  gst_object_unref (sinkpad);
}
```

### 15.2 Pad Probe（拦截/改写/丢弃数据，不写 element）

最强大的应用层手段。在任意 pad 上挂回调，数据/事件/查询经过时被调用：

```c
gulong id = gst_pad_add_probe (pad,
    GST_PAD_PROBE_TYPE_BUFFER, my_probe, NULL, NULL);

static GstPadProbeReturn
my_probe (GstPad *pad, GstPadProbeInfo *info, gpointer data)
{
  GstBuffer *buf = GST_PAD_PROBE_INFO_BUFFER (info);
  /* 读：统计、记录 */
  GST_INFO ("buf pts=%" GST_TIME_FORMAT, GST_TIME_ARGS (GST_BUFFER_PTS (buf)));
  /* 改：改时间戳（buf 已 writable，probe 拿到的是可写引用） */
  GST_BUFFER_PTS (buf) += 1 * GST_SECOND;
  /* 丢：返回 DROP */
  if (should_drop) return GST_PAD_PROBE_DROP;
  /* 放行 */
  return GST_PAD_PROBE_OK;
}
/* 移除 */
gst_pad_remove_probe (pad, id);
```

Probe 类型（`GST_PAD_PROBE_TYPE_*`）：
- `BUFFER` — 数据 buffer
- `BUFFER_LIST` — buffer 列表
- `EVENT_DOWNSTREAM`/`EVENT_UPSTREAM` — 事件
- `QUERY_DOWNSTREAM`/`QUERY_UPSTREAM` — 查询
- `BLOCK` — 阻塞 pad（配合动态插拔，先阻塞再 unlink/link）

**典型用法**：动态换 sink 时，先 `gst_pad_add_probe(pad, BLOCK, ...)` 阻塞数据流，
在回调里安全 unlink 旧 sink、link 新 sink，再移除 probe。这是 GStreamer 动态修改
拓扑的标准模式（见 `tools/gst-launch.c` 的 EOS 处理）。

### 15.3 Bus 消息处理

```c
GstBus *bus = gst_element_get_bus (pipe);
gst_bus_add_watch (bus, bus_handler, NULL);
gst_object_unref (bus);

static gboolean bus_handler (GstBus *bus, GstMessage *msg, gpointer data) {
  switch (GST_MESSAGE_TYPE (msg)) {
    case GST_MESSAGE_EOS:    g_main_loop_quit (loop); break;
    case GST_MESSAGE_ERROR:  { GError *e; gst_message_parse_error (msg, &e, NULL);
                               g_print ("err: %s", e->message); g_error_free (e);
                               g_main_loop_quit (loop); break; }
    case GST_MESSAGE_STATE_CHANGED: /* 状态变化 */ break;
    case GST_MESSAGE_BUFFERING: { gint pct; gst_message_parse_buffering (msg, &pct);
                                   if (pct<100) gst_element_set_state(pipe,PAUSED);
                                   else gst_element_set_state(pipe,PLAYING); break; }
    default: break;
  }
  return TRUE;  /* TRUE 保留 watch，FALSE 移除 */
}
```

### 15.4 launch 字符串 + 手动组合混合

```c
GstElement *pipe = gst_parse_launch ("videotestsrc ! queue ! autovideosink", NULL);
/* 拿到后还能手动改：加 probe、改属性、动态加 element */
GstElement *queue = gst_bin_get_by_name (GST_BIN (pipe), "queue0");
gst_element_set_property (queue, "max-size-time", 2 * GST_SECOND);
```

### 15.5 何时用应用层定制而非写插件

| 情况 | 选择 |
|------|------|
| 逻辑只在这一个应用里 | 应用层（§15） |
| 逻辑要复用、要被 gst-launch 用 | 写插件（§7+） |
| 要拦截/观察数据但不改处理 | Pad Probe（§15.2） |
| 要改数据格式/内容 | 写 Element（§7） |

---

## 16. 修改核心库本身（高侵入，慎用）

### 16.1 何时该改 `gst/` 内部

极少。只在以下情况考虑：
1. **协议级语义改动**：如改变 Caps 协商规则、状态机语义——这些是核心契约，
   无法用插件改。
2. **核心性能瓶颈**：如 `gst_pad_push`/`gst_pad_chain` 热路径有可证实的开销，
   且无法用 Tracer/Probe 替代。
3. **新增核心级 hook**：如给所有 element 加一个新 vfunc（影响 ABI，慎之又慎）。

> 99% 的"我想改 GStreamer 行为"都能用插件/应用层解决。改核心库前先问：
> "能不能写个插件？" 几乎总能。

### 16.2 改动点示例（仅说明，不鼓励）

- `gst/gstpad.c`：`gst_pad_push`/`gst_pad_chain` 数据路径。
  Tracer 钩子就埋在这里（`pad-push-pre` 等）。
- `gst/gstbin.c`：状态传播 `gst_bin_change_state_func`、子元素管理。
- `gst/gstelement.c`：状态机核心 `gst_element_set_state`/`change_state`。
- `gst/gstutils.c`：通用工具函数。

### 16.3 ABI 兼容与维护

- **GST_PADDING**：所有公开结构体末尾有 `gpointer _gst_reserved[GST_PADDING]`
  预留位，用于未来加字段而不破坏 ABI。**不要挪用**，否则破坏二进制兼容。
- **新增 vfunc**：只能加到 Class 结构末尾的预留位，且要考虑旧子类未实现的后果。
- **版本号**：改了核心要同步升 `GST_VERSION_MINOR`（`gst/gstversion.h.in`）。
- **上游贡献**：改核心最好走上游 PR，否则私有 fork 要持续 merge 上游更新，成本高。

### 16.4 替代方案优先级

```
应用层定制 (§15)  >  外部插件 (§7-14)  >  改核心库 (§16)
   侵入度低                              侵入度高
   维护成本低                             维护成本高
```

---

## 17. 二次开发常见陷阱与最佳实践

汇总前面各章踩坑，按类别归并，便于速查。

### 17.1 线程

| 陷阱 | 说明 | 对策 |
|------|------|------|
| 跨线程改共享字段 | `set_property`（应用线程）改 `transform`（streaming 线程）读的字段 | `GST_OBJECT_LOCK` 保护，或异步 `post_message` |
| 阻塞 streaming 线程 | `render`/`transform` 里做慢 IO | 用 queue 隔离，或异步化；`unlock` 必须能打断 |
| 忘记 `unlock` | stop 时 `fill`/`render` 仍阻塞 | 实现 `unlock`/`unlock_stop` 唤醒阻塞 |
| Bus 回调线程 | `gst_bus_add_watch` 回调在主循环或 Bus 线程 | 跨线程访问 Element 用锁 |

### 17.2 引用计数

| 陷阱 | 说明 | 对策 |
|------|------|------|
| ref/unref 不配对 | 泄漏或 use-after-free | 严格配对；用 `gst_clear_*` 宏 |
| push 后还用 buffer | push 所有权转移给下游 | push 后不再碰，除非先 `ref` |
| `_full` 变体语义 | `gst_pad_push_full` 等带所有权转移 | 读文档确认 transfer 语义 |
| floating ref | Element 创建时 floating，加入 Bin 后 sink | 别手动 sink 除非你知道在做什么 |

### 17.3 Caps 协商

| 陷阱 | 说明 | 对策 |
|------|------|------|
| chain 里改 caps | 运行中改 caps 破坏协商 | 只在 `set_caps`/`transform_caps` 改 |
| 不实现 transform_caps | 改格式的 filter 没实现，下游拿错 caps | 改格式必实现 |
| fixate 不定值 | 多个可能 caps 没收敛 | 实现 `fixate_caps` 选定值 |

### 17.4 状态机

| 陷阱 | 说明 | 对策 |
|------|------|------|
| start/stop 时机错 | 在错的状态转换里分配/释放 | start=NULL→READY，stop=PAUSED→READY |
| preroll 卡住 | sink 等首帧，源不产生 | 确保源会推数据或发 EOS |
| change_state 不 chain up | override 后没调父类 | 必须 `parent_class->change_state` |

### 17.5 Buffer 可写性

| 陷阱 | 说明 | 对策 |
|------|------|------|
| 写非 writable buffer | refcount>1 时改写，破坏共享 | `gst_buffer_make_writable` 先 |
| in-place 误用 | 非 in-place 模式直接改 inbuf | in-place 要 `set_in_place(TRUE)` |
| Meta 不跟随 | transform 到新 buf，Meta 丢 | `transform_meta` 显式处理 |

### 17.6 错误传播

- `GstFlowReturn`：`GST_FLOW_OK` 继续，`GST_FLOW_FLUSHING` 被冲刷，
  `GST_FLOW_EOS` 结束，`GST_FLOW_ERROR` 出错，`GST_FLOW_NOT_NEGOTIATED` 协商失败。
- vfunc 返回非 OK 会向上游传播，基类据此停流或发消息。
- 出错时用 `GST_ELEMENT_ERROR(elem, LIBRARY, FAILED, (msg), (debug))` 宏发错误消息。

### 17.7 日志

```c
GST_DEBUG_CATEGORY_INIT (cat, "myfilter", 0, "my filter");
#define GST_CAT_DEFAULT cat
GST_ERROR_OBJECT (self, "fatal: %s", s);   /* ERROR 级 */
GST_WARNING_OBJECT (self, "warn: %d", n);
GST_INFO_OBJECT (self, "info");
GST_DEBUG_OBJECT (self, "debug");
GST_LOG_OBJECT (self, "trace");              /* LOG 级 */
```
- `GST_DEBUG=myfilter:5` 开到 LOG 级，`*:3` 全局 INFO。
- 用 `_OBJECT` 变体带对象名前缀，便于定位。

### 17.8 测试

- `tests/check/` 是 GStreamer 单元测试框架（`libs/gst/check/`）。
- 写 Element 时配套 `tests/check/elements/myfilter.c`，用 `gst_check` 宏断言
  buffer 数量、caps、flow return。
- `gst-validate`（`tests/validate/`）做场景级验证。

---

## 18. 开发决策树（我该选哪条路）

把前面所有方向收束成"按需求查表"。

```
你的需求是什么？
│
├─ 处理/产生/消费数据？
│   │
│   ├─ 1 进 1 出，改数据 ────────────────▶ §7 GstBaseTransform
│   │   ├─ 原地改（尺寸不变） ───────────▶ transform_ip + in_place
│   │   └─ 改格式 ──────────────────────▶ transform + transform_caps
│   │
│   ├─ 产生数据（源） ──────────────────▶ §8
│   │   ├─ 实时/不可 seek ──────────────▶ GstPushSrc（fill）
│   │   └─ 可随机访问 ──────────────────▶ GstBaseSrc（create + do_seek）
│   │
│   ├─ 消费数据（宿） ──────────────────▶ §9 GstBaseSink（render）
│   │
│   ├─ 多进 1 出（合流） ────────────────▶ §10 GstAggregator
│   │
│   └─ 解析容器/流 ──────────────────────▶ GstBaseParse（handle_frame）
│
├─ 伴随数据但不改数据？
│   │
│   ├─ 给 Buffer 贴私有标签 ─────────────▶ §11 GstMeta
│   ├─ 观察/统计流量 ────────────────────▶ §13 GstTracer 或 §15.2 Pad Probe
│   └─ 拦截/改写/丢数据（一次性） ────────▶ §15.2 Pad Probe
│
├─ 不碰数据流，只做控制/观测？
│   │
│   ├─ 属性动画 ────────────────────────▶ §14.2 ControlSource
│   ├─ 自定义时钟/同步 ──────────────────▶ §14.1 GstClock
│   ├─ 设备发现 ────────────────────────▶ §14.3 DeviceProvider
│   ├─ 格式探测 ────────────────────────▶ §14.4 TypeFind
│   └─ 性能/行为追踪 ────────────────────▶ §13 GstTracer
│
├─ 内存/零拷贝？
│   ├─ 自定义内存来源 ──────────────────▶ §12 GstAllocator
│   └─ 缓冲池策略 ──────────────────────▶ §12 GstBufferPool + decide_allocation
│
├─ 只在应用里加逻辑，不编译？
│   ├─ 动态插拔 ────────────────────────▶ §15.1 pad-added + link
│   ├─ 拦截数据 ────────────────────────▶ §15.2 Pad Probe
│   └─ 消息处理 ────────────────────────▶ §15.3 Bus watch
│
└─ 协议级/核心瓶颈？
    └─ 改核心库 ────────────────────────▶ §16（最后手段）
```

**父类速选口诀**：
- 滤镜 → `GstBaseTransform`
- 源 → `GstPushSrc`（实时）/ `GstBaseSrc`（可 seek）
- 宿 → `GstBaseSink`
- 合流 → `GstAggregator`
- 解析 → `GstBaseParse`

---

## 19. 你可能没考虑到的（补充）

这些点不直接是"开发方向"，但二次开发中常被忽略，影响成品质量与分发。

### 19.1 国际化（i18n）

GStreamer 用 GLib 的 `gettext`。插件里用户可见字符串（错误信息、属性描述）应可翻译：
```c
#include <glib/gi18n-lib.h>   // 注意是 gi18n-lib，不是 gi18n
g_param_spec_string ("location", _("Location"), _("File location"),
    NULL, G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);
```
- `gi18n-lib` 用于库/插件，`gi18n` 用于应用。
- 在 meson 里配 `i18n.gettext('gst-my-plugins')`，生成 `.po/.mo`。
- 核心库 `po/` 目录已有翻译模板可参考。

### 19.2 调试体系

- **GST_DEBUG**：`GST_DEBUG=2,myfilter:5`（全局 WARN，myfilter 到 LOG）。
- **GST_DEBUG_FILE**：输出到文件而非 stderr。
- **gst-info / gst-stats**：`tools/` 下的工具，分析日志/统计。
- **dot 图**：`GST_DEBUG_DUMP_DOT_DIR=/tmp gst-launch ...` 生成 pipeline 拓扑 dot 图，
  或代码里 `gst_debug_bin_to_dot_file(bin, GST_DEBUG_GRAPH_SHOW_ALL, "name")`
  （`gst/gstdebugutils.c`）。用 graphviz 渲染成图，调试拓扑/状态极有用。
- **leaks tracer**：`GST_TRACERS=leaks gst-launch ...` 检测对象泄漏，开发期必备。

### 19.3 插件版本与 registry 缓存

- 改了插件源码但没生效：registry 二进制缓存（`~/.cache/gstreamer-1.0/registry-*.bin`）
  可能未更新。删掉它或 `GST_REGISTRY_UPDATE=1` 强制重扫。
- 插件 `GST_VERSION_MINOR` 与核心不匹配会被拒载。跨大版本要重新编译。
- `gst-inspect-1.0` 看不到你的插件：检查 `name_prefix: 'gst'`、`GST_PLUGIN_PATH`、
  `.so` 是否真的装到插件目录。

### 19.4 跨平台差异

| 平台 | 注意 |
|------|------|
| Linux | 主平台，DMABuf、shm、udev device provider |
| Windows | `gst/gstpluginloader-win32.c`（插件加载器不同）、FD 源/宿条件编译 |
| macOS | `gst/gstmacos.m`（Objective-C 时钟/主循环集成） |
| Android | `gst/gstandroid.c`（Android 特定初始化）、静态链接常见 |

二次开发时用条件编译（`#ifdef G_OS_WIN32` 等）处理平台差异，参考 `plugins/elements/gstcoreelementsplugin.c`
对 `fdsrc/fdsink` 的 `#if defined(HAVE_SYS_SOCKET_H) || defined(G_OS_WIN32)`。

### 19.5 与外部生态的边界

本代码库只是**核心库**。完整 GStreamer 生态：

| 仓库 | 内容 | 与二次开发关系 |
|------|------|----------------|
| `gstreamer` | 核心（本库） | 你基于它 |
| `gst-plugins-base` | 基础插件（videoconvert/audioconvert/decodebin...）+ `libs/gst/video` 等库 | 常被你的插件依赖 |
| `gst-plugins-good` | 稳定插件（vpx、jpeg...） | 可参考实现 |
| `gst-plugins-bad` | 实验性插件（nvcodec、webrtc...） | 硬件/AI 插件多在此 |
| `gst-plugins-ugly` | 许可受限插件（x264...） | 分发注意许可 |
| `gst-rtsp-server` | RTSP 服务 | 流媒体服务开发 |
| `gstreamer-vaapi` | 硬件加速 | 硬件编解码 |

写视频/音频 Element 时，通常依赖 `gst-plugins-base` 的 `gst-video-1.0`/`gst-audio-1.0` 库
（提供 `GstVideoInfo`、`GstAudioInfo` 等格式描述），而非自己解析。

### 19.6 语言绑定（introspection）

GStreamer 通过 GObject Introspection 生成 `.gir`/`.typelib`，供 Python/JS/Rust 等绑定：
- Python：`gi.repository.Gst`，可用 Python 写应用层逻辑（§15），但写 Element 仍需 C。
- 你的插件若想被 Python 用，确保 meson 里开了 `introspection`，属性/信号有完整 `GParamSpec`。
- 绑定对二次开发的影响：应用层可用 Python 快速原型，Element 层仍需 C/GObject。

### 19.7 安全

- **解析器**：`gst/parse/`（`grammar.y.in`/`parse.l`）解析 launch 字符串。
  若接受不可信 launch 字符串，注意注入（属性值、文件路径）。应用层应校验。
- **插件加载**：`GST_PLUGIN_PATH` 指向的目录会被 `dlopen`，不要指向不可信目录。
- **typefind**：探测未知格式时可能被恶意文件触发大量工作，注意超时/大小限制。

### 19.8 性能

- **zero-copy**：§12 的自定义 allocator + `decide_allocation`/`propose_allocation`
  协商，让 buffer 在 element 间不拷贝。视频处理性能关键。
- **线程数**：每个 queue 后是新 streaming 线程。过多 queue = 过多线程 + 上下文切换。
  按需用 queue（隔离慢 element、多分支）。
- **queue 水位**：`queue` 的 `max-size-buffers/time/bytes` 太小会频繁阻塞，
  太大增延迟。按场景调。
- **passthrough**：不改数据的 element 设 `passthrough=TRUE`，基类跳过 buffer 分配/拷贝。

### 19.9 许可证（LGPL vs GPL）

- GStreamer 核心是 **LGPL**。`GST_PLUGIN_DEFINE` 的 license 参数声明你的插件许可。
- **LGPL 插件**：可被闭源应用动态链接，分发友好。绝大多数第三方插件选 LGPL。
- **GPL 插件**：要求链接它的应用也开源，限制分发。
- 静态链接 LGPL 插件到闭源应用需满足 LGPL 条款（可替换性），见 `README.static-linking`。
- 二次开发分发前确认：你用的依赖插件许可、你的插件许可、应用许可三者兼容。

### 19.10 文档生成

- `docs/` 下用 gtk-doc/meson 生成 API 文档。
- Element 的 `SECTION:element-xxx` 注释块（见 `gstidentity.c` 顶部）会被
  `gst-plugins-base` 的文档工具提取。给每个 Element 写这种注释，`gst-inspect` 和
  文档都会用到。

---

## 20. 附录

### 20.1 核心文件 → 二次开发相关度速查

| 文件 | 相关度 | 你什么时候碰它 |
|------|--------|----------------|
| `gst/gst.h` | 必用 | 总入口，include 它 |
| `gst/gstelement.h` | 必用 | 继承/注册 Element、Pad 模板宏 |
| `gst/gstpad.h` | 常用 | 设 chain/getrange/event/query、Probe |
| `gst/gstbuffer.h` | 常用 | 读写 buffer |
| `gst/gstmemory.h` | 中 | 自定义 allocator 时 |
| `gst/gstmeta.h` | 中 | 自定义 Meta 时 |
| `gst/gstcaps.h` | 常用 | 协商 |
| `gst/gstevent.h`/`gstquery.h`/`gstmessage.h` | 中 | 事件/查询/消息 |
| `gst/gstplugin.h` | 必用 | `GST_PLUGIN_DEFINE` |
| `gst/gstpadtemplate.h` | 常用 | `GST_STATIC_PAD_TEMPLATE` |
| `gst/gstinfo.h` | 常用 | 日志 |
| `gst/gstclock.h`/`gstsystemclock.h` | 低 | 自定义时钟 |
| `gst/gsttracer.h` | 低 | 自定义 Tracer |
| `gst/gstallocator.h` | 低 | 自定义 Allocator |
| `gst/gstbufferpool.h` | 低 | 自定义 Pool |
| `gst/gstcontrolsource.h` | 低 | 属性动画 |
| `gst/gstdeviceprovider.h` | 低 | 设备发现 |
| `gst/gsttypefind.h` | 低 | 格式探测 |
| `libs/gst/base/gstbasetransform.h` | **高频** | 写滤镜 |
| `libs/gst/base/gstbasesrc.h`/`gstpushsrc.h` | **高频** | 写源 |
| `libs/gst/base/gstbasesink.h` | **高频** | 写宿 |
| `libs/gst/base/gstaggregator.h` | 中 | 写合流 |
| `libs/gst/base/gstbaseparse.h` | 中 | 写解析器 |
| `libs/gst/base/gstadapter.h` | 中 | 拼接字节流（解析器常用） |
| `libs/gst/base/gstcollectpads.h` | 中 | 多 pad 同步收集（老式合流） |
| `libs/gst/controller/*` | 低 | 属性动画 |
| `libs/gst/net/*` | 低 | 网络时钟/PTP |
| `plugins/elements/gstidentity.c` | 参考 | 最简 transform 样例 |
| `plugins/elements/gstfakesrc.c`/`gstfakesink.c` | 参考 | 最简 src/sink 样例 |
| `plugins/elements/gstqueue.c` | 参考 | queue 实现 |
| `plugins/elements/gsttee.c` | 参考 | 1 进多出 |
| `plugins/tracers/gststats.c` | 参考 | Tracer 样例 |
| `tools/gst-launch.c` | 参考 | 应用层完整用法 |

### 20.2 基类 vfunc 速查

**GstBaseTransform**（`libs/gst/base/gstbasetransform.h:218`）：
`transform`、`transform_ip`、`transform_caps`、`fixate_caps`、`accept_caps`、
`set_caps`、`query`、`decide_allocation`、`propose_allocation`、`transform_size`、
`get_unit_size`、`start`、`stop`、`sink_event`、`src_event`、`prepare_output_buffer`、
`copy_metadata`、`transform_meta`、`before_transform`、`submit_input_buffer`、
`generate_output`、`prepare_allocator`。

**GstBaseSrc**（`libs/gst/base/gstbasesrc.h:171`）：
`get_caps`、`negotiate`、`fixate`、`set_caps`、`decide_allocation`、`start`、`stop`、
`get_times`、`get_size`、`is_seekable`、`prepare_seek_segment`、`do_seek`、`unlock`、
`unlock_stop`、`query`、`event`、`create`、`alloc`、`fill`、`prepare_allocator`。

**GstBaseSink**（`libs/gst/base/gstbasesink.h:165`）：
`get_caps`、`set_caps`、`fixate`、`activate_pull`、`get_times`、`propose_allocation`、
`start`、`stop`、`unlock`、`unlock_stop`、`query`、`event`、`wait_event`、`prepare`、
`prepare_list`、`preroll`、`render`、`render_list`。

**GstAggregator**（`libs/gst/base/gstaggregator.h:262`）：
`aggregate`、`create_new_pad`、`sink_pad_cloned`、`find_best_sinkpad`、
`sink_event`、`sink_query`、`src_event`、`src_query`、`start`、`stop`、`get_next_time`、
`create_new_pad`、`negotiate`、`decide_allocation`、`finish_buffer`。

### 20.3 环境变量速查

| 变量 | 作用 |
|------|------|
| `GST_DEBUG` | 日志级别，如 `2,myfilter:5` |
| `GST_DEBUG_FILE` | 日志输出文件 |
| `GST_DEBUG_DUMP_DOT_DIR` | pipeline dot 图输出目录 |
| `GST_PLUGIN_PATH` | 追加插件搜索目录 |
| `GST_PLUGIN_SYSTEM_PATH` | 覆盖默认插件目录 |
| `GST_REGISTRY_UPDATE` | 强制更新 registry 缓存 |
| `GST_TRACERS` | 激活的 tracer，分号分隔 |
| `GST_REGISTRY_FORK` | 是否 fork 扫描插件（加速启动） |
| `GST_OPTION_NO_REGISTRY` | 跳过 registry 加载 |

### 20.4 术语表

| 术语 | 含义 |
|------|------|
| Element | 处理单元 |
| Pad | 元素间连接接口（src/sink） |
| Bin | 容器元素 |
| Pipeline | 顶层 Bin，含 bus/clock |
| Buffer | 数据载体 |
| Memory | buffer 内的内存块 |
| Meta | buffer 上的元数据 |
| Caps | 格式描述 |
| Event | 控制事件（seek/flush/segment） |
| Query | 查询（duration/position/allocation） |
| Message | 异步通知（EOS/error） |
| Bus | 消息通道 |
| Clock | 时钟，同步用 |
| Segment | 流位置/速率/累积时间 |
| Preroll | PAUSED 首帧就绪 |
| COW | Copy-On-Write 写时复制 |
| Rank | autoplugging 优先级 |
| Tracer | 观测钩子 |
| Probe | pad 上的拦截回调 |

---

## 结语

GStreamer 的二次开发本质是**"在正确的扩展点插入正确的代码"**。核心库提供了
十几种扩展点（§1），每种都有成熟的基类和参考实现。绝大多数定制需求都能用
**外部插件 + 基类继承**解决，无需触碰核心。

落地路径建议：
1. 用 §18 决策树定位扩展点；
2. 读对应基类头文件的 vfunc 列表（§20.2）；
3. 找一个最接近的参考实现（§20.1）改起；
4. 用 `gst-launch` + `GST_DEBUG` 快速验证；
5. 用 `tests/check/` 框架补单元测试；
6. 用 `GST_TRACERS=leaks` 查泄漏，`GST_DEBUG_DUMP_DOT_DIR` 看拓扑。

配套阅读：`gstream-design-analysis.md`（架构通论）、本仓库 `README.md`、
`release-notes-1.29.md`（版本变化）、`docs/random/`（设计笔记）。
