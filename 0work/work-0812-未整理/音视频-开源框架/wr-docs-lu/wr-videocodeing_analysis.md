# WebRTC Video Coding Module 深度代码梳理

## 一、整体架构概览

该模块位于 `modules/video_coding/`，是 WebRTC 的**视频接收端核心模块**（Video Coding Module, VCM），总代码量约 **14,862 行**。它负责**接收 RTP 视频流、重组帧、解码、抖动缓冲、丢包重传、定时控制**等完整接收端流程。

> **注意**：该目录下没有 `source/` 子目录。所有核心代码直接平铺在根目录，子目录包括 `codecs/`、`deprecated/`、`include/`、`svc/`、`timing/`、`utility/`、`g3doc/`。

---

## 二、目录结构详解

### 2.1 根目录（核心引擎）

| 文件 | 作用 |
|------|------|
| `video_coding_impl.h/cc` | **模块入口**，`VideoCodingModuleImpl` 实现 `VideoCodingModule` 接口，组合 `VCMTiming` + `VideoReceiver` |
| `video_receiver.h/cc` | **旧版接收器**（legacy），封装了完整的接收逻辑，使用 `VCMReceiver`（deprecated jitter buffer） |
| `video_receiver2.h/cc` | **新版接收器**，精简版，用于新的 `VideoReceiveStream`，去除了 deprecated 依赖 |
| `packet_buffer.h/cc` | **RTP 包重组缓冲**，按序列号重组分片 RTP 包为完整帧 |
| `decoder_database.h/cc` | **解码器注册表**，按 payload type 管理解码器实例，支持动态切换 codec |
| `nack_requester.h/cc` | **NACK 请求器**，检测丢包并生成 NACK 反馈 |
| `generic_decoder.h/cc` | **解码器适配器**，将底层 `VideoDecoder` 适配为 VCM 内部接口 |
| `encoded_frame.h/cc` | **编码帧数据结构**，继承 `EncodedImage`，携带 codec 特定信息 |
| `frame_helpers.h/cc` | 帧辅助工具函数 |
| `frame_dependencies_calculator.h/cc` | 帧依赖关系计算（用于 SVC/Simulcast） |
| `chain_diff_calculator.h/cc` | 帧间差异计算（用于帧率控制） |
| `h26x_packet_buffer.h/cc` | H.26x 专用包缓冲（SPS/PPS 追踪） |
| `h264_sps_pps_tracker.h/cc` | H.264 SPS/PPS 参数集追踪 |
| `h264_sprop_parameter_sets.h/cc` | H.264 SProp 参数集解析 |
| `loss_notification_controller.h/cc` | 丢包通知控制器 |
| `histogram.h/cc` | 统计直方图工具 |
| `fec_rate_table.h` | FEC 速率查找表 |
| `internal_defines.h` | 内部宏定义 |
| `video_coding_defines.h/cc` | 错误码和公共类型定义 |
| `video_codec_initializer.h/cc` | 编解码器初始化辅助 |

### 2.2 `include/` — 公共 API

| 文件 | 作用 |
|------|------|
| `video_coding.h` | **核心抽象接口** `VideoCodingModule`，定义 `IncomingPacket`/`Decode`/`Process` 等 API |
| `video_codec_interface.h` | **编解码器特定信息结构**：`CodecSpecificInfo` union（VP8/VP9/H264） |
| `video_coding_defines.h` | 错误码（`VCM_OK`/`VCM_GENERAL_ERROR` 等）、回调接口（`VCMReceiveCallback`/`VCMFrameTypeCallback`/`VCMPacketRequestCallback`） |
| `video_codec_initializer.h` | 编解码器初始化接口 |
| `video_error_codes.h` | 错误码枚举 |

### 2.3 `codecs/` — 编解码器实现

```
codecs/
├── interface/     — 编解码器公共接口
├── vp8/           — VP8 编解码器实现
├── vp9/           — VP9 编解码器实现
├── h264/          — H.264 编解码器实现
├── av1/           — AV1 编解码器实现
└── test/          — 编解码器测试框架（videocodec_test_fixture、videoprocessor 等）
```

### 2.4 `svc/` — SVC（可伸缩视频编码）

| 文件 | 作用 |
|------|------|
| `scalable_video_controller.h/cc` | **SVC 控制器**，管理多空间层/多时间层的帧编码配置 |
| `create_scalability_structure.h/cc` | 创建可扩展性结构（Simulcast/Full SVC/L2T2 Key Shift） |
| `scalability_structure_*` | 多种可扩展性结构实现：Simulcast、Full SVC、Key Shift 等 |
| `svc_rate_allocator.h/cc` | SVC 速率分配器 |
| `scalability_mode_util.h/cc` | 可扩展性模式工具函数 |
| `scalable_video_controller_no_layering.h/cc` | 无分层模式的 SVC 控制器 |

### 2.5 `timing/` — 定时控制

| 文件 | 作用 |
|------|------|
| `timing.h/cc` | **核心定时管理器** `VCMTiming`，管理抖动缓冲延迟、解码时间估计、渲染时间计算 |
| `timestamp_extrapolator.h/cc` | RTP 时间戳外推器，将 RTP 时间戳映射到系统时间 |
| `decode_time_percentile_filter.h/cc` | 解码时间百分位滤波器（95th percentile） |
| `jitter_estimator.h/cc` | 抖动估计器 |
| `rtt_filter.h/cc` | RTT 滤波器 |
| `frame_delay_variation_kalman_filter.h/cc` | 帧延迟变化的卡尔曼滤波器 |
| `inter_frame_delay_variation_calculator.h/cc` | 帧间延迟变化计算器 |

### 2.6 `utility/` — 工具类

| 文件 | 作用 |
|------|------|
| `frame_dropper.h/cc` | **帧丢弃器**，基于 leaky bucket 算法在编码器跟不上时丢弃帧 |
| `simulcast_rate_allocator.h/cc` | **Simulcast 速率分配器**，按空间层/时间层分配码率 |
| `quality_scaler.h/cc` | 质量缩放器 |
| `bandwidth_quality_scaler.h/cc` | 带宽质量缩放器 |
| `decoded_frames_history.h/cc` | 已解码帧历史记录 |
| `vp8_header_parser.h/cc` | VP8 头解析器 |
| `vp9_uncompressed_header_parser.h/cc` | VP9 无压缩头解析器 |
| `qp_parser.h/cc` | QP（量化参数）解析器 |
| `ivf_file_reader/writer.h/cc` | IVF 文件格式读写（用于测试） |
| `simulcast_utility.h/cc` | Simulcast 辅助工具 |

### 2.7 `deprecated/` — 废弃代码

包含旧的 JitterBuffer、Receiver、FrameBuffer、Packet 等实现，逐步被 `VideoReceiver2` + `PacketBuffer` 替代。

---

## 三、核心数据流与控制流

### 3.1 接收端主流程

```
网络线程                          Module线程                       Decoder线程
   |                                 |                                 |
   |-- IncomingPacket() ------------>|                                 |
   |   (RTP payload + header)        |                                 |
   |                                 |-- PacketBuffer::InsertPacket()  |
   |                                 |   (按 seq_num 重组帧)           |
   |                                 |                                 |
   |                                 |-- Decode() ------------------>  |
   |                                 |   (获取解码器, 送编码帧)        |
   |                                 |                                 |
   |                                 |                                 |-- decoder_->Decode()
   |                                 |                                 |   (硬件/软件解码)
   |                                 |                                 |
   |                                 |<-- Decoded() callback -----------|
   |                                 |   (VCMDecodedFrameCallback)     |
   |                                 |                                 |
   |                                 |-- FrameToRender() ------------>|
   |                                 |   (回调给用户渲染)              |
   |                                 |                                 |
   |<-- NACK request ----------------|                                 |
   |   (ProcessNacks 周期触发)       |                                 |
   |                                 |                                 |
   |<-- KeyFrame request ------------|                                 |
   |   (RequestKeyFrame)             |                                 |
```

### 3.2 关键数据对象

**`EncodedFrame` / `VCMEncodedFrame`** (`encoded_frame.h`):

```cpp
class VCMEncodedFrame : public EncodedImage {
  int64_t _renderTimeMs;           // 渲染时间
  uint8_t _payloadType;            // RTP payload type
  bool _missingFrame;              // 是否有前序帧缺失
  CodecSpecificInfo _codecSpecificInfo;  // 编解码器特定信息 (VP8/VP9/H264)
};
```

**`CodecSpecificInfo`** (`video_codec_interface.h`):

- **VP8**: `temporalIdx`, `keyIdx`, `referencedBuffers[]`, `updatedBuffers[]` (SVC 依赖)
- **VP9**: `temporal_idx`, `ss_data_available`, `gof_idx`, `num_ref_pics`, `p_diff[]`
- **H264**: `temporal_idx`, `idr_frame`, `packetization_mode`

**`Packet`** (`packet_buffer.h`):

```cpp
struct Packet {
  uint16_t seq_num;
  uint32_t timestamp;
  bool continuous;        // 前序包是否已到达
  bool marker_bit;
  int times_nacked;       // NACK 重传次数
  rtc::CopyOnWriteBuffer video_payload;
  RTPVideoHeader video_header;  // 视频扩展头
};
```

---

## 四、核心组件详细分析

### 4.1 `VideoCodingModuleImpl` — 模块入口

**位置**: `video_coding_impl.cc:176`

这是整个模块的顶层入口，遵循 **Facade 模式**：

- 组合 `VCMTiming`（定时管理）+ `VideoReceiver`（接收逻辑）
- 对外暴露 `VideoCodingModule` 抽象接口
- 构造方式: `VideoCodingModule::Create(clock, field_trials)`

**关键参数**:

- `Clock* clock`: 时间源
- `FieldTrialsView field_trials`: 实验特性开关

### 4.2 `PacketBuffer` — RTP 包重组

**位置**: `packet_buffer.h/cc`

**算法设计**:

1. **环形数组**存储 RTP 包，用 `seq_num % buffer_size` 做索引
2. **动态扩容**: 缓冲区满时自动翻倍（2x），最大不超过 `max_size_`
3. **帧检测** (`FindFrames`):
   - 从当前 seq_num 向前扫描，检查 `is_first_packet_in_frame` 标志
   - 对于 H.264 特殊处理：没有 `frame_begin` 位，需向后遍历相同 timestamp 的包
   - H.264 keyframe 判定：可选策略 `sps_pps_idr_is_h264_keyframe_`（需 SPS+PPS+IDR 或仅 IDR）
4. **缺失包追踪** (`UpdateMissingPackets`): 维护 `missing_packets_` set，用于 NACK

**关键参数**:

- `start_buffer_size`: 初始缓冲区大小（必须是 2 的幂）
- `max_buffer_size`: 最大缓冲区大小

### 4.3 `NackRequester` — 丢包检测与重传请求

**位置**: `nack_requester.h/cc`

**算法设计**:

1. **到达检测** (`OnReceivedPacket`): 每收到一个 RTP 包，检查 `seq_num` 是否连续
   - 如果 `seq_num < newest_seq_num_`: 乱序到达，从 NACK 列表移除
   - 如果 `seq_num > newest_seq_num_ + 1`: 中间缺失，将缺失序列加入 NACK 列表
2. **NACK 发送策略** (`GetNackBatch`):
   - 三种过滤选项: `kSeqNumOnly`（序列号）/ `kTimeOnly`（时间）/ `kSeqNumAndTime`
   - 延迟发送: `send_nack_delay_`（可通过 field trial 配置，0-20ms）
   - RTT 等待: 发送 NACK 后需等待 RTT 再重发
   - 最大重传: `kMaxNackRetries = 10`
3. **重排序统计** (`UpdateReorderingStatistics`): 用直方图记录重排序分布，用于计算 `WaitNumberOfPackets`
4. **周期性处理** (`NackPeriodicProcessor`): 每 20ms 周期性地调用 `ProcessNacks()`

**关键参数**:

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `kMaxPacketAge` | 10,000 | NACK 包最大年龄(ms) |
| `kMaxNackPackets` | 1,000 | NACK 列表最大长度 |
| `kDefaultRtt` | 100ms | 默认 RTT |
| `kMaxNackRetries` | 10 | 最大 NACK 重试次数 |
| `kMaxReorderedPackets` | 128 | 最大重排序包数 |
| `send_nack_delay_` | 0ms | NACK 发送延迟（可通过 field trial `WebRTC-SendNackDelayMs` 配置） |

**触发 KeyFrame 的条件**:

- NACK 列表满（>1000 项）
- 缺失包超过 `max_packet_age_to_nack`
- 不连续帧超过 `max_incomplete_time_ms`

### 4.4 `VCMTiming` — 定时控制

**位置**: `timing/timing.h/cc`

**核心算法**:

```
target_delay = jitter_delay + estimated_max_decode_time + render_delay + min_playout_delay
current_delay = 平滑后的 target_delay
render_time = extrapolated_rtp_timestamp + current_delay
```

**关键组件**:

1. **`TimestampExtrapolator`**: 将 RTP 时间戳外推到系统时间（基于到达时间和 RTP 时间戳的线性回归）
2. **`DecodeTimePercentileFilter`**: 计算 95th 百分位解码时间
3. **`RenderTime()`**: 计算帧的渲染时间 = 外推的 RTP 时间 + 当前延迟
4. **`MaxWaitingTime()`**: 计算最大等待时间 = render_time - now - decode_time

**关键参数**:

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `kDefaultRenderDelay` | 10ms | 固定渲染延迟 |
| `kDelayMaxChangeMsPerS` | 100ms/s | 延迟最大变化速率 |
| `zero_playout_delay_min_pacing_` | field trial 配置 | 零延迟时的最小帧间距 |

**`VideoDelayTimings` 结构**:

```cpp
struct VideoDelayTimings {
  size_t num_decoded_frames;          // 已解码帧数
  TimeDelta minimum_delay;            // 最小延迟（抖动缓冲）
  TimeDelta estimated_max_decode_time; // 95th 百分位解码时间
  TimeDelta render_delay;             // 渲染延迟
  TimeDelta min_playout_delay;        // 最小播放延迟（来自 RTP ext 或 API）
  TimeDelta max_playout_delay;        // 最大播放延迟
  TimeDelta target_delay;             // 目标总延迟
  TimeDelta current_delay;            // 当前总延迟（平滑后）
};
```

### 4.5 `VCMDecoderDatabase` — 解码器管理

**位置**: `decoder_database.h/cc`

**设计模式**: 按 payload type 的**懒加载解码器池**

1. **注册**: `RegisterReceiveCodec(payload_type, settings)` + `RegisterExternalDecoder(payload_type, decoder)`
2. **获取** (`GetDecoder`): 根据帧的 payload_type 获取/创建解码器
   - 如果当前解码器匹配 → 直接返回
   - 否则销毁旧解码器，创建新解码器
3. **线程安全**: 所有操作在 `decoder_sequence_checker_` 上执行

### 4.6 `VCMGenericDecoder` — 解码器适配器

**位置**: `generic_decoder.h/cc`

**职责**: 将底层 `VideoDecoder` 接口适配为 VCM 内部使用

- `Configure()`: 配置解码器参数
- `Decode()`: 送帧解码，在送码前记录 `FrameInfo`（时间戳、解码开始时间、NTP 时间等）
- 解码完成后通过 `VCMDecodedFrameCallback::Decoded()` 回调
  - 计算实际解码时间
  - 记录 timing 指标（capture→encode→packetize→network→decode 全流程）
  - 调用 `VCMReceiveCallback::FrameToRender()` 送回应用层

### 4.7 `ScalableVideoController` — SVC 控制

**位置**: `svc/scalable_video_controller.h`

**职责**: 控制视频如何编码以实现可伸缩性（Simulcast / SVC）

**核心接口**:

```cpp
StreamLayersConfig StreamConfig();           // 返回空间层/时间层配置
FrameDependencyStructure DependencyStructure(); // 依赖描述符结构
void OnRatesUpdated(VideoBitrateAllocation); // 通知各层码率
std::vector<LayerFrameConfig> NextFrameConfig(bool restart); // 下一帧配置
GenericFrameInfo OnEncodeDone(LayerFrameConfig); // 编码完成回调
```

**`LayerFrameConfig`**: 每帧的配置，包含 spatial_id、temporal_id、keyframe 标志、buffer 引用/更新列表

**具体实现**:

- `scalability_structure_simulcast.cc`: Simulcast 结构
- `scalability_structure_full_svc.cc`: 完整 SVC 结构
- `scalability_structure_l2t2_key_shift.cc`: L2T2 Key Shift 结构

### 4.8 `FecControllerDefault` — FEC 控制

**位置**: `fec_controller_default.h/cc`

**职责**: 根据网络状况动态调整 FEC 冗余率

- `UpdateFecRates()`: 根据估计码率、丢包率、RTT 等计算 FEC 速率
- `UpdateWithEncodedData()`: 根据实际编码数据更新统计

### 4.9 `FrameDropper` — 帧丢弃

**位置**: `utility/frame_dropper.h/cc`

**算法**: **Leaky Bucket（漏桶算法）**变体

- `Fill(size, delta_frame)`: 编码器输出一帧后调用，将帧大小"注入"桶中
- `Leak(framerate)`: 按帧率"漏掉"固定量
- `DropFrame()`: 判断当前是否应丢弃帧（桶满时）
- 大帧（关键帧/大 delta 帧）不立即累积，而是分摊到多帧

### 4.10 `SimulcastRateAllocator` — Simulcast 码率分配

**位置**: `utility/simulcast_rate_allocator.h/cc`

**职责**: 将总码率分配给 Simulcast 的各层

- `DistributeAllocationToSimulcastLayers()`: 先分空间层
- `DistributeAllocationToTemporalLayers()`: 再分时间层
- 区分 `Screenshare` 和 `Camera` 场景的不同分配策略

---

## 五、回调接口体系

```cpp
// 解码帧回调 — 解码后的帧送给渲染
class VCMReceiveCallback {
  virtual int32_t FrameToRender(VideoFrame& frame, absl::optional<uint8_t> qp,
                                TimeDelta decode_time, VideoContentType,
                                VideoFrameType) = 0;
  virtual void OnDroppedFrames(uint32_t) = 0;
  virtual void OnIncomingPayloadType(int) = 0;
};

// 帧类型请求回调 — 需要关键帧时触发
class VCMFrameTypeCallback {
  virtual int32_t RequestKeyFrame() = 0;
};

// 包请求回调 — 需要重传特定包时触发（旧版）
class VCMPacketRequestCallback {
  virtual int32_t ResendPackets(const uint16_t* seqNumbers, uint16_t length) = 0;
};
```

---

## 六、线程模型

```
Construction Thread:     创建模块、注册 codec/decoder/callback
                          (VideoReceiver2::RegisterReceiveCodec 等)

Module Thread:           调用 Process()、处理定时任务
                          (NACK 周期性处理、KeyFrame 定时请求)

Decoder Thread:          解码器操作在此线程
                          (GetDecoder、Decode 在 decoder_sequence_checker_ 上)
```

每个线程有对应的 `SequenceChecker` 保证线程安全。

---

## 七、设计特点总结

1. **分层架构**: `VideoCodingModule` (Facade) → `VideoReceiver` → `PacketBuffer`/`DecoderDatabase`/`NackRequester`
2. **策略模式**: 多种 `ScalabilityStructure` 实现可伸缩编码策略
3. **适配器模式**: `VCMGenericDecoder` 适配通用 `VideoDecoder` 接口
4. **懒加载**: 解码器按 payload type 按需创建
5. **环形缓冲**: `PacketBuffer` 使用环形数组 + 动态扩容
6. **统计驱动**: 用百分位滤波器、卡尔曼滤波、直方图做自适应控制
7. **渐进式重构**: `VideoReceiver2` 是 `VideoReceiver` 的精简版，`deprecated/` 保留旧实现

---

## 八、类图

### 8.1 顶层架构类图

```
+---------------------------------------------------------------+
|                   VideoCodingModule (interface)                |
|  + RegisterReceiveCodec()                                      |
|  + RegisterExternalDecoder()                                   |
|  + RegisterReceiveCallback()                                   |
|  + RegisterFrameTypeCallback()                                 |
|  + RegisterPacketRequestCallback()                             |
|  + Decode()                                                    |
|  + IncomingPacket()                                            |
|  + SetNackSettings()                                           |
|  + Process()                                                   |
+----------------------------+-----------------------------------+
                             | implements
                             v
+---------------------------------------------------------------+
|              VideoCodingModuleImpl (Facade)                     |
|  - field_trials_                                               |
|  - timing_: VCMTiming*                                         |
|  - receiver_: VideoReceiver                                    |
+---+----------------------+-------------------------------------+
    | composition           | composition
    v                       v
+-----------+    +--------------------------------------------------+
|  VCMTiming|    |                VideoReceiver                      |
|  +Reset() |    |  - clock_                                        |
|  +RenderTime|  |  - timing: VCMTiming*                            |
|  +MaxWait()|   |  - _receiver: VCMReceiver (deprecated JitterBuf) |
|  +UpdateCur|   |  - _decodedFrameCallback                         |
|  +SetJitter|   |  - _frameTypeCallback                            |
|  +StopDec()|   |  - _packetRequestCallback                        |
|  +Target() |   |  - _codecDataBase: DEPRECATED_VCMDecoderDataBase |
+---+--------+   |  - _retransmissionTimer                          |
    |            |  - _keyRequestTimer                              |
    |            +--------------------------------------------------+
    |
    | composition
    v
+---------------------------------------------------------------+
|  TimestampExtrapolator  |  DecodeTimePercentileFilter          |
|  +IncomingTimestamp()   |  +UpdateDecodeTime()                 |
|  +RenderTime()          |  +EstimatedMaxDecodeTime()           |
+-----------------------+  +------------------------------------+
```

### 8.2 接收器类图（旧版 vs 新版）

```
+---------------------------------------------------------------+
|                        VideoReceiver (legacy)                  |
|  - clock_                  |  VideoReceiver2 (new, trimmed)    |
|  - _timing                 |  - clock_                         |
|  - _receiver: VCMReceiver    |  - decoded_frame_callback_      |
|  - _decodedFrameCallback   |  - codec_database_: VCMDecoderDatabase |
|  - _frameTypeCallback      |                                  |
|  - _packetRequestCallback  |  +RegisterReceiveCodec()         |
|  - _codecDataBase          |  +RegisterExternalDecoder()      |
|  - _retransmissionTimer    |  +RegisterReceiveCallback()      |
|  - _keyRequestTimer        |  +Decode()                        |
|                              |  (takes EncodedFrame*)           |
|  +IncomingPacket()         |  (no jitter buffer, no NACK —    |
|  +Decode(maxWaitTimeMs)    |   those are handled by           |
|  +Process()                |   VideoReceiveStream)             |
+---------------------------------------------------------------+
```

### 8.3 解码器管理层类图

```
+---------------------------------------------------------------+
|                    VCMDecoderDatabase                           |
|  - decoder_sequence_checker_                                    |
|  - current_payload_type_: optional<uint8_t>                    |
|  - current_decoder_: optional<VCMGenericDecoder>               |
|  - decoder_settings_: map<uint8_t, VideoDecoder::Settings>     |
|  - decoders_: map<uint8_t, unique_ptr<VideoDecoder>>           |
|                                                                |
|  +RegisterExternalDecoder(payload_type, unique_ptr<VideoDecoder>)|
|  +RegisterReceiveCodec(payload_type, Settings)                 |
|  +GetDecoder(EncodedFrame, VCMDecodedFrameCallback) -> VCMGenericDec*|
|  - CreateAndInitDecoder(EncodedFrame)                          |
+--------------------------+-------------------------------------+
                           | provides
                           v
+---------------------------------------------------------------+
|                      VCMGenericDecoder (Adapter)              |
|  - decoder_: VideoDecoder*           <- wraps actual decoder  |
|  |  (libvpx, OpenH264, VideoToolbox...)                       |
|  - _callback: VCMDecodedFrameCallback                         |
|  - _last_keyframe_content_type                                |
|                                                                |
|  +Configure(Settings) -> bool                                  |
|  +Decode(EncodedFrame, Timestamp) -> int32_t                  |
|  +RegisterDecodeCompleteCallback(callback)                    |
|  +IsSameDecoder(decoder) -> bool                              |
+--------------------------+-------------------------------------+
                           | calls
                           v
+---------------------------------------------------------------+
|                     VCMDecodedFrameCallback                   |
|  - _clock              |  (implements DecodedImageCallback)    |
|  - _timing             |  - _receiveCallback: VCMReceiveCallback*|
|  - lock_               |  - frame_infos_: deque<FrameInfo>    |
|  - frame_infos_        |  - ntp_offset_                        |
|                                                                |
|  +SetUserReceiveCallback(callback)                            |
|  +Decoded(VideoFrame, decode_time_ms, qp)                     |
|  +Map(FrameInfo)  /  ClearTimestampMap()                      |
|  |                                                            |
|  |  Decoded() 流程:                                            |
|  |  1. FindFrameInfo(rtp_timestamp)  // 查找对应 FrameInfo    |
|  |  2. _timing->StopDecodeTimer()     // 更新解码时间统计      |
|  |  3. 计算并上报全流程 timing 指标                            |
|  |  4. _receiveCallback->FrameToRender()  // 回调用户          |
+---------------------------------------------------------------+
```

### 8.4 包缓冲与 NACK 类图

```
+---------------------------------------------------------------+
|                        PacketBuffer                             |
|  - max_size_ (power of 2)                                      |
|  - first_seq_num_                                              |
|  - buffer_: vector<unique_ptr<Packet>>  // 环形数组            |
|  - missing_packets_: set<uint16_t, Descending>                 |
|  - newest_inserted_seq_num_: optional<uint16_t>                |
|  - sps_pps_idr_is_h264_keyframe_                               |
|                                                                |
|  +InsertPacket(unique_ptr<Packet>) -> InsertResult             |
|  |  1. 按 seq_num % buffer_size 定位槽位                       |
|  |  2. 处理重复包 / 缓冲区满 -> 扩容或清空                      |
|  |  3. UpdateMissingPackets() 更新缺失列表                     |
|  |  4. FindFrames() 检测完整帧并返回                           |
|  +ClearTo(seq_num) / Clear()                                   |
|  +ForceSpsPpsIdrIsH264Keyframe()                               |
|  -FindFrames(seq_num) -> vector<unique_ptr<Packet>>            |
|  |  向前遍历找帧头，H.264 特殊处理 (按 timestamp 回溯)         |
|  |  判定 keyframe: IDR 或 SPS+PPS+IDR                          |
|  -UpdateMissingPackets(seq_num)                                |
|  -ExpandBufferSize()  // 2x 扩容                               |
+---------------------------------------------------------------+


+---------------------------------------------------------------+
|                     NackRequester                               |
|  - worker_thread_                                              |
|  - nack_list_: map<uint16_t, NackInfo, Descending>             |
|  - recovered_list_: set<uint16_t>  // FEC/RTX 恢复的包         |
|  - reordering_histogram_: Histogram                            |
|  - rtt_: TimeDelta                                             |
|  - newest_seq_num_: uint16_t                                   |
|  - send_nack_delay_: TimeDelta  // 可通过 field trial 配置     |
|                                                                |
|  +OnReceivedPacket(seq_num)                                    |
|  |  1. 检查是否乱序 -> 从 nack_list 移除                       |
|  |  2. 检查是否断号 -> AddPacketsToNack()                      |
|  |  3. 检查是否有待发送 NACK -> GetNackBatch() + SendNack()    |
|  +ProcessNacks()  // 周期性触发                                |
|  |  GetNackBatch(kTimeOnly) -> 按 RTT 超时发送                 |
|  -AddPacketsToNack(start, end)                                |
|  |  将缺失序列加入 nack_list，超 1000 项 -> 请求 KeyFrame      |
|  -GetNackBatch(options) -> vector<uint16_t>                   |
|  |  过滤条件: delay_timed_out && (seq_num_passed || rtt_passed)|
|  |  重传次数 > 10 -> 移除                                      |
|  -WaitNumberOfPackets(probability) -> int                     |
|  |  基于 reordering_histogram 的逆 CDF 计算等待包数            |
+---------------------------------------------------------------+
```

### 8.5 SVC 类图

```
+---------------------------------------------------------------+
|                  ScalableVideoController (interface)          |
|  +StreamConfig() -> StreamLayersConfig                        |
|  +DependencyStructure() -> FrameDependencyStructure           |
|  +OnRatesUpdated(VideoBitrateAllocation)                       |
|  +NextFrameConfig(bool restart) -> vector<LayerFrameConfig>   |
|  +OnEncodeDone(LayerFrameConfig) -> GenericFrameInfo          |
+--------+---------------------+--------------------------------+
   | implements            | implements
   v                       v
+------------+   +--------------------------------------------------+
| Simulcast  |   | ScalabilityStructureFullSVC                       |
| Structure  |   | + 完整的 SVC 层级 (S1T1-S3T3 等)                 |
| + 多空间层 |   |                                                   |
|   独立编码 |   | + 跨空间层参考 (reference scaling)                |
|   不互相依赖|  +--------------------------------------------------+
+------------+

+---------------------------------------------------------------+
|                  LayerFrameConfig (builder pattern)            |
|  - id_ / is_keyframe_ / spatial_id_ / temporal_id_            |
|  - buffers_: vector<CodecBufferUsage>                         |
|                                                               |
|  +Id(int) -> LayerFrameConfig&   // 设置 ID                   |
|  +Keyframe() -> LayerFrameConfig&  // 标记关键帧               |
|  +S(int) / T(int) -> LayerFrameConfig&  // 空间/时间层         |
|  +Reference(buf_id) -> LayerFrameConfig&  // 标记可被参考的 buffer|
|  +Update(buf_id) -> LayerFrameConfig&  // 标记需要更新的 buffer|
|  +ReferenceAndUpdate(buf_id) -> LayerFrameConfig&            |
+---------------------------------------------------------------+
```

### 8.6 FEC 控制类图

```
+---------------------------------------------------------------+
|                     FecController (interface)                  |
|  +SetProtectionCallback()                                      |
|  +SetProtectionMethod(bool fec, bool nack)                     |
|  +SetEncodingData(width, height, temporal_layers, max_payload_size)|
|  +UpdateFecRates(bitrate, fps, loss, loss_mask, rtt) -> uint32_t|
|  +UpdateWithEncodedData(encoded_len, frame_type)               |
|  +UseLossVectorMask() -> bool                                  |
+------------------------+---------------------------------------+
                         | implements
                         v
+---------------------------------------------------------------+
|                    FecControllerDefault                         |
|  - env_: Environment                                           |
|  - protection_callback_: VCMProtectionCallback*                |
|  - loss_prot_logic_: VCMLossProtectionLogic*  <- 核心保护逻辑  |
|  - max_payload_size_: size_t  // 默认 1460                     |
|  - overhead_threshold_: float  // 默认 0.5                     |
|                                                                |
|  +UpdateFecRates()                                             |
|  |  1. 过滤丢包率 (kMaxFilter)                                 |
|  |  2. loss_prot_logic_->UpdateMethod() 选择保护方式            |
|  |  3. 计算 key/delta 帧的 FEC rate 和 max_fec_frames          |
|  |  4. 通过 callback 通知上层设置 FEC                          |
|  |  5. 限制 overhead <= 50%                                    |
|  |     return source_bitrate * (1 - overhead_rate)             |
|  +SetProtectionMethod()  // kNone / kNack / kFec / kNackFec   |
|  +UpdateWithEncodedData()  // 更新每帧包数统计                  |
+---------------------------------------------------------------+
```

### 8.7 回调与定时类图

```
+---------------------------------------------------------------+
|  VCMReceiveCallback (interface)         VCMFrameTypeCallback   |
|  +FrameToRender(frame, qp, decode_      (interface)            |
|    time, content_type, frame_type)      +RequestKeyFrame() -> int32_t|
|  +OnDroppedFrames(count)        VCMPacketRequestCallback       |
|  +OnIncomingPayloadType(payload_type) (interface, deprecated)   |
+------------------------------------------------+----------------+
                                                 |
                                                 v
+---------------------------------------------------------------+
|                     NackPeriodicProcessor                      |
|  - update_interval_: TimeDelta  // 默认 20ms                  |
|  - repeating_task_: RepeatingTaskHandle                       |
|  - modules_: vector<NackRequesterBase*>                       |
|                                                               |
|  +RegisterNackModule(module)  // 启动周期性任务               |
|  +UnregisterNackModule(module)  // 最后一个注销时停止任务      |
|  -ProcessNackModules()  // 遍历调用各 module->ProcessNacks()   |
|                                                               |
|  注册方式: ScopedNackPeriodicProcessorRegistration (RAII)      |
+---------------------------------------------------------------+
```

---

## 九、代码设计风格分析与优劣评估

### 9.1 核心设计风格

这组代码体现了典型的 **Google 内部 C++ 工程风格**，融合了 Chromium 和 WebRTC 两大项目的设计哲学。可以归纳为以下几个特征：

#### 风格 1: 接口-实现分离 + Facade 模式

```
VideoCodingModule (纯虚接口, include/)
        ^ implements
VideoCodingModuleImpl (具体实现, 匿名 namespace 隐藏)
        ^ composes
VideoReceiver + VCMTiming
```

**优势**: 接口稳定，实现可随意替换；`include/video_coding.h` 是对外契约。
**劣势**: 多层间接调用增加理解成本；`VideoCodingModuleImpl` 放在匿名 namespace 说明这个接口本身已经不够稳定。

#### 风格 2: 适配器模式包裹第三方/硬件编解码器

`VCMGenericDecoder` 将 `VideoDecoder`（可能指向 libvpx、OpenH264、VideoToolbox、FFMPEG 等）统一适配为内部接口。

**优势**: 解码器实现与 VCM 解耦，新增 codec 只需实现 `VideoDecoder` 接口。
**劣势**: 适配器层有薄薄一层开销；`VCMGenericDecoder` 承担了过多责任（配置、解码、回调映射、内容类型传播）。

#### 风格 3: 按 payload type 懒加载解码器池

`VCMDecoderDatabase` 用 `map<uint8_t, unique_ptr<VideoDecoder>>` 管理解码器，`GetDecoder()` 按需创建。

**优势**: 支持 SDP 协商中动态切换 codec（如 VP8->VP9）；不需要预先创建所有解码器。
**劣势**: 解码器切换时有初始化延迟；`current_decoder_` 的 optional 状态机容易出错。

#### 风格 4: 环形数组 + 序列号取模的 PacketBuffer

```
buffer_[seq_num % buffer_size]
```

**优势**: O(1) 插入/查找；动态扩容适应不同码率场景。
**劣势**: 取模运算有性能损耗；环形数组在并发场景下需要额外同步（虽然 VCM 是单线程设计）；H.264 的 `FindFrames` 需要 O(n) 回溯（因为 H.264 没有 `frame_begin` 标志）。

#### 风格 5: 统计驱动的自适应控制

- `VCMTiming`: 95th percentile 解码时间估计 + RTP 时间戳外推
- `NackRequester`: 重排序直方图 + 逆 CDF 计算等待包数
- `FrameDropper`: leaky bucket 算法
- `FecControllerDefault`: 丢包率滤波 + 码率动态分配

**优势**: 不依赖硬编码阈值，能自适应不同网络条件。
**劣势**: 统计类组件（卡尔曼滤波、指数滤波、百分位滤波器）堆叠在一起，参数调优困难，行为不够可预测。

#### 风格 6: Builder Pattern 用于 SVC 帧配置

`LayerFrameConfig` 用链式调用构建帧的引用/更新关系：

```cpp
config.Id(0).Keyframe().S(0).T(0)
      .ReferenceAndUpdate(0)
      .Reference(1);
```

**优势**: 可读性好，配置意图清晰。
**劣势**: 链式调用暴露了内部 buffer ID 实现细节；`Id` 字段是"实现细节"但不应该暴露给用户。

#### 风格 7: 线程安全通过 SequenceChecker 而非锁

大部分组件用 `SequenceChecker` 断言线程归属，共享状态用 `Mutex` 保护。

**优势**: 开发期就能捕获线程误用；运行时开销小（release 下 SequenceChecker 为空）。
**劣势**: 没有编译期保证；`RTC_GUARDED_BY` 注解需要人肉维护。

### 9.2 整体优劣总结

| 维度 | 优势 | 劣势 |
|------|------|------|
| **模块化** | 接收端各关注点清晰分离（包缓冲/解码/NACK/定时） | 旧版 `VideoReceiver` 耦合了 NACK、KeyFrame 请求、解码，职责过重 |
| **可扩展性** | 新增 codec 只需实现 `VideoDecoder` 接口；SVC 结构可插拔 | `CodecSpecificInfo` union 每次新增 codec 都要改；H.264 在 `PacketBuffer` 里有大量硬编码 |
| **性能** | 环形数组 O(1) 插入；零拷贝 `CopyOnWriteBuffer`；无锁统计 | `unique_ptr` 频繁分配；H.264 帧检测 O(n)；`map` 查找有 log(n) 开销 |
| **可维护性** | `RTC_DCHECK`/`RTC_DCHECK_RUN_ON` 覆盖全面；单元测试密集 | 新旧两套接收器并存（`VideoReceiver` + `VideoReceiver2`）；`deprecated/` 目录持续膨胀 |
| **线程模型** | 单线程 + SequenceChecker 简单可靠 | 没有真正的并发，但多线程回调（decoder thread）增加了心智负担 |
| **自适应** | 统计驱动的延迟/NACK/FEC 控制能应对复杂网络 | 参数过多（至少 15+ 可调参数），field trial 配置分散，难以调优和调试 |
| **代码量** | 单文件控制在 200-400 行，粒度合理 | 14,862 行总量仍偏大，`video_receiver.cc` 279 行但承担了 5 种职责 |

### 9.3 代码演进方向

从 `VideoReceiver` -> `VideoReceiver2` 的演进可以看出：

1. **剥离 deprecated 依赖**（`VCMReceiver`/`JitterBuffer`/`VCMPacket`）
2. **职责下移**：NACK 和 JitterBuffer 交给上层 `VideoReceiveStream` 管理
3. **智能指针替代裸指针**：`unique_ptr<VideoDecoder>` 替代裸指针
4. **线程模型简化**：减少 `SequenceChecker` 数量

这反映了 WebRTC 接收端从 **"大包大揽"** 到 **"组合拼装"** 的设计哲学转变。
