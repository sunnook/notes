# GStreamer 1.29 二次开发分析 — 写作规划

> 本文档是 `gs-2dev-analysis.md` 的写作大纲。最终文档面向"想基于 GStreamer 1.29.2
> 做定制化 / 二次开发"的工程师，区别于已有 `gstream-design-analysis.md`（偏架构通论），
> 本文聚焦**可操作的扩展点、开发方向、完整案例、涉及文件/类、踩坑**。

---

## 0. 文档定位与读者画像

- 读者：有 C/GObject 基础、读过 `gstream-design-analysis.md`、想动手改/扩 GStreamer 的工程师
- 与已有文档关系：已有文档讲"是什么"，本文讲"怎么改、往哪改、改哪里"
- 代码基线：`gstreamer-1.29.2`（仅核心库 + coreelements + base/libs）

---

## 1. 二次开发全景图（扩展点矩阵）

一张总表：所有可扩展点 × 侵入度 × 涉及文件/类 × 典型场景。
让读者先建立"我该动哪里"的直觉。

扩展点维度：
1. 写一个新 Element（最常见）
2. 写一个新 Plugin（打包多个 Element）
3. 扩展基类（BaseSrc/BaseSink/BaseTransform/Aggregator/BaseParse/PushSrc）
4. 自定义 Pad / PadTemplate / Pad Probe
5. 自定义 GstMeta（给 Buffer 挂私有元数据）
6. 自定义 GstAllocator / GstBufferPool（内存架构定制）
7. 自定义 GstClock（时钟/同步定制）
8. 自定义 GstControlSource / ControlBinding（属性动画）
9. 自定义 GstTracer（性能/行为追踪）
10. 自定义 GstDeviceProvider（设备发现）
11. 自定义 GstTypeFind（格式探测）
12. 修改核心库本身（gst/ 内部，高侵入）
13. 应用层定制（不碰核心，只组合 + Bus 消息 + 动态插拔）

---

## 2. 入口与构建：如何把你的代码编进去

- Meson 构建模型（subproject / 外部 plugin 仓库两种姿势）
- `GST_PLUGIN_DEFINE` 与 `plugin_init` 约定
- `GST_ELEMENT_REGISTER_DEFINE` 宏族（1.20+ 新机制）
- 插件搜索路径：`GST_PLUGIN_PATH` / registry / `.gir`
- 静态链接 vs 动态插件（README.static-linking 要点）
- 一个最小外部插件的 meson.build 模板

---

## 3. 核心数据结构速查（二次开发必背）

精简版，只列开发时真正要碰的字段：
- GstObject / GstElement / GstBin / GstPipeline（实例结构 + Class 虚函数表）
- GstPad（chainfunc/getrangefunc/eventfunc/queryfunc + probes + stream_rec_lock + task）
- GstBuffer / GstMemory / GstMeta / GstBufferPool
- GstCaps / GstStructure / GstEvent / GstQuery / GstMessage
- GstClock / GstTask
- 每个结构标注"开发时你通常只读 / 通常要写 / 通常要 override"

---

## 4. 类图与继承体系（开发视角）

- GObject → GstObject → GstElement → GstBin → GstPipeline
- GstElement 的"开发子树"：BaseSrc→PushSrc、BaseSink、BaseTransform、Aggregator、BaseParse
  （这些在 libs/gst/base/，是 90% 新 Element 的真正父类）
- MiniObject 子树：GstBuffer/GstEvent/GstQuery/GstMessage/GstCaps
- 用 UML 风格 ASCII 图，标注"你继承谁、override 哪些 vfunc"

---

## 5. 数据流图（开发视角：数据经过你的代码时发生了什么）

- Push 模式：上游 chain → 你的 transform/sink → 下游
- Pull 模式：你的 src getrange → 下游
- 标注"你的 vfunc 在哪一步被调用"
- Buffer 引用计数 / writable 检查 / Meta 传递规则
- Caps 协商：transform_caps / set_caps / decide_allocation 时机

---

## 6. 分层控制流图（状态机 + 线程）

- NULL→READY→PAUSED→PLAYING 传播 + 你的 start/stop/change_state 时机
- 线程架构：streaming thread（Pad 的 stream_rec_lock + GstTask）、Bus 线程、clock 线程、应用 main loop
- 你的 vfunc 运行在哪个线程（关键！线程安全清单）
- 内存架构：GstMemory allocator 链、BufferPool 复用、zero-copy（fd/DMABuf 思路）

---

## 7. 开发方向一：写一个 Transform Element（完整案例）

最常见、最完整的教学案例。从零到可 `gst-launch` 调用。
- 场景：一个"视频灰度化"或"音频音量调节"或通用"数据打戳" filter
- 选父类：GstBaseTransform（in-place vs 非 in-place）
- 完整代码骨架：头文件、G_DEFINE_TYPE、class_init、instance_init、
  transform_caps / set_caps / transform / transform_ip、properties、signals、pad templates
- meson.build
- gst-launch 验证命令
- 涉及文件/类清单
- 踩坑：writable buffer、passthrough、单元大小、segment/pts

---

## 8. 开发方向二：写一个 Src Element（完整案例）

- 场景：从自定义数据源（网络/共享内存/硬件）产生数据
- 选父类：GstBaseSrc vs GstPushSrc
- 完整代码骨架：create / fill / fixate / is_seekable / do_seek / get_times / start/stop
- 时钟同步（live source 的 GstClock）
- 涉及文件/类清单
- 踩坑：segment、discont、duration query、随机访问

---

## 9. 开发方向三：写一个 Sink Element（完整案例）

- 场景：输出到自定义目标（硬件显示/网络/文件格式）
- 选父类：GstBaseSink
- 完整代码骨架：render / preroll / event / get_times / set_caps / start/stop
- 同步渲染 vs async 同步
- 涉及文件/类清单

---

## 10. 开发方向四：多输入聚合 / 多输出分发

- Aggregator（libs/gst/base/gstaggregator.c）— 多路合流
- tee / funnel / input_selector / output_selector 已有实现可参考
- 何时该用 Aggregator 而不是手搓 Pad
- 完整骨架：aggregate / sink_event / create_new_pad

---

## 11. 开发方向五：自定义 GstMeta（给 Buffer 挂私有数据）

- 场景：AI 推理结果、硬件时间戳、自定义对齐信息
- GstMetaInfo 注册、init/transform/serialize/deserialize
- 完整代码：定义结构 + register + add/get 宏 + transform 策略
- 与 BufferPool 的 clear_func 配合
- 踩坑：meta 在 transform 时的传递/丢失

---

## 12. 开发方向六：自定义 Allocator / BufferPool（内存架构定制）

- 场景：DMA-Buf、GPU 显存、固定物理内存、零拷贝
- GstAllocatorClass: alloc/free
- GstBufferPool 配置与 acquire/release
- decide_allocation / propose_allocation 钩子
- 完整骨架

---

## 13. 开发方向七：自定义 Tracer（性能/行为追踪）

- 场景：统计每 element 吞吐、延迟、丢帧、自定义指标
- gst_tracing_register_hook 钩子列表
- 完整骨架 + GST_TRACER_DEFINE
- 现有 tracer 参考（plugins/tracers/gststats.c / gstlatency.c）
- 通过 `GST_TRACERS` 环境变量激活

---

## 14. 开发方向八：自定义时钟 / 控制源 / 设备提供 / TypeFind

四个较小但实用的扩展点，各给精简骨架：
- GstClock 子类（外部时钟同步，如 PTP/自定义硬件时钟）
- GstControlSource（属性动画/自动化）
- GstDeviceProvider（设备热插拔发现）
- GstTypeFind（新容器/格式探测）

---

## 15. 开发方向九：应用层定制（不碰核心）

- 动态插拔 Pad（gst_pad_link/unlink + pad-added 信号）
- Pad Probe（拦截/改写/丢弃数据，不写 element）
- Bus 消息处理模式
- GstParse launch 字符串 + 手动组合混合
- 适合"我不想编译插件，只想在应用里加逻辑"的场景

---

## 16. 修改核心库本身（高侵入，慎用）

- 何时该改 gst/ 内部（极少：协议级改动、性能瓶颈在核心）
- 改动点示例：gstpad.c push/chain 路径、gstbin 状态传播
- ABI/ABI 兼容、GST_PADDING 预留位、版本号策略
- 上游贡献流程 vs 私有 fork 维护成本

---

## 17. 二次开发常见陷阱与最佳实践

汇总清单：
- 线程：哪些回调在 streaming thread，哪些在 main loop
- 引用计数：ref/unref 配对、_full 变体、transfer 语义
- Caps 协商：不要在 chain 里改 caps
- 状态机：start/stop 与 READY↔PAUSED 的对应
- Buffer 可写性：gst_buffer_make_writable
- Meta 传递：默认不跟随，需 transform
- 错误传播：GstFlowReturn 的语义
- 日志：GST_DEBUG_CATEGORY 与分类
- 测试：tests/check/ 框架

---

## 18. 开发决策树（我该选哪条路）

一张流程图：需求 → 推荐扩展点 → 推荐父类 → 涉及文件。
把前面所有方向收束成"按需求查表"。

---

## 19. 你可能没考虑到的（补充）

- 国际化（i18n / gi18n-lib）
- 调试体系（GST_DEBUG / gst-info / dot 图 gst_debug_bin_to_dot_file）
- 插件版本与 registry 缓存失效
- 跨平台（Windows/Android/macOS 差异，gstandroid.c 等）
- 与 GStreamer 外部生态（gst-plugins-base/good/bad）的边界
- Python/JS 绑定（introspection）对二次开发的影响
- 安全：解析器（gst/parse）的输入边界、插件加载安全
- 性能：zero-copy、线程数、queue 水位
- 许可证（LGPL vs GPL 插件）对二次开发分发的影响

---

## 20. 附录

- 核心文件 → 二次开发相关度 速查表
- 基类 vfunc 速查表（BaseSrc/BaseSink/BaseTransform/Aggregator）
- 环境变量速查（GST_DEBUG / GST_PLUGIN_PATH / GST_TRACERS ...）
- 术语表

---

## 写作执行说明

- 输出文件：`docs-lu/gs-2dev-analysis.md`
- 顺序写入，每章写完确认持久化
- 长章分多次写入（先前半段，再追加后半段）
- 章节间回读确认完整性
- 若总量过大，提示用户拆分多文件
- 不创建过多任务对象，顺序执行
