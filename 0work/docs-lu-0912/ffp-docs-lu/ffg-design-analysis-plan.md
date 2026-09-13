# FFmpeg 8.1.2 架构分析 — 写作规划

本文件是 `docs-lu/ffg-anaysis.md`（正式分析文档）的章节大纲与写作计划。
分析对象：`/data1/luhonghao/codes/avm/ffmpeg/ffmpeg-8.1.2/`（约 1 万文件，FFmpeg 8.1.2）。

## 写作策略
- 按章节顺序逐章写入 `ffg-anaysis.md`，每章写完即持久化（Write/Edit）。
- 每章之间回读已写内容确认完整性，再继续下一章。
- 长章节分多次写入（先前半段，再追加）。
- 全文用中文，配 Mermaid 图表（数据流图、控制流图、类图、时序图）。
- 若单文件过大（> ~1500 行），提示用户拆分为多个文件。

---

## 章节大纲

### 第 0 章 · 文档导读
- 文档目的、读者对象、分析范围、术语约定（DAG、pts/dts、time_base、AVClass 等）。
- 源码版本与目录定位。

### 第 1 章 · 总体架构与分层
- 1.1 七大库划分（libavutil / libavcodec / libavformat / libavfilter / libavdevice / libswresample / libswscale）及职责边界。
- 1.2 fftools 命令行工具层（ffmpeg / ffplay / ffprobe）与库层的关系。
- 1.3 分层架构图（Mermaid）：CLI → fftools → libraries → OS/硬件。
- 1.4 库间依赖关系图（libavutil 是根，avformat→avcodec→avutil 等）。
- 1.5 设计哲学：注册表模式、回调驱动、零拷贝引用计数、平台抽象。

### 第 2 章 · 入口与启动流程
- 2.1 `main()`（fftools/ffmpeg.c）启动序列：init_dynload → 日志 → 注册 → sch_alloc → ffmpeg_parse_options → transcode → cleanup。
- 2.2 选项解析总览：`ffmpeg_parse_options`（ffmpeg_opt.c）→ OptionsContext → 打开输入/输出。
- 2.3 启动时序图（Mermaid 时序）：main → parse → open_input → open_output → sch_start。
- 2.4 cmdutils / opt_common 的通用选项机制。

### 第 3 章 · 核心数据结构（类图）
- 3.1 `AVFrame` / `AVPacket`（数据载体，引用计数）+ `AVBufferRef`/`AVBuffer`（内存所有权）。
- 3.2 `AVCodecContext` / `AVCodec` / `FFCodec`（编解码器：公有 API vs 内部扩展）。
- 3.3 `AVFormatContext` / `AVStream` / `AVInputFormat` / `AVOutputFormat` / `AVIOContext`（封装/IO）。
- 3.4 `AVFilter` / `AVFilterContext` / `AVFilterGraph` / `AVFilterLink` / `AVFilterPad`（滤镜图）。
- 3.5 `AVCodecParameters`（编解码参数，流与编解码器解耦）。
- 3.6 `AVClass` / `AVOption`（统一的日志与选项系统）。
- 3.7 综合类图（Mermaid classDiagram）。

### 第 4 章 · 转码调度器 Scheduler（核心枢纽）
- 4.1 Scheduler 的角色：所有组件只与调度器通信，互不直连。
- 4.2 节点类型：Demux / Dec / FilterIn / FilterOut / Enc / Mux，构成 DAG。
- 4.3 `sch_connect` 连接模型与 DAG 校验。
- 4.4 线程模型：每个组件一个线程 + ThreadQueue 同步队列。
- 4.5 同步策略：以输出流 DTS 对齐，通过调节 demux 读取速率实现。
- 4.6 Scheduler 内部结构（SchDec/SchEnc/SchMux/SchFilterGraph 等）。
- 4.7 调度控制流图（Mermaid flowchart）。

### 第 5 章 · 完整业务流程 — 视频转码
- 5.1 端到端数据流：Demux → Dec → FilterGraph → Enc → Mux。
- 5.2 Demux 线程（ffmpeg_demux.c: input_thread）：av_read_frame → input_packet_process → demux_send。
- 5.3 Decoder 线程（ffmpeg_dec.c: decoder_thread）：sch_dec_receive → packet_decode → avcodec_send/receive → sch_dec_send。
- 5.4 Filter 线程（ffmpeg_filter.c: filter_thread）：buffersrc → filtergraph → buffersink。
- 5.5 Encoder 线程（ffmpeg_enc.c: encoder_thread）：sch_enc_receive → encode_frame → sch_enc_send。
- 5.6 Mux 线程（ffmpeg_mux.c: muxer_thread）：sch_mux_receive → sync_queue → write_packet → avio。
- 5.7 数据流图（Mermaid）+ 线程时序图。

### 第 6 章 · 完整业务流程 — 音频转码
- 6.1 与视频的差异：采样率/声道布局协商、音频 FIFO、帧大小、重采样（libswresample）。
- 6.2 音频滤镜链（aresample/anull/format 等）、format 自动转换。
- 6.3 音频编码的帧队列（audio_frame_queue）与 VARIABLE_FRAME_SIZE。
- 6.4 音频数据流图。

### 第 7 章 · 完整业务流程 — 字幕与流拷贝
- 7.1 字幕路径：Decoder→Encoder（不经滤镜图），sub2video 机制。
- 7.2 Stream copy（-c copy）：Demux→Mux 直连，不经 Dec/Enc，bsf 比特流过滤。
- 7.3 多视图（multiview）、流组（AVStreamGroup）、附件数据。

### 第 8 章 · libavformat — 封装与 IO 抽象
- 8.1 输入/输出格式注册（allformats.c）与探测（probe）。
- 8.2 AVIOContext 分层 I/O（协议层 avio → file/pipe/network）。
- 8.3 Demuxer/Muxer 回调接口（read_packet/write_packet/read_header 等）。
- 8.4 交错（interleaving）、索引、seek。
- 8.5 协议层（libavformat/protocols）与 URL 上下文。

### 第 9 章 · libavcodec — 编解码抽象
- 9.1 编解码器注册（allcodecs.c）与查找（avcodec_find_decoder/encoder）。
- 9.2 FFCodec 内部结构与回调类型（DECODE/RECEIVE_FRAME/ENCODE/RECEIVE_PACKET）。
- 9.3 编解码线程模型（frame threads / slice threads）。
- 9.4 硬件加速（hwaccel / hw_device / hw_frames_ctx）。
- 9.5 比特流过滤器（bsf）与解析器（parser）。
- 9.6 编解码时序图。

### 第 10 章 · libavfilter — 滤镜图引擎
- 10.1 滤镜注册（allfilters.c）与滤镜描述（AVFilter + pads）。
- 10.2 图构建：avfilter_graph_parse → query_formats → graph_config。
- 10.3 格式协商（query_formats / pick_format / reduce_formats）。
- 10.4 帧调度：ff_filter_frame / ff_request_frame / 就绪堆（ready heap）。
- 10.5 滤镜线程（slice threading）与命令传递（send_command）。
- 10.6 buffersrc/buffersink 与 fftools 的对接。

### 第 11 章 · libavutil — 基础设施
- 11.1 内存与引用计数（buffer.h / frame.h / mem.h）。
- 11.2 AVClass/AVOption 统一元系统（日志 + 选项 + 自省）。
- 11.3 时间基与时间戳（rational.h / time.h / timestamp.h）。
- 11.4 像素/采样格式、色彩空间、声道布局。
- 11.5 并发原语（thread.h / executor.h / fifo.h）。
- 11.6 平台抽象（config.h / attributes.h / bswap/bswap）。

### 第 12 章 · libswresample / libswscale / libavdevice
- 12.1 libswresample：音频重采样、声道布局转换、格式转换。
- 12.2 libswscale：图像缩放、色彩空间转换、像素格式转换。
- 12.3 libavdevice：采集设备抽象（alsa/v4l2/dshow 等），与 avformat 的关系。

### 第 13 章 · 构建系统与平台移植
- 13.1 configure 脚本（8840 行）：特性探测、编译器/汇编器探测、生成 config.mak/config.h。
- 13.2 ffbuild/*.mak：common.mak / library.mak / arch.mak 的分层 Makefile。
- 13.3 条件编译宏（CONFIG_* / HAVE_*）与各库独立 enable/disable。
- 13.4 汇编优化（asm / x86 / arm / aarch64）与 NASM/YASM。
- 13.5 compat/ 层与跨平台兼容。

### 第 14 章 · 工程设计方法与特点总结
- 14.1 设计模式归纳：注册表、回调/虚表、引用计数、模板代码（_template.c）、DAG 调度、选项自省。
- 14.2 工程特点：库的强分层与 ABI 稳定、零拷贝、海量编解码器/格式的统一抽象、跨平台。
- 14.3 设计优势：可扩展性、性能（汇编+多线程）、解耦、向后兼容。
- 14.4 设计劣势/痛点：API 复杂度高、内部/公有结构混用（FFCodec vs AVCodec）、线程模型演进阵痛、文档稀疏。
- 14.5 值得学习之处：Scheduler 的 DAG 解耦、AVClass/AVOption 元系统、_template.c 代码复用、引用计数所有权模型、configure 的可移植性工程。

### 附录
- A. 关键文件索引（按库）。
- B. 关键函数调用链速查。
- C. 术语表。

---

## 进度跟踪
- [x] 规划文档（本文件）
- [x] 第 0 章 文档导读
- [x] 第 1 章 总体架构与分层
- [x] 第 2 章 入口与启动流程
- [x] 第 3 章 核心数据结构（类图）
- [x] 第 4 章 转码调度器 Scheduler
- [x] 第 5 章 视频转码完整业务流程
- [x] 第 6 章 音频转码完整业务流程
- [x] 第 7 章 字幕与流拷贝
- [x] 第 8 章 libavformat 封装与 IO 抽象
- [x] 第 9 章 libavcodec 编解码抽象
- [x] 第 10 章 libavfilter 滤镜图引擎
- [x] 第 11 章 libavutil 基础设施
- [x] 第 12 章 libswresample/swscale/avdevice
- [x] 第 13 章 构建系统与平台移植
- [x] 第 14 章 工程设计方法与特点总结
- [x] 附录 A/B/C

最终文档：`docs-lu/ffg-anaysis.md`（2032 行，102K，含 Mermaid 图表 20+）。
