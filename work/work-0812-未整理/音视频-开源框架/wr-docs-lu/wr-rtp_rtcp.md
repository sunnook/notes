# WebRTC RTP/RTCP Module 代码详细梳理

## 一、目录结构总览

```
modules/rtp_rtcp/
├── include/          # 对外暴露的头文件（公共 API）
├── source/           # 核心实现（本次重点）
│   ├── rtcp_packet/  # 每种 RTCP packet type 的独立实现
│   └── deprecated/   # 已废弃的旧实现
├── api/              # 模块的 BUILD.gn、DEPS 等
└── test/             # 测试文件
```

## 二、核心架构设计

整个模块是 WebRTC 的 **RTP/RTCP 协议栈**，负责音视频数据的网络发送和接收。整体采用**分层+职责分离**的设计：

```
                    ┌─────────────────────────────────────┐
                    │     RtpRtcpInterface (顶层接口)       │
                    │  Configuration / 所有虚函数声明        │
                    └──────────┬──────────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                 │
    ┌─────────▼──────┐ ┌──────▼──────┐ ┌────────▼────────┐
    │  RTPSender     │ │ RTCPSender  │ │ RTCPReceiver    │
    │  (RTP 发送构造) │ │ (RTCP 发送) │ │ (RTCP 接收解析)  │
    └─────────┬──────┘ └──────┬──────┘ └────────┬────────┘
              │               │                  │
    ┌─────────▼──────┐ ┌─────▼─────┐  ┌─────────▼─────────┐
    │ RTPSenderVideo │ │ FEC       │  │ ReceiveStatistics   │
    │ RTPSenderAudio │ │ (前向纠错) │  │ (接收统计)          │
    └────────────────┘ └───────────┘  └───────────────────┘
```

## 三、Source 目录核心文件详解

### 1. 顶层接口层

#### `rtp_rtcp_interface.h` — 顶层抽象接口
- **作用**：定义整个 RTP/RTCP 模块的完整 API 契约
- **核心内容**：
  - `Configuration` 结构体：包含所有配置参数（SSRC、Transport、回调、FEC 等）
  - **接收端 API**：`IncomingRtcpPacket()`、`SetRemoteSSRC()`
  - **发送端 API**：`RegisterSendPayloadFrequency()`、`SetSendingMediaStatus()`、`TrySendPacket()`
  - **RTCP API**：`SendRTCP()`、`SetCNAME()`、`SetRemb()`、`SendNACK()`
  - **Video 专用 API**：`SetFecProtectionParams()`、`FetchFecPackets()`、`SetVideoBitrateAllocation()`
- **设计模式**：纯虚接口，多个实现类实现它

#### `rtp_rtcp_impl.h` — 遗留的旧实现 (Deprecated)
- **作用**：旧的 `ModuleRtpRtcp` 实现，继承自 `RtpRtcp`（旧接口）
- **核心成员**：
  - `RtpSenderContext`：封装了 packet_history、sequencer、packet_sender、packet_generator
  - `RTCPSender rtcp_sender_`：RTCP 发送器
  - `RTCPReceiver rtcp_receiver_`：RTCP 接收器
- **注意**：正在被 `ModuleRtpRtcpImpl2` 替代

#### `rtp_rtcp_impl2.h` — 新实现
- **作用**：新一代 RTP/RTCP 实现，解耦更彻底
- 继承 `RtpRtcpInterface` 和 `RTCPReceiver::ModuleRtpRtcp`

### 2. RTP 发送层

#### `rtp_sender.h` — RTP 发送器（通用基类）
- **作用**：处理所有类型（音频/视频）RTP 包的通用发送逻辑
- **核心职责**：
  - **RTP 头填充**：SSRC、sequence number、timestamp、csrcs
  - **Header Extension 管理**：`RegisterRtpHeaderExtension()`、`DeregisterRtpHeaderExtension()`
  - **Padding 包生成**：`GeneratePadding()` — 用于带宽估计
  - **RTX 重传**：`BuildRtxPacket()`、`SetRtxStatus()`、`ReSendPacket()`
  - **NACK 处理**：`OnReceivedNack()` — 收到接收端的 NACK 后重传
  - **ACK 处理**：`OnReceivedAckOnSsrc()` — 优化 MID/RID extension 发送
- **关键成员**：
  - `RtpPacketSender* paced_sender_`： paced 发送器接口
  - `RtpPacketHistory* packet_history_`：已发送包的缓存（用于重传）
  - `RtpHeaderExtensionMap rtp_header_extension_map_`：header extension 注册表
  - `Mutex send_mutex_`：线程安全

#### `rtp_sender_video.h` — 视频 RTP 发送器
- **作用**：继承 `RTPSender`，处理视频特有的逻辑
- **核心接口**：
  ```cpp
  bool SendVideo(payload_type, codec_type, rtp_timestamp, capture_time,
                 payload, encoder_output_size, video_header,
                 expected_retransmission_time, csrcs);
  ```
- **视频特有功能**：
  - **Simulcast**：`SetVideoLayersAllocation()` — 视频层分配（分辨率/帧率）
  - **Video Structure**：`SetVideoStructure()` — 依赖描述符（用于可解码性）
  - **重传策略**：`RetransmissionMode` 枚举：
    - `kRetransmitOff`：关闭重传
    - `kRetransmitBaseLayer`：只重传基础层
    - `kRetransmitHigherLayers`：重传高层
    - `kRetransmitAllLayers`：重传所有层
    - `kConditionallyRetransmitHigherLayers`：条件性重传高层
  - **Post Encode Overhead 追踪**：`BitrateTracker post_encode_overhead_bitrate_`
  - **绝对捕获时间**：`AbsoluteCaptureTimeSender` — RFC 7456
  - **Active Decode Targets**：`ActiveDecodeTargetsHelper` — 用于依赖描述符
  - **帧加密**：`FrameEncryptorInterface* frame_encryptor_` — E2EE
  - **RED 冗余编码**：`red_enabled()` — 音频冗余（但视频也用到）

#### `rtp_sender_audio.h` — 音频 RTP 发送器
- **作用**：处理音频 RTP 发送（代码中未详细读取，但结构类似）

#### `rtp_sender_egress.h` — 发送出口层
- **作用**：RTP 包的最终出口，负责：
  - 将包交给 `Transport` 发送到网络
  - 统计发送字节数/包数
  - FEC 延迟生成（`SetFecProtectionParameters()` / `FetchFecPackets()`）
  - 每秒定时更新比特率统计
  - 包批处理（`enable_send_packet_batching_`）
- **关键成员**：
  - `RtpPacketHistory* packet_history_`：缓存已发包
  - `RtpSequenceNumberMap* rtp_sequence_number_map_`：序列号→时间戳映射
  - `VideoFecGenerator* fec_generator_`：视频 FEC 生成器
  - `RepeatingTaskHandle update_task_`：每秒定时任务

### 3. RTCP 层

#### `rtcp_sender.h` — RTCP 发送器
- **作用**：构建和发送各种 RTCP 包
- **支持的 RTCP 包类型**（每个对应一个 `BuildXXX` 方法）：
  | 方法 | RTCP 包 | RFC |
  |------|---------|-----|
  | `BuildSR` | Sender Report (SR) | 3550 6.4.1 |
  | `BuildRR` | Receiver Report (RR) | 3550 6.4.2 |
  | `BuildSDES` | Source Description | 3550 6.5 |
  | `BuildPLI` | Picture Loss Indication | 4585 6.3.1.1 |
  | `BuildFIR` | Full Intra Request | 5104 4.3.1.2 |
  | `BuildREMB` | Receiver Estimated Max Bitrate | 占位 |
  | `BuildTMMBR` | Target Maximum Media Bitrate Request | 5104 3.5.4 |
  | `BuildTMMBN` | Target Maximum Media Bitrate Notification | 5104 3.5.4 |
  | `BuildNACK` | Negative Acknowledgement | 4585 6.2 |
  | `BuildBYE` | BYE | 3550 6.6 |
  | `BuildLossNotification` | Loss Notification | 私有扩展 |
  | `BuildExtendedReports` | XR | 3611 |
  | `BuildAPP` | Application-defined | 3550 6.7 |
- **关键机制**：
  - `ReportFlag` 机制：volatile/non-volatile 标记控制哪些 RTCP 内容需要发送
  - `builders_` 映射：`RTCPPacketType -> BuilderFunc` 的分发表
  - `TimeToSendRTCPReport()`：根据发送比特率计算下一次发送 RTCP 的时机
  - REMB/TMMBR/TMMBN：带宽估算相关
  - NACK 统计：`RtcpNackStats`

#### `rtcp_receiver.h` — RTCP 接收器
- **作用**：解析接收到的 RTCP 包并触发相应回调
- **支持的 RTCP 包类型**（每个对应一个 `HandleXXX` 方法）：
  - `HandleSenderReport` / `HandleReceiverReport`：计算 RTT
  - `HandleSdes`：解析 CNAME
  - `HandleXr` / `HandleXrReceiveReferenceTime`：XR RRTR（非发送端 RTT 测量，RFC 3611）
  - `HandleXrDlrrReportBlock`：DLRR（延迟参考）
  - `HandleXrTargetBitrate`：XR 目标比特率
  - `HandleNack`：解析 NACK 列表 -> 回调 `OnReceivedNack()`
  - `HandlePli`：图片丢失指示 -> 回调 `OnRequestKeyFrame()`
  - `HandleFir`：全内帧请求
  - `HandleTmmbr` / `HandleTmmbn`：TMMBR/TMMBN 带宽协商
  - `HandleTransportFeedback`：传输反馈（RTCP APP 包，用于拥塞控制）
  - `HandleBye`：会话结束
- **RTT 计算**：
  - 标准 RTT：通过 SR/RR 的 `DLSR` + 本地时间戳
  - 非发送端 RTT：通过 XR DLRR（RFC 3611）
- **TMMBR 状态机**：`TmmbrInformation` 管理每个远端 SSRC 的 TMMBR 状态
- **超时检测**：`RtcpRrTimeout()` / `RtcpRrSequenceNumberTimeout()`

#### `rtcp_transceiver.*` — RTCP 收发器
- **作用**：统一管理 RTCP 的发送和接收，是 `RTCPSender` 和 `RTCPReceiver` 之间的协调层

### 4. 前向纠错 (FEC) 层

#### `forward_error_correction.h/cc` — 通用 FEC 引擎 (RFC 5109)
- **作用**：编解码器无关的前向纠错，基于 RFC 5109 (ULPFEC)
- **核心算法**：
  - **EncodeFec**：对一组 media packets 生成 FEC 包
    - 使用 **XOR** 操作恢复数据
    - 支持 **UEP (Unequal Error Protection)**：重要包获得更多保护
    - 支持两种 packet mask 类型：
      - `FEC_MASK_TYPE_RANDOM`：随机掩码（适用于 >12 个包）
      - `FEC_MASK_TYPE_BURSTY`：突发掩码（适用于 <=12 个包）
  - **DecodeFec**：接收端解码
    - 将收到的 media + FEC packets 按序列号排序
    - 对缺失的包，用覆盖它的 FEC 包进行 XOR 恢复
    - **限制**：一个 FEC 包最多只能恢复 **1 个**丢失包
- **关键数据结构**：
  - `Packet`：引用计数的数据包
  - `ReceivedPacket`：收到的包（区分 FEC 包和媒体包）
  - `RecoveredPacket`：恢复后的包
  - `ProtectedPacket`：被 FEC 保护的包
  - `ReceivedFecPacket`：收到的 FEC 包，包含 `protected_packets` 列表
  - `ProtectedStream`：被保护的流（SSRC + seq_num_base + packet_mask）
- **工厂方法**：
  - `CreateUlpfec(ssrc)`：创建 ULPFEC 实例
  - `CreateFlexfec(ssrc, protected_media_ssrc)`：创建 FlexFEC 实例

#### `ulpfec_generator.h/cc` — ULPFEC 生成器
- 封装 FEC 编码，为每个视频帧生成 ULPFEC 包

#### `ulpfec_receiver.h/cc` — ULPFEC 接收器
- 封装 FEC 解码，尝试恢复丢失的包

#### `flexfec_sender.h/cc` — FlexFEC 发送器
- FlexFEC-03 (draft-ietf-avflexfec-03) 实现

#### `flexfec_receiver.h/cc` — FlexFEC 接收器

#### `video_fec_generator.h` — 视频 FEC 生成器接口
- 封装视频帧级别的 FEC 策略（deferred FEC）

### 5. RTP 打包/解包层

#### `rtp_format.h/cc` — RTP Packetizer（打包器）
- **作用**：将完整视频帧拆分成多个 RTP 包
- **接口**：
  ```cpp
  std::unique_ptr<RtpPacketizer> Create(codec_type, payload, limits, video_header);
  virtual size_t NumPackets() const = 0;
  virtual bool NextPacket(RtpPacketToSend* packet) = 0;
  ```
- **支持的视频编码**：
  - `rtp_format_h264.cc` — H.264/AVC (FU-A, STAP-A)
  - `rtp_format_vp8.cc` — VP8
  - `rtp_format_vp9.cc` — VP9
  - `rtp_format_video_generic.cc` — Generic RTP Video (AV1)
  - `rtp_format_h265.cc` — H.265/HEVC (FU-A, STAP-A1/A2)
  - `rtp_packetizer_av1.cc` — AV1

#### `video_rtp_depacketizer.h` — 视频解包器接口
- **作用**：将 RTP 包重组为完整视频帧
- **接口**：
  ```cpp
  // 解析单个 RTP 包的 payload
  virtual absl::optional<ParsedRtpPayload> Parse(rtp_payload) = 0;
  // 将多个 RTP payload 组装成一帧
  virtual rtc::scoped_refptr<EncodedImageBuffer> AssembleFrame(payloads) = 0;
  ```
- **支持的视频编码**：
  - `video_rtp_depacketizer_h264.cc` — H.264 (STAP-A, MTAP16, MTAP24, FU-A)
  - `video_rtp_depacketizer_vp8.cc` — VP8
  - `video_rtp_depacketizer_vp9.cc` — VP9
  - `video_rtp_depacketizer_av1.cc` — AV1
  - `video_rtp_depacketizer_h265.cc` — H.265/HEVC
  - `video_rtp_depacketizer_generic.cc` — Generic
  - `video_rtp_depacketizer_raw.cc` — Raw (YUV)

### 6. 接收统计层

#### `receive_statistics_impl.h/cc` — 接收统计实现
- **`StreamStatisticianImpl`**：统计单个 SSRC 流的接收数据
  - **Jitter 计算**：`UpdateJitter()` — RFC 3550 Appendix A 的 I 算法
  - **丢包检测**：`cumulative_loss_` — 基于序列号间隙
  - **乱序处理**：`UpdateOutOfOrder()` — 使用 `RtpSequenceNumberUnwrapper` 展开 64-bit 序列号
  - **Report Block 生成**：`MaybeAppendReportBlockAndReset()` — 生成 RTCP RR 中的 Report Block
  - **关键统计量**：
    - `jitter_q4_`：Q4 定点表示的 jitter
    - `cumulative_loss_`：累积丢包数（可能为负，因为乱序）
    - `received_seq_max_`：最大接收序列号
    - `incoming_bitrate_`：接收比特率

#### `packet_loss_stats.h/cc` — 丢包统计
- 更高层的丢包率统计

### 7. NACK 与重传

#### `rtcp_packet/nack.h/cc` — NACK 包解析
- 解析 RTCP NACK (RTCP FB, Type 1, Payload Type 15)

#### `rtp_packet_history.h/cc` — 已发送包历史缓存
- 缓存最近发送的 RTP 包，用于 RTX 重传和 NACK 响应

#### `packet_sequencer.h/cc` — 序列号分配器
- 为 RTP 包分配连续的序列号

### 8. RTCP Packet 解析层 (`rtcp_packet/`)

每个文件对应一种 RTCP 包类型的**解析器/构建器**：

| 文件 | RTCP 类型 | 说明 |
|------|-----------|------|
| `sender_report.h` | SR | 发送端报告 |
| `receiver_report.h` | RR | 接收端报告 |
| `report_block.h` | Report Block | RR 中的报告块 |
| `sdes.h` | SDES | 源描述 (CNAME) |
| `bye.h` | BYE | 会话结束 |
| `nack.h` | NACK | 负确认 (FB) |
| `pli.h` | PLI (FB) | 图片丢失指示 |
| `fir.h` | FIR (FB) | 全内帧请求 |
| `remb.h` | REMB | 接收端估算最大比特率 |
| `tmmbr.h` | TMMBR | 目标最大媒体比特率请求 |
| `tmmbn.h` | TMMBN | 目标最大媒体比特率通知 |
| `target_bitrate.h` | Target Bitrate (XR) | XR 目标比特率 |
| `transport_feedback.h` | Transport Feedback (APP) | 传输反馈 |
| `compound_packet.h` | Compound Packet | RTCP 复合包组装 |
| `extended_reports.h` | XR | 扩展报告 |
| `rrtr.h` | RRTR (XR) | 接收端参考时间 |
| `dlrr.h` | DLRR (XR) | 延迟参考 |
| `loss_notification.h` | Loss Notification | 私有扩展 |
| `common_header.h` | Common Header | RTCP 包通用头部解析 |

### 9. RTP Header Extension

| 文件 | 作用 |
|------|------|
| `rtp_header_extensions.h/cc` | Header Extension 注册/查找 |
| `rtp_header_extension_map.h/cc` | Extension URI->ID 映射表 |
| `rtp_header_extension_size.h/cc` | Extension 大小计算 |
| `rtp_dependency_descriptor_*.h/cc` | 依赖描述符 extension (VP9/AV1) |
| `rtp_generic_frame_descriptor.h/cc` | Generic Frame Descriptor |
| `rtp_video_layers_allocation_extension.h/cc` | 视频层分配 extension |
| `absolute_capture_time_*.h/cc` | 绝对捕获时间 extension (RFC 7456) |
| `capture_clock_offset_updater.h/cc` | 捕获时钟偏移更新 |

### 10. 其他辅助文件

| 文件 | 作用 |
|------|------|
| `rtp_packet.h/cc` | RTP 数据包结构（发送/接收） |
| `rtp_packet_to_send.h/cc` | 待发送的 RTP 包（含时间戳信息） |
| `rtp_packet_received.h/cc` | 已接收的 RTP 包 |
| `rtp_video_header.h/cc` | 视频 RTP 头（temporal_id, layer_id 等） |
| `frame_object.h/cc` | 帧对象（用于 FEC 保护） |
| `source_tracker.h/cc` | SSRC 冲突检测 |
| `time_util.h/cc` | 时间工具函数 |
| `leb128.h/cc` | LEB128 编码（用于 Generic Frame Descriptor） |
| `byte_io.h/cc` | 字节序转换工具 |
| `fec_private_tables_*.h/cc` | FEC 包掩码预计算表 |
| `fec_test_helper.h/cc` | FEC 测试辅助 |
| `dtmf_queue.h/cc` | DTMF 队列 |
| `tmmbr_help.h/cc` | TMMBR 辅助逻辑 |
| `remote_ntp_time_estimator.h/cc` | 远端 NTP 时间估计 |
| `rtcp_nack_stats.h/cc` | NACK 统计 |
| `rtp_util.h/cc` | RTP 工具函数 |
| `create_video_rtp_depacketizer.h/cc` | 视频解包器工厂 |

## 四、数据流控制

### 发送方向 (Send Path)

```
视频编码器输出
    |
    v
EncodedImage + RTPVideoHeader
    |
    v
RTPSenderVideo::SendVideo()
    |  |-- 添加绝对捕获时间 extension
    |  |-- 添加依赖描述符 extension
    |  |-- 添加视频层分配 extension
    |  |  帧加密 (FrameEncryptor)
    v
RTPSender::AllocatePacket()  ->  分配 RTP 包，填充 SSRC/seq/timestamp
    |
    v
RtpPacketizer::NextPacket()  ->  将帧拆分为多个 RTP 包 (FU-A, STAP-A 等)
    |
    v
RTPSender::EnqueuePackets()
    |
    v
RtpSenderEgress::SendPacket()
    |  |-- 更新统计 (bitrate, packet count)
    |  |-- 缓存到 packet_history
    |  |  延迟 FEC 生成
    v
Transport::SendRtp()  ->  发送到网络
    |
    v
(同时) RTCPSender::SendRTCP()  ->  周期性发送 SR/REMB/NACK 等
```

### 接收方向 (Receive Path)

```
网络收到 RTP/RTCP 包
    |
    v
RTP 包 -> StreamStatisticianImpl::UpdateCounters()
    |        |-- 序列号展开 (RtpSequenceNumberUnwrapper)
    |        |-- 丢包检测 (序列号间隙)
    |        |-- Jitter 计算 (RFC 3550 Appendix A)
    |         比特率统计
    v
VideoRtpDepacketizer::Parse()  ->  解析 RTP payload
    v
VideoRtpDepacketizer::AssembleFrame()  ->  重组完整帧 (FU-A -> 原始帧)
    v
解码器输入
    v
RTCP 包 -> RTCPReceiver::IncomingPacket()
    |         |-- 解析复合包 (ParseCompoundPacket)
    |         |-- 分发到 HandleXXX()
    |          触发回调 (keyframe request, nack, etc.)
```

### RTT 计算流程

```
发送端: SR 包含 NTP 时间 T1 和 RTP 时间戳
    |
    v
接收端: RR 返回 DLSR (距收到 SR 的时间) + 发送端 SSRC
    |
    v
发送端: 收到 RR，根据 DLSR 和自己的接收时间 T2
    |       RTT = T2 - T1 - DLSR
    v
ReceiveStatisticsImpl -> Report Block -> 发送 RR
```

## 五、关键算法

### 1. Jitter 计算 (RFC 3550 Appendix A)
```
D = (R_i - R_{i-1}) - (S_i - S_{i-1})
jitter = jitter + (|D| - jitter) / 16  (近似除以16)
```

### 2. FEC 恢复 (XOR-based)
```
FEC 包 = XOR(媒体包_1, 媒体包_2, ..., 媒体包_n)  (按 packet_mask 选择)
缺失包 = XOR(FEC 包, 其他媒体包)
```

### 3. NACK 优化
- 初始发送完整 NACK 列表
- 后续只发送新丢失的包（增量 NACK）
- 基于 RTT 控制完整列表的重发间隔

### 4. 视频重传策略
- `kRetransmitBaseLayer`：只重传基础层，保证可解码
- `kConditionallyRetransmitHigherLayers`：如果高层帧距离上一帧太久，或预计新帧在低层可用时间 < NACK+RTT，则重传高层

## 六、线程模型

- **`send_mutex_`** (RTPSender)：保护 RTP 发送状态
- **`mutex_rtcp_sender_`** (RTCPSender)：保护 RTCP 发送状态
- **`rtcp_receiver_lock_`** (RTCPReceiver)：保护 RTCP 接收状态
- **`worker_queue_`** (RtpSenderEgress)：egress 操作在 TaskQueue 上串行化
- **`send_checker_`** (RTPSenderVideo)：RaceChecker 确保 SendVideo 只在一个线程调用

## 七、配置参数 (`Configuration`)

核心参数包括：
- `audio`：音频/视频模式
- `local_media_ssrc` / `rtx_send_ssrc`：SSRC
- `outgoing_transport`：网络发送回调
- `paced_sender`：Paced 发送器
- `fec_generator`：FEC 生成器
- `receive_statistics`：接收统计提供者
- `intra_frame_callback`：关键帧请求回调
- `rtcp_report_interval_ms`：RTCP 报告间隔
- `frame_encryptor`：帧加密器 (E2EE)
- `field_trials`：实验特性开关

---

## 类图

### 1. 顶层聚合架构

```
+-----------------------------------------------------------------+
|                   RtpRtcpInterface (纯虚接口)                      |
|  Configuration / IncomingRtcpPacket / SetSendingMediaStatus     |
|  SendRTCP / SendNACK / SetRemb / TrySendPacket / ...           |
+-------------------------------+---------------------------------+
                                | 实现
            +-------------------+-------------------+
            |                   |                   |
     +------+------+    +-------+-------+  +--------v---------+
     |   RtpRtcp   |    |ModuleRtpRtcpImpl2| |  (deprecated)   |
     |   [旧]      |    |  [当前主力实现]   |  +----------------+
     +-------------+    +--+------+--+--+
                            |        |
              +-------------+--+  +--+----------+
              |  RtpSender     |  | RTCPReceiver |
              |  Context       |  |              |
              +-------+--------+  +------+-------+
                      |                |
        +-------------+-----+    +----+--------+
        |      RTPSender     |    |  RTCPSender |
        |   (通用RTP发送)    |    |  (RTCP发送) |
        +--+-----------+----+    +-------------+
         +----+------+  +----+-----------+
         |  Video   |  |  Audio         |
         |  (扩展)  |  |                |
         +----------+  +----------------+
```

### 2. ModuleRtpRtcpImpl2 内部组成

```
+--------------------------------------------------------------------------+
|                      ModuleRtpRtcpImpl2                                   |
|  implements: RtpRtcpInterface, RTCPReceiver::ModuleRtpRtcp               |
|                                                                           |
|  +-------------------------------------------------------------------+   |
|  |  RtpSenderContext (嵌套结构体)                                      |   |
|  |  +----------------+  +----------------+  +---------------------+   |   |
|  |  |packet_history  |  |   sequencer    |  |  packet_sender      |   |   |
|  |  |(RtpPacket      |  |(PacketSeq-     |  |(RtpSenderEgress)    |   |   |
|  |  |  History)      |  |  uencer)       |  |  +----------------+ |   |   |
|  |  |  缓存已发包     |  |  序列号分配     |  |  |NonPaced        | |   |   |
|  |  |  用于重传       |  |                |  |  |PacketSender    | |   |   |
|  |  +----------------+  +----------------+  |  |(非paced回退)    | |   |   |
|  |                                          +---------------------+   |   |
|  |  +-----------------------------------------------------------+   |   |
|  |  |              packet_generator (RTPSender)                   |   |   |
|  |  |  - SSRC/seq/timestamp填充                                   |   |   |
|  |  |  - Header Extension 管理                                    |   |   |
|  |  |  - RTX 重传包构建                                           |   |   |
|  |  |  - Padding 包生成                                           |   |   |
|  |  +-----------------------------------------------------------+   |   |
|  +-------------------------------------------------------------------+   |
|                                                                           |
|  +-------------------------------------------------------------------+   |
|  |  rtcp_sender_ (RTCPSender)                                         |   |
|  |  BuildSR / BuildRR / BuildSDES / BuildPLI / BuildFIR              |   |
|  |  BuildREMB / BuildTMMBR / BuildNACK / BuildBYE ...                |   |
|  +-------------------------------------------------------------------+   |
|                                                                           |
|  +-------------------------------------------------------------------+   |
|  |  rtcp_receiver_ (RTCPReceiver)                                     |   |
|  |  HandleSR / HandleRR / HandleNack / HandleTmmbr / ...             |   |
|  +-------------------------------------------------------------------+   |
+--------------------------------------------------------------------------+
```

### 3. RTP 发送链路

```
+--------------------------------------------------------------------------+
|                        RTPSenderVideo (视频)                               |
|  SendVideo()                                                              |
|  +-- absolute_capture_time_sender_                                        |
|  +-- active_decode_targets_tracker_                                       |
|  +-- frame_transformer_delegate_                                           |
|      +-- 委托给 RTPVideoFrameTransformerDelegate                          |
+--------------------------------------------------------------------------+
|                        RTPSender (通用)                                    |
|  AllocatePacket() -> 分配RTP包，填充SSRC/seq/timestamp/csrcs              |
|  EnqueuePackets() -> 交给 paced_sender_ 或 non_paced_sender_              |
|  +-- OnReceivedNack() -> 重传                                             |
|  +-- BuildRtxPacket() -> RTX 重传包                                       |
|  +-- GeneratePadding() -> 带宽估计 Padding                                |
+--------------------------------------------------------------------------+
|                      RtpSenderEgress (出口)                                |
|  SendPacket() -> 更新统计 -> 缓存到 packet_history -> FEC延迟生成         |
|  -> Transport::SendRtp() 发送到网络                                        |
|  +-- PeriodicUpdate() 每秒更新比特率                                      |
|  +-- fec_generator_ -> FetchFecPackets()                                 |
+--------------------------------------------------------------------------+
```

### 4. RTCP 收发链路

```
+--------------------------------------------------------------------------+
|                       RTCPReceiver                                        |
|  IncomingPacket() -> ParseCompoundPacket() -> 分发到各 HandleXXX         |
|  +-- HandleSenderReport() -> 计算RTT -> ReportBlock                      |
|  +-- HandleReceiverReport() -> 更新远端统计                               |
|  +-- HandleNack() -> 回调 OnReceivedNack()                               |
|  +-- HandlePli/HandleFir() -> 回调 OnRequestKeyFrame()                   |
|  +-- HandleTmmbr/HandleTmmbn() -> 带宽协商                               |
|  +-- HandleTransportFeedback() -> 拥塞控制                                |
|  +-- HandleXr*() -> 非发送端RTT / 参考时间                               |
|  +-- HandleSdes() -> CNAME 解析                                          |
|  +-- HandleBye() -> 会话结束                                              |
|                                                                           |
|  内部状态:                                                                |
|  +-- rtts_[ssrc] -> RttStats (RTT 计算)                                  |
|  +-- tmmbr_infos_[ssrc] -> TmmbrInformation                              |
|  +-- received_report_blocks_ -> ReportBlockData                          |
|  +-- received_rrtrs_ -> RRTR 时间戳链                                    |
+--------------------------------------------------------------------------+
|                         RTCPSender                                        |
|  TimeToSendRTCPReport() -> 计算下次发送时机                               |
|  SendRTCP(feedback_state, packet_type) -> 组装 Compound Packet            |
|  +-- report_flags_ (volatile/non-volatile 标记)                          |
|  +-- builders_[RTCPPacketType] -> BuildXXX() 分发表                      |
+--------------------------------------------------------------------------+
```

### 5. FEC 架构

```
+--------------------------------------------------------------------------+
|                     ForwardErrorCorrection (核心引擎)                     |
|  RFC 5109 - 编解码器无关的 XOR-based FEC                                  |
|                                                                           |
|  EncodeFec(media_packets, protection_factor, ...)                        |
|  +-- InsertZerosInPacketMasks()  -> 在掩码中插入空洞                      |
|  +-- GenerateFecPayloads()  -> XOR 生成 FEC 载荷                         |
|  +-- FinalizeFecHeaders()  -> 写入 packet mask                           |
|                                                                           |
|  DecodeFec(received_packet, recovered_packets)                           |
|  +-- InsertPacket() -> 存入内部列表或 recovered list                      |
|  +-- UpdateCoveringFecPackets() -> 关联 FEC 包与媒体包                   |
|  +-- AttemptRecovery() -> 对缺失包尝试 XOR 恢复                           |
|      +-- RecoverPacket() -> StartPacketRecovery() -> XorPayloads()       |
|                          -> FinishPacketRecovery()                        |
+--------------------------------------------------------------------------+
|  FecHeaderReader / FecHeaderWriter (策略模式)                             |
|  +-- UlpfecHeaderReaderWriter  -> ULPFEC                                 |
|  +-- FlexfecHeaderReaderWriter -> FlexFEC                                 |
+--------------------------------------------------------------------------+
|  UlpfecGenerator / UlpfecReceiver / FlexfecSender / FlexfecReceiver      |
+--------------------------------------------------------------------------+
```

### 6. 打包/解包架构

```
+--------------------------------------------------------------------------+
|                     RtpPacketizer (工厂接口)                              |
|  Create(codec_type, payload, limits, video_header)                       |
|  +-- NumPackets() -> 剩余包数                                             |
|  +-- NextPacket(RtpPacketToSend*) -> 填充下一个 RTP 包                   |
|                                                                           |
|  具体实现:                                                               |
|  +-- RtpPacketizerH264  (FU-A, STAP-A, STAP-B)                           |
|  +-- RtpPacketizerH265  (FU-A, STAP-A1, STAP-A2)                         |
|  +-- RtpPacketizerVp8                                                     |
|  +-- RtpPacketizerVp9                                                     |
|  +-- RtpPacketizerAv1                                                     |
+--------------------------------------------------------------------------+
|                     VideoRtpDepacketizer (接口)                           |
|  Parse(rtp_payload) -> ParsedRtpPayload                                  |
|  AssembleFrame(payloads[]) -> EncodedImageBuffer                         |
|                                                                           |
|  具体实现:                                                               |
|  +-- VideoRtpDepacketizerH264  (STAP-A, MTAP16, MTAP24, FU-A)            |
|  +-- VideoRtpDepacketizerH265  (STAP-A1, STAP-A2, FU-A)                  |
|  +-- VideoRtpDepacketizerVp8                                              |
|  +-- VideoRtpDepacketizerVp9                                              |
|  +-- VideoRtpDepacketizerAv1                                              |
+--------------------------------------------------------------------------+
```

### 7. 接收统计架构

```
+--------------------------------------------------------------------------+
|                     ReceiveStatistics (工厂创建)                          |
|  Create(clock) -> ReceiveStatisticsLocked (线程安全)                      |
|  CreateThreadCompatible(clock) -> ReceiveStatisticsImpl (非线程安全)      |
|                                                                           |
|  OnRtpPacket() -> GetOrCreateStatistician(ssrc) -> UpdateCounters()      |
|  RtcpReportBlocks() -> RtcpSender 每周期调用                              |
+--------------------------------------------------------------------------+
|                     ReceiveStatisticsImpl                                 |
|  管理 flat_map<ssrc, StreamStatisticianImplInterface>                     |
|                                                                           |
|  StreamStatisticianImplInterface (内部接口)                               |
|  +-- StreamStatisticianImpl (线程不兼容)                                  |
|  |  +-- RtpSequenceNumberUnwrapper -> 64-bit 序列号展开                   |
|  |  +-- UpdateOutOfOrder() -> 乱序检测                                    |
|  |  +-- UpdateJitter() -> RFC 3550 App A I 算法                          |
|  |  +-- cumulative_loss_ -> 累积丢包 (可负)                               |
|  |  +-- MaybeAppendReportBlockAndReset() -> 生成 RTCP RR Report Block    |
|  |                                                                       |
|  +-- StreamStatisticianLocked (线程安全 wrapper)                         |
|     +-- 所有方法加 MutexLock 委托给 impl_                                 |
+--------------------------------------------------------------------------+
```

---

## 设计风格分析

### 核心设计模式

| 模式 | 应用位置 | 说明 |
|------|---------|------|
| **抽象接口 + 具体实现** | `RtpRtcpInterface` -> `ModuleRtpRtcpImpl2` | 顶层解耦，接口与实现分离 |
| **组合优于继承** | `ModuleRtpRtcpImpl2` 组合 `RTCPSender` + `RTCPReceiver` + `RTPSender` | 不是继承而是组合三个子模块 |
| **策略模式** | `FecHeaderReader` / `FecHeaderWriter` -> ULPFEC / FlexFEC | FEC 头部格式可插拔 |
| **工厂模式** | `RtpPacketizer::Create()` / `ReceiveStatistics::Create()` | 根据参数创建具体实现 |
| **观察者/回调** | `Configuration` 中的各类 Observer/Callback | 事件驱动，解耦模块间依赖 |
| **模板方法** | `RTCPSender::SendRTCP()` -> `builders_` 分发表调用 `BuildXXX` | 固定组装流程，各 RTCP 类型自定义构建 |
| **双重实现(线程安全/不安全)** | `ReceiveStatistics` -> `Impl` / `Locked` | 按场景选择性能或安全 |
| **嵌套 Context 对象** | `RtpSenderContext` | 将相关状态打包，控制可见性 |

### 设计优点

1. **职责高度分离**：RTP 发送、RTCP 发送、RTCP 接收、FEC、打包解包各自独立，每个类/模块只做一件事
2. **接口先行**：`RtpRtcpInterface` 定义了完整契约，实现类可以独立演进（Impl -> Impl2）
3. **组合优于继承**：`ModuleRtpRtcpImpl2` 组合了三个核心子模块而非深层继承，降低了耦合
4. **线程安全设计**：通过 `Mutex`、`SequenceChecker`、`RTC_GUARDED_BY` 注解、`ScopedTaskSafety` 多层保障，且有 `Locked`/`Impl` 双版本适配不同场景
5. **可测试性**：每个模块都有独立单元测试，接口天然适合 mock
6. **协议标准对齐**：RTCP packet 解析层几乎一对一映射 RFC 规范，每种 RTCP 包类型一个文件

### 设计缺点

1. **历史包袱重**：`RtpRtcpImpl` (deprecated) 和 `ModuleRtpRtcpImpl2` 并存，`DEPRECATED_RtpSenderEgress` 和 `RtpSenderEgress` 并存，增加了维护成本
2. **接口膨胀**：`RtpRtcpInterface` 有 70+ 个虚函数，违反了接口隔离原则，音频/视频/RTCP 的所有功能都堆在一个接口里
3. **嵌套结构不清晰**：`RtpSenderContext` 作为 `ModuleRtpRtcpImpl2` 的嵌套 struct，但内部又包含 `RtpSenderEgress`（含 `NonPacedPacketSender`），层次过深
4. **裸指针泛滥**：`Configuration` 中大量裸指针回调（`Transport*`、`Clock*`、各类 Observer），没有明确的 ownership 语义，容易内存泄漏
5. **RTCP 包解析耦合**：`RTCPReceiver::ParseCompoundPacket` 内部用类型分发调用 15+ 个 `HandleXXX` 方法，缺乏统一的 visitor 模式
6. **FEC 设计反模式**：`ForwardErrorCorrection` 内部有大量 public 的 struct-like 类（`Packet`、`ReceivedPacket`、`RecoveredPacket`、`ProtectedPacket`），数据和方法分离，违背封装原则（代码自身 TODO 也承认了这一点）
7. **配置对象过大**：`Configuration` 结构体包含 30+ 个字段，没有按功能分组，容易传错参数

### 总体评价

这是一个**协议栈级别**的工程实现，核心设计哲学是 **"正确性优先于简洁性"**。它在协议标准对齐、线程安全、可测试性方面做得很好，但历史演进导致了明显的架构层积（architectural layering）。从 Impl -> Impl2 的迁移反映了 WebRTC 团队正在做 **从"大模块"到"细粒度组合"** 的架构瘦身。
