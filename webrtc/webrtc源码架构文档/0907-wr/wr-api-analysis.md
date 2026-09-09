# WebRTC `api/` 目录分析 —— 从接口/工程应用角度

> 日期：2026-09-07
> 工程：`/data1/luhonghao/codes/adrtc/webrtc/webrtc-m144_release`（M144）
> 视角：接口层 / 工程应用（LiveKit 集成）
> 相关记忆：`webrtc-native-source.md`、`livekit-webrtc-integration.md`

---

## 〇、导读须知（2026-09-08 补充，先读这段再往下看）

**① 读 WebRTC 的两把钥匙（结合你已有的 C 经验，完整版）**

你见过的两套 C 代码，正好对应 WebRTC 的两种"可读性策略"：

| 你的 C 经验 | 特点 | 对应 WebRTC |
|---|---|---|
| 全在一个文件、两线程追踪 | 顺序流，读起来线性 | 对应 WebRTC 的**数据流链路**（一条线到底） |
| 插件式 `priv_`/`Plugin_` 标识 | 分层 + 接口，靠命名区分内外 | 对应 WebRTC 的 **api/ 接口 + 实现分层** |

**技巧 1：先看"数据流"，再看"控制流"——像读你第一个 C 代码那样读 WebRTC**
WebRTC 虽然文件多，但每一条数据流（视频上行/下行/音频）是一条线，和"全在一个文件"的 C 代码本质一样，区别只是被拆到多个文件。**技巧：把一条数据流从头到尾追一遍（就像追 jitter buffer），记住"这条线"，其他都是分支。** 你会追两线程的 C 代码，同样的方法追 WebRTC 的单条数据流即可。

**技巧 2：用"命名"快速定位内外——像 `priv_`/`Plugin_` 那样**
WebRTC 的命名也有规律，相当于 C 插件的 `priv_`/`Plugin_`：
- **`*_interface.h`**（api/）= 对外契约，相当于 `Plugin_`（公开接口）
- **`*Impl`**（如 `NetEqImpl`、`VideoSendStreamImpl`）= 内部实现，相当于 `priv_`（私有实现）
- **方法名**：`OnXxx` = 回调（被调进来），`CreateXxx` = 工厂，`SetXxx`/`GetXxx` = 配置/读取

**技巧 3：WebRTC 比 FFmpeg 更像 GStreamer**
FFmpeg 是"**编解码库**"（核心是算法，`priv_` 藏实现细节），GStreamer 是"**媒体框架**"（核心是管线 + 插件 + 元素，`Plugin_` 是插件边界）。WebRTC 更接近 GStreamer——它**不只是编解码，而是一整套"会话 + 传输 + 媒体"框架**，靠接口分层、回调衔接、可插拔替换。所以用"插件式"那套 C 代码的心智模型理解 WebRTC 的分层和接口，比用"单文件"那套更贴合。

> **一句话总结技巧**：读 WebRTC = **用"单文件 C"的方法追数据流（一条线到底）+ 用"插件 C"的方法看分层（`*_interface.h` 是契约、`*Impl` 是实现、`OnXxx` 是回调）**。你已有的两套 C 经验正好覆盖这两个维度——单文件教你"怎么追线"，插件式教你"怎么分层"。

**② 步骤为什么这么琐碎？（完整版）**

这是 WebRTC 的核心设计哲学，不是"过度设计"。原因有三层：
- **① 多线程 + 线程安全 → 每个对象都归属一个线程**：信令/工作/网络/解码四线程，每个对象只能在自己线程被访问（`RTC_DCHECK_RUN_ON`）。一条链路被切成很多小步骤，**每步都是一次"跨线程投递"的边界**（如 `OnEncodedFrame` 里 `decode_queue_->PostTask` 就是 worker → 解码队列的线程切换）。**步骤多，是因为线程边界多。**
- **② 生命周期管理 → 每层管自己一环**：PeerConnection 存活久，但媒体流可动态增删、编解码器可换、网络可断。全塞一个函数会成意大利面条。拆成多步，**每步只做一件事、只持有自己需要的对象，谁创建谁销毁就清晰了。**
- **③ 可插拔/可替换 → 面向接口编程**：`VideoStreamBufferController`/`FrameBuffer`/`VideoStreamDecoder` 都是可替换实现。拆开是为了"换一个模块不影响其他模块"（换 jitter buffer 算法只需守住 `InsertFrame`/`OnCompleteFrame` 接口）。

**类比**：这就像流水线——每个工位做一件小事，但整条线能稳定生产。**步骤多不是冗余，是每个步骤都对应一个"职责边界"（线程边界 / 生命周期边界 / 接口边界）。**

**③ 带"2"的类名（`VideoReceiveStream2`/`VideoStreamDecoder2`/`VideoReceiver2`）是历史遗留**
M144 里**只有 2，没有 1**。这是 2020 年（M80 前后）重构时加的后缀，1 早已删除但名字没改回。看到带 2 的类就当作"当前唯一实现"，不用去找 1。

**④ 跨线程投递对性能的影响可控**
跨线程投递的只是**任务/回调（lambda）**，帧/包数据通过 `std::move` 转移所有权，**零拷贝**。开销在调度（加锁+入队+唤醒，微秒级），不在数据复制。WebRTC 用"解码独立 HIGH 优先级队列 + 高频路径留同一线程 + 数据不跨 JNI"来缓解。

---

## 一、重要前提：`api/` 不完全是"外部接口"

`api/` 目录的官方定位（`api/README.md`）是 **"对外公共 C++ API 的家"**，但这里的"对外"指**给 WebRTC 库的使用者**（LiveKit、Chrome、其他集成方），而不是最终用户。

关键点：**`api/` 目录里既有"真正的公开接口"（`*_interface.h`），也有"内部实现细节"（`webrtc_sdp.cc`、`jsep.cc`），还有"内部工具"（`units/`、`task_queue/`、`numerics/`）**。不能简单说"所有对外接口都在这里"。

- 真正的**对外接口** = `*_interface.h`（纯抽象类）+ 工厂函数 + 数据类
- 目录里也混着**实现文件**（`.cc`）和**内部工具**

### api/ 的边界设计（README 三条规则）

1. **`.h` 不 `#include` 目录外内容** —— 避免把内部头文件泄漏给使用者
2. **`.cc` 可以自由 include 外部** —— 实现细节藏在 .cc 里
3. **优先 class 而非 struct** —— 便于 API 演进（struct 加约束/改表示很难迁移）

**所以 `api/` 的真正价值 = 稳定的"契约层"**：把 WebRTC 内部（pc/、call/、modules/）的实现细节全部挡在 `*_interface.h` 抽象类后面，只暴露稳定接口。LiveKit 只依赖这些接口，不碰内部实现——这就是为什么 LiveKit 能通过 `android-prefixed:144` 版本升级 WebRTC 而不用改代码。

---

## 二、核心疑问解答：为什么"内部实现"会暴露到 api/？

> 直觉：媒体不就是数据（音视频）吗？拥塞和 neteq 不都是内部实现吗，需要提供给上层什么？

**答案：api/ 暴露的是"控制面"和"观测面"，不是"数据面"本身。**

用比喻：发动机内部（喷油、点火、活塞）= `modules/`（内部实现）；你坐在驾驶室只需要**油门踏板**和**仪表盘** = `api/transport/`、`api/neteq/`（暴露的接口）。你不需要碰发动机，但需要"踩油门"和"看转速表"。

具体到两个疑问：

### ① 拥塞控制为什么暴露到 api/？
上层不需要实现拥塞控制，但需要：
- **配置**：设初始码率、最小/最大码率（`bitrate_settings.h`）
- **观测**：知道当前带宽估计值、丢包率（`network_types.h` 里的 `TargetTransferRate`）
- **可选替换**：WebRTC 允许**自己写一个拥塞控制器**替换内置 Goog-CC（`network_control.h` 定义了"插槽"接口）

### ② NetEq 为什么暴露到 api/？
NetEq（抖动缓冲+丢包隐藏）也是内部实现，但 api/ 暴露的是：
- **配置**：抖动缓冲的延迟管理策略（`delay_manager_interface.h`）
- **可选替换**：`neteq_factory.h` 允许注入自定义 NetEq

**一句话总结：api/ 里凡是"看起来像内部实现"的东西，暴露的都是"配置/观测/替换插槽"，而不是把内部逻辑搬上来。**

---

## 三、内部实现映射图

```
┌─────────────────────────────────────────────────────────────┐
│  api/ 对外接口层（契约）                                      │
└─────────────────────────────────────────────────────────────┘
        │ 实现（implements）
        ▼
┌─────────────────────────────────────────────────────────────┐
│  pc/  PeerConnection 编排层                                   │
│  PeerConnectionInterface ──► PeerConnection (pc/peer_connection.h)│
│  RtpSenderInterface     ──► RtpSender (pc/rtp_sender.h)          │
│  RtpReceiverInterface   ──► RtpReceiver (pc/rtp_receiver.h)      │
│  RtpTransceiverInterface─► RtpTransceiver (pc/rtp_transceiver.h) │
│  DataChannelInterface   ──► SctpDataChannel (pc/sctp_data_channel.h)│
│  IceTransportInterface  ──► P2PTransportChannel (p2p/base/)      │
│  DtlsTransportInterface ──► DtlsTransport (p2p/dtls/)            │
└─────────────────────────────────────────────────────────────┘
        │ 调用
        ▼
┌─────────────────────────────────────────────────────────────┐
│  call/ 媒体调用层                                             │
│  transport.h ──► Call / RtpTransportControllerSend             │
│  bitrate_allocation.h ──► BitrateAllocator                     │
└─────────────────────────────────────────────────────────────┘
        │ 调用
        ▼
┌─────────────────────────────────────────────────────────────┐
│  modules/ 媒体处理模块（真正的"内部实现"）                      │
│  audio_processing.h ──► AudioProcessingImpl (modules/audio_processing/)│
│  audio_device.h     ──► AudioDeviceModule (modules/audio_device/)     │
│  neteq.h            ──► NetEqImpl (modules/audio_coding/neteq/)       │
│  bandwidth_usage.h  ──► GoogCcNetworkController (modules/congestion_controller/goog_cc/)│
│  video_frame.h      ──► VideoFrameBuffer (modules/video_coding/)      │
│  encoded_image.h    ──► EncodedImage (modules/video_coding/)          │
└─────────────────────────────────────────────────────────────┘
```

---

## 四、详细表格：文件 / 作用 / 详解

### 1. 核心会话接口（连接骨架）

| 文件 | 作用 | 详解 |
|---|---|---|
| `peer_connection_interface.h` | 定义 `PeerConnectionInterface` | 76KB 的巨无霸，W3C 规范实现。声明所有连接操作：`CreateOffer/Answer`、`SetLocal/RemoteDescription`、`AddTrack/RemoveTrack`、`AddIceCandidate`、`GetStats`。**LiveKit 的 `PeerConnection` 底层就是它**。实现类在 `pc/peer_connection.h` |
| `create_peerconnection_factory.h` | 工厂函数 | `CreatePeerConnectionFactory(...)` 传入网络/工作/信令线程 + 音频/视频编解码工厂 + ADM。**整个引擎的唯一入口**，LiveKit 的 `PeerConnectionFactoryManager` 调它 |
| `rtp_sender_interface.h` | 发送端 | 一个 track 的发送控制：`SetParameters`（编码参数）、`ReplaceTrack`、`GetStats`。实现 `pc/rtp_sender.h` |
| `rtp_receiver_interface.h` | 接收端 | 接收 track 控制：`SetParameters`、`GetParameters`。实现 `pc/rtp_receiver.h` |
| `rtp_transceiver_interface.h` | 收发器 | 把 sender+receiver 配成一对，控制方向（sendonly/recvonly/sendrecv）。实现 `pc/rtp_transceiver.h` |
| `media_stream_interface.h` | 媒体流 | `MediaStreamInterface`（一组音视频轨）+ `MediaStreamTrackInterface`（单轨）。LiveKit 的 `LocalVideoTrack` 包装它 |
| `data_channel_interface.h` | 数据通道 | `DataChannelInterface`：`Send`、`OnMessage`、`buffered_amount`。实现 `pc/sctp_data_channel.h`（走 SCTP）。**LiveKit 的 DataStream/RPC 走这里** |
| `dtls_transport_interface.h` | DTLS 传输 | `DtlsTransportInterface`，状态机 `kNew/Connecting/Connected/Closed/Failed`。实现 `p2p/dtls/dtls_transport.cc` |
| `sctp_transport_interface.h` | SCTP 传输 | 数据通道的底层传输 |
| `ice_transport_interface.h` | ICE 传输 | ICE 传输抽象 |
| `jsep.h` / `jsep_ice_candidate.h` | SDP 抽象 | `SessionDescriptionInterface`（offer/answer）、`IceCandidateInterface`。**SDP 协商的核心**，实现 `pc/webrtc_session_description_factory.cc` |
| `rtc_error.h` | 错误码 | `RTCError`，所有操作的返回类型 |
| `dtmf_sender_interface.h` | 电话拨号音 | DTMF（电话按键音），VoIP 场景用 |

### 2. 编解码器接口

| 文件 | 作用 | 详解 |
|---|---|---|
| `audio_codecs/audio_encoder.h` | 音频编码器抽象 | `AudioEncoder`，实现 Opus/G711/G722/L16 |
| `audio_codecs/audio_decoder.h` | 音频解码器抽象 | `AudioDecoder` |
| `audio_codecs/audio_encoder_factory.h` | 编码器工厂 | 创建编码器集合，LiveKit 用 `builtin_audio_encoder_factory` |
| `audio_codecs/opus/` | Opus 编解码 | 内置 Opus 实现 |
| `video_codecs/video_encoder.h` | 视频编码器抽象 | `VideoEncoder`，LiveKit 的 `VideoEncoderFactory` 注入点 |
| `video_codecs/video_decoder.h` | 视频解码器抽象 | `VideoDecoder` |
| `video_codecs/sdp_video_format.h` | SDP 编解码格式 | VP8/VP9/H264/H265/AV1 的 SDP 协商参数 |
| `video_codecs/scalability_mode.h` | 可伸缩编码 | SVC 模式（L1T3 等） |

### 3. 媒体处理接口

| 文件 | 作用 | 详解 |
|---|---|---|
| `audio/audio_processing.h` | 音频处理 | `AudioProcessing`：AEC（回声消除）/NS（降噪）/AGC（自动增益）。实现 `modules/audio_processing/` |
| `audio/audio_device.h` | 音频设备 | `AudioDeviceModule`（ADM），采集/播放。LiveKit 用 `JavaAudioDeviceModule` 实现它 |
| `audio/audio_mixer.h` | 音频混音 | 多方混音器 |
| `audio/echo_canceller3_config.h` | AEC3 配置 | 回声消除算法参数 |
| `video/video_frame.h` | 视频帧 | `VideoFrame`，时间戳+像素缓冲 |
| `video/i420_buffer.h` | I420 像素缓冲 | YUV 4:2:0 数据，视频帧的实际像素载体 |
| `video/encoded_image.h` | 编码后图像 | `EncodedImage`，编码后的 H264/VP8 比特流 |
| `video/color_space.h` | 色彩空间 | HDR/色彩元数据 |
| `video/frame_buffer.h` | 视频抖动缓冲 | 帧缓冲（解码前的重排序） |

### 4. 传输/拥塞/统计接口

| 文件 | 作用 | 详解 |
|---|---|---|
| `transport/network_types.h` | 网络数据类型 | `TargetTransferRate`（带宽估计结果）、`NetworkControlUpdate` |
| `transport/network_control.h` | 拥塞控制插槽 | `NetworkControllerInterface`——**允许你替换内置拥塞控制器**。内置实现 `GoogCcNetworkController`（`modules/congestion_controller/goog_cc/`） |
| `transport/bandwidth_usage.h` | 带宽状态 | `BandwidthUsage`：`kBwNormal/Underusing/Overusing` |
| `transport/goog_cc_factory.h` | Goog-CC 工厂 | 创建 Goog-CC 控制器 |
| `transport/bitrate_settings.h` | 码率配置 | 初始/最小/最大码率设置 |
| `transport/stun.h` | STUN 协议 | STUN 消息构造/解析 |
| `transport/data_channel_transport_interface.h` | 数据通道传输 | DataChannel 的传输层抽象 |
| `stats/rtc_stats.h` | 统计报告 | `RTCStatsReport`，LiveKit 的 `RTCStatsExt` 解析它 |
| `stats/rtcstats_objects.h` | 统计对象 | `RTCIceCandidateStats`、`RTCInboundRtpStreamStats` 等具体统计项 |
| `call/transport.h` | 传输回调 | `Transport`：`SendRtp/SendRtcp` 回调 |
| `call/bitrate_allocation.h` | 码率分配 | 多流之间的码率分配结果 |
| `neteq/neteq.h` | NetEq 接口 | `NetEq`：抖动缓冲+丢包隐藏。实现 `modules/audio_coding/neteq/neteq_impl.h` |
| `neteq/neteq_factory.h` | NetEq 工厂 | 允许注入自定义 NetEq |

### 5. 基础设施/内部工具

| 文件 | 作用 | 详解 |
|---|---|---|
| `units/timestamp.h` | 时间戳类型 | 带单位的 `Timestamp`，全库通用 |
| `units/data_rate.h` | 码率类型 | `DataRate`（bps） |
| `units/data_size.h` | 数据量类型 | `DataSize`（bytes） |
| `units/time_delta.h` | 时间差类型 | `TimeDelta` |
| `task_queue/task_queue_factory.h` | 任务队列 | 线程抽象，创建任务队列 |
| `task_queue/pending_task_safety_flag.h` | 任务安全 | 防止任务在对象销毁后执行 |
| `rtc_event_log/rtc_event_log.h` | 事件日志 | 记录 RTP/RTCP 事件用于调试 |
| `crypto/frame_encryptor_interface.h` | 帧加密 | `FrameEncryptorInterface`，**LiveKit E2EE 的 FrameEncryptor 实现它** |
| `crypto/frame_decryptor_interface.h` | 帧解密 | 同上，解密侧 |
| `crypto/crypto_options.h` | 加密配置 | SRTP 加密算法选项 |
| `scoped_refptr.h` / `ref_counted_base.h` | 引用计数 | 智能指针，全库内存管理基础 |
| `sequence_checker.h` | 线程检查 | 断言代码在指定线程执行 |
| `array_view.h` / `function_view.h` | 视图类型 | 轻量数组/函数引用 |
| `field_trials.h` | 实验开关 | 特性开关（A/B 实验） |
| `voip/` | VoIP 专用 | 纯 VoIP 场景的简化接口，LiveKit 不用 |
| `metronome/` | 节拍器 | 定时调度，特定优化用 |

---

## 五、哪些"必要"、哪些"不必要"？（从 LiveKit 集成角度）

### 绝对必要（LiveKit 直接依赖）
- `peer_connection_interface.h`、`create_peerconnection_factory.h` —— 连接核心
- `rtp_*_interface.h`、`media_stream_interface.h` —— 媒体
- `data_channel_interface.h` —— 数据通道
- `audio_processing.h`、`audio_device.h` —— 音频处理
- `crypto/frame_encryptor_interface.h` —— E2EE
- `stats/` —— 统计
- `units/`、`task_queue/`、`scoped_refptr.h`、`rtc_error.h` —— 基础设施

### 可选/按需（取决于业务）
- `voip/` —— 纯 VoIP 场景才用（LiveKit 不用，走通用 PeerConnection）
- `metronome/`、`adaptation/` —— 特定优化
- `neteq/` —— 自定义 NetEq 才用
- 各种 `*_unittest.cc` —— 测试，不编译进库

---

## 六、深度澄清：VideoFrame 与 buffer 的关系

**精确关系**：`VideoFrame` 是"一帧的元数据容器"，内部持有一个 `VideoFrameBuffer` 指针，而真正的像素数据在 `VideoFrameBuffer` 的具体实现里。

看代码结构（`api/video/`）：
- `video_frame.h` 的 `VideoFrame` 持有成员：`scoped_refptr<VideoFrameBuffer> video_frame_buffer_`（line 131）+ 时间戳（`timestamp_us_`、`timestamp_rtp_`、`ntp_time_ms_`）
- `video_frame_buffer.h` 的 `VideoFrameBuffer` 是**抽象基类**，定义 `width()/height()/type()/ToI420()` 等接口，**不存数据**
- **真正的像素数据**在 `VideoFrameBuffer` 的具体子类里（`I420Buffer`、`NV12Buffer` 等），实现在 `api/video/i420_buffer.h`

**准确说法**：
> 数据（像素）在 buffer 的具体子类里流动；`VideoFrame` 是对"这一帧"的元数据描述（时间戳、尺寸、引用哪个 buffer）；`VideoFrameBuffer` 是访问像素数据的统一接口（抽象基类）。

**为什么这样设计？** 解码器（Android 的 MediaCodec，WebRTC 在 `sdk/android/` 层调用它）可能产生 GPU 纹理（`kNative` 类型），软件编码器需要 CPU 内存（`kI420`）。上层拿到 `VideoFrameBuffer` 接口，不用关心底层是 GPU 还是 CPU，只需调 `ToI420()` 就能拿到统一的 I420 数据。这就是"接口抽象数据访问"。

**关键澄清（MediaCodec 与纹理）**：
- **MediaCodec 不是 WebRTC 内部类**，而是 **Android 系统**的硬件编解码器（`android.media.MediaCodec`）。WebRTC 在 `sdk/android/` 层调用它（`MediaCodecVideoDecoderFactory.java`、`HardwareVideoEncoder.java`、`AndroidVideoDecoder.java`），不在 `modules/video/` 里。
- **纹理（texture）= GPU 显存里的图像数据**，与 CPU 内存（RAM，如 I420 的 Y/U/V 平面）相对。Android MediaCodec 解码后默认输出 Surface（GPU 纹理），因为最终要渲染到屏幕，全程在 GPU 可避免"解码→拷 CPU→传回 GPU"的两次拷贝。
- `ToI420()` 是抽象方法，每个子类自己实现：`kI420`（CPU）直接返回自身；`kNative`（GPU 纹理）则把纹理读回 CPU 转成 I420。渲染时直接用纹理（快），需像素数据时调 `ToI420()`（慢但通用）。

**修正表述**：音视频数据在 modules 里流动，`api/video/video_frame.h` 的对象（`VideoFrame`）不是"管理" buffer，而是**"携带"buffer 引用 + 描述其元数据**，并通过 `VideoFrameBuffer` 这个抽象接口提供统一的像素访问方式。

---

## 七、深度澄清：拥塞控制与 NetEq 的理解

### 你的理解（基本全对）：
1. **简单功能**：走通用配置，设个开关/基本参数就行
2. **动态调整**（码率/分辨率）：需要单独接口（拥塞控制的 `NetworkControllerInterface` 就是干这个）
3. **替换模块**：只需实现相同接口即可

### 补充和精确化：

**关于"开关/基本配置"**：
- 拥塞控制默认就是**开着的**（Goog-CC 是内置默认），不需要"打开"它
- 配置的只是**边界参数**：初始码率、最小/最大码率（`bitrate_settings.h`）
- NetEq 也是默认开启的，配置的是**延迟策略**（`delay_manager_interface.h`）

**关于"动态调整"**：
- 拥塞控制的动态调整是**自动的**，不是上层手动调的。Goog-CC 根据网络反馈（丢包/延迟）**自动**升降码率。上层只是**观测**结果（`TargetTransferRate`）并**响应**（比如收到码率下降通知后，降低编码分辨率）
- 所以 api/transport 暴露的是：**配置入口 + 观测出口 + 替换插槽**

**关于"替换模块"（最准确的理解）**：
- `NetworkControllerInterface` 就是一个**插槽**，实现它就能替换 Goog-CC
- NetEq 同理：`NetEqFactory` 允许注入自定义实现
- 这就是"面向接口编程"——api/ 定义契约，实现随便换

### 一个需要纠正的细微点：
"只需要随着整个 webrtc 模块的通用配置设置一个开关"——**部分对**。拥塞控制和 NetEq 不是"开关型"功能，而是**默认常驻的算法**。它们更像"发动机里的变速箱"，一直工作，你只是偶尔调档或看仪表，而不是"开关"它。真正的"开关"是像 `field_trials.h`（实验特性开关）那样的东西。

### 总结表

| 观点 | 准确性 | 修正 |
|---|---|---|
| 音视频 buffer 在 modules 流动，api 对象管理它们 | ⚠️ 方向对 | 不是"管理"，是"携带引用+描述元数据+统一访问接口" |
| 简单功能走通用配置开关 | ✅ 基本对 | 拥塞/NetEq 是常驻算法，不是开关；配置的是边界参数 |
| 动态调整需要单独接口 | ✅ 对 | 且调整是自动的，上层只观测+响应 |
| 替换模块只需实现相同接口 | ✅ 完全对 | 这正是 api/ 接口层的核心价值 |

---

## 八、api/ 目录结构速览

```
api/
├── peer_connection_interface.h        # 核心：PeerConnection 接口（76KB）
├── create_peerconnection_factory.h    # 引擎唯一入口
├── rtp_sender/receiver/transceiver_interface.h
├── media_stream_interface.h / media_stream_track.h
├── data_channel_interface.h           # DataChannel（LiveKit DataStream/RPC）
├── dtls/sctp/ice_transport_interface.h
├── jsep.h / jsep_ice_candidate.h      # SDP 抽象
├── rtc_error.h / dtmf_sender_interface.h
├── audio_codecs/  video_codecs/       # 编解码接口
├── audio/  video/                     # 媒体处理接口
├── transport/  # 拥塞控制 + 传输层接口 + STUN + 网络类型
├── stats/      # 统计报告（RTCStats）
├── call/       # 媒体调用层：传输回调 + 码率分配
├── neteq/      # 抖动缓冲 + 丢包隐藏
├── crypto/                            # E2EE 帧加密/解密
├── units/  task_queue/  rtc_event_log/# 基础设施
├── scoped_refptr.h  sequence_checker.h  array_view.h  field_trials.h
├── voip/  metronome/  adaptation/     # 可选/特定场景
└── webrtc_sdp.cc  jsep.cc             # 实现文件（混在 api/ 里）
```

---

## 九、一级/二级目录分层分析（工程结构图）

WebRTC 源码是**严格分层**的。从最上层（对外接口）到最底层（系统基础设施），依赖方向是**单向向下的**：上层 include 下层，下层不 include 上层。这是理解整个工程结构的钥匙。

### 分层总览（7 层）

```
┌──────────────────────────────────────────────────────────────┐
│ L1  api/          对外接口层（契约）—— 只放接口/数据类/工厂      │
├──────────────────────────────────────────────────────────────┤
│ L2  pc/  media/   会话编排层 —— PeerConnection 逻辑 + 媒体引擎   │
├──────────────────────────────────────────────────────────────┤
│ L3  call/         媒体调用层 —— 把"会话"变成"可运行的媒体流"      │
├──────────────────────────────────────────────────────────────┤
│ L4  video/ audio/ 媒体流实现层 —— 音视频收发流的具体实现          │
├──────────────────────────────────────────────────────────────┤
│ L5  modules/      媒体处理模块层 —— 编解码/处理/网络协议（核心）   │
├──────────────────────────────────────────────────────────────┤
│ L6  p2p/ net/     传输层 —— ICE/DTLS 连接 + SCTP/数据通道        │
├──────────────────────────────────────────────────────────────┤
│ L7  rtc_base/     基础设施层 —— 线程/内存/日志/网络/工具          │
│     common_audio/ common_video/ system_wrappers/               │
│     logging/  stats/  data/  examples/  test/                  │
└──────────────────────────────────────────────────────────────┘
```

### 各层目录详解

| 层 | 目录 | 作用 | 关键内容 |
|---|---|---|---|
| **L1 接口** | `api/` | 对外契约层，所有 `*_interface.h` | `peer_connection_interface.h`、`create_peerconnection_factory.h`、`rtp_*_interface.h`、`data_channel_interface.h`、`jsep.h`、`units/`、`task_queue/` |
| **L2 会话编排** | `pc/` | PeerConnection 核心实现，把 api 接口变成具体对象 | `peer_connection.h`、`rtp_sender.h`、`rtp_transceiver.h`、`sctp_data_channel.h`、`dtls_srtp_transport.cc`、`jsep_transport_controller.cc`、`webrtc_session_description_factory.cc` |
| **L2 媒体引擎** | `media/` | 音视频引擎，编解码器与轨道的"胶水" | `engine/webrtc_media_engine.cc`、`webrtc_video_engine.cc`、`webrtc_voice_engine.cc`、`simulcast_encoder_adapter.cc`；`base/` 轨道源 |
| **L3 媒体调用** | `call/` | 把会话编排成可运行的媒体流，含发送控制 | `call.cc`、`rtp_transport_controller_send.cc`、`bitrate_allocator.cc`、`rtp_video_sender.cc`、`video_send_stream.cc`、`rtp_demuxer.cc` |
| **L4 媒体流实现** | `video/` | 视频收发流的具体实现 | `video_send_stream_impl.cc`、`video_receive_stream2.cc`、`video_stream_encoder.cc`、`rtp_video_stream_receiver2.cc`、`stream_synchronization.cc` |
| **L4 音频流实现** | `audio/` | 音频收发流实现 | `audio_send_stream.cc`、`audio_receive_stream.cc`、`channel_send.cc`、`channel_receive.cc`、`audio_state.cc` |
| **L5 媒体模块** | `modules/` | **核心算法库**，平台无关 | `audio_coding/`(NetEq)、`audio_processing/`(AEC)、`audio_device/`、`video_coding/`(编解码/jitter buffer)、`congestion_controller/`(GCC)、`rtp_rtcp/`(协议栈)、`pacing/`、`desktop_capture/`、`video_capture/` |
| **L6 传输层** | `p2p/` | P2P 连接：ICE/DTLS | `base/`(PortAllocator/ICE)、`dtls/dtls_transport.cc` |
| **L6 网络** | `net/` | 网络传输实现 | `dcsctp/`(数据通道 SCTP)、`dtls/` |
| **L7 基础设施** | `rtc_base/` | **最底层**，全库依赖 | `thread`、`socket`、`logging`、`memory`、`network`、`synchronization`、`numerics`、`strings`、`boringssl` |
| **L7 公共** | `common_audio/` | 音频公共处理 | FFT、信号处理等 |
| **L7 公共** | `common_video/` | 视频公共处理 | 帧工具 |
| **L7 系统** | `system_wrappers/` | 系统抽象 | 时钟、CPU 等 |
| **L7 日志** | `logging/` | 事件日志 | `rtc_event_log/` |
| **L7 统计** | `stats/` | 统计 | `rtc_stats.h` |
| **L7 数据** | `data/` | 数据通道相关 | `audio_processing/`、`voice_engine/` |
| **L7 平台 SDK** | `sdk/` | **平台专属**（Android/ObjC），不属于核心分层 | `android/`(JNI+MediaCodec)、`objc/` |
| **辅助** | `examples/` `test/` `rtc_tools/` `tools_webrtc/` `docs/` `infra/` | 示例/测试/工具/文档，不编译进库 | — |

### 依赖方向与关键理解

**① 依赖单向向下**：`api/`(L1) 不被下层 include（它只被上层用）；`rtc_base/`(L7) 被所有层依赖，但从不依赖上层。这就是为什么 `api/README.md` 要求 `.h` 不 include 目录外——保持契约层纯净。

**② 核心是 `modules/`**：1951 个文件，是算法的家（编解码、处理、协议）。`pc/`(245)、`call/`(114)、`media/`(91)、`video/`(246)、`audio/`(61) 都是**编排和胶水**，真正干活的算法在 modules/。

**③ `sdk/` 是"旁支"**：它实现 `api/` 的接口（如 `VideoEncoder`），但带平台专属逻辑（JNI、MediaCodec），不属于核心分层，是"平台适配层"。

**④ 从 LiveKit 集成视角，最该关注的核心链路**：
```
api/(接口) → pc/(PeerConnection) → media/(媒体引擎) → call/(媒体流)
          → video//audio/(流实现) → modules/(编解码/处理/协议)
          → p2p//net/(连接/传输) → rtc_base/(基础设施)
```

### 必要目录 vs 辅助目录

**必要（编译进库，LiveKit 依赖）**：`api/`、`pc/`、`media/`、`call/`、`video/`、`audio/`、`modules/`、`p2p/`、`net/`、`rtc_base/`、`common_audio/`、`common_video/`、`system_wrappers/`、`logging/`、`stats/`、`data/`、`sdk/`

**辅助（不编译进库）**：`examples/`、`test/`、`rtc_tools/`、`tools_webrtc/`、`docs/`、`g3doc/`、`infra/`、`resources/`

---

## 十、精细版工程结构图（补充）

上一节的 7 层图是骨架；这一节把每个目录的**关键子目录/关键文件**和**依赖/调用方向**补进去，做成可当"工程地图"用的精细版。

### 精细分层图（含关键文件）

```
┌─────────────────────────────────────────────────────────────────────────┐
│ L1  api/ 对外接口层（契约）—— 只放接口/数据类/工厂，.h 不 include 目录外    │
│                                                                         │
│   peer_connection_interface.h   create_peerconnection_factory.h         │
│   rtp_sender/receiver/transceiver_interface.h  media_stream_interface.h │
│   data_channel_interface.h  dtls/sctp/ice_transport_interface.h         │
│   jsep.h  rtc_error.h  dtmf_sender_interface.h                          │
│   ├─ audio_codecs/  video_codecs/   编解码接口                          │
│   ├─ audio/  video/                 媒体处理接口                        │
│   ├─ transport/  stats/  call/  neteq/  拥塞/统计/传输/抖动缓冲接口      │
│   ├─ crypto/                         E2EE 帧加密/解密接口               │
│   └─ units/  task_queue/  rtc_event_log/  基础设施                      │
└─────────────────────────────────────────────────────────────────────────┘
        │ 实现（implements）＋ 调用
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ L2  pc/ 会话编排层 —— PeerConnection 核心，把接口变成具体对象             │
│                                                                         │
│   peer_connection.cc(.h)        ← 实现 PeerConnectionInterface          │
│   peer_connection_factory.cc    ← 实现 create_peerconnection_factory    │
│   rtp_sender.h  rtp_receiver.h  rtp_transceiver.h  ← 实现 Rtp*Interface │
│   sctp_data_channel.h           ← 实现 DataChannelInterface             │
│   video_track.h  audio_track.h  media_stream.h                          │
│   dtls_srtp_transport.cc  srtp_transport.cc  ← SRTP 加密                │
│   jsep_transport_controller.cc  webrtc_session_description_factory.cc   │
│   channel.cc  channel_interface.h                                       │
└─────────────────────────────────────────────────────────────────────────┘
        │ 组合
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ L2  media/ 媒体引擎层 —— 编解码器与轨道的"胶水"                          │
│                                                                         │
│   engine/webrtc_media_engine.cc    ← 总引擎                            │
│   engine/webrtc_video_engine.cc    ← 视频引擎                          │
│   engine/webrtc_voice_engine.cc    ← 音频引擎                          │
│   engine/simulcast_encoder_adapter.cc  ← 多路编码适配                   │
│   base/  (adapted_video_track_source.h 等轨道源)                        │
└─────────────────────────────────────────────────────────────────────────┘
        │ 调用
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ L3  call/ 媒体调用层 —— 把"会话"变成"可运行的媒体流"，含发送控制          │
│                                                                         │
│   call.cc                          ← 总调度                            │
│   rtp_transport_controller_send.cc ← 发送控制（pacing+拥塞）            │
│   bitrate_allocator.cc             ← 码率分配                          │
│   rtp_video_sender.cc  rtp_demuxer.cc                                  │
│   video_send_stream.cc  video_receive_stream.cc                        │
│   audio_send_stream.cc  audio_receive_stream.cc                        │
└─────────────────────────────────────────────────────────────────────────┘
        │ 调用
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ L4  video/ + audio/ 媒体流实现层 —— 收发流的具体实现                     │
│                                                                         │
│   video/: video_send_stream_impl.cc  video_receive_stream2.cc           │
│           video_stream_encoder.cc  rtp_video_stream_receiver2.cc        │
│           video_source_sink_controller.cc  stream_synchronization.cc    │
│   audio/: audio_send_stream.cc  audio_receive_stream.cc                 │
│           channel_send.cc  channel_receive.cc  audio_state.cc           │
└─────────────────────────────────────────────────────────────────────────┘
        │ 调用
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ L5  modules/ 媒体处理模块层 —— ★核心算法库（平台无关，1951 文件）         │
│                                                                         │
│   audio_coding/      NetEq 抖动缓冲 + 编解码(acm2/codecs/neteq)          │
│   audio_processing/  AEC/NS/AGC（回声消除/降噪/增益）                    │
│   audio_device/      音频设备抽象                                        │
│   audio_mixer/       多方混音                                            │
│   video_coding/      视频编解码 + jitter buffer(codecs/svc/timing)       │
│   congestion_controller/  GCC 拥塞控制(goog_cc/ + scream/ + pcc/)        │
│   rtp_rtcp/          RTP/RTCP 协议栈(source/)                           │
│   pacing/            发送节流                                            │
│   remote_bitrate_estimator/ 远端码率估计                                 │
│   video_capture/  desktop_capture/  采集                                 │
└─────────────────────────────────────────────────────────────────────────┘
        │ 调用
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ L6  p2p/ + net/ 传输层 —— 连接建立 + 数据通道                            │
│                                                                         │
│   p2p/base/   PortAllocator + ICE 状态机                                │
│   p2p/dtls/   dtls_transport.cc  ← 实现 DtlsTransportInterface          │
│   p2p/base/p2p_transport_channel.cc  ← 实现 IceTransportInterface       │
│   net/dcsctp/  数据通道 SCTP（DataChannel 底层）                        │
│   net/dtls/    DTLS 实现                                                │
└─────────────────────────────────────────────────────────────────────────┘
        │ 依赖
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ L7  rtc_base/ 基础设施层 —— ★最底层，被所有层依赖                        │
│                                                                         │
│   thread/  socket/  network/  memory/  logging/                         │
│   synchronization/  numerics/  strings/  boringssl/  units/             │
│   common_audio/  common_video/  system_wrappers/  → 公共处理/系统抽象    │
│   logging/rtc_event_log/  stats/  data/  → 日志/统计/数据               │
└─────────────────────────────────────────────────────────────────────────┘
        │ 平台适配（旁支，非核心分层）
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ sdk/ 平台适配层 —— 实现 api/ 接口，带平台专属逻辑                        │
│                                                                         │
│   android/  JNI 桥接 + MediaCodec 硬件编解码 + Camera 采集               │
│   objc/     iOS/macOS 适配                                              │
└─────────────────────────────────────────────────────────────────────────┘
```

### 依赖关系与调用方向（一图看懂）

```
[应用/LiveKit]
   │ 调用 api/ 接口
   ▼
api/ ──实现──► pc/ ──组合──► media/ ──调用──► call/
   │                                              │
   │                                              ▼
   │                                        video/ + audio/
   │                                              │
   │                                              ▼
   │                                        modules/（核心算法）
   │                                              │
   │                                              ▼
   │                                        p2p/ + net/（连接/传输）
   │                                              │
   └──────────────────────────────► rtc_base/（基础设施，被全部依赖）
```

### 关键理解（补充）

**① 依赖严格单向向下**：`api/`(L1) 只被上层用，不被实现层 include；`rtc_base/`(L7) 被所有层依赖但不依赖任何上层。这就是为什么 `api/README.md` 要求 `.h` 不 include 目录外——保持契约层纯净，避免循环依赖。

**② 三层"编排/胶水" vs 一层"核心算法"**：
- `pc/`(245)、`media/`(91)、`call/`(114)、`video/`(246)、`audio/`(61) —— 都是**编排和胶水**，负责把接口变成对象、把对象串成流程
- `modules/`(1951) —— **真正的算法家**：编解码、音频处理、拥塞控制、RTP 协议全在这
- 理解方式：**上层管"怎么串"，modules 管"怎么算"**

**③ `sdk/` 是"旁支"而非"层级"**：它实现 `api/` 的接口（如 `VideoEncoder`），但带平台专属逻辑（JNI、MediaCodec），不属于核心分层，是"平台适配层"。`modules/` 里的软件编解码（libvpx/libaom）与 `sdk/android/` 里的硬件编解码（MediaCodec）都实现同一个 `api/video_codecs/` 接口。

**④ 一条完整数据流的落点**（以视频上行为例）：
```
api/(VideoEncoder 接口)
  → sdk/android/(HardwareVideoEncoder，MediaCodec 编码)
  → modules/video_coding/(编码后帧)
  → call/(rtp_video_sender + rtp_transport_controller_send 拥塞)
  → modules/rtp_rtcp/(RTP 打包)
  → modules/congestion_controller/(GCC 码率决策)
  → pc/(dtls_srtp_transport SRTP 加密)
  → p2p/(ICE 发送)
  → rtc_base/(socket 网络发送)
```
---

## 十一、架构问答精要（2026-09-07 补充）

本节回答 6 个关于架构的追问，重点是**区分"静态依赖层级"与"动态数据流"**——这是理解 WebRTC 分层的关键。

### Q1：为什么有那么多"胶水层"？

因为 WebRTC 是**多线程 + 多生命周期**系统，每层解决不同问题，由不同线程/生命周期管理：

| 层 | 管什么 | 线程/生命周期 |
|---|---|---|
| `pc/` | 会话编排：offer/answer、ICE、轨道增删 | **信令线程**，管"连接状态" |
| `media/` | 媒体引擎：编解码器工厂、轨道源 | **worker 线程**，管"能编解码什么" |
| `call/` | 媒体调度：把轨道变成收发流、码率分配 | **worker 线程**，管"流怎么跑" |
| `video/`+`audio/` | 流实现：具体收发流对象 | 管"单条流怎么收发" |

**核心原因**：一个 PeerConnection 有信令/worker/网络三个线程，每个对象生命周期不同（PeerConnection 存活久，媒体流可动态增删）。若全塞进一层会成意大利面条，线程安全无法保证。**胶水层 = 每层管自己一环，通过接口衔接**（像流水线，每工位做一件事，传送带衔接）。

### Q2：硬件解码的本质链路

```
LiveKit (Kotlin)
  │ 调用 livekit.org.webrtc.VideoDecoder 接口（api/video_codecs/）
  ▼
WebRTC sdk/android/ (JNI 桥)
  │ MediaCodecVideoDecoderFactory → AndroidVideoDecoder
  ▼
Android MediaCodec（系统硬件解码器）
  ▼
解码出 GPU 纹理（Surface）
```

**关键**：LiveKit 调的是 **`VideoDecoder` 接口**，不是 MediaCodec。WebRTC 的 `sdk/android/` 实现该接口，内部才用 MediaCodec。**LiveKit 代码完全不知道 MediaCodec 存在**——这就是接口隔离：LiveKit 可在 Android(MediaCodec)/iOS(VideoToolbox)/桌面(软件)间无缝切换。

### Q3：音视频引擎在干什么？

引擎（`media/engine/`）是**编解码器与轨道之间的适配层**，不自己编解码，而是：

- **`WebRtcVoiceEngine`**：`GetAudioState()`(音频状态)、`CreateSendChannel/ReceiveChannel`(创建收发通道)、`encoder_factory/decoder_factory`(编解码器工厂)、`StartAecDump`(回声调试)、`LegacySendCodecs`(可用编解码器列表)
- **`WebRtcVideoEngine`**：`CreateSendChannel/ReceiveChannel`、`GetRtpHeaderExtensions`(RTP扩展头能力)、管理视频编解码器工厂

**一句话**：引擎 = "编解码器 + 轨道源"的**仓库和工厂**。真正编解码在 `modules/video_coding/` 和 `modules/audio_coding/`。

### Q4：media 在 call 前面吗？

**是的。** 代码证据（`pc/peer_connection_factory.cc` 的 `CreateCall_w`）：
```cpp
call_config.audio_state = media_engine()->voice().GetAudioState();
```
**Call 依赖 media_engine**（audio_state、neteq_factory、fec_controller_factory 都来自/关联 media_engine）。所以必须先有 media_engine 才能创建 Call。

### Q5：调用关系不严格分层？

**对，真实架构是"分层为主 + 交叉依赖 + 回调"**，不是严格单向直线。反例：
1. `media/` 和 `call/` **互相依赖**（media 建通道，call 用通道；call 的 audio_state 又来自 media）
2. `pc/` **直接调用** `modules/`（如 `pc/dtls_srtp_transport.cc` 直接用 modules/rtp_rtcp 的 SRTP，跳过 call/media）
3. **大量回调**：call 创建流后通过回调把结果传回 pc（`OnIceCandidate`、`OnTrack`），是反向调用
4. 依赖方向是**实现层 → api/**（实现层 include api/ 接口），不是 api/ 单向向下

### Q6：细致的依赖/调用关系图（关键澄清）

**核心：call 和 modules 是"组合"关系，不是并列，也不是简单上下级。**

- **静态依赖**：`call/` include `modules/`（call 依赖 modules），`modules/` 核心不 include `call/` → **call 在上，modules 在下**
- **动态数据流**：数据**穿梭**于 call 和 modules 之间（call 编排 → modules 执行 → 结果回调给 call）

代码证据（`call/rtp_video_sender.h`）：
```cpp
class RtpVideoSender {
  std::map<uint32_t, RtpRtcpInterface*> ssrc_to_rtp_module_;  // 持有 modules 的 RTP 对象
  std::unique_ptr<ModuleRtpRtcpImpl2> rtp_rtcp;               // 组合 modules 对象
};
```

**比喻**：call 像**乐队指挥**（编排：何时让谁演奏、节奏控制），modules 像**乐手**（演奏：RTP打包、拥塞计算、编解码）。指挥不演奏，乐手不编排，但数据（音乐）在两者间穿梭。

#### 静态依赖层级图

```
api/       接口层（契约）
  ▲ 实现
pc/        会话编排层（信令线程）
  │ 组合
media/     媒体引擎层（worker 线程）
  │ 依赖
call/      媒体调度层（编排者，持有 modules 对象）
  │ 依赖
video/ + audio/  媒体流实现层
  │ 依赖
modules/   核心算法层（被 call 持有和调用）
  │ 依赖
p2p/ + net/  传输层
  │ 依赖
rtc_base/  基础设施层（被全部依赖）
```

#### 动态数据流图（视频上行，展示穿梭与回调）

```
[call/]  RtpVideoSender（编排者）
   │ 调用
   ▼
[modules/] ModuleRtpRtcpImpl2（RTP 协议栈，被 call 持有）
   │
   ▼
[modules/] RtpSenderEgress（RTP 打包）
   │
   ▼
[modules/] PacingController（发送节流）
   │
   ▼
[call/]  rtp_transport_controller_send（拥塞，回调回来）
   │ 拥塞结果回调
   ▼
[call/]  调整编码/码率（回到编排者）
```

**关键**：数据流**交替经过 call 和 modules**，不是简单的从上到下。之前的"流水线"图有误导——它把"数据流经过的模块"画成了"层级递进"。

#### 完整依赖/回调关系（含交叉）

```
                    ┌─────────────────────────────┐
                    │  LiveKit / 应用 (Kotlin)      │
                    └──────────────┬──────────────┘
                                   │ 调用 api/ 接口
                                   ▼
                    ┌─────────────────────────────┐
                    │  api/ 接口层（契约）           │
                    └──────┬──────────────┬───────┘
                           │              │
             实现(implements)│              │ include
                           ▼              ▼
     ┌─────────────────────────────┐  ┌──────────────────────────┐
     │  pc/ 会话编排层              │  │  media/ 媒体引擎层         │
     │  PeerConnection             │  │  WebRtcMediaEngine        │
     │   └ 信令线程: SDP/ICE        │◄─┤   ├ WebRtcVoiceEngine      │
     │   └ 创建 Call               │  │   └ WebRtcVideoEngine      │
     └──────┬──────────────────────┘  └──────────┬───────────────┘
            │ 创建Call(依赖media)                  │ 提供audio_state/编解码器
            ▼                                    ▼
     ┌─────────────────────────────────────────────────────────┐
     │  call/ 媒体调度层（编排者）                                │
     │  Call → rtp_transport_controller_send(拥塞)              │
     │  Call → bitrate_allocator(码率分配)                      │
     │  Call → video_send_stream / audio_send_stream            │
     └──────┬───────────────────────────────────────────────────┘
            │ 创建流
            ▼
     ┌─────────────────────────────────────────────────────────┐
     │  video/ + audio/ 媒体流实现层                             │
     │  VideoSendStreamImpl / AudioSendStream                   │
     └──────┬───────────────────────────────────────────────────┘
            │ 调用（组合 modules 对象）
            ▼
     ┌─────────────────────────────────────────────────────────┐
     │  modules/ 核心算法层（被 call 持有和调用）                 │
     │  video_coding/  audio_coding/  congestion_controller/    │
     │  rtp_rtcp/  pacing/                                     │
     └──────┬───────────────────────────────────────────────────┘
            │ 依赖
            ▼
     ┌─────────────────────────────────────────────────────────┐
     │  p2p/ + net/ 传输层                                       │
     │  ICE/DTLS/SCTP                                           │
     └──────┬───────────────────────────────────────────────────┘
            │ 依赖
            ▼
     ┌─────────────────────────────────────────────────────────┐
     │  rtc_base/ 基础设施层（被全部依赖）                        │
     └─────────────────────────────────────────────────────────┘

     交叉依赖与回调（用箭头标注，非严格单向）:
     pc/  ──回调──►  call/   （OnIceCandidate, OnTrack）
     call/ ──回调──►  pc/    （流状态变化）
     pc/  ──直接调用──►  modules/ （SRTP 加密，跳过 call/）
     media/ ◄──双向──►  call/  （media 建通道，call 用通道）
     sdk/ ──实现──►  api/    （VideoEncoder 接口）
```

**关键修正**：真实架构是"**分层为主 + 交叉依赖 + 回调**"，不是严格单向。数据流在 call 和 modules 之间**穿梭**，并有**回调**（反向调用）和**跨层直接调用**（pc/ 直接用 modules/ 的 SRTP）。

---

## 十二、控制图 + 数据流图（2026-09-07 补充）

上一节的图偏"结构"。本节用两张图把**控制关系**和**数据流向/回调**分开画清楚。

### 图 A：控制图（分层分模块，谁控制谁）

控制图回答"**谁创建谁、谁调用谁**"。实线 = 创建/持有（组合），箭头 = 控制方向。

```
┌────────────────────────────────────────────────────────────────────┐
│  LiveKit / 应用 (Kotlin)                                            │
│   └ 调用 api/ 接口（唯一入口）                                       │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ 控制
                               ▼
┌────────────────────────────────────────────────────────────────────┐
│  L1  api/ 接口层（契约，只放接口/数据类/工厂）                        │
│   PeerConnectionInterface  VideoEncoder/Decoder  RtpTransceiver     │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ 实现（implements）
                               ▼
┌────────────────────────────────────────────────────────────────────┐
│  L2  pc/ 会话编排层 ──【信令线程 signaling_thread】                  │
│   PeerConnectionFactory ──创建──► PeerConnection                    │
│   PeerConnection ──创建──► RtpSender / RtpReceiver / Transceiver    │
│   PeerConnection ──创建──► DataChannel / DtlsTransport / IceTransport│
│   └ 轨道对象：VideoTrack / AudioTrack / MediaStream                 │
└───────┬──────────────────────────────┬─────────────────────────────┘
        │ 创建 Call                     │ 组合（持有 media_engine）
        ▼                              ▼
┌───────────────────────────┐  ┌────────────────────────────────────┐
│  L3  call/ 媒体调度层      │  │  L2  media/ 媒体引擎层              │
│  ──【工作线程 worker】     │  │  ──【工作线程 worker】              │
│   Call（编排者）           │  │   WebRtcMediaEngine                 │
│    ├ 创建 VideoSendStream  │  │    ├ WebRtcVoiceEngine（音频引擎）  │
│    ├ 创建 AudioSendStream  │  │    └ WebRtcVideoEngine（视频引擎）  │
│    └ 创建 RtpTransport     │  │                                     │
└───────┬───────────────────┘  └────────────────────────────────────┘
        │ 创建流
        ▼
┌────────────────────────────────────────────────────────────────────┐
│  L4  video/ + audio/ 媒体流实现层 ──【工作线程 worker】              │
│   VideoSendStreamImpl / VideoReceiveStream2                        │
│   AudioSendStream / AudioReceiveStream                             │
└───────┬────────────────────────────────────────────────────────────┘
        │ 组合（持有 modules 对象，调用其算法）
        ▼
┌────────────────────────────────────────────────────────────────────┐
│  L5  modules/ 核心算法层 ──(ICE/DTLS/SCTP)【工作线程 worker 为主】       │
│   video_coding/  audio_coding/  congestion_controller/             │
│   rtp_rtcp/  pacing/  audio_processing/  audio_device/             │
└───────┬────────────────────────────────────────────────────────────┘
        │ 依赖
        ▼
┌────────────────────────────────────────────────────────────────────┐
│  L6  p2p/ + net/ 传输层 ──【网络线程 network_thread】                │
│   ICE/DTLS/SCTP                                                    │
└───────┬────────────────────────────────────────────────────────────┘
        │ 依赖
        ▼
┌────────────────────────────────────────────────────────────────────┐
│  L7  rtc_base/ 基础设施层（被全部依赖，跨所有线程）                   │
└────────────────────────────────────────────────────────────────────┘

旁支：sdk/ 平台适配层（实现 api/ 的 VideoEncoder/Decoder 接口）
      硬件编解码在【工作线程 worker】被 video/ 流调用
```

  L2  pc/ 会话编排层 ──【信令线程 signaling_thread】
  L3  call/ 媒体调度层 ──【工作线程 worker】
  L2  media/ 媒体引擎层 ──【工作线程 worker】
  L4  video/+audio/ 媒体流实现层 ──【工作线程 worker】
  L5  modules/ 核心算法层 ──【工作线程 worker 为主】
  L6  p2p/+net/ 传输层 ──【网络线程 network_thread】
  L7  rtc_base/ 基础设施层（跨所有线程）
  旁支 sdk/ 硬件编解码在【工作线程 worker】被 video/ 流调用


**控制图要点**：
- **创建关系**：`PeerConnectionFactory` 创建 `PeerConnection`，`PeerConnection` 创建 `Call`，`Call` 创建各收发流
- **组合关系**：上层**持有**下层的对象（`call/rtp_video_sender.h` 持有 `modules/rtp_rtcp/` 的 `ModuleRtpRtcpImpl2`）
- **控制方向**：从上到下，上层控制下层


---

### 图 B：数据流图（视频上行，含数据流向与回调）

数据流图回答"**一帧数据怎么走**"。实线 = 数据流向，虚线/标注 = 回调。

```
【视频上行：Camera → 网络】
┌────────────┐
│ Camera 采集 │  (sdk/android/ CameraCapturer)
└─────┬──────┘
      │ VideoFrame（像素）
      ▼
┌──────────────────────────────┐
│ video/ VideoStreamEncoder     │  编码器（软件 libvpx / 硬件 MediaCodec）
│  ├ 编码前的帧处理             │
│  └ 调用 VideoEncoder 编码     │
└─────┬────────────────────────┘
      │ EncodedImage（编码后比特流）
      │ ──回调──► EncodedImageCallback::OnEncodedImage
      ▼
┌──────────────────────────────┐
│ call/ RtpVideoSender（编排者）│
└─────┬────────────────────────┘
      │ 交给 RTP 协议栈
      ▼
┌──────────────────────────────┐
│ modules/rtp_rtcp/             │  RTP 打包
│  ModuleRtpRtcpImpl2           │
│   └ RtpSenderEgress           │
└─────┬────────────────────────┘
      │ RTP 包
      ▼
┌──────────────────────────────┐
│ modules/pacing/ PacingController │  发送节流（平滑）
└─────┬────────────────────────┘
      │ 待发送包
      ▼
┌──────────────────────────────┐
│ call/ rtp_transport_controller_send │  拥塞控制（GCC）
│  └ modules/congestion_controller/   │
└─────┬────────────────────────┘
      │ 网络反馈（丢包/延迟）
      │ ──回调──► TargetTransferRateObserver::OnTargetTransferRate
      ▼
┌──────────────────────────────┐
│ pc/ dtls_srtp_transport       │  SRTP 加密
└─────┬────────────────────────┘
      │ 加密包
      ▼
┌──────────────────────────────┐
│ p2p/ ICE + rtc_base/socket    │  网络发送
└──────────────────────────────┘

【回调回路】拥塞结果 → 调整编码
  modules/congestion_controller（算完码率）
    ──回调──► call/ rtp_transport_controller_send
        ──► video/ VideoStreamEncoder（降低分辨率/码率）
```

---

### 图 C：数据流图（视频下行，含数据流向与回调）

```
【视频下行：网络 → 渲染】
┌──────────────────────────────┐
│ p2p/ ICE + rtc_base/socket    │  网络接收
└─────┬────────────────────────┘
      │ 加密包
      ▼
┌──────────────────────────────┐
│ pc/ dtls_srtp_transport       │  SRTP 解密
└─────┬────────────────────────┘
      │ RTP 包
      ▼
┌──────────────────────────────┐
│ call/ rtp_demuxer             │  按 SSRC 分发
└─────┬────────────────────────┘
      │
      ▼
┌──────────────────────────────┐
│ video/ VideoReceiveStream2    │
│  ├ modules/video_coding/      │  jitter buffer（抖动缓冲）
│  │  帧重排序/丢包处理          │
│  └ 调用 VideoDecoder 解码     │
└─────┬────────────────────────┘
      │ VideoFrame（像素）
      │ ──回调──► DecodedImageCallback::OnDecodedImage
      ▼
┌──────────────────────────────┐
│ VideoSinkInterface::OnFrame   │  渲染回调
│  └ (sdk/android/ SurfaceViewRenderer / TextureViewRenderer)
└──────────────────────────────┘
```

---

### 图 D：数据流图（音频，含回调）

```
【音频上行：麦克风 → 网络】
┌──────────────────────────────┐
│ audio_device/ 采集（ADM）     │  (sdk/android/ JavaAudioDeviceModule)
└─────┬────────────────────────┘
      │ 原始 PCM
      │ ──回调──► AudioTransport::RecordedDataIsAvailable
      ▼
┌──────────────────────────────┐
│ audio_processing/ AEC/NS/AGC  │  回声消除/降噪/增益
└─────┬────────────────────────┘
      │ 处理后 PCM
      ▼
┌──────────────────────────────┐
│ audio/ AudioSendStream        │
│  └ audio_coding/ Opus 编码    │
└─────┬────────────────────────┘
      │ 编码后
      ▼
┌──────────────────────────────┐
│ call/ → modules/rtp_rtcp/     │  RTP 打包 → pacing → 拥塞 → SRTP → 网络
└──────────────────────────────┘

【音频下行：网络 → 扬声器】
┌──────────────────────────────┐
│ call/ rtp_demuxer             │  接收分发
└─────┬────────────────────────┘
      ▼
┌──────────────────────────────┐
│ audio/ AudioReceiveStream     │
│  └ audio_coding/ NetEq        │  抖动缓冲 + 丢包隐藏
│  └ audio_coding/ Opus 解码    │
└─────┬────────────────────────┘
      │ PCM
      │ ──回调──► AudioTransport::NeedMorePlayData
      ▼
┌──────────────────────────────┐
│ audio_device/ 播放（ADM）     │  扬声器输出
└──────────────────────────────┘
```

---

### 控制图 vs 数据流图：区别与联系

| | 控制图（图 A） | 数据流图（图 B/C/D） |
|---|---|---|
| 回答 | 谁创建谁、谁调用谁 | 数据怎么走、回调在哪 |
| 方向 | 创建/组合，从上到下 | 数据流动，可上下穿梭 |
| 体现 | 静态结构、生命周期 | 动态过程、实时回调 |
| 关键 | 上层持有下层对象 | 数据在层间穿梭 + 回调回路 |

**联系**：控制图是"骨架"（谁持有谁），数据流图是"血液"（数据怎么流）。控制关系决定数据能走哪条路，数据流又通过回调反过来影响控制（如拥塞回调调整编码）。

### 12.1 媒体引擎（media/engine）是什么 + 媒体流的两条线（初始化 / 流处理）

**`media/engine` = 媒体引擎 = 装配车间**。它不直接做编解码、不直接做网络传输，而是**把编解码器、音频设备（ADM）、音频处理（AEC/NS/AGC）这些零件组装起来，创建出"发送通道"和"接收通道"**。

**三个核心文件对应三个角色**：

| 文件 | 类 | 职责 |
|---|---|---|
| `webrtc_media_engine.h/.cc` | `WebRtcMediaEngine`（工厂） | 总装配，创建视频引擎和语音引擎 |
| `webrtc_video_engine.h/.cc` | `WebRtcVideoEngine` | 视频装配，持有编解码器工厂，创建视频发送/接收通道 |
| `webrtc_voice_engine.h/.cc` | `WebRtcVoiceEngine` | 语音装配，持有 ADM/编码器/AudioProcessing，创建音频发送/接收通道 |

**两个引擎共有的关键方法**：
```cpp
CreateSendChannel(...)      // 创建"发送通道"
CreateReceiveChannel(...)   // 创建"接收通道"
```

**在分层中的位置**：`api → pc → media(engine) → call → modules → p2p → rtc_base`，媒体引擎在 pc 之下、call 之上——它把 modules 的编解码器/ADM/AudioProcessing 装配成通道，供 call 层的流使用。

---

#### 线一：初始化链路（通道怎么建起来）—— SDP offer/answer 触发

**入口**：收到/生成 SDP，**JNI 层**触发 → `PeerConnection` → `SdpOfferAnswerHandler` 解析出 audio/video 内容，创建通道。

```
【0】JNI 层（最上层）：Java 调 SetRemoteDescription / SetLocalDescription
  sdk/android/src/jni/pc/peer_connection.cc:655
  JNI_PeerConnection_SetRemoteDescription(jni, j_pc, j_observer, j_sdp)
    │  → ExtractNativePC(jni, j_pc)->SetRemoteDescription(sdp, observer)   // :661
    ▼
  pc/peer_connection.cc:1550  PeerConnection::SetRemoteDescription(...)
    │  → sdp_handler_->SetRemoteDescription(observer, desc)                // :1558
    ▼
  【1】pc/sdp_offer_answer.cc:5548  SdpOfferAnswerHandler::CreateChannels(desc)
  │  解析 SDP，分别对 audio/video transceiver 调 CreateChannel
  ├── GetAudioTransceiver()->internal()->CreateChannel(...)   // :5557 音频
  └── GetVideoTransceiver()->internal()->CreateChannel(...)   // :5574 视频
        │
        ▼
【2】pc/rtp_transceiver.cc:204  RtpTransceiver::CreateChannel(...)
  │  判断媒体类型，切到 worker 线程（BlockingCall）
  ├── AUDIO 分支：
  │     media_engine()->voice().CreateSendChannel(...)        // :233
  │     media_engine()->voice().CreateReceiveChannel(...)     // :237
  │     → 组装 VoiceChannel
  └── VIDEO 分支：
        media_engine()->video().CreateSendChannel(...)        // :264
        media_engine()->video().CreateReceiveChannel(...)     // :268
        → 组装 VideoChannel
              │
              ▼
【3】media/engine/webrtc_video_engine.cc:827  WebRtcVideoEngine::CreateSendChannel(...)
  │  创建 WebRtcVideoSendChannel（发送通道对象）
  │
  ▼
【4】后续：WebRtcVideoSendChannel::AddSendStream(sp)          // :1530
  │  为每个 SSRC 创建 WebRtcVideoSendStream
  │  → new WebRtcVideoSendStream(...)                        // :1565
  │
  ▼
【5】WebRtcVideoSendStream 内部：call_->CreateVideoSendStream(config)  // :2704
  │  进入 call 层，创建真正的 VideoSendStream
  ▼
【6】call/call.cc:920  Call::CreateVideoSendStream
  │  → new VideoSendStreamImpl(...)                           // :941
  │    → video/video_send_stream_impl.cc:385（编码器 + RtpVideoSender）
  ▼
【7】video/video_send_stream_impl.cc:385  VideoSendStreamImpl 构造函数
  │  video_stream_encoder_ = CreateVideoStreamEncoder(...)   // :408 → video/video_stream_encoder.cc
  │  rtp_video_sender_ = transport->CreateRtpVideoSender()   // :429 → call/rtp_video_sender.cc
  │  → 流真正持有编码器 + 发送器
```

 1. 初始化链路（线一）补上了 JNI 最上层：
  【0】JNI 层：JNI_PeerConnection_SetRemoteDescription   // sdk/android/src/jni/pc/peer_connection.cc:655
    → PeerConnection::SetRemoteDescription               // pc/peer_connection.cc:1550
    → sdp_handler_->SetRemoteDescription                 // :1558
    → SdpOfferAnswerHandler::CreateChannels              // sdp_offer_answer.cc:5548
    → RtpTransceiver::CreateChannel                      // rtp_transceiver.cc:204
    → WebRtcVideoEngine::CreateSendChannel               // webrtc_video_engine.cc:827
    → AddSendStream → new WebRtcVideoSendStream          // :1530, :1565
    → Call::CreateVideoSendStream                        // call/call.cc:920
    → VideoSendStreamImpl 构造函数                       // video/video_send_stream_impl.cc:385
  最上层确认是 JNI（Java 调 SetRemoteDescription），不是 sdp_offer_answer.cc。


**要点**：初始化链路是**从 JNI → SDP → 通道 → 流**的"装配过程"。最上层是 **JNI 层**（Java 调 `SetRemoteDescription`），往下到 `PeerConnection`、`SdpOfferAnswerHandler`、`RtpTransceiver`，最后到 `media/engine` 装配通道、`call/` 创建流。关键是 `RtpTransceiver::CreateChannel` 里 `BlockingCall` 切到 **worker 线程**——通道创建必须在 worker 线程上做（呼应三线程模型）。

---

#### 线二：流处理链路（数据怎么流动）—— 采集/解码 → 引擎 → call → modules → 传输

**视频上行（采集→发送）**—— 精确到文件/类/函数：

```
【采集】Camera → VideoSource(api/video) → VideoTrack(pc/)
  │  VideoTrack 通过 SetSource 把 source 接到发送通道
  ▼
【引擎】WebRtcVideoSendStream::SetVideoSend(...)           // media/engine/webrtc_video_engine.cc:1884
  │  → stream_->SetSource(source_)                          // :1911（函数内调用，非 SetSource 函数）
  │  source → WebRtcVideoSendStream
  ▼
【引擎】RecreateWebRtcStream()                             // media/engine/webrtc_video_engine.cc:2666
  │  → stream_->SetSource(source_, GetDegradationPreference())  // :2725（函数内调用）
  ▼
【call 层】Call::CreateVideoSendStream(config)             // call/call.cc:920
  │  → new VideoSendStreamImpl(...)                        // call/call.cc:941
  ▼
【call 层】VideoSendStreamImpl 构造函数                    // video/video_send_stream_impl.cc:385
  │  video_stream_encoder_ = CreateVideoStreamEncoder(...) // :408 → video/video_stream_encoder.cc
  │  rtp_video_sender_ = transport->CreateRtpVideoSender() // :429 → call/rtp_video_sender.cc
  ▼
【编码】VideoStreamEncoder::Encode(frame)                 // video/video_stream_encoder.cc
  │  → VideoEncoder::Encode（硬件 MediaCodec 或软件，H264/VP8/VP9/AV1）
  │  → 产出 EncodedImage，回调 OnEncodedImage
  ▼
【打包】RtpVideoSender::OnEncodedImage(image)             // call/rtp_video_sender.cc:550
  │  → rtp_streams_[i].sender_video（RTPSenderVideo）打包  // modules/rtp_rtcp/source/rtp_sender_video.cc
  │    → RtpPacketizer（rtp_format.cc）分包
  │  → rtp_sender_->EnqueuePackets(packets)                // rtp_sender_video.cc:243
  ▼
【节流】RTPSender::EnqueuePackets                          // modules/rtp_rtcp/source/rtp_sender.cc:489
  │  → paced_sender_->EnqueuePackets                       // :502
  │    → TaskQueuePacedSender（modules/pacing/task_queue_paced_sender.cc）
  │      → PacingController（modules/pacing/pacing_controller.cc，节流算法）
  ▼
【拥塞+发送】RtpTransportControllerSend（实现 RtpPacketSender）// call/rtp_transport_controller_send.cc
  │  packet_sender() = &pacer_                              // :260
  │  拥塞控制 GCC 调码率（GoogCcNetworkController）
  │  → SendPacket → RtpTransport::SendRtpPacket             // pc/rtp_transport.cc:155
  ▼
【加密】SrtpTransport / DtlsSrtpTransport（DTLS-SRTP 加密）  // pc/srtp_transport.cc
  ▼
【网络】PacketTransportInternal::SendPacket → 网络发送

```
**视频上行——泳道缩进版（2026-09-08 补充，体现分层 + 穿梭点）**：

```
【采集/轨道】sdk/android + pc/
        Camera → VideoSource(api/video) → VideoTrack(pc/)
                     │ VideoTrack::SetSource 把 source 接到发送通道
                     ▼
【媒体引擎】media/engine
        WebRtcVideoSendStream::SetVideoSend(...)            // webrtc_video_engine.cc:1884
          → stream_->SetSource(source_)                      // :1911（函数内调用）
        RecreateWebRtcStream()                               // webrtc_video_engine.cc:2666
          → stream_->SetSource(source_, GetDegradationPreference())  // :2725（函数内调用）
                     ▼
【媒体调用】call/
        Call::CreateVideoSendStream(config)                 // call/call.cc:920
          → new VideoSendStreamImpl(...)                    // :941
                     ▼
【媒体流实现】video/
        VideoSendStreamImpl 构造函数                        // video_send_stream_impl.cc:385
          ├ video_stream_encoder_ = CreateVideoStreamEncoder(:408) → VideoStreamEncoder
          └ rtp_video_sender_     = CreateRtpVideoSender(:429)     → RtpVideoSender
                     ▼
        VideoStreamEncoder::Encode(frame)                   // video_stream_encoder.cc
          → VideoEncoder::Encode（MediaCodec 硬件 / 软件）→ OnEncodedImage
                     │ EncodedImage 回调
                     ▼
【媒体调用】call/  ← 数据流从 video 回到 call（穿梭①）
        RtpVideoSender::OnEncodedImage(image)               // rtp_video_sender.cc:550
                     ▼
【媒体模块】modules/
        RTPSenderVideo 打包（RtpPacketizer 分包）            // rtp_sender_video.cc
          → RTPSender::EnqueuePackets                       // rtp_sender.cc:489
            → PacingController 节流                          // pacing_controller.cc
                     ▼
【媒体调用】call/  ← 数据流从 modules 回到 call（穿梭②）
        RtpTransportControllerSend（实现 RtpPacketSender，拥塞 GCC 调码率）
                     │ packet_sender() = &pacer_            // rtp_transport_controller_send.cc:260
                     ▼
【加密】pc/
        SrtpTransport / DtlsSrtpTransport（DTLS-SRTP 加密）  // pc/srtp_transport.cc
                     ▼
【网络】p2p/ + rtc_base/
        PacketTransportInternal::SendPacket → 网络发送
```

**泳道缩进版说明**：
- **缩进越深 = 层越底层**：采集 → 引擎 → call → video → modules → 加密 → 网络
- **穿梭点**：视频上行**不是严格单向**。`RtpVideoSender`（call）调 `RTPSenderVideo`（modules）打包，又回到 `RtpTransportControllerSend`（call）拥塞——数据流在 call 和 modules 之间**穿梭**（呼应十一节"数据流在 call 和 modules 之间穿梭"）
- 与上方平铺版内容一致，仅增加分层缩进与穿梭标注，便于一眼看出"每步在哪层"




  一张图看清"进"和"出"

    【进 buffer】                    【出 buffer】
    VideoReceiveStream2::            VideoStreamBufferController::
      OnCompleteFrame (:753)           FrameReadyForDecode (:293)  ← 调度到点
        → buffer_->InsertFrame           → ExtractNextDecodableTemporalUnit
          → VSBC::InsertFrame              → OnFrameReady (:208)
            → FrameBuffer::InsertFrame       → receiver_->OnEncodedFrame (:276)
              （排队/重排序/等关键帧）            ↓
                                          VideoReceiveStream2::OnEncodedFrame (:815)
                                            → OnPreDecode (:832)
                                            → decode_queue_->PostTask (:834)
                                              → HandleEncodedFrameOnDecodeQueue (:841)
                                                → video_stream_decoder_ → VideoDecoder

  - 左边（进） = 帧存进去排队，方法名 InsertFrame
  - 右边（出） = 帧取出来去解码，方法名 OnEncodedFrame

  你贴的 OnPreDecode + decode_queue_->PostTask 在最右边（出 buffer 之后、真正解码之前）。文档写的 FrameBuffer::InsertFrame
  在最左边（进 buffer）。中间隔了整个 VideoStreamBufferController 的抖动缓冲 + 定时调度逻辑，所以它们不是同一个东西。

  一句话：OnPreDecode/PostTask 是"缓冲完了去解码"；InsertFrame 是"把帧放进缓冲"。你贴的是下游，文档写的是上游，方向相反。



  2. 流处理链路（线二）的视频上行/下行，全部精确到文件/行号： 【大概率是错的】
  - 上行：
  SetSource 
  → Call::CreateVideoSendStream 
  → VideoSendStreamImpl（创建 VideoStreamEncoder + RtpVideoSender）
  → VideoStreamEncoder::Encode 
  → RtpVideoSender::OnEncodedImage 
  → RTPSenderVideo 打包（RtpPacketizer）
  → RTPSender::EnqueuePackets 
  → TaskQueuePacedSender/PacingController 
  → RtpTransportControllerSend（拥塞）
  → RtpTransport::SendRtpPacket 
  → SrtpTransport 加密

  - 下行：
  RtpTransport::OnReadPacket 
  → RtpDemuxer::OnRtpPacket 
  → RtpVideoStreamReceiver2 
  → VideoReceiveStream2::OnEncodedFrame 
  → VideoStreamBufferController/FrameBuffer（jitter,buffer）
  → VideoStreamDecoder 
  → VideoReceiver2::Decode 
  → WebRtcVideoReceiveChannel::OnFrame 
  → 渲染


**视频下行（接收→渲染）**—— 精确到文件/类/函数：

```
【网络】RTP 包到达 → PacketTransportInternal::OnReadPacket
  ▼
【解密】RtpTransport::OnReadPacket                         // pc/rtp_transport.cc:86
  │  → DemuxPacket(packet)                                 // :215
  │  → rtp_demuxer_.OnRtpPacket(parsed_packet)             // :229
  ▼
【分发】RtpDemuxer::OnRtpPacket(packet)                    // call/rtp_demuxer.cc:295
  │  → sink->OnRtpPacket(packet)                           // :298
  │    → sink = ResolveSink(packet) 按 SSRC/MID 解析出的接收器
  │       = VideoReceiveStream2 的成员 rtp_video_stream_receiver_
  │         （RtpVideoStreamReceiver2，实现 RtpPacketSinkInterface，经 AddSink 注册）
  ▼
【接收/组帧】RtpVideoStreamReceiver2（实现 RtpPacketSinkInterface）// video/rtp_video_stream_receiver2.h
  │  OnRtpPacket(:759) → ReceivePacket(:765) → OnReceivedPayloadData(:546)
  │  [OnReceivedPayloadData 内部 :546-735 先做 codec 特定处理：
  │   H264 的 SPS/PPS tracker 修补 payload、绝对捕获时间外插等]
  │  → packet_buffer_.InsertPacket(:742)      // PacketBuffer 拼包（H26x 走 h26x_packet_buffer_ 分支 :740）
  │     ├ 组帧成功：PacketBuffer 经 assembled_frame_callback_ 内嵌回调
  │     │   → OnAssembledFrame(RtpFrameObject)(:916)   // 拼成 EncodedFrame ← 先发生
  │     │     → reference_finder_->ManageFrame(:979)   // 帧间引用重排序（codec 变更先 reset :957）
  │     │     → OnCompleteFrames(:983)
  │     │       → complete_frame_callback_->OnCompleteFrame(:991)  // 回调出去
  │     └ InsertPacket 返回值 → OnInsertedPacket(:812) ← 后发生（处理缺口/清理旧包）
  │     ⚠️ OnAssembledFrame 与 OnInsertedPacket 不是串行三步：前者是 InsertPacket
  │     内部组帧成功时的内嵌回调，后者处理返回值，方向是"一调用+一内嵌回调"
  ▼
【进 jitter buffer】VideoReceiveStream2::OnCompleteFrame(frame)  // video/video_receive_stream2.cc:753（回调入口）
  │  → buffer_->InsertFrame(:763)                          // 真正进抖动缓冲
  │    → VideoStreamBufferController::InsertFrame          // video/video_stream_buffer_controller.cc:156
  │      → FrameBuffer::InsertFrame（抖动缓冲:排队/重排序/等关键帧）// :161
  │      → (172:)MaybeScheduleFrameForRelease(:392)        // 决定何时解码
  │        → (:424)frame_decode_scheduler_->ScheduleFrame  // 定时调度解码
  │        → TaskQueueFrameDecodeScheduler::ScheduleFrame()(:42) // TaskQueueFrameDecodeScheduler.cc
  │            // 排的延迟任务绑 worker 线程（bookkeeping_queue_=call_->worker_thread()，:294）
  │            // 调度器从初始化→投递→运行→pop 的完整链路见下方「视频解码调度器+线程」独立图
  ▼
【出 jitter buffer → 解码】调度到点 → FrameReadyForDecode(:293)
  │  → ExtractNextDecodableTemporalUnit(:311)  // 取出可解码帧
  │    → OnFrameReady(:208) → receiver_->OnEncodedFrame(:276)
  │      → VideoReceiveStream2::OnEncodedFrame   // video/video_receive_stream2.cc:815（出口）
  │        → OnPreDecode(:832) 记统计
  │        → decode_queue_->PostTask(:834)       // 投到解码队列(HIGH 优先级，:272)
  │          → HandleEncodedFrameOnDecodeQueue(:841)  // 真正解码
  ▼
【解码】VideoStreamDecoder（连接 buffer 和 decoder）        // video/video_stream_decoder2.h
  │  → VideoReceiver2::Decode                               // modules/video_coding/video_receiver2.h:54
  │    → VideoDecoder（硬件 MediaCodec 或软件）
  │  → OnFrameToRender（VCMReceiveCallback）                // video/video_stream_decoder2.h:37
  ▼
【引擎】WebRtcVideoReceiveChannel::OnFrame(frame)           // media/engine/webrtc_video_engine.cc:3770
  │  解码后的帧进入接收通道
  ▼
【渲染】sink_->OnFrame(frame) → SurfaceViewRenderer/TextureViewRenderer
```

**视频下行链路澄清（2026-09-08 补充，修正原"jitter buffer"一段）**：

**① "组帧"和"jitter buffer"是两个不同阶段，别混在一起：**
- **组帧**（在 `RtpVideoStreamReceiver2` 里）= 把 RTP **包**拼成完整**帧**。工具是 `PacketBuffer`（拼包）+ `RtpFrameReferenceFinder`（帧间引用重排序）。这**不是**抖动缓冲。
- **jitter buffer**（在 `VideoStreamBufferController` 里）= 把完整**帧**排队、重排序、等关键帧、决定解码时机。核心是 `FrameBuffer`。

**② 入口方法名是 `OnCompleteFrame`，不是 `OnEncodedFrame`：**
- `RtpVideoStreamReceiver2` 的 `complete_frame_callback_` 指向 `VideoReceiveStream2` 自己（`video_receive_stream2.cc:259` 传 `this`）。
- 所以进 jitter buffer 的入口是 **`VideoReceiveStream2::OnCompleteFrame`（:753）** → `buffer_->InsertFrame`。
- `VideoReceiveStream2::OnEncodedFrame`（:815）是**出口**（缓冲完、去解码），和入口方向相反。原文档把两者搞混了。
- `VideoStreamBufferController` 里**没有** `OnEncodedFrame` 方法，进 buffer 的方法是 `InsertFrame`。

**③ 一进一出，方向相反：**
```
进 buffer（存进去排队）:  OnCompleteFrame(:753) → InsertFrame → FrameBuffer::InsertFrame
出 buffer（取出来解码）:  FrameReadyForDecode(:293) → OnFrameReady(:208) → OnEncodedFrame(:815) → decode_queue_ → 解码
```

**④ 组帧 + jitter buffer 分阶段精讲（2026-09-08 下午补充，比上面链路更明了的浓缩版）**

把视频下行拆成两个阶段、标出**三个异步边界**——每一处边界就是一次线程/时序交接，这正是 VSBC 重构的意义：

```
【阶段 A：组帧】—— RtpVideoStreamReceiver2（网络线程/包序列）
RtpTransport::OnReadPacket                       (pc/rtp_transport.cc:86)
  → RtpDemuxer::OnRtpPacket                       (call/rtp_demuxer.cc:295)
  → RtpVideoStreamReceiver2::OnRtpPacket          (video/rtp_video_stream_receiver2.cc:759)
    → ReceivePacket                               (:765)
      → OnReceivedPayloadData                     (:546)
          [中间 ~200 行是 codec 特定处理：H264 SPS/PPS tracker、payload 修补等]
        → packet_buffer_.InsertPacket(packet)     (:742)   ← H26x 有分支走 h26x_packet_buffer_(:740)
            │  PacketBuffer 内部：按序列号拼包
            ├── 组帧成功：assembled_frame_callback_ 回调
            │     → OnAssembledFrame(RtpFrameObject)        (:916)  ← 在 InsertPacket 内部先发生
            │         → reference_finder_->ManageFrame      (:979)  [codec 变更时先 reset reference_finder_(:957)]
            │         → OnCompleteFrames                    (:983)
            │             → complete_frame_callback_->OnCompleteFrame (:991)
            └── InsertPacket 返回值 → OnInsertedPacket       (:812)  ← 后发生（处理缺口/清理）
            ⚠️ 注意这两条不是串行：OnAssembledFrame 是 InsertPacket 的内嵌回调（先），
               OnInsertedPacket 处理返回值（后），"一个调用+一条内嵌回调"

【阶段 B：jitter buffer】—— VideoReceiveStream2（入口在网络/包序列，之后转 worker）
complete_frame_callback_ = VideoReceiveStream2 自己（构造时 :259 传 this）

VideoReceiveStream2::OnCompleteFrame(frame)       (video/video_receive_stream2.cc:753)  ← 进 buffer 入口
  [先处理帧携带的 PlayoutDelay(:755-761)]
  → buffer_->InsertFrame(frame)                   (:763)
    → VideoStreamBufferController::InsertFrame    (video/video_stream_buffer_controller.cc:156)
      → FrameBuffer::InsertFrame                  (:161)   ← 帧入队/重排序
      [仅当出现新的连续 temporal unit 时:]
      → MaybeScheduleFrameForRelease()            (:172 调用, :392 定义)
        → frame_decode_scheduler_->ScheduleFrame (:424)
          → PostDelayedHighPrecisionTask(wait)    (task_queue_frame_decode_scheduler.cc:54)
                ══════ 异步边界①：投延迟任务到 worker 线程，当前调用链到此返回 ══════

  [worker 线程定时到点，消息循环 pop 延迟任务]
FrameReadyForDecode(rtp, render_time)             (video/video_stream_buffer_controller.cc:293)
  [先校验帧仍可解码(:295-305)，不可解码直接 return]
  → ExtractNextDecodableTemporalUnit()            (:311)   ← 出 buffer：从 FrameBuffer 取帧
  → OnFrameReady(frames, render_time)             (:319 调用, :208 定义)  ← 合并 temporal unit
    → receiver_->OnEncodedFrame(frame)            (:276)
      → VideoReceiveStream2::OnEncodedFrame       (video_receive_stream2.cc:815)  ← 出口
        → stats_proxy_.OnPreDecode                (:832)
        → decode_queue_->PostTask(...)           (:834)   ← 切独立解码队列
          ══════ 异步边界②：worker → 解码队列 ══════
          → HandleEncodedFrameOnDecodeQueue      (:841 调用, :903 定义)
            → video_stream_decoder_ (VideoStreamDecoder, video_stream_decoder2.h)
              → VideoReceiver2::Decode           (modules/video_coding/video_receiver2.h:54)
                → VideoDecoder（MediaCodec 硬件/软件）→ OnFrameToRender
```

**与「一张图看清进和出」的分工**：那张图是"进/出两栏对照"（看方向）；本图是"全链路时序"（看顺序+异步边界）。两图结合：方向看那张图，顺序和三次线程/时序交接看本图。
**三个异步边界小结**：①进 buffer 后排延迟任务即返回（当前调用链结束，等 worker 到点）②worker 出 buffer 后投解码队列（解码是 CPU 密集，不能占 worker）③解码队列执行真正解码。理解"卡在哪一环"就查对应边界前后的环节。

**音频上行（麦克风→编码→RTP→发送）**—— 精确到文件/类/函数：

```
【采集+前处理】麦克风 → AudioDeviceModule(ADM) 采集 PCM
  │  ADM 采集线程回调 AudioTransportImpl::RecordedDataIsAvailable
  │    // audio/audio_transport_impl.cc:135（AudioTransport 接口实现）
  │  ① RemixAndResample(:177)  // 重采样/重混音到发送采样率
  │  ② ProcessCaptureFrame(:180 → :58)  // APM 前处理，见下方展开
  │  ③ SendProcessedData(:200)  // 分发给所有 AudioSendStream::SendAudioData
  │    （第一路用原件，其余拷贝，audio_transport_impl.cc:194-206）
  ▼
【APM 前处理管线】AudioProcessingImpl::ProcessCaptureStreamLocked
  │  // modules/audio_processing/audio_processing_impl.cc:1272，在 capture_buffer 上原地处理
  │  顺序：① capture_levels_adjuster（麦克风增益模拟/预增益）
  │       ② high_pass_filter（高通滤波，去直流/低频噪声）
  │       ③ echo_controller（AEC3：AnalyzeCapture 分析 → ProcessCapture 消除回声）
  │       ④ noise_suppressor->Process（降噪 NS）
  │       ⑤ agc_manager->Process → gain_control（AGC1 数字增益）
  │       ⑥ gain_controller2->Process（AGC2 后置增益）
  │       ⑦ echo_detector（回声检测，辅助统计）
  │  注意：AEC 是双向的——播放侧 NeedMorePlayData(:218) 里调 ProcessReverseStream
  │  把扬声器信号喂给 APM 作远端参考；采集侧消、播放侧喂参考
  ▼
【引擎】WebRtcVoiceSendChannel::WebRtcAudioSendStream（实现 AudioSource::Sink）
  │  media/engine/webrtc_voice_engine.cc:747
  │  → stream_ = call_->CreateAudioSendStream(config_)   // :803
  ▼
【call 层】Call::CreateAudioSendStream                      // call/call.cc:815
  │  → new AudioSendStream(...)                            // :833
  ▼
【call 层】AudioSendStream 构造函数                         // audio/audio_send_stream.cc:121
  │  channel_send_ = voe::ChannelSendInterface             // audio/channel_send.h
  │  rtp_rtcp_module_ = channel_send_->GetRtpRtcp()
  ▼
【编码】ChannelSend::ProcessAndEncodeAudio
  │  调用 (audio/audio_send_stream.cc:410 SendAudioData) ... 实现 (audio/channel_send.cc:847)
  │  → encoder_queue_->PostTask(:884)  // 投到编码队列（释放 ADM 采集线程）
  │    → audio_coding_->Add10MsData(:918)  // ACM 入队 10ms 数据
  │      → AudioCodingModuleImpl::Add10MsData(:348) → Encode(:226, acm2/audio_coding_module.cc)
  │        → encoder_stack_->Encode(:263)  // AudioEncoder(Opus) 编码
  │        → packetization_callback_->SendData(:304)  // 编完立刻同步回调（见下）
  ▼
【回调交接】ChannelSend::SendData → SendRtpAudio
  │  声明 (:233...:375) ... SendRtpAudio 实现 (:408)  // audio/channel_send.cc
  │  SendData 触发机制（回调注入，非队列）：
  │    ChannelSend::StartSend 时 audio_coding_->RegisterTransportCallback(this)（:542）
  │    → ACM 保存为 packetization_callback_（acm2/audio_coding_module.cc:183）
  │    → ACM Encode 末尾当场回调 ChannelSend::SendData —— 同一次调用链一进一出，
  │      全程在 encoder_queue_ 线程，无队列无异步。ChannelSend 一人分饰两角：
  │      既是 ACM 的"喂数据者"，又是"编码结果接收者"
  │  SendData 内部：FrameEncryptor（E2EE）→ SendRtpAudio(:408) → rtp_sender_audio_->SendAudio(:481)
  ▼
【打包】RTPSenderAudio::SendAudio                           // modules/rtp_rtcp/source/rtp_sender_audio.cc:131
  │  一帧一个包（packets(1)，不分包）                      // :266-267
  │  → rtp_sender_->EnqueuePackets                         // :268
  ▼
【节流】ChannelSend::EnqueuePackets（RtpPacketSenderProxy） // audio/channel_send.cc:342
  │  → rtp_packet_pacer_->EnqueuePackets                   // :354
  │    → TaskQueuePacedSender / PacingController（modules/pacing/）
  ▼
【拥塞+发送】RtpTransportControllerSend（实现 RtpPacketSender） // call/rtp_transport_controller_send.cc
  │  → RtpTransport::SendRtpPacket                          // pc/rtp_transport.cc:155
  ▼
【加密】SrtpTransport / DtlsSrtpTransport（DTLS-SRTP）       // pc/srtp_transport.cc
  ▼
【网络】PacketTransportInternal::SendPacket → 网络发送
```

**线程视角小结（音频上行跨了 3 个线程/队列）**：
- **ADM 采集线程**：采集 → APM 前处理 → SendAudioData → ProcessAndEncodeAudio（只投任务就返回，尽快释放采集线程）
- **encoder_queue_**：Add10MsData → Opus 编码 → SendData 回调 → SendRtpAudio → RTPSenderAudio 打包 → 进 pacer
- **pacer 拥塞队列**：PacingController 节流 → 拥塞控制 → RtpTransport → SRTP 加密 → 网络
- 每个 10ms 帧在线程间都是"投任务+move 所有权"交接（呼应第 21 节"传命令不传数据"）

**音频下行（接收→NetEq→解码→播放）**—— 精确到文件/类/函数：

```
【网络】RTP 包到达 → RtpTransport::OnReadPacket              // pc/rtp_transport.cc:86
  │  → DemuxPacket → rtp_demuxer_.OnRtpPacket                // :215, :229
  ▼
【分发】RtpDemuxer::OnRtpPacket                              // call/rtp_demuxer.cc:295
  │  → sink->OnRtpPacket                                     // :298
  │    → AudioReceiveStream 的 ChannelReceive
  ▼
【接收】ChannelReceive::OnRtpPacket（实现 RtpPacketSinkInterface）// audio/channel_receive.cc:681
  │  解析 → OnReceivedPayloadData                            // :341
  ▼
【抖动缓冲】NetEqImpl::InsertPacket                          // modules/audio_coding/neteq/neteq_impl.cc:184
  │  → packet_buffer_->InsertPacket                          // :367（NetEq 抖动缓冲 + 丢包隐藏 PLC）
  ▼
【解码】NetEqImpl::GetAudio / GetAudioInternal               // neteq_impl.cc:432, :663
  │  → AudioDecoder（Opus）解码
  ▼
【播放】ChannelReceive::GetAudioFrameWithInfo
  │  声明 (audio/channel_receive.cc:195) ... 实现 (:410)
  │  播放端拉模型：ADM 播放线程每 10ms 经 AudioMixer 来拉一次
  │  → AudioMixer 混音 → AudioDeviceModule(ADM) 播放到扬声器
```

#### 音视频链路对比（媒体处理层 vs 传输层）

**结论先行**：音视频在**媒体处理层**（编解码/缓冲/打包）是两套完全不同的实现，但在**传输层**（pacing/拥塞/加密/网络）是同一套。

**媒体处理层对比表**：

| 环节 | 视频 | 音频 |
|---|---|---|
| 采集/播放 | Camera → VideoSource | ADM 采集 / ADM 播放 |
| 编码前处理 | 无 | `AudioProcessing`（AEC/NS/AGC） |
| 编码器 | `VideoStreamEncoder`→`VideoEncoder`（H264/VP8/VP9/AV1） | `AudioCodingModule`→`AudioEncoder`（Opus） |
| RTP 打包 | `RtpPacketizer` **分包**（一帧拆多包） | `RTPSenderAudio` **一帧一包**（不分包） |
| 抖动缓冲 | `VideoStreamBufferController::FrameBuffer`（按帧重组） | **`NetEq`**（`neteq_impl.cc`，含丢包隐藏 PLC） |
| 接收流 | `VideoReceiveStream2` → `RtpVideoStreamReceiver2` | `AudioReceiveStream` → `ChannelReceive` |
| 解码后 | 渲染到 `SurfaceViewRenderer` | ADM 播放到扬声器 |

**传输层共用**（音视频汇入同一条管线）：

| 环节 | 音视频共用 |
|---|---|
| 节流 | `TaskQueuePacedSender` / `PacingController`（modules/pacing/） |
| 拥塞 | `RtpTransportControllerSend`（call/rtp_transport_controller_send.cc） |
| 发送 | `RtpTransport::SendRtpPacket`（pc/rtp_transport.cc:155） |
| 加密 | `SrtpTransport` / `DtlsSrtpTransport`（pc/srtp_transport.cc） |
| 接收分发 | `RtpDemuxer::OnRtpPacket`（call/rtp_demuxer.cc:295） |

**关键差异**：
1. **音频走 `AudioProcessing`**（AEC/NS/AGC），视频没有
2. **音频 RTP 不分包**（一帧一包，`packets(1)`），视频要分包
3. **音频抖动缓冲是 `NetEq`**，不只缓冲还做**丢包隐藏（PLC）**；视频 `FrameBuffer` 不做
4. **最底层（pacing/拥塞/加密/传输/demux）音视频共用**——都汇入 `TaskQueuePacedSender`→`RtpTransportControllerSend`→`RtpTransport`→`SrtpTransport`

**一句话**：**音视频在"媒体处理"（编解码/缓冲/打包）上是两套完全不同的实现，但在"传输"（pacing/拥塞/加密/网络）上是同一套**——它们最后都汇入 `TaskQueuePacedSender`→`RtpTransportControllerSend`→`RtpTransport`→`SrtpTransport` 这条共用管线。

---

#### 两条线的对比

| | 初始化链路（线一） | 流处理链路（线二） |
|---|---|---|
| 触发 | SDP offer/answer | 采集到帧 / 收到 RTP |
| 方向 | 从 SDP 装配通道（上→下） | 数据流动（可上下穿梭） |
| 线程 | worker 线程（BlockingCall） | 各层自己的线程 |
| 关键 | 通道/流对象怎么建 | 帧/包数据怎么走 |
| 对应 | 控制图（骨架） | 数据流图（血液） |

**一句话**：**初始化链路回答"通道怎么建起来"（SDP→通道→流），流处理链路回答"数据怎么走"（采集/解码→引擎→call→modules→传输）**。`media/engine` 是这两条线的交汇点——初始化时它创建通道，流处理时帧从它的 `OnFrame` 入口穿过。

---

#### 视频解码调度器 + 线程（独立调用图，2026-09-08）

**背景**：视频下行主流程里 `MaybeScheduleFrameForRelease → frame_decode_scheduler_->ScheduleFrame` 只是"排了个延迟任务"。这个调度器**跑在 worker 线程**，不是解码队列。下面是它从**初始化 → 投递 → 运行 → pop** 的完整链路，单独画，不塞进视频流主流程。

**约定**：`(调用行:)函数名(定义行)` —— 括号里前一个行号是调用点，后一个行号是定义处。

**① 调度器初始化（谁创建、绑在哪个线程）**

```
【JNI 建线程】sdk/android/src/jni/pc/peer_connection_factory.cc
  worker_thread = Thread::Create()(:289) → SetName("worker_thread") → Start()(:291)
  └ 三线程：network_thread(:285) / worker_thread(:289) / signaling_thread(:293)，都是 rtc_base::Thread
      │ 作为 TaskQueueBase* 注入 PeerConnectionFactory → 传给 CallConfig.worker_thread
      ▼
【Call 持有】call/call.cc  Call::Create(CallConfig config)(:529)
  worker_thread_ = config.worker_thread（TaskQueueBase*）
      ▼
【VideoReceiveStream2 构造】video/video_receive_stream2.cc
  decode_queue_ = CreateTaskQueue("DecodingQueue", Priority::HIGH)(:270)   // 独立解码队列
  scheduler = decode_sync ? DecodeSynchronizer 调度器
                          : new TaskQueueFrameDecodeScheduler(&clock, call_->worker_thread())(:294)
      // bookkeeping_queue_ = worker 线程（关键！调度器绑 worker，不是 decode_queue_）
  buffer_ = new VideoStreamBufferController(&clock, call_->worker_thread(), ..., std::move(scheduler))(:296)
      // VideoStreamBufferController 持有 frame_decode_scheduler_
```

**② 运行时：投递延迟任务（worker 线程上排定时）**

```
【进 jitter buffer 时】VideoStreamBufferController::InsertFrame(video/video_stream_buffer_controller.cc:156)
  → MaybeScheduleFrameForRelease()(:172 调用, :392 定义)
    → frame_decode_scheduler_->ScheduleFrame(rtp, schedule, cb)(:424)
      → TaskQueueFrameDecodeScheduler::ScheduleFrame(video/task_queue_frame_decode_scheduler.cc:42)
        → wait = max(0, latest_decode_time - now)
        → bookkeeping_queue_->PostDelayedHighPrecisionTask(SafeTask(...), wait)(:52)
            // bookkeeping_queue_ = worker 线程
```

**③ 运行时：worker 线程消息循环 pop 并执行（rtc_base/thread.cc）**

```
【worker 线程启动即循环】Thread::Run()(:734) → ProcessMessages(kForever)(:735)
  → Thread::Get(cmsWait)(:413)                       // 消息循环取任务
    → 扫描 delayed_messages_（优先队列，按 run_time_ms 排序）(:429)
    → 到点：messages_.push(top().functor); delayed_messages_.pop()(:435-436)  // 延迟→普通队列
    → 普通队列非空：task = messages_.front(); messages_.pop()(:441-443)       // pop 出来
  → Dispatch(std::move(task))(:543)                  // 执行任务
    → 回调 FrameReadyForDecode(rtp, render_time)      // 到点触发解码
```

**④ 到点后：出 jitter buffer → 切到解码队列**

```
【worker 线程】FrameReadyForDecode(video/video_stream_buffer_controller.cc:293, RTC_DCHECK_RUN_ON worker)
  → ExtractNextDecodableTemporalUnit()(:311)          // 取出可解码帧
  → OnFrameReady(:208) → receiver_->OnEncodedFrame(:276)
    → VideoReceiveStream2::OnEncodedFrame(video/video_receive_stream2.cc:815)
      → decode_queue_->PostTask(...)(:834)            // 切到独立解码队列（HIGH 优先级）
        → HandleEncodedFrameOnDecodeQueue(:841)       // 真正解码（解码队列线程）
```

**核心结论**：
1. **调度器绑 worker 线程**：`TaskQueueFrameDecodeScheduler` 的 `bookkeeping_queue_` = `call_->worker_thread()`（video_receive_stream2.cc:294）。`DecodeSynchronizer` 也绑 worker（decode_synchronizer.cc:112-113）。
2. **投递**：`ScheduleFrame` 用 `PostDelayedHighPrecisionTask` 在 worker 线程排一个延迟任务（task_queue_frame_decode_scheduler.cc:52）。
3. **运行/pop**：worker 线程消息循环 `Thread::Get`（thread.cc:413）扫描 `delayed_messages_` 优先队列，到点 pop 到普通队列再执行（:435-436, :441-443），回调 `FrameReadyForDecode`。
4. **切线程发生在下游**：`FrameReadyForDecode` 到 `OnEncodedFrame` 都在 worker 线程，**只有 `decode_queue_->PostTask`（:834）才切到独立解码队列**。
5. **为什么独立解码队列**：解码是 CPU 密集 + 可能阻塞（硬件/软件编解码），不能占着 worker 线程；HIGH 优先级（:272）保证解码不被饿死。

**与视频下行主流程的关系**：主流程里 `ScheduleFrame(:424)` 是"排好定时"，到点由 worker 线程 pop 执行（本图 ③④）。主流程只画到"排定时"，本图补全"谁在何时执行"。

  ┌────────┬───────────────────────────────────────────┬──────────────────────────────────────────────────────────────────┐
  │        │                   视频                    │                               音频                               │
  ├────────┼───────────────────────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ 模型   │ 推（帧到→排定时→到点解码）                │ 拉（播放端来拉）                                                 │
  ├────────┼───────────────────────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ 触发   │ ScheduleFrame 排一次性延迟任务            │ ADM 播放线程每 10ms 调 NeedMorePlayData                          │
  ├────────┼───────────────────────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ 调度器 │ TaskQueueFrameDecodeScheduler（视频特有） │ 没有独立帧解码调度器                                             │
  ├────────┼───────────────────────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │        │                                           │ NeedMorePlayData(audio_state.cc:215) →                           │
  │ 链路   │ worker 线程 pop → FrameReadyForDecode     │ GetAudioFrameWithInfo(channel_receive.cc:410) →                  │
  │        │                                           │ neteq_->GetAudio(:421) → NetEq 解码                              │
  └────────┴───────────────────────────────────────────┴──────────────────────────────────────────────────────────────────┘


**⚠️ 音频不是这样（拉模型，非推模型）**：
- 视频是**推模型**：帧到达 → `ScheduleFrame` 排**一次性**延迟任务 → 到点触发解码。每帧排一次。
- 音频是**拉模型**：**播放端周期性来拉**，不是帧到达后排定时。ADM 播放线程（真实设备，audio_device_buffer.cc:370）或 `RepeatingTaskHandle`（空设备，audio_state.cc:203）每 **10ms** 调一次 `NeedMorePlayData`（audio_state.cc:215）→ `GetAudioFrameWithInfo`（channel_receive.cc:410）→ `neteq_->GetAudio`（:421）→ NetEq 解码。
- **NetEq 没有独立的帧解码调度器**：它就是个被周期性拉取的缓冲+解码器，内部由 `GetAudio` 驱动决定何时把缓冲的包解码输出。所以**视频那个 `TaskQueueFrameDecodeScheduler` 是视频特有**，音频不适用。

**还有别的定时任务吗**（除视频解码调度外，WebRTC 里常见的周期/延迟任务）：
| 任务 | 机制 | 位置 |
|---|---|---|
| 视频解码调度 | 一次性延迟任务（`PostDelayedHighPrecisionTask`） | task_queue_frame_decode_scheduler.cc:52 |
| 音频播放拉取 | 周期 10ms（ADM 播放线程 / `RepeatingTaskHandle`） | audio_state.cc:203, audio_device_buffer.cc:370 |
| 音频/视频发送节流 | `TaskQueuePacedSender` 周期发送（pacing） | modules/pacing/task_queue_paced_sender.cc |
| 拥塞控制 | `ProcessThread` 周期 `OnProcessInterval`（默认 25ms，kUpdateIntervalMs 定义在 api/transport/goog_cc_factory.cc:52，处理入口 goog_cc_network_control.cc:191） | api/transport/goog_cc_factory.cc:52 |
| NACK 重传定时 | `NackRequester` 周期检查待重传包 | modules/video_coding/nack_requester.cc |
| 统计/心跳 | `ProcessThread` 周期任务（RTP/RTCP、统计上报） | modules/rtp_rtcp/source/rtp_rtcp_impl2.cc |

**一句话**：视频解码调度是"帧到→排一次定时→到点解码"（推）；音频是"播放端每 10ms 来拉一次→NetEq 解码"（拉）。两者都涉及定时，但**触发方向相反**——视频靠 worker 线程的延迟任务，音频靠 ADM 播放线程的周期回调。此外 pacing、拥塞控制、NACK、RTCP 统计等都有各自的周期/延迟任务，各跑各的线程。

---

## 十三、补充澄清：硬件编解码位置 + 三线程 + Track/Stream 区分（2026-09-07）

### 1. 安卓硬件编解码放哪一层？

**在 `sdk/android/` 层，作为"平台适配层"（旁支），不属于 L1-L7 核心分层。**

```
api/video_codecs/  VideoEncoder / VideoDecoder 接口（契约）
        ▲ 实现（implements）
        │
sdk/android/  平台适配层（旁支）
  ├ HardwareVideoEncoder.java  implements VideoEncoder   ← 硬件编码
  ├ AndroidVideoDecoder.java   implements VideoDecoder   ← 硬件解码
  ├ MediaCodecVideoDecoderFactory.java                   ← 解码器工厂
  └ MediaCodecWrapper.java                               ← 封装 Android MediaCodec
        │ 内部调用
        ▼
Android 系统 MediaCodec（android.media.MediaCodec，系统硬件编解码器）
```

- 硬件编解码器**实现 `api/` 的接口**，但代码放 `sdk/android/`（带平台专属逻辑：JNI、MediaCodec）
- `modules/` = **平台无关**软件编解码（libvpx/libaom/openh264）；`sdk/android/` = **平台相关**硬件编解码（MediaCodec）
- 两者**都实现同一个 `api/video_codecs/` 接口**，上层（video/ 流实现）不用区分硬件/软件
- **数据流图落点**：在 `video/ VideoStreamEncoder`（编码）和 `VideoReceiveStream2`（解码）调用编解码器处

### 2. 三线程模型（标注到控制图）

WebRTC 是**三个线程**（信令、工作、网络），不是两个。定义在 `api/peer_connection_interface.h:1442-1444`，管理在 `pc/connection_context.h`，类型是 `rtc_base/thread.h` 的 `Thread`。

```
┌────────────────────────────────────────────────────────────┐
│  信令线程 signaling_thread  →  pc/（会话编排：SDP/ICE/轨道） │
│  工作线程 worker_thread     →  media/+call/+video/+audio/    │
│                              （媒体：编解码/轨道/音频状态）   │
│  网络线程 network_thread    →  p2p/+net/+rtc_base/network    │
│                              （收发：ICE/DTLS/SRTP/socket）  │
└────────────────────────────────────────────────────────────┘

这三个线程是 CreatePeerConnectionFactory() 的入口参数：
CreatePeerConnectionFactory(
    Thread* network_thread,     // 网络线程
    Thread* worker_thread,      // 工作线程
    Thread* signaling_thread,   // 信令线程
    ...);
```

**为什么三个线程？** 三件事互不阻塞：
- 信令线程慢（SDP 协商、网络请求），不能阻塞媒体
- 工作线程处理媒体（编解码），不能阻塞网络收发
- 网络线程收发数据（高频），必须独立

### 3. Track/Stream 区分：pc/ 里的 track 文件是正常的

**你观察到 `pc/` 里有 `video_track.cc`、`jitter_buffer_delay.cc` 等，这是正常的，分层没有被破坏。** 关键区分：

| pc/ 文件 | 实际是什么 | 属于哪层 |
|---|---|---|
| `video_track.cc` | `VideoTrack`，实现 `api/` 的 `VideoTrackInterface` | **pc/ 编排层**（轨道对象） |
| `audio_track.cc` | `AudioTrack`，实现 `AudioTrackInterface` | **pc/ 编排层** |
| `video_rtp_receiver.cc` | `VideoRtpReceiver`，实现 `RtpReceiverInternal` | **pc/ 编排层** |
| `jitter_buffer_delay.cc` | `JitterBufferDelay`，**配置类**（非抖动缓冲算法） | **pc/ 编排层** |
| `media_stream.cc` | `MediaStream`，实现 `MediaStreamInterface` | **pc/ 编排层** |

**Track（轨道）vs Stream（流）是两个概念**：
- **Track** = 一个媒体轨道（一路视频），**应用可见**的抽象（LiveKit 操作的是 Track）
- **Stream** = 一条 RTP 收发流，**引擎内部**实现（带 SSRC、编解码、拥塞）

**代码证据**：`VideoRtpReceiver`（pc/）持有的是 `media/` 层通道，不直接持有 `video/` 层流：
```cpp
// pc/video_rtp_receiver.h
VideoMediaReceiveChannelInterface* media_channel_;  // ← media/ 层的通道
```

**真实衔接**（分层没有被破坏）：
```
pc/  VideoTrack（轨道对象，应用可见）
  │ 通过 media/ 通道
  ▼
media/  VideoMediaReceiveChannelInterface（通道）
  │
  ▼
video/  VideoReceiveStream2（流实现）
  │
  ▼
modules/  video_coding/（jitter buffer 算法）
```

**结论**：`pc/` 里的 video_track、jitter_buffer_delay 是**轨道对象和配置类**，不是流实现。真正的抖动缓冲算法在 `modules/video_coding/`。分层关系**成立**，补充"Track 在 pc/，Stream 在 video/"这个区分即可。

---

## 十四、三线程模型详解 + pc/ 目录明细（2026-09-07 补充）

### 1. 三线程模型（已标注到图 A 控制图）

| 线程 | 英文 | 管什么 | 对应目录 | 线程特性 |
|---|---|---|---|---|
| **信令线程** | `signaling_thread` | SDP offer/answer、ICE candidate、轨道增删 | `pc/` | 慢，网络请求多，不能阻塞媒体 |
| **工作线程** | `worker_thread` | 媒体处理：编解码、轨道、音频状态 | `media/`、`call/`、`video/`、`audio/` | 中，处理媒体，不能阻塞网络 |
| **网络线程** | `network_thread` | 网络收发：ICE、DTLS、SRTP、socket | `p2p/`、`net/`、`rtc_base/network` | 快，高频收发，必须独立 |

**为什么三个线程？** 三件事互不阻塞：
- 信令线程慢（SDP 协商、网络请求），不能阻塞媒体
- 工作线程处理媒体（编解码），不能阻塞网络收发
- 网络线程收发数据（高频），必须独立

### 2. 三线程的代码定义与管理

**定义位置**：`api/peer_connection_interface.h:1442-1444`
```cpp
// PeerConnectionFactoryInterface::RTCConfiguration
Thread* network_thread = nullptr;    // 网络线程
Thread* worker_thread = nullptr;     // 工作线程
Thread* signaling_thread = nullptr;  // 信令线程
```

**管理位置**：`pc/connection_context.h`（`ConnectionContext` 类）
```cpp
class ConnectionContext {
  Thread* signaling_thread();                  // 访问器
  Thread* worker_thread();                     // 访问器（owned）
  Thread* network_thread();                    // 访问器
  std::unique_ptr<Thread> owned_network_thread_...  // 持有/管理
};
```

**传入位置**：`CreatePeerConnectionFactory()` 的入口参数
```cpp
CreatePeerConnectionFactory(
    Thread* network_thread,     // 网络线程
    Thread* worker_thread,      // 工作线程
    Thread* signaling_thread,   // 信令线程
    ...);
```

  新增"三线程模型详解 + pc/ 目录明细"：

  - 三线程表格：信令/工作/网络，各管什么、对应目录、线程特性
  - 代码定义与管理：
    - 定义：api/peer_connection_interface.h:1442-1444
    - 管理：pc/connection_context.h（ConnectionContext）
    - 传入：CreatePeerConnectionFactory() 参数
    - 线程安全：SequenceChecker + RTC_DCHECK_RUN_ON(...)
  - pc/ 目录明细：
    - 轨道对象表格（VideoTrack、AudioTrack、VideoRtpReceiver 等，实现 api/ 接口）
    - 会话编排文件表格（peer_connection.cc、jsep_transport_controller.cc 等）
    - Track/Stream/算法 三者区分



**线程安全机制**：`SequenceChecker`（`api/sequence_checker.h`）断言代码在指定线程执行。代码里常见 `RTC_DCHECK_RUN_ON(signaling_thread())`、`RTC_DCHECK_RUN_ON(worker_thread())` 等，保证每个对象只在它所属的线程被访问。

### 3. pc/ 目录明细（轨道对象 vs 流实现）

**pc/ 里的"轨道对象"**（实现 api/ 接口，属编排层，不是流实现）：

| pc/ 文件 | 类 | 实现接口 | 作用 |
|---|---|---|---|
| `video_track.cc` | `VideoTrack` | `VideoTrackInterface` | 视频轨道对象（应用可见） |
| `audio_track.cc` | `AudioTrack` | `AudioTrackInterface` | 音频轨道对象 |
| `video_rtp_receiver.cc` | `VideoRtpReceiver` | `RtpReceiverInternal` | 视频接收端（持有 media/ 通道） |
| `audio_rtp_receiver.cc` | `AudioRtpReceiver` | `RtpReceiverInternal` | 音频接收端 |
| `video_rtp_track_source.cc` | `VideoRtpTrackSource` | `VideoTrackSourceInterface` | 远程视频源 |
| `video_track_source.cc` | `VideoTrackSource` | `VideoTrackSourceInterface` | 本地视频源 |
| `media_stream.cc` | `MediaStream` | `MediaStreamInterface` | 媒体流（一组轨道） |
| `jitter_buffer_delay.cc` | `JitterBufferDelay` | —（配置类） | 抖动缓冲延迟配置（非算法） |
| `track_media_info_map.cc` | `TrackMediaInfoMap` | — | 轨道↔媒体信息映射 |

**pc/ 里的"会话编排"文件**（核心逻辑）：

| pc/ 文件 | 作用 |
|---|---|
| `peer_connection.cc` | PeerConnection 核心实现 |
| `peer_connection_factory.cc` | 工厂（创建引擎） |
| `jsep_transport_controller.cc` | JSEP 传输控制（合并 ICE+DTLS） |
| `webrtc_session_description_factory.cc` | SDP offer/answer 生成 |
| `dtls_srtp_transport.cc` | DTLS-SRTP 加密传输 |
| `sctp_data_channel.cc` | 数据通道（SCTP） |
| `channel.cc` | 媒体通道基类 |
| `codec_vendor.cc` | 编解码器管理 |

**关键区分**：
- **Track（轨道）** = 应用可见的媒体轨道，在 `pc/`（如 `VideoTrack`）
- **Stream（流）** = 引擎内部的 RTP 收发流，在 `video/`（如 `VideoSendStreamImpl`）
- **算法（Algorithm）** = 真正的处理逻辑，在 `modules/`（如 jitter buffer）
- 三者通过 `media/` 的通道（`VideoMediaReceiveChannelInterface`）衔接

---

## 十五、QoS 分布 + 线程运行机制（2026-09-07 补充）

### 1. QoS 在哪一层？

**QoS 不是单一模块，而是一组机制，分散在 `modules/` 层，但被 `call/` 层编排决策。**

| QoS 机制 | 作用 | 实现位置 |
|---|---|---|
| **NACK**（重传） | 丢包后请求重传 | `modules/video_coding/nack_requester.cc`（接收端） |
| **FEC**（前向纠错） | 冗余包，丢包可自恢复 | `modules/rtp_rtcp/source/forward_error_correction.cc`、`ulpfec_receiver.cc`、`flexfec_*` |
| **RTCP 反馈** | NACK/PLI/FIR/REMB 的载体 | `modules/rtp_rtcp/source/rtcp_sender.cc`、`rtcp_receiver.cc` |
| **Pacing**（发送节流） | 平滑发送，避免突发 | `modules/pacing/pacing_controller.cc` |
| **拥塞控制**（GCC） | 动态码率调整 | `modules/congestion_controller/goog_cc/` |
| **jitter buffer**（抖动缓冲） | 抗抖动、重排序 | `modules/video_coding/`、`modules/audio_coding/neteq/` |

**分层位置**：
```
call/（编排者）—— 决定"要不要 NACK、FEC 加多少、码率调多少"
  │ 调用
  ▼
modules/（执行者）—— 真正执行 QoS 算法
  ├ rtp_rtcp/（NACK/FEC/RTCP 反馈）
  ├ video_coding/nack_requester（重传请求）
  ├ pacing/（发送节流）
  └ congestion_controller/（码率控制）
```

**关键**：
- **QoS 算法在 `modules/`**（NACK、FEC、pacing、拥塞都在这）
- **QoS 决策在 `call/`**（`rtp_transport_controller_send` 编排拥塞、`rtp_video_sender` 编排发送）
- **RTCP 是 QoS 的"反馈通道"**：接收端通过 RTCP 把 NACK/丢包信息发回发送端

**所以 QoS 横跨 call/（决策）和 modules/（执行）两层，不是单一层。**

### 2. 线程运行机制（while 循环，不是线程池）

**WebRTC 用的是"每个线程一个 while 循环 + 消息队列"，不是线程池。** 三个线程（信令/工作/网络）是三个独立的 OS 线程（pthread 创建），各自跑自己的 while 循环。

**核心代码**（`rtc_base/thread.cc`）：
```cpp
// 每个 Thread 的主循环
void Thread::Run() {
  ProcessMessages(kForever);   // 永远处理消息
}

bool Thread::ProcessMessages(int cmsLoop) {
  while (true) {
    absl::AnyInvocable<void() &&> task = Get(cmsNext);  // 从消息队列取任务
    if (!task) return !IsQuitting();
    Dispatch(std::move(task));  // 执行任务
  }
}
```

**任务如何投递**（跨线程）：
```cpp
// PostTaskImpl：把任务加到目标线程的消息队列
void Thread::PostTaskImpl(absl::AnyInvocable<void() &&> task, ...) {
  MutexLock lock(&mutex_);
  messages_.push(std::move(task));  // 加入队列
  WakeUpSocketServer();              // 唤醒线程
}
```

**任务如何取出**（`Get()`）：
```cpp
absl::AnyInvocable<void() &&> Thread::Get(int cmsWait) {
  while (true) {
    // 检查 delayed_messages_（定时任务），到期则移入 messages_
    // 从 messages_ 队列取一个任务
    if (!messages_.empty()) {
      task = std::move(messages_.front());
      messages_.pop();
      return task;  // 返回任务给 ProcessMessages 执行
    }
    // 队列空则阻塞等待（SocketServer::Wait 多路复用）
    ss_->Wait(cmsNext, /*process_io=*/true);
  }
}
```

**完整机制**：
```
【任务投递】线程 A 想在线程 B 上运行任务：
  B->PostTask(functor)  →  加入 B 的 messages_ 队列
                            → WakeUpSocketServer() 唤醒 B

【任务执行】线程 B 的主循环：
  Thread::Run() → ProcessMessages(kForever)
    → while(true):
        task = Get()   // 从 messages_ 取任务；空则 Wait() 阻塞
        Dispatch(task) // 执行任务
```

**关键点**：
1. **不是线程池**：三个线程是三个独立 OS 线程，各自跑 while 循环
2. **消息队列 + 互斥锁**：每线程有自己的 `messages_` 队列，用 `MutexLock` 保护；跨线程投递就是往对方队列 push
3. **SocketServer 多路复用**：队列空时 `ss_->Wait()` 阻塞等待，同时处理网络 socket 事件（网络线程能同时处理 socket 和消息）
4. **`PostTask` / `PostDelayedTask`**：投递任务的两种方式，后者带延迟（定时任务）
5. **`BlockingCall`**：同步调用——A 往 B 投任务，然后等待 B 完成（用 `Event` 阻塞）

**三个线程各自跑什么**：
```
信令线程：  while循环 处理 SDP/ICE/轨道 消息
工作线程：  while循环 处理 媒体/编解码/轨道 消息
网络线程：  while循环 处理 socket 收发 + 消息
```

**线程安全机制**：`SequenceChecker`（`api/sequence_checker.h`）配合 `RTC_DCHECK_RUN_ON(thread)` 断言代码在指定线程执行，保证每个对象只在它所属的线程被访问。

### 3. QoS 精确到文件/类/函数（结合媒体流链路）

**QoS 不是单一模块，而是**一组机制**，分散在 `modules/`（执行）+ `call/`/`video/`/`audio/`（编排决策）。以下把每个 QoS 机制追到具体代码位置。

#### 3.1 视频下行 QoS：NACK + FEC（接收端检测丢包 → 请求重传/自恢复）

```
【接收】RtpVideoStreamReceiver2::OnRtpPacket(packet)   // video/rtp_video_stream_receiver2.cc:759
  │  实现 RtpPacketSinkInterface，接收 RTP 包
  ▼
【检测丢包】nack_module_->OnReceivedPacket(...)        // :1199
  │  NackRequester（modules/video_coding/nack_requester.h）
  │  检测序列号空洞 → 判定丢包
  ▼
【发 NACK】RtpVideoStreamReceiver2::SendNack(seq_nums) // :791
  │  → rtp_rtcp_->SendNack(sequence_numbers)           // :794
  │    → ModuleRtpRtcpImpl2（modules/rtp_rtcp/source/rtp_rtcp_impl2.cc）
  │    → RTCP 反馈包发回发送端
  │
  ├─【FEC 自恢复】ulpfec_receiver_（UlpfecReceiver，modules/rtp_rtcp/source/ulpfec_receiver.h）
  │    → OnRecoveredPacket（video/rtp_video_stream_receiver2.cc:747）
  │    → 用冗余包恢复丢失的包（无需重传）
```

#### 3.2 视频上行 QoS：NACK 重传 + FEC 冗余 + 拥塞调码率（发送端）

```
【收 NACK】ModuleRtpRtcpImpl2::OnReceivedNack(seq_nums, rtt)  // modules/rtp_rtcp/source/rtp_rtcp_impl2.cc:693
  │  → rtp_sender_->packet_generator.OnReceivedNack(...)      // :708
  ▼
【重传】RTPSender 重传（modules/rtp_rtcp/source/rtp_sender.cc）
  │  用 RTX（SetRtxSendStatus，call/rtp_video_sender.cc:761）
  │  retransmission_rate_limiter_ 限速（rtp_sender.cc:290，防重传风暴）
  │
  ├─【FEC 冗余】FlexfecSender（modules/rtp_rtcp/include/flexfec_sender.h）
  │    FecController 决定加多少冗余（call/rtp_video_sender.cc:59）
  │
  └─【拥塞调码率】RtpTransportControllerSend（call/rtp_transport_controller_send.cc）
       │  PostUpdates(controller_->OnTransportPacketsFeedback(feedback))  // :764
       │  PostUpdates(controller_->OnProcessInterval(msg))                // :872
       ▼
     GoogCcNetworkController（modules/congestion_controller/goog_cc/goog_cc_network_control.cc）
       │  OnTransportPacketsFeedback(:407) → OnProcessInterval(:191)
       │  bandwidth_estimation_->UpdateEstimate(:222)
       │  → 产出 TargetTransferRate（:565）
       ▼
     PostUpdates → GetUpdate()（rtp_transport_controller_send.cc:226）
       │  → observer_->OnTargetTransferRate(*update)（:232）
       ▼
     VideoStreamEncoder 接收码率（video/video_stream_encoder.cc）
       │  stream_resource_manager_.SetTargetBitrate(target_bitrate)  // :2530
       │  → 调 VideoEncoder 码率（降/升码率）
```

#### 3.3 音频 QoS：NetEq（抖动缓冲 + 丢包隐藏 PLC）

```
【接收】ChannelReceive::OnRtpPacket（audio/channel_receive.cc:681）
  │  → OnReceivedPayloadData（:341）
  ▼
【NetEq】NetEqImpl::InsertPacket（modules/audio_coding/neteq/neteq_impl.cc:184）
  │  → packet_buffer_->InsertPacket（:367）
  │  NetEq 不只是缓冲，还做：
  │    ① 抖动缓冲（抗网络抖动）
  │    ② 丢包隐藏 PLC（丢包时用算法补出缺失音频）
  │    ③ 音频重排序
  ▼
【解码】NetEqImpl::GetAudio/GetAudioInternal（neteq_impl.cc:432, :663）
  │  → AudioDecoder（Opus）解码
  ▼
【播放】ChannelReceive::GetAudioFrameWithInfo（声明 audio/channel_receive.cc:195...实现 :410，拉模型）
  │  → AudioMixer → ADM 播放
```

#### 3.4 QoS 全景图（精确到文件）

```
┌─ 发送端 ─────────────────────────────────────────────────┐
│  VideoStreamEncoder（video/video_stream_encoder.cc）      │
│    │ SetTargetBitrate(:2530) ← 拥塞调码率                │
│    ▼                                                     │
│  RtpVideoSender（call/rtp_video_sender.cc）               │
│    │ OnEncodedImage(:550) → 打包 → EnqueuePackets         │
│    │ FEC 冗余（FlexfecSender）                           │
│    │ RTX 重传（SetRtxSendStatus:761）                    │
│    ▼                                                     │
│  RtpTransportControllerSend（call/rtp_transport_controller_send.cc）│
│    │ controller_=GoogCcNetworkController（拥塞）          │
│    │ OnTransportPacketsFeedback(:764) → TargetTransferRate(:226)│
│    │ → observer_->OnTargetTransferRate(:232) → 编码器      │
│    ▼                                                     │
│  RtpTransport::SendRtpPacket（pc/rtp_transport.cc:155）    │
│    → SrtpTransport 加密 → 网络                            │
└──────────────────────────────────────────────────────────┘
        │ 网络（丢包/延迟/抖动）
        ▼
┌─ 接收端 ─────────────────────────────────────────────────┐
│  RtpTransport::OnReadPacket（pc/rtp_transport.cc:86）      │
│    → RtpDemuxer::OnRtpPacket（call/rtp_demuxer.cc:295）    │
│    ▼                                                     │
│  视频：RtpVideoStreamReceiver2（video/rtp_video_stream_receiver2.cc）│
│    │ nack_module_.OnReceivedPacket(:1199) 检测丢包        │
│    │ ulpfec_receiver_ 自恢复（:296）                      │
│    │ SendNack(:791) → rtp_rtcp_->SendNack(:794) 发回      │
│    ▼                                                     │
│  VideoStreamBufferController::FrameBuffer（video/video_stream_buffer_controller.h:130）│
│    → 按帧重组 → 解码                                     │
│                                                          │
│  音频：ChannelReceive（audio/channel_receive.cc）          │
│    → NetEqImpl::InsertPacket（neteq_impl.cc:184）          │
│    → 抖动缓冲 + 丢包隐藏 PLC → GetAudio(:432) → 解码       │
└──────────────────────────────────────────────────────────┘
```

**QoS 核心结论**：
1. **QoS 算法在 `modules/`**：NACK（nack_requester）、FEC（ulpfec/flexfec）、pacing（pacing_controller）、拥塞（goog_cc）、NetEq（neteq）
2. **QoS 决策在 `call/` + `video/` + `audio/`**：`RtpTransportControllerSend` 编排拥塞、`RtpVideoSender` 编排发送、`RtpVideoStreamReceiver2` 编排接收
3. **RTCP 是 QoS 的"反馈通道"**：接收端通过 RTCP 把 NACK/丢包信息发回发送端（`rtp_rtcp_impl2.cc`）
4. **拥塞控制闭环**：发送端 `GoogCcNetworkController` 根据接收端反馈（丢包/延迟）算出 `TargetTransferRate` → 调 `VideoStreamEncoder` 码率 → 影响编码 → 影响发送 → 再反馈
5. **音频 QoS 靠 NetEq**（抖动缓冲 + 丢包隐藏 PLC），视频靠 NACK/FEC + FrameBuffer 重组

---

## 十六、任务本质 + 传参方式 + C 库对比（2026-09-07 补充）

### 1. 任务到底是不是函数？

**任务 = 一个 `absl::AnyInvocable<void() &&>` 对象，它包装了一个可调用对象（lambda/函数指针/函数对象）。本质上是"函数 + 它捕获的参数"打包在一起。**

`AnyInvocable` 来自 **Abseil**（Google 的 C++ 库），是 `std::function` 的现代替代。内部存了：
- **函数指针**（要执行的代码）
- **捕获的参数**（lambda 捕获的变量）

所以**任务 = 函数体 + 参数，打包成一个对象**，可以放进队列、跨线程传递。

**核心心法：从"调用函数"到"投递任务"**
- 传统 C：**调用** = 立刻执行，参数当场传，同步返回
- C++ 异步：**投递** = 打包好（函数+参数），稍后执行，执行完回调通知

### 2. 传参如何处理？（三种方式，从 WebRTC 代码看）

**方式 1：按值捕获（`[rids]`）—— 最常用**
```cpp
// pc/rtp_sender.cc:917
worker_thread_->PostTask([&, rids] {   // [&, rids] = 默认引用捕获，但 rids 按值捕获
  video_media_channel()->GenerateSendKeyFrame(ssrc_, rids);
});
```
- `rids` **按值捕获**（拷贝进 lambda），线程安全
- 其他变量默认按引用（`&`），但只在 lambda 内同步使用

**方式 2：显式捕获 + 移动（`[collector, sctp_transport_name = ..., timestamp]`）**
```cpp
// pc/rtc_stats_collector.cc:1292
network_thread_->PostTask([collector,
                           sctp_transport_name = pc_->sctp_transport_name(),
                           timestamp]() mutable {
  collector->ProducePartialResultsOnNetworkThread(
      timestamp, std::move(sctp_transport_name));
});
```
- `collector` 按值捕获（智能指针，引用计数+1）
- `sctp_transport_name = pc_->sctp_transport_name()` **在捕获时求值**，把结果存进 lambda
- 这就是"**传参**"——参数在投递那一刻就"冻结"进 lambda 了

**方式 3：捕获弱引用/移动所有权（线程安全的精髓）**
```cpp
// pc/data_channel_controller.cc:337
network_thread()->PostTask([channel = std::move(channel)] {
  // channel 的所有权被移动进 lambda，线程安全
});
```
- `std::move(channel)` 把对象**所有权转移**进 lambda
- 避免跨线程拷贝，也避免悬垂引用

### 3. 跳出传统 C 思维的关键转变

1. **从"调用函数" → "投递任务"**：不关心什么时候执行，只负责打包好
2. **从"传参" → "捕获"**：参数在创建 lambda 时就绑定，不用等执行时再传
3. **从"同步等待" → "回调通知"**：任务执行完，通过回调/事件把结果传回来
4. **线程安全**：捕获的变量要么按值拷贝、要么移动所有权、要么用弱引用，**绝不让悬垂指针跨线程**

### 4. C 的类似实现：FFmpeg 对比（本机源码 `~/codes/avm/ffmpeg/ffmpeg-8.1.2`）

**FFmpeg 用同样的"线程 + 消息队列 + while 循环"模式。** 和 WebRTC 的 `Thread::Run()` 完全同构。

**① 消息队列实现**（`libavutil/threadmessage.c`）—— 类似 WebRTC 的 `Thread::Get()`

接收端（`recv`，line 142）：**while 循环 + 条件变量阻塞等待**
```c
static int av_thread_message_queue_recv_locked(AVThreadMessageQueue *mq,
                                               void *msg,
                                               unsigned flags)
{
    while (!mq->err_recv && !av_fifo_can_read(mq->fifo)) {
        if ((flags & AV_THREAD_MESSAGE_NONBLOCK))
            return AVERROR(EAGAIN);
        pthread_cond_wait(&mq->cond_recv, &mq->lock);   // 队列空则阻塞
    }
    if (!av_fifo_can_read(mq->fifo))
        return mq->err_recv;
    av_fifo_read(mq->fifo, msg, 1);                       // 取出消息
    pthread_cond_signal(&mq->cond_send);                  // 唤醒发送者
    return 0;
}
```

发送端（`send`，line 125）：**把消息写入 FIFO，唤醒接收者**
```c
static int av_thread_message_queue_send_locked(AVThreadMessageQueue *mq,
                                               void *msg,
                                               unsigned flags)
{
    while (!mq->err_send && !av_fifo_can_write(mq->fifo)) {
        if ((flags & AV_THREAD_MESSAGE_NONBLOCK))
            return AVERROR(EAGAIN);
        pthread_cond_wait(&mq->cond_send, &mq->lock);   // 队列满则阻塞
    }
    if (mq->err_send)
        return mq->err_send;
    av_fifo_write(mq->fifo, msg, 1);                      // 写入消息
    pthread_cond_signal(&mq->cond_recv);                  // 唤醒接收者
    return 0;
}
```

**② 编码线程循环**（`libavcodec/frame_thread_encoder.c`，line 75）—— 类似 WebRTC 的 `Thread::Run()`

```c
static void * attribute_align_arg worker(void *v){        // 编码线程入口
    AVCodecContext *avctx = v;
    ThreadContext *c = avctx->internal->frame_thread_encoder;

    while (!atomic_load(&c->exit)) {                      // 主循环
        AVPacket *pkt; AVFrame *frame; Task *task;

        pthread_mutex_lock(&c->task_fifo_mutex);
        while (c->next_task_index == c->task_index || atomic_load(&c->exit)) {
            if (atomic_load(&c->exit)) { pthread_mutex_unlock(&c->task_fifo_mutex); goto end; }
            pthread_cond_wait(&c->task_fifo_cond, &c->task_fifo_mutex);  // 无任务则阻塞
        }
        task_index = c->next_task_index;                  // 取一个任务索引
        c->next_task_index = (c->next_task_index + 1) % c->max_tasks;
        pthread_mutex_unlock(&c->task_fifo_mutex);

        task  = &c->tasks[task_index];                    // 取出任务
        frame = task->indata;
        pkt   = task->outdata;

        ret = ff_encode_encode_cb(avctx, pkt, frame, &task->got_packet);  // 执行编码

        pthread_mutex_lock(&c->finished_task_mutex);
        task->return_code = ret;                          // 写回结果
        task->finished    = 1;
        pthread_cond_signal(&c->finished_task_cond);      // 通知主线程任务完成
        pthread_mutex_unlock(&c->finished_task_mutex);
    }
end:
    avcodec_free_context(&avctx);
    return NULL;
}
```

### 5. WebRTC vs FFmpeg 对比表

| | WebRTC | FFmpeg |
|---|---|---|
| 线程循环 | `Thread::Run()` → `ProcessMessages()` | `worker()` → `while(!exit)` |
| 取任务 | `Thread::Get()` 从 `messages_` 队列 | `recv_locked()` 从 FIFO |
| 阻塞等待 | `ss_->Wait()`（SocketServer 多路复用） | `pthread_cond_wait()`（条件变量） |
| 任务类型 | `absl::AnyInvocable`（函数+捕获） | `Task` struct（frame/pkt 指针） |
| 队列 | `messages_` + `MutexLock` | `av_fifo` + `pthread_mutex` |
| 唤醒 | `WakeUpSocketServer()` | `pthread_cond_signal()` |
| 完成通知 | 回调/事件 | `pthread_cond_signal(finished_task_cond)` |

**核心相同**：都是"**每线程一个 while 循环 + 消息队列 + 条件变量/多路复用阻塞等待**"。看懂一个，另一个就通了。

### 6. 其他 C 库推荐

- **libuv**（Node.js 异步库）：事件循环 `while` + `uv__io_poll` 多路复用，最贴近 WebRTC 的 `SocketServer::Wait()`
- **GStreamer**（音视频框架）：`GstTask`（线程）+ `GstPad`（消息传递）
- **c-ares**（异步 DNS）：事件循环 + 回调

**推荐**：先看 FFmpeg 的 `threadmessage.c` 和 `frame_thread_encoder.c`（最贴近音视频），再看 libuv 的事件循环（最贴近 WebRTC 的 SocketServer）。

---

## 十七、串行（Serialization）如何实现？（2026-09-07 补充）

**串行 = 保证"任务 A 完成后，任务 B 才开始"。** WebRTC 用**三种机制**实现不同粒度的串行。

### 机制 1：同一线程内，天然串行（队列 FIFO）

**最简单也最基础。** 同一个线程的消息队列是 **FIFO（先进先出）**，任务按投递顺序依次执行。

```cpp
// 线程 X 上，按顺序投递 3 个任务
threadX->PostTask(task1);
threadX->PostTask(task2);
threadX->PostTask(task3);
// 执行顺序：task1 → task2 → task3（严格串行）
```

**为什么天然串行？** 因为 `Thread::ProcessMessages()` 是**单线程 while 循环**，一次只取一个任务执行，执行完才取下一个。所以**同一线程上，投递顺序 = 执行顺序**。

**作用**：保证"同一条流"内的接续。如一条视频流的编码、打包、发送，都在 worker 线程投递，就严格按序。

### 机制 2：链式回调（跨线程/跨步骤的串行）

**这是"不同流前后接续"的核心。** 当任务 A 需要跨线程，或需要等某个异步操作完成后才做 B 时，用**回调**把 B"挂"在 A 的完成事件上。

### 机制 3：同步串行（BlockingCall）—— 需要"等结果"时

当任务 A 执行完**必须拿到结果**才能继续时，用 `BlockingCall`（同步等待）：

```cpp
// pc/peer_connection.cc:1690
return worker_thread()->BlockingCall([&]() { return SetBitrate(bitrate); });
// 投递任务到 worker 线程，然后【阻塞等待】它完成并返回结果
```

**BlockingCall 的内部**：
```cpp
void Thread::BlockingCallImpl(functor) {
  Event done;
  PostTask([functor, &done] { functor(); done.Set(); });  // 投递任务
  done.Wait(Event::kForever);  // 阻塞等待任务完成
}
```

**这就是"串行 + 等结果"**：调用线程阻塞，直到任务在目标线程执行完。

### 三种机制对比

| 机制 | 用于 | 串行粒度 | 是否阻塞 |
|---|---|---|---|
| **队列 FIFO** | 同一线程内 | 同线程任务严格按序 | 否 |
| **链式回调** | 跨线程/跨步骤 | 上一步完成才触发下一步 | 否 |
| **BlockingCall** | 需要等结果 | 调用线程阻塞到完成 | **是** |

### 完整例子：SDP 协商的链式串行（offer → answer）

这是"不同步骤前后接续"的典型。每一步的"完成"都通过回调触发下一步。

**代码调用链**（`pc/peer_connection.cc` + `pc/webrtc_session_description_factory.cc`）：

```
【步骤1】CreateOffer() 生成 offer
  pc/peer_connection.cc:1500
  → sdp_handler_->CreateOffer(observer, options)   // SdpOfferAnswerHandler

【步骤2】WebRtcSessionDescriptionFactory::CreateOffer（异步生成 SDP）
  pc/webrtc_session_description_factory.cc:194
  → InternalCreateOffer(request)                   // 真正生成 SDP
      → session_desc_factory_.CreateOfferOrError() // 生成 offer
      → PostCreateSessionDescriptionSucceeded()    // 成功后回调

【步骤3】PostCreateSessionDescriptionSucceeded：把回调投递回信令线程
  pc/webrtc_session_description_factory.cc:405
  → Post([observer, description]() {
      observer->OnSuccess(description.release());  // 通知调用者 offer 生成好了
    });

【步骤4】调用者的 OnSuccess 里继续下一步（SetLocalDescription）
  → 设置本地描述
      → 完成回调 → 发送 offer 给对方（网络）

【步骤5】收到 answer → SetRemoteDescription(answer)
  → 完成回调 → 开始收发媒体
```

**关键代码**（`pc/webrtc_session_description_factory.cc`）：
```cpp
// 生成 offer 成功后，把 OnSuccess 回调投递回信令线程
void WebRtcSessionDescriptionFactory::PostCreateSessionDescriptionSucceeded(
    CreateSessionDescriptionObserver* observer,
    std::unique_ptr<SessionDescriptionInterface> description) {
  description->RelinquishThreadOwnership();
  Post([observer = scoped_refptr<CreateSessionDescriptionObserver>(observer),
        description = std::move(description)]() mutable {
    observer->OnSuccess(description.release());   // ← 链式回调：通知下一步
  });
}

// Post 内部：投递到信令线程执行
void WebRtcSessionDescriptionFactory::Post(
    absl::AnyInvocable<void() &&> callback) {
  callbacks_.push(std::move(callback));
  signaling_thread_->PostTask([weak_ptr = weak_factory_.GetWeakPtr()] {
    // 在信令线程上执行回调
    std::move(callbacks.front())();
    callbacks_.pop();
  });
}
```

**完整串行流程**：
```
1. CreateOffer() 生成 offer
   └ 完成回调(OnSuccess) → 2. SetLocalDescription(offer)
        └ 完成回调 → 3. 发送 offer 给对方（网络）
             └ 收到 answer → 4. SetRemoteDescription(answer)
                  └ 完成回调 → 5. 开始收发媒体
```

**每一步的"完成"都通过回调触发下一步**。这就是"**链式串行**"——不是靠队列顺序，而是靠**回调把下一步挂在上一步的完成事件上**。

### 回答："不同流怎么实现前后接续？"

**关键区分：同一条流 vs 不同流**

- **同一条流**（严格串行）：用**同一个线程的队列**，任务按投递顺序执行；或用一个**状态机**（`OnXxx` 回调里推进到下一个状态）
- **不同流**（各自独立，互不阻塞）：每条流**各自投递到自己的线程/队列**，天然并行；需要接续时用**链式回调**，流 A 的完成回调里触发流 B 的下一步

**典型例子：音视频同步**
```cpp
// 视频流和音频流各自独立
video_thread->PostTask(视频任务);
audio_thread->PostTask(音频任务);
// 两者并行，各自串行

// 但需要同步时（音画同步），用回调协调
// 视频帧到达 → 回调 → 检查音频时间戳 → 决定渲染时机
```

### 一句话总结

**串行的三种实现**：
1. **同线程队列 FIFO** —— 投递顺序 = 执行顺序（同一条流内严格串行）
2. **链式回调** —— 上一步完成回调触发下一步（跨步骤/跨线程的前后接续）
3. **BlockingCall** —— 同步等待任务完成（需要结果时）

**"不同流前后接续" = 链式回调**：每条流各自在队列里串行，需要跨流接续时，用完成回调把下一步"挂"上去。

---

## 十八、三个线程从哪里来？（完整链路 + LiveKit 例子，2026-09-07 补充）

### 1. 三个线程启动的完整链路

`pc/connection_context.cc` 是**中间层**。真正创建线程的是 **JNI 层**（`sdk/android/src/jni/pc/peer_connection_factory.cc`），LiveKit 通过 **Java 层**（`PeerConnectionFactory.java`）触发。

```
【1】LiveKit: libWebrtcInitialization()
    dagger/RTCModule.kt:102
    → executeBlockingOnRTCThread { PeerConnectionFactory.initialize(...) }
    （在 RTC 线程上初始化 WebRTC，加载 native 库）

【2】LiveKit: createPeerConnectionFactory()
    dagger/RTCModule.kt:358
    → PeerConnectionFactory.builder()...createPeerConnectionFactory()

【3】Java: PeerConnectionFactory.builder().createPeerConnectionFactory()
    sdk/android/api/org/webrtc/PeerConnectionFactory.java:290
    → nativeCreatePeerConnectionFactory(...)   // JNI 调用

【4】JNI: CreatePeerConnectionFactoryForJava()  ← 真正创建线程！
    sdk/android/src/jni/pc/peer_connection_factory.cc:259
    → 创建 network_thread / worker_thread / signaling_thread
    → 填入 PeerConnectionFactoryDependencies
    → CreateModularPeerConnectionFactory(dependencies)

【5】C++: ConnectionContext 构造函数
    pc/connection_context.cc
    → 使用 dependencies 里的三个线程（MaybeStartNetworkThread / lambda / MaybeWrapThread）
```

### 2. 三个线程的创建位置（JNI 层）

```cpp
// sdk/android/src/jni/pc/peer_connection_factory.cc:285-295
auto socket_server = std::make_unique<PhysicalSocketServer>();
auto network_thread = std::make_unique<Thread>(socket_server.get());
network_thread->SetName("network_thread", nullptr);
RTC_CHECK(network_thread->Start());          // 网络线程

std::unique_ptr<Thread> worker_thread = Thread::Create();
worker_thread->SetName("worker_thread", nullptr);
RTC_CHECK(worker_thread->Start());           // 工作线程

std::unique_ptr<Thread> signaling_thread = Thread::Create();
signaling_thread->SetName("signaling_thread", NULL);
RTC_CHECK(signaling_thread->Start());        // 信令线程
```

### 3. 线程就绪回调（JNI → Java）

JNI 层创建线程后，通过 `PostJavaCallback` 回调 Java 记录线程信息：

```cpp
// sdk/android/src/jni/pc/peer_connection_factory.cc:164-169
PostJavaCallback(env, owned_factory->network_thread(), j_pcf,
                 &Java_PeerConnectionFactory_onNetworkThreadReady);
PostJavaCallback(env, owned_factory->worker_thread(), j_pcf,
                 &Java_PeerConnectionFactory_onWorkerThreadReady);
PostJavaCallback(env, owned_factory->signaling_thread(), j_pcf,
                 &Java_PeerConnectionFactory_onSignalingThreadReady);
```

`PostJavaCallback` 内部用 `queue->PostTask` 把回调投递到对应线程：
```cpp
// sdk/android/src/jni/pc/peer_connection_factory.cc:104
void PostJavaCallback(JNIEnv* env, Thread* queue, ...) {
  queue->PostTask([object, java_method_pointer] {
    java_method_pointer(AttachCurrentThreadIfNeeded(), object);
  });
}
```

Java 侧接收回调：
```java
// sdk/android/api/org/webrtc/PeerConnectionFactory.java:614
@CalledByNative
private void onNetworkThreadReady() {
  networkThread = ThreadInfo.getCurrent();   // 记录当前线程
  staticNetworkThread = networkThread;
}
```

### 4. 为什么复用外部线程？线程从哪里来？

**`ConnectionContext` 优先使用外部传入的线程，只有没传时才自己创建**：

```cpp
// pc/connection_context.cc
network_thread_(MaybeStartNetworkThread(dependencies->network_thread, ...))  // 优先用外部的
worker_thread_(dependencies->worker_thread, []() { ... })                   // 优先用外部的
signaling_thread_(MaybeWrapThread(dependencies->signaling_thread, ...))     // 优先用外部的
```

`MaybeStartNetworkThread` 的逻辑（`pc/connection_context.cc:35`）：
```cpp
Thread* MaybeStartNetworkThread(Thread* old_thread, ...) {
  if (old_thread) {
    return old_thread;   // 外部传了 → 直接复用，不新建
  }
  // 没传 → 自己创建
  thread_holder = std::make_unique<Thread>(socket_server.get());
  thread_holder->SetName("pc_network_thread", nullptr);
  thread_holder->Start();
  return thread_holder.get();
}
```

**线程从 `PeerConnectionFactoryDependencies` 结构体来**（JNI 层填充）：
```cpp
// sdk/android/src/jni/pc/peer_connection_factory.cc:303-305
dependencies.network_thread = network_thread.get();
dependencies.worker_thread = worker_thread.get();
dependencies.signaling_thread = signaling_thread.get();
```

**为什么设计成"可复用外部线程"**：
1. JNI 层已经创建了线程（带 Java 回调），`ConnectionContext` 直接复用，避免重复创建
2. 允许上层自定义线程（某些集成方想用自己的线程）
3. 线程所有权由 `OwnedFactoryAndThreads` 统一管理生命周期

### 5. 以 LiveKit 为例

**不是观察者接口，而是通过 `PeerConnectionFactoryDependencies` 结构体传递。** 但 Java 侧有 `@CalledByNative` 就绪回调。

**LiveKit 的 RTC 线程**（`executeBlockingOnRTCThread`）：LiveKit 自己的 `RTCExecutor`，所有 WebRTC 操作都在这个线程上执行。

```
LiveKit 启动
  │
  ├─ LiveKit.create() → libWebrtcInitialization()
  │    └ executeBlockingOnRTCThread { PeerConnectionFactory.initialize(...) }
  │         └ 加载 native 库 "lkjingle_peerconnection_so"
  │
  └─ 创建工厂 → createPeerConnectionFactory()
       └ executeBlockingOnRTCThread {
            PeerConnectionFactory.builder()
              .setAudioDeviceModule(...)
              .setVideoEncoderFactory(...)
              .createPeerConnectionFactory()
         }
            └ nativeCreatePeerConnectionFactory()
                 └ JNI: CreatePeerConnectionFactoryForJava()
                      └ 创建三个线程 + 回调 Java onXxxThreadReady
```

**LiveKit 用线程信息做什么？** 用于 `printInternalStackTraces()` 调试——打印三个线程的堆栈：
```java
// sdk/android/api/org/webrtc/PeerConnectionFactory.java:600
public void printInternalStackTraces(boolean printNativeStackTraces) {
  printStackTrace(signalingThread, printNativeStackTraces);
  printStackTrace(workerThread, printNativeStackTraces);
  printStackTrace(networkThread, printNativeStackTraces);
}
```

### 6. 总结

| 问题 | 答案 |
|---|---|
| 三个线程在哪启动？ | **JNI 层** `sdk/android/src/jni/pc/peer_connection_factory.cc:285-295` |
| 为什么复用外部线程？ | `ConnectionContext` 优先用 `dependencies` 里的线程，没传才自己创建 |
| 线程从哪里来？ | JNI 层创建 → 填入 `PeerConnectionFactoryDependencies` → 传给 `ConnectionContext` |
| 是观察者接口吗？ | **不是**，是 `PeerConnectionFactoryDependencies` 结构体；但 Java 侧有 `@CalledByNative` 就绪回调 |
| LiveKit 怎么用？ | `libWebrtcInitialization` + `createPeerConnectionFactory` 都在 RTC 线程执行，触发 native 创建线程 |

### 6. while 循环的确切位置：构造函数 → Start() → pthread_create → PreRun → Run()

**疑问**：构造函数 `ConnectionContext::ConnectionContext` 里看不到 while 循环，它到底在哪？

**答案**：while 不在构造函数的执行流里，而在 `pthread_create` 创建的**那个新线程的独立执行流**里。

**构造函数里真正启动线程的调用**（`pc/connection_context.cc`）：
- `network_thread_ = MaybeStartNetworkThread(...)`（:103）→ 内部 `thread_holder->Start()`（:47）
- `worker_thread_ = dependencies->worker_thread ...`（:107）→ lambda 内 `thread_holder->Start()`
- `signaling_thread_ = MaybeWrapThread(...)`（:113）→ **不创建新线程**，包装当前调用线程

**`Thread::Start()` 干了什么**（`rtc_base/thread.cc:616`）：
```cpp
bool Thread::Start() {
  ...
  pthread_create(&thread_, &attr, PreRun, this);   // thread.cc:639 ← 创建线程，立即返回
  ...
}
```
`pthread_create` 创建新线程，入口函数 `PreRun`。**新线程从此刻独立运行，不再回到构造函数**。

**`PreRun` → `Run()` → while**（`rtc_base/thread.cc:716,724,734`）：
```cpp
void* Thread::PreRun(void* pv) {
  Thread* thread = static_cast<Thread*>(pv);
  ...
  thread->Run();                       // thread.cc:724  ← while 循环在这里
}

void Thread::Run() {
  ...
  ProcessMessages(kForever);           // 内部 while(true){ Get(); Dispatch(); }
}
```

**完整树形图**（上面到 pc/，下面到 while 内部）：

```
【上面：谁调用 ConnectionContext】
pc/peer_connection_factory.cc:90  ConnectionContext::Create(env, &dependencies)
  │
  ▼
【构造函数：主线程（调用方）执行流】
ConnectionContext 构造函数
  │
  ├── network_thread_ = MaybeStartNetworkThread(...)      // connection_context.cc:103
  │     └── thread_holder->Start()                        // connection_context.cc:47  ← 真正启动线程
  │           └── pthread_create(&thread_, &attr, PreRun, this)   // thread.cc:639 ← 立即返回
  │
  ├── worker_thread_ = dependencies->worker_thread ...    // connection_context.cc:107
  │     └── thread_holder->Start()                        // 上面 lambda 里第 5 行  ← 启动线程
  │           └── pthread_create(&thread_, &attr, PreRun, this)   // thread.cc:639 ← 立即返回
  │
  ├── signaling_thread_ = MaybeWrapThread(...)            // connection_context.cc:113
  │     └── 不创建新线程，包装当前调用线程（WrapCurrentThread）
  │
  └── 继续初始化 socket factory / network manager，构造函数返回

  （pthread_create 立即返回 → 构造函数继续 → 返回调用方）
  （新线程从 PreRun 开始，独立进入下面这条链）

【下面：新线程（网络/worker 线程）独立执行流】
PreRun                                          // thread.cc:716
  └── thread->Run()                             // thread.cc:724
        └── ProcessMessages(kForever)           // thread.cc:734
              └── while(true) {                 // 真正的循环
                    Get()                       //   从消息队列取一条任务
                      └── 若队列空 → 调 SocketServer::Wait() 阻塞等待
                    Dispatch()                  //   执行任务（回调 lambda）
                  }
```

**关键点**：`pthread_create` 是**异步的**——创建新线程后**立即返回**，构造函数继续走；新线程从 `PreRun` 开始**独立地**进入 while。构造函数和 while 是**两个并行执行流**，所以构造函数里看不到 while。

**为什么 signaling_thread 没有 while**：`MaybeWrapThread`（`connection_context.cc:51`）**不创建新线程**，把当前调用线程包装成 `Thread`（`WrapCurrentThread`）。信令线程的 while 由调用方自己驱动（LiveKit 里是 `RTCExecutor` 的线程）。

**一句话**：while 在 `Thread::Start()` → `pthread_create` → `PreRun` → `Run()` → `ProcessMessages()` 这条链里。构造函数只调 `Start()` 创建线程，新线程**独立地**进入 while——所以构造函数里看不到 while，它在另一个线程的执行流里。

---

## 十九、外部注入线程的普遍性 + Dependencies 概念澄清（2026-09-07 补充）

### 1. "外部注入线程"其实是几种不同的模式

WebRTC 的例子混合了三种模式，普遍性差别很大：

| 模式 | 是什么 | 普遍性 |
|---|---|---|
| **依赖注入（DI）** | 把依赖（线程/工厂/服务）从外部传入，而不是自己 new | **非常常见**，几乎所有大型框架 |
| **线程所有权转移** | 外层创建线程，把所有权交给内层管理 | 常见，但看场景 |
| **线程就绪回调** | 线程启动后通知外层"我准备好了" | 常见，尤其跨语言/跨层 |

**"外部注入线程"太笼统。真正普遍的是依赖注入思想，"注入线程"只是它的特例。**

### 2. 依赖注入（DI）—— 极其普遍

**核心思想：不自己 new，让外层把依赖给你。** 遍布所有领域：

| 领域 | 例子 |
|---|---|
| Java/Android | Spring、Dagger（LiveKit 用 Dagger）、Guice |
| C++ | 构造函数注入、工厂模式 |
| Python | FastAPI 依赖注入、Django settings |
| 前端 | React Context、Vue provide/inject |
| C | 结构体指针传递（FFmpeg 的 `AVCodecContext`） |

**为什么普遍**：可测试性（注入 mock）、可配置性（不同场景不同实现）、解耦（依赖接口不依赖实现）。

### 3. 线程所有权转移 —— 常见，但看场景

- 常见于：库初始化（库需要线程但不自己管生命周期）、跨语言（JNI/Python 扩展）
- 但很多库自己创建线程自己管理（FFmpeg 的 `frame_thread_encoder.c` 内部创建 `worker()` 线程）
- 所以"注入线程"不是唯一选择，取决于库的设计哲学

### 4. 线程就绪回调 —— 常见，尤其跨层

- 常见于：Android 生命周期（onCreate/onStart）、Node worker 的 online 事件、浏览器 DOMContentLoaded
- WebRTC 的 `onNetworkThreadReady` 就是这种

### 5. 关键洞察：WebRTC 为什么"半注入、半自建"？

```
网络线程：优先用外部，没传才自建（MaybeStartNetworkThread）
工作线程：优先用外部，没传才自建（lambda）
信令线程：优先用外部，没传就包装当前线程（MaybeWrapThread）
```

**因为 WebRTC 要同时满足两种用户**：
1. **高级用户**（Chrome、大型应用）：想自己控制线程，传入自己的线程
2. **普通用户**（LiveKit、小应用）：不想管线程，让 WebRTC 自己创建

**这就是"可选依赖注入"**——提供默认实现，但允许覆盖。这是库设计的常见模式。

### 6. 普遍性排序

| 模式 | 普遍性 | 例子 |
|---|---|---|
| 依赖注入 | 极高 | Spring、Dagger、React Context |
| 线程就绪回调 | 高 | Android 生命周期、Node worker |
| 线程所有权转移 | 中等 | WebRTC、JNI、库初始化 |
| "可选注入 + 默认自建" | 高（库设计） | WebRTC、很多框架 |

**类比**：想象餐厅——
- 依赖注入 = 餐厅不自己种菜，从供应商进货（普遍）
- 线程所有权转移 = 供应商送菜，餐厅自己管菜（中等）
- 线程就绪回调 = 菜到了，供应商通知餐厅（常见）
- 可选注入 + 默认自建 = 餐厅有自己菜园，也可从供应商进货（库设计常见）

### 7. `PeerConnectionFactoryDependencies` 概念澄清

**不是"对使用者的依赖"，而是"WebRTC 依赖使用者提供的东西"——方向反过来了。**

定义在 `api/peer_connection_interface.h:1428`，注释原文（line 1422-1427）：
> "PeerConnectionFactoryDependencies holds all of the PeerConnectionFactory dependencies. All new dependencies should be added here instead of overloading the function. This simplifies dependency injection and makes it clear which are mandatory and optional."

**依赖方向**：
```
使用者（LiveKit） ──提供──► WebRTC
   提供线程、编解码器工厂、音频设备等
```

**结构体成员分类**（`api/peer_connection_interface.h:1439-1489`）：

| 成员 | 类型 | 谁提供 | 注释里的说法 |
|---|---|---|---|
| `network_thread` | `Thread*` | 使用者 | **Optional**（可选） |
| `worker_thread` | `Thread*` | 使用者 | **Optional** |
| `signaling_thread` | `Thread*` | 使用者 | **Optional** |
| `adm`（音频设备） | `AudioDeviceModule` | 使用者 | Media specific |
| `video_encoder_factory` | `VideoEncoderFactory` | 使用者 | Media specific |
| `video_decoder_factory` | `VideoDecoderFactory` | 使用者 | Media specific |
| `audio_encoder_factory` | `AudioEncoderFactory` | 使用者 | Media specific |
| `neteq_factory` | `NetEqFactory` | 使用者 | — |
| `event_log_factory` | `RtcEventLogFactory` | 使用者 | — |

**设计意图**（注释明确）：
1. 新依赖都加这里，**避免函数参数爆炸**（否则 `CreatePeerConnectionFactory` 会有几十个参数）
2. **简化依赖注入**（DI）
3. **明确必填/可选**（线程都是 Optional）

**为什么叫 Dependencies 而不是 Options**：
- `Options`（如 `PeerConnectionFactoryInterface::Options`）= 配置项，WebRTC 自己决定怎么用，只是调节行为
- `Dependencies` = 外部对象，WebRTC **需要它们才能工作**，是"依赖"

**类比**：`Options` = 告诉餐厅"我要辣一点"（配置）；`Dependencies` = 给餐厅"提供食材、厨师"（依赖）。

**一句话**：`PeerConnectionFactoryDependencies` = **"WebRTC 需要你提供的一组依赖清单"**，是依赖注入的载体，方向是使用者 → WebRTC。

---

## 二十、Java / Android 内容掌握优先级（2026-09-07 补充）

**目标定位**：不是"用引擎做业务"，而是"**做引擎、优化引擎**"。因此掌握优先级与纯应用开发者不同——不是"够用就行"，而是"**能改引擎、能定位引擎瓶颈**"。

### 前提：WebRTC 的 Java 层其实是"三层"，价值完全不同

```
┌─────────────────────────────────────────────────────────────┐
│  LiveKit Kotlin 层（应用层，用引擎做业务）                     │
│  webrtc/PeerConnectionFactoryManager.kt 等                  │
├─────────────────────────────────────────────────────────────┤
│  ① Java 接口层  sdk/android/api/org/webrtc/*.java           │
│     = C++ 接口的 Java 门面（facade），一一对应                │
├─────────────────────────────────────────────────────────────┤
│  ② JNI 桥      sdk/android/src/jni/*.cc                     │
│     = Java ↔ C++ 的机械翻译胶水（@CalledByNative）            │
├─────────────────────────────────────────────────────────────┤
│  ③ Android 平台特有  sdk/android/src/java/org/webrtc/       │
│     MediaCodec / Camera / Surface / AudioTrack（平台适配）    │
└─────────────────────────────────────────────────────────────┘
```

### 三层各自的"做引擎"价值

#### ① Java 接口层（`api/org/webrtc/*.java`）—— **必掌握，是 C++ 接口的镜像**

这一层不是"另一个东西"，而是你已研究的 C++ `api/*.h` 的**Java 形态**，一一对应：

| Java 类 | 对应 C++ 接口 | 做引擎价值 |
|---|---|---|
| `PeerConnectionFactory.java` | `PeerConnectionFactoryInterface` | 工厂 + 3 线程启动回调（`onNetworkThreadReady` 等） |
| `PeerConnection.java` | `PeerConnectionInterface` | 会话编排 |
| `VideoEncoder/Decoder.java` | `VideoEncoder/DecoderInterface` | **自定义/替换编解码的入口** |
| `VideoFrame.java` | `api/video/video_frame.h` | 像素 + 元数据 |
| `VideoEncoderFactory.java` | `VideoEncoderFactory` | **LiveKitOverrides 注入点** |

**为什么必掌握**：因为**优化引擎往往从"换算法/换实现"入手**，而换实现就是从这些 Java 接口注入的。你在 C++ 层理解了 `PeerConnectionInterface`，这里的 `PeerConnection.java` 就是同一个契约的 Java 侧。**理解它 = 打通"接口契约"从 C++ 到 Java 的整条线**，这是改引擎的前提。

#### ② JNI 桥（`src/jni/*.cc`）—— **掌握机制，不必逐行**

核心机制就一个 **`@CalledByNative` 注解**：
- Java 侧标 `@CalledByNative` 的方法（如 `PeerConnectionFactory.java` 的 `onNetworkThreadReady`）= **C++ 回调进 Java 的入口**
- C++ 侧 `src/jni/pc/peer_connection_factory.cc` 用 `jni_helpers.cc` 缓存 Java 方法 ID，`PostJavaCallback` 投递回 Java

**做引擎的价值**：当你**给 WebRTC 新增 Java API**（比如给 LiveKit 加新能力）时，必须懂这一层怎么加。但它是**机械翻译**，没有新算法概念，所以**掌握机制即可，不必深挖每个文件**。

#### ③ Android 平台特有（`src/java/org/webrtc/`）—— **按需掌握，重点是"边界"**

| 内容 | 是什么 | 做引擎价值 |
|---|---|---|
| `MediaCodecVideoDecoderFactory` / `HardwareVideoEncoder` | **Android 系统类 MediaCodec 的封装**（非 WebRTC 内部类） | 硬件编解码优化、自定义编码器 |
| `Camera1/2Capturer`、`ScreenCapturerAndroid` | Android 相机 API 封装 | 自定义采集 |
| `SurfaceViewRenderer`、`EglBase`、`SurfaceTextureHelper` | OpenGL ES + Surface 渲染管线 | 渲染优化、延迟优化 |
| `JavaAudioDeviceModule` | Android AudioTrack/AudioRecord 封装 | 音频延迟优化 |

**为什么按需**：这些是**平台 API + WebRTC 适配**，不是 WebRTC 自己的算法。**算法（码率控制、jitter buffer、AEC）仍在 C++ 的 `modules/`**，MediaCodec 只是"用硬件加速编解码的壳"。做引擎时，这些是**优化点**（延迟、功耗、画质），但**不是引擎核心**。

### 做引擎的掌握优先级排序

```
优先级 1（必掌握）：
  C++ 引擎本身（你已在做的）→ api/pc/call/media/modules
  Java 接口层（api/org/webrtc/*.java）—— 作为 C++ 接口的镜像，打通契约线

优先级 2（掌握机制）：
  JNI 桥（@CalledByNative 机制）—— 为了新增/修改 Java API

优先级 3（按需，做优化时）：
  Android 平台特有（MediaCodec/Camera/Surface/Audio）—— 延迟/功耗/画质优化点
```

### 关键结论

> **做引擎，C++ 层是根本，Java 接口层是"契约的 Java 镜像"（必掌握），JNI 桥是"新增 API 要懂的机制"，Android 平台特有是"优化点但非核心"。**
>
> 方向是：**C++ 引擎（核心算法）← Java 接口（契约镜像）← JNI 桥（翻译）← Android 平台（适配）**。越往右越是"壳"，越往左越是"引擎"。优化引擎 = 优化左边的算法 + 优化右边的平台适配（延迟/功耗/画质）。

### 20.1 Facade 是不是设计模式？—— 是，且 Java 层正是典型 Facade

**是标准设计模式（GoF 23 种之一），但"看起来像普通工程行为"的直觉也对——二者不矛盾。**

**Facade（门面）模式本质**：给一个**复杂的子系统**提供一个**简化的统一入口**。关键在"简化"和"统一"——不是随便包一层就叫 Facade，而是**把一堆复杂交互收敛成一个简单接口**。

**为什么 WebRTC 的 Java 层是典型 Facade**：
- C++ 引擎有 7 层（api/pc/call/media/modules/p2p/rtc_base），几十个类，调用关系复杂
- Java 层只暴露 `PeerConnectionFactory`、`PeerConnection`、`VideoTrack` 等**极少数类**，把下层复杂性全藏起来
- LiveKit（Kotlin）只需对着这几个类编程，无需知道 C++ 内部

```
LiveKit (Kotlin)
   │  只认识这几个门面
   ▼
PeerConnectionFactory / PeerConnection / VideoTrack   ← Facade
   │  隐藏了
   ▼
[pc] → [call] → [media] → [modules] → [rtc_base]     ← 复杂子系统
```

**为什么"看起来就是普通工程行为"也对**：因为**好的设计模式本就该"自然到不像模式"**。Facade 成为"模式"而非"习惯"，是因为它回答了一个**反复出现的问题**："子系统太复杂，外部使用者只需一小部分功能，怎么不被复杂度淹没？"——答案是"提供统一门面"。当问题反复出现、有公认解法时，就升级为模式。

**类比**：`PeerConnectionFactoryDependencies` 是 DI 的载体——DI 也是模式，价值不在"命名"，而在"解决反复出现的耦合问题"。Facade 同理。

**一句话**：**Facade 是模式，因为它解决"子系统复杂度对外暴露"这个反复出现的问题；它看起来普通，是因为好模式本该自然。** `PeerConnectionFactory` 就是 WebRTC 对 C++ 引擎的 Facade。

### 20.2 做引擎也要准备业务层——业务层是引擎的"入口 + 验证场"

**做引擎不是一蹴而就，业务层是理解引擎的"入口"和"验证场"。**

**为什么业务层对做引擎也重要**：
- **入口**：从 LiveKit 的 Kotlin 层进入，才知道引擎被怎么用、哪些能力被用到、哪些是热点
- **验证场**：优化引擎后，要回到业务层验证效果（延迟降了没、画质好了没、功耗省了没）
- **需求来源**：引擎优化方向（低延迟、抗弱网、省功耗）都来自业务场景

**但区分"准备"与"深入"**：
- **准备**（值得）：理解 LiveKit 怎么调用 WebRTC、哪些能力被用到、渲染/采集/编解码的边界在哪
- **深入**（不必）：LiveKit 的业务状态机（Room/Participant/Track 生命周期）、信令协议细节——这些是"用引擎做业务"，对做引擎帮助不大

**修正后的掌握优先级**：
```
业务层（LiveKit Kotlin）   —— 引擎的"入口 + 验证场"，准备即可，不必深入业务状态机
Java 接口层（api/org/webrtc）—— C++ 接口镜像，必掌握，打通契约线
JNI 桥                       —— 掌握 @CalledByNative 机制
Android 平台特有              —— 优化点（延迟/功耗/画质），按需
C++ 引擎（根本）              —— 核心算法，持续深入
```

### 20.3 `@CalledByNative` 是什么？—— "被 C++ 调用"的注解

拆开：**"Called By Native" = 被 Native（C++）调用**。是**注解（Annotation）**，标记在 Java 方法上，告诉 JNI 桥：**"这个方法不是 Java 自己调的，而是 C++ 引擎调进来的。"**

**为什么需要它**：Java 和 C++ 是两个世界。C++ 想调 Java 方法，必须先通过 JNI 拿到该 Java 方法的**方法 ID（method ID）**才能调用。`@CalledByNative` 是给生成工具的一个标记，告诉它"帮我把这个 Java 方法的方法 ID 找出来、缓存好，方便 C++ 侧调用"。

**具体例子**（`PeerConnectionFactory.java`）：
```java
// Java 侧 —— 标 @CalledByNative，表示会被 C++ 调
@CalledByNative
void onNetworkThreadReady() {
    // 网络线程准备好了，Java 收到通知
}
```
C++ 侧（`src/jni/pc/peer_connection_factory.cc`）：
```cpp
// 通过 JNI 拿到 onNetworkThreadReady 的方法 ID，然后调用
jmethodID method = GetMethodID(env, java_class, "onNetworkThreadReady", "()V");
env->CallVoidMethod(java_peer_connection_factory, method);
```

**一句话**：`@CalledByNative` = **"这个方法是被 C++ 调进来的"**。与 `@CalledByNativeUnchecked`（不检查异常版本）一起构成 Java ↔ C++ 回调桥梁。之前研究的"3 线程启动回调"（`onNetworkThreadReady`/`onWorkerThreadReady`/`onSignalingThreadReady`）就是靠它从 C++ 回调进 Java。

### 20.4 接口镜像（Interface Mirror）是什么？—— 同一接口的 C++/Java 双份

**"镜像" = 同一个接口，在 C++ 和 Java 各有一份，内容一一对应。** 像镜子里的倒影——C++ 有什么，Java 就有什么，只是语言不同。

**为什么有镜像**：WebRTC 引擎是 C++ 写的，但 LiveKit（Kotlin）是 JVM 语言，**没法直接调 C++**。所以 WebRTC 在 Java 侧**复制了一份接口**，让 Java 开发者能用 Java 语法操作 C++ 引擎。这份 Java 接口就是 C++ 接口的"镜像"。

**具体例子**：`VideoEncoder` 接口
C++ 侧（`api/video_codecs/video_encoder.h`）：
```cpp
class VideoEncoder {
public:
    virtual int32_t Encode(const VideoFrame& frame, ...) = 0;  // 编码一帧
    virtual VideoEncoderInfo GetEncoderInfo() const = 0;       // 编码器信息
    virtual void Release() = 0;                                 // 释放
};
```
Java 侧（`api/org/webrtc/VideoEncoder.java`）——同一接口的镜像：
```java
public interface VideoEncoder {
    EncoderInfo getEncoderInfo();                              // 对应 GetEncoderInfo
    VideoCodecStatus encode(VideoFrame frame, EncodeInfo info); // 对应 Encode
    void release();                                            // 对应 Release
}
```

**关键点**：两个接口**不是两套逻辑，是同一套逻辑的两种语言表达**。实现 Java 的 `VideoEncoder`，底层经 JNI 桥接到 C++ 编码器。所以**理解了 C++ 接口，Java 镜像就是"换个写法"**——这就是"Java 接口层必掌握，因为它是 C++ 接口的镜像"。

**为什么对做引擎重要**：**换算法/换实现就是从这些镜像接口注入的**。比如换自定义编码器，在 Java 侧实现 `VideoEncoder` 接口，经 `LiveKitOverrides` 注入，底层就替换了 C++ 编码器。

### 20.5 为什么 Kotlin 是 JVM 语言？为什么能和 Java 无缝互调？

**因为 Kotlin 编译后不是"Kotlin 字节码"，而是"JVM 字节码"**——与 Java 编译产物是**同一种东西**（`.class` 文件，跑在 JVM 上）。

```
Kotlin 源码 (.kt)  ──编译──►  JVM 字节码 (.class)  ──►  JVM 执行
Java 源码 (.java)  ──编译──►  JVM 字节码 (.class)  ──►  JVM 执行
```

**两者编译到同一个目标**，所以 JVM 分不清"方法是 Kotlin 写的还是 Java 写的"。这就是"无缝互调"的根本原因——**不是 Kotlin 特意兼容 Java，而是它们编译到同一目标**。

**"无缝"到什么程度**：
- Kotlin 直接 `import` Java 类、调 Java 方法、实现 Java 接口
- Java 也能调 Kotlin 类（Kotlin 编译器生成 Java 能识别的签名）
- 唯一的"缝"是语法糖：Kotlin 的 `null` 安全、扩展函数、协程，Java 侧要用特殊方式访问（`@JvmStatic`/`@JvmField` 注解调整生成方式）

**一句话**：不是"Kotlin 兼容 Java"，而是"**Kotlin 和 Java 是同一门 JVM 语言的两个方言**"。LiveKit 用 Kotlin 写，`import livekit.org.webrtc.PeerConnectionFactory`（Java 写的）能直接调，就是因为这个。

### 20.6 Facade 模式源自 Java 吗？它规范了什么？之前怎么做？

**Facade 不源自 Java，源自 GoF《设计模式》（1994），语言无关。** Java 只是后来最常被举例的语言。

**它规范了什么**：规范"**复杂子系统与外部使用者的边界**"——规定"外部只能通过门面访问子系统，不能直接碰内部"。带来三个好处：
1. **降低耦合**：外部不依赖内部细节，子系统改了，外部不用改
2. **简化使用**：外部只需面对几个门面类
3. **隐藏内部**：实现细节不泄露

**之前（无 Facade）怎么做**：外部直接 new 子系统内部一堆类，自己组装调用链。没有 `PeerConnectionFactory` 门面时，LiveKit 要自己创建 `PeerConnection`、`VideoTrack`、`RtpSender` 等一堆对象，自己管理生命周期和依赖——**又麻烦又脆弱**，内部一改外部就崩。

**类比**：不用门面 = 去餐厅自己进厨房找食材开火调味装盘（直接操作子系统内部）；用门面 = 对服务员说"来份宫保鸡丁"（对门面说一句话）。`PeerConnectionFactory` 就是那个"服务员"。

### 20.7 Java 操作 C++ 怎么做？只要类名函数名一致就行？

**不是。JNI 不靠"名字一致"自动对接，靠"注册"。** 两种注册方式：

**方式 A：静态注册（靠名字）**——Java 声明 `native` 方法，C++ 按固定命名规则写函数：
```java
// Java
public native void doSomething();
```
```cpp
// C++ —— 函数名 = JNIEXPORT + Java_包名_类名_方法名
JNIEXPORT void JNICALL Java_org_webrtc_PeerConnectionFactory_doSomething(JNIEnv* env, jobject thiz) {}
```
确实靠名字，但命名规则极严（`Java_` + 包名用 `_` 分隔 + 类名 + `_` + 方法名），易错。

**方式 B：动态注册（靠注册表）——WebRTC 用这种**。在 `src/jni/jni_onload.cc` 把 Java 方法和 C++ 函数**显式绑定**：
```cpp
static const JNINativeMethod kMethods[] = {
    {"createPeerConnectionFactory", "(...)J", reinterpret_cast<void*>(&CreatePeerConnectionFactory)},
    {"createPeerConnection", "(...)J", reinterpret_cast<void*>(&CreatePeerConnection)},
};
```
`JNINativeMethod`：`{"Java方法名", "JNI签名", C++函数指针}`。**靠注册表绑定，不靠名字**（Java 方法名和 C++ 函数名可以不同）。

**"看起来没太多内容"是错觉**——JNI 桥的内容不是"类名函数名一致"，而是：
1. **JNI 签名（signature）**：每方法都要写，如 `"(...)J"`，`(` 后参数类型、`)` 后返回类型，`J`=long。JNI 最繁琐部分。
2. **类型转换**：Java `String`↔C++ `jstring`、`byte[]`↔`jbyteArray`，手动转换。
3. **方法 ID 缓存**：`GetMethodID`/`GetFieldID` 每次有开销，须缓存。

**一句话**：JNI 靠**注册表（`JNINativeMethod`）+ 签名（signature）+ 类型转换**把 Java 和 C++ 绑起来。内容不少但都是**机械翻译**——无算法，所以"掌握机制即可，不必深挖"。

### 20.8 JNI 有开销吗？多大？—— 做引擎必须知道

**有，且是做引擎的关键点。** JNI 开销分几类：

**开销来源**：
1. **调用开销**：每次 JNI 调用经 JVM 边界检查、栈帧切换、异常检查。一次简单 JNI 调用约**几十到几百纳秒**（比普通 Java 调用慢一个数量级）。
2. **类型转换开销**：字符串/数组转换要分配内存、复制数据。`byte[]`↔`jbyteArray` 数据量大时显著。
3. **`GetFieldID`/`GetMethodID` 查找**：每次查找很慢——WebRTC 缓存它们（`jni_helpers.cc`）。
4. **跨线程**：C++ 线程调 Java 需 `AttachCurrentThread`，开销更大。

**具体量级**：
- 纯 JNI 方法调用：约 **50-100 ns**（一次）
- 带字符串/数组转换：**微秒级**（取决于数据量）
- 对比：普通 Java 方法调用约 **5-10 ns**

**为什么对做引擎重要**：**WebRTC 音视频数据路径（编解码、渲染）会尽量避免 JNI 开销**——每帧数据经过 JNI 会拖慢性能。因此：
- **高频路径**（每帧像素数据）尽量**留在 C++ 侧**，不经过 JNI
- **低频路径**（配置、回调通知）才走 JNI
- 这就是为什么 `VideoFrame` 的像素 buffer 在 C++ 侧流动，Java 侧只拿引用（`WrappedNativeVideoDecoder` 等），避免每帧拷贝

**一句话**：JNI 有开销（单次 ~50-100ns，带数据转换到微秒级），**做引擎时音视频高频路径要避开 JNI**，只让低频控制/回调走 JNI。这也是为什么 WebRTC 把数据留在 C++ 侧、Java 只做门面。

### 20.6.1 门面是对"库"做封装吗？—— 对，但太窄；门面封装的是"复杂子系统"

**对的部分**：门面确实是"封装"，把复杂东西藏起来、给个简单入口。`PeerConnectionFactory` 就是对 C++ 引擎这个"库"的封装。

**太窄的部分**：门面封装的不只是"库"，而是**任何复杂的子系统**。库只是子系统的一种。子系统可以是：
- **一个库**（WebRTC C++ 引擎）→ `PeerConnectionFactory`
- **一组类**（支付模块：账户/订单/退款/风控）→ `PaymentFacade`
- **一个外部服务**（短信网关、第三方 API）
- **一个硬件/驱动层**（音频设备、相机）

**一句话**：门面是对"复杂子系统"的封装，**库只是最常见的一种子系统**。从"库"的角度看，是因为 WebRTC 恰好是库；但门面模式本身不局限于库。

### 20.6.2 门面的三条原则

**原则 1：最小暴露（Minimal Interface）**
**只暴露子系统的一小部分能力，不是全部。** 门面不是"把子系统所有方法转发一遍"，而是**精选外部真正需要的少数方法**。
- WebRTC 引擎几十个类、几百个方法，但 `PeerConnectionFactory` 只暴露 `createPeerConnection`、`createVideoSource`、`createAudioSource` 等少数几个
- 反例（门面失败）：门面把子系统所有方法都转发，就退化成"透明转发器"，没有意义

**原则 2：单向依赖（Dependency Inversion）**
**外部只依赖门面，不依赖子系统内部。** 依赖方向单向：外部 → 门面 → 子系统。
```
外部 (LiveKit)  →  门面 (PeerConnectionFactory)  →  子系统 (C++ 引擎)
```
- 好处：子系统内部怎么改（重构、换实现），只要门面接口不变，外部不受影响
- "降低耦合"的本质 = **把"外部依赖子系统"变成"外部依赖一个稳定的门面"**

**原则 3：隐藏实现细节（Information Hiding）**
**外部看不到子系统内部发生了什么。** 门面背后的复杂性、状态、协作关系，对外部完全不可见。
- LiveKit 调 `createPeerConnection`，不需要知道 C++ 里创建了哪些内部对象、怎么协作
- 好处：外部心智负担小，子系统实现自由演进

**一句话**：门面三条原则 = **最小暴露**（只露需要的）+ **单向依赖**（外部只依赖门面）+ **隐藏细节**（内部不可见）。合起来回答"它规范了什么"——**规范了外部与子系统的边界，让复杂度不泄漏到外部**。

---

## 二十一、`VideoReceiveStream2` 重构 + 跨线程性能（2026-09-08 补充）

### 21.1 为什么有 `VideoReceiveStream2`？和 1 有何区别？

**M144 里只有 `VideoReceiveStream2`，没有 `VideoReceiveStream`（不带 2 的）**（`video/video_receive_stream2.cc` 版权 2020）。

这是**历史遗留类名**：WebRTC 在约 2020 年（M80 前后）对视频接收流做了一次大重构，新实现命名为 `VideoReceiveStream2`，旧版 1 随后被**删除**，但"2"后缀一直保留至今——**即使 1 早就不存在了，名字也没改回去**。同理，`VideoStreamDecoder2`、`VideoReceiver2`（`modules/video_coding/video_receiver2.h`）都是同一批重构的后缀。

**结论：不是"1 和 2 并存"，而是"只有 2，1 已删除"。看到带 2 的类就当作当前唯一实现。**

### 21.2 为什么重构？改变了什么？

**重构核心：把"缓冲 + 解码调度"从 `VideoReceiveStream` 里抽出来，独立成 `VideoStreamBufferController`（VSBC）+ `FrameBuffer`。**

重构前（旧 `VideoReceiveStream`）：一个类既管"会话/渲染"又管"缓冲/解码调度"，太臃肿，难测试、难替换。

重构后（`VideoReceiveStream2`）拆成三层：

| 类 | 职责 | 位置 |
|---|---|---|
| `VideoReceiveStream2` | **会话层**：接收器、渲染、统计、生命周期 | `video/video_receive_stream2.h` |
| `VideoStreamBufferController` | **缓冲决策层**：何时解码、等关键帧、超时、调度 | `video/video_stream_buffer_controller.h` |
| `FrameBuffer` | **纯数据结构**：帧的存储/重排序 | `api/video/frame_buffer.h` |

**三个动机**（从代码结构推断）：
1. **职责分离**：会话 vs 缓冲决策 vs 数据结构，各管一环
2. **可测试性**：VSBC 是独立类，可单独单测（有 `video_stream_buffer_controller_unittest.cc`）
3. **可替换性**：`FrameDecodeScheduler` 是接口（可插拔同步/任务队列调度策略）；`FrameBuffer` 从 modules 提升到 **`api/`**（`api/video/frame_buffer.h`），成为稳定契约，可被外部替换

### 21.3 这么多跨线程投递，对性能有影响吗？

**有，但 WebRTC 刻意设计成"影响可控"。**

**关键：跨线程投递的是"任务/回调（lambda）"，不是数据本身。**
- 帧/包数据通过 `std::move` **转移所有权**，**零拷贝**——不复制像素数据
- 开销在**调度**（加锁 + 入队 + 唤醒线程，单次微秒级），不在数据复制

**WebRTC 的缓解手段**：
1. **解码独立队列 + HIGH 优先级**：`decode_queue_` 是 `Priority::HIGH`（`video_receive_stream2.cc:272`），避免解码阻塞 worker 主循环
2. **高频路径尽量留同一线程**：组帧 + jitter buffer 都在 worker 线程（`RTC_DCHECK_RUN_ON(&worker_sequence_checker_)`），**不跨线程**
3. **网络线程 SocketServer 多路复用**：一次 `Wait()` 处理多个 socket 事件
4. **数据不跨 JNI**：像素 buffer 留在 C++ 侧，Java 只拿引用（JNI 单次 ~50-100ns，数据转换到微秒级，更高频路径更贵）

**实际量级**：视频下行从网络线程 → worker → decode_queue 大约 **2-3 次线程切换**，每次微秒级。对实时音视频（要求几十 ms 延迟）可接受。**真正的性能瓶颈通常在编解码本身，而非线程调度。**

**一句话**：跨线程投递 = **传"命令"不传"数据"**（lambda 零拷贝转移所有权），开销在微秒级调度，靠"HIGH 优先级解码队列 + 高频留同线程 + 不跨 JNI"控制住。数据路径（编解码）才是性能大头。

### 20.6.3 门面对做引擎者是"双刃剑"

**门面对使用者友好，但对引擎开发者是"障碍"**：
- 门面把内部藏起来，意味着**改内部结构时要保证门面接口不变**（否则外部崩）
- 门面是"稳定契约"，但内部可自由演进——**这正是门面对做引擎的启示**：优化引擎内部时，只要守住 `PeerConnectionFactory` 门面接口，LiveKit 就不用改

**双刃剑**：
- 约束你"对外接口要稳定"
- 但也**解放你"内部随便优化"**

**这正是做引擎想要的——内部自由，契约稳定。**
