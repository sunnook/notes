# FFmpeg 二次开发与定制化设计分析 — 写作规划

本文件是 `docs-lu/ffp-2dev-design.md`（FFmpeg 二次开发指南）的章节大纲与写作计划。
基于已完成的架构分析 `docs-lu/ffg-anaysis.md`，本文档聚焦"如何基于 FFmpeg 做定制化/二次开发"。

## 写作策略
- 按章节顺序逐章写入 `ffp-2dev-design.md`。
- 每章结合具体文件、结构体、API，给出完整可落地的开发案例。
- 二次开发方向按"侵入度"递进：从最轻（命令行/选项）到最重（改核心）。
- 全文用中文，配 Mermaid 图。

---

## 章节大纲

### 第 1 章 · 二次开发总览与方向分类
- 1.1 二次开发的五种侵入层级（从轻到重）。
- 1.2 各方向涉及的核心库与文件矩阵。
- 1.3 选型决策树：什么需求走哪条路。
- 1.4 二次开发通用工程纪律（ABI、版本、测试、configure）。

### 第 2 章 · 方向一：新增编解码器（libavcodec）
- 2.1 编解码器骨架：FFCodec 结构、回调类型选择。
- 2.2 完整案例：实现一个"反转行序"的无损视频编码器（decoder + encoder）。
- 2.3 涉及文件：新增 `libavcodec/myrevdec.c`/`myrevenc.c`、`allcodecs.c` 注册、`codec_id.h` 加 ID、`Makefile`。
- 2.4 私有上下文 + AVOption 参数化。
- 2.5 帧线程/片线程适配、`caps_internal`。
- 2.6 测试：FATE 测试 + 命令行验证。

### 第 3 章 · 方向二：新增滤镜（libavfilter）
- 3.1 滤镜骨架：FFFilter 结构、pad、filter_frame/request_frame。
- 3.2 完整案例：实现一个"加时间戳水印"的视频滤镜 `vf_mydrawtext`。
- 3.3 涉及文件：新增 `libavfilter/vf_mydrawtext.c`、`allfilters.c` 注册、`Makefile`。
- 3.4 格式协商 query_formats、slice threading、命令传递。
- 3.5 音频滤镜与视频滤镜差异。

### 第 4 章 · 方向三：新增封装格式/协议（libavformat）
- 4.1 demuxer/muxer 骨架：FFInputFormat/FFOutputFormat、回调。
- 4.2 完整案例：实现一个"内存帧序列"自定义 muxer（把帧写入内存 buffer）。
- 4.3 涉及文件：新增 `libavformat/myframemux.c`、`allformats.c` 注册、`Makefile`。
- 4.4 协议层：新增自定义 URLProtocol（如从数据库读字节）。
- 4.5 探测函数 read_probe 编写要点。

### 第 5 章 · 方向四：用库 API 构建独立应用（libav* 编程）
- 5.1 不改 FFmpeg，用公共 API 写自己的转码/播放/探测程序。
- 5.2 完整案例：一个最小转码器（demux→dec→filter→enc→mux 全用 API）。
- 5.3 涉及头文件：libavformat/avformat.h、libavcodec/avcodec.h、libavfilter/avfilter.h、libavutil。
- 5.4 与 fftools 内部 API（Scheduler）的区别：公共 API 简单但无内置多线程调度。
- 5.5 内存/引用计数使用规范。

### 第 6 章 · 方向五：定制 fftools 行为
- 6.1 修改 ffmpeg/ffprobe 行为：选项、输出格式、进度回调。
- 6.2 复用 Scheduler 做高级定制（自定义组件线程）。
- 6.3 完整案例：给 ffmpeg 加一个"转码进度 HTTP 上报"钩子。
- 6.4 涉及文件：fftools/ffmpeg.c、ffmpeg_opt.c、新增 hook 文件。

### 第 7 章 · 硬件加速集成
- 7.1 接入新硬件后端：hw_device_ctx / hw_frames_ctx / AVCodecHWConfig。
- 7.2 完整案例：接入一个假想的"MyGPU"硬件编码器骨架。
- 7.3 硬件滤镜链路（cuda/vaapi/vulkan 模式）。

### 第 8 章 · 构建集成与版本管理
- 8.1 configure 选项注册：`configure` 脚本加 `--enable-mycodec`。
- 8.2 Makefile/Makefile.am 集成、外部库依赖探测。
- 8.3 ABI 兼容：如何保证改动不破坏下游。
- 8.4 FATE 测试编写、回归保护。

### 第 9 章 · 常见陷阱与未考虑事项补充
- 9.1 线程安全：哪些结构体可跨线程共享、哪些不行。
- 9.2 时间基/时间戳坑：pts/dts 转换、AV_NOPTS_VALUE 处理。
- 9.3 EOF/flush 语义：每个组件的 drain 责任。
- 9.4 错误码与退出码约定。
- 9.5 性能：零拷贝边界、避免 av_frame_copy。
- 9.6 调试：av_log 层级、tlog、valgrind/sanitizer。
- 9.7 许可证：LGPL vs GPL、外部库的传染性。
- 9.8 用户未考虑的方向：DNN/AI 滤镜、流媒体（RTMP/SRT/WHIP）、低延迟优化、嵌入式裁剪、多路并发服务化。

### 附录
- A. 二次开发检查清单（Checklist）。
- B. 关键 API 速查（按开发方向）。
- C. 参考实现文件索引（最小范例：vf_null/nullenc/pcm）。

---

## 进度跟踪
- [x] 规划文档（本文件）
- [x] 第 1 章 二次开发总览与方向分类
- [x] 第 2 章 新增编解码器（libavcodec）+ 完整案例
- [x] 第 3 章 新增滤镜（libavfilter）+ 完整案例
- [x] 第 4 章 新增封装格式/协议（libavformat）+ 完整案例
- [x] 第 5 章 用库 API 构建独立应用 + 完整案例
- [x] 第 6 章 定制 fftools 行为 + 完整案例
- [x] 第 7 章 硬件加速集成
- [x] 第 8 章 构建集成与版本管理
- [x] 第 9 章 常见陷阱与未考虑事项补充
- [x] 附录 A/B/C

最终文档：`docs-lu/ffp-2dev-design.md`（9 章 + 3 附录，5 个开发方向 + 完整案例）。
