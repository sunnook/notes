# WebRTC 原生库模块架构分析

> 读者画像：具备 C/C++ 经验，熟悉高级 C++ 用法但需要补充；希望理解 webRTC 库的架构分层、模块协作、数据流与控制流。

---

## 目录

| 章节 | 标题 | 摘要 |
|---|---|---|
| 第 1 章 | 工程概览 | 5 层架构总览、文件夹-模块对应关系表（26 个模块）、核心概念速查 |
| 第 2 章 | 底层基础设施 —— rtc_base | 线程/消息系统、Socket 抽象、sigslot 信号槽、scoped_refptr、Proxy 模式 |
| 第 3 章 | API 层 —— api/ | PeerConnectionInterface 标准 API、MediaStream/Track、Proxy 跨线程访问 |
| 第 4 章 | 信令与媒体控制层 —— pc/ | PeerConnection 实现、JsepTransportController、RtpTransceiver、DataChannel、SDP 协商控制流 |
| 第 5 章 | Call 层 —— call/ | Call 类、音视频 Send/Receive Stream、RTP/RTCP Demuxer、三层连接机制 |
| 第 6 章 | 核心处理模块 —— modules/ | 音频编解码/设备/处理(AEC/NS/AGC/VAD)、视频编解码/采集/处理、拥塞控制、pacing、RTP/RTCP |
| 第 7 章 | 编解码实现 —— video/ + common_audio/ + common_video/ | VideoStreamEncoder、common_audio DSP 工具、common_video 工具、SIMD 优化 |
| 第 8 章 | P2P 与网络层 —— p2p/ | STUN 协议、ICE 候选类型、NAT 穿透原理 |
| 第 9 章 | 媒体引擎桥接层 —— media/engine/ | WebRTCMediaEngine 桥接、WebRTCVoiceEngine、WebRTCVideoEngine、SimulcastEncoderAdapter |
| 第 10 章 | SDK 与平台适配 —— sdk/ | Android JNI 桥接、Objective-C 桥接 |
| 第 11 章 | 完整业务流程分析 | 呼叫建立全流程（6 阶段）、音频发送/接收完整路径、视频发送/接收完整路径、DataChannel 流、拥塞控制闭环、分层调用关系图 |
| 第 12 章 | C++ 高级技巧在 WebRTC 中的应用 | 零拷贝设计、跨线程编程（Proxy/WeakPtr）、类型擦除、内存池、SIMD 内联汇编、编译期线程安全注解 |

---

## 分层路径-模块对应关系表（索引）

按 **架构分层** 排列，方便快速查阅某个路径对应哪个模块、某个模块在哪个层：

| 层 | 路径 | 模块名 | 一句话说明 |
|---|---|---|---|
| **L5 应用层** | `examples/peerconnection/` | 示例应用 | 完整 PeerConnection 使用示例 |
| | `sdk/android/` | Android SDK | Android JNI 桥接 |
| | `sdk/objc/` | iOS SDK | Objective-C 桥接 |
| **L4 API 层** | `api/` | 标准 API 接口 | PeerConnectionInterface / MediaStream / RTP 参数 / Proxy |
| | `pc/` | PeerConnection 实现 | SDP 协商、ICE 状态机、RtpTransceiver、DataChannel、MediaSession |
| **L3 呼叫层** | `call/` | Call 管理层 | 音视频流调度中心，管理 Send/Receive Stream 生命周期 |
| | `media/engine/` | 媒体引擎桥接 | 连接 pc/call 层与 modules 层的统一资源管理 |
| **L2 处理层** | `modules/audio_device/` | 音频设备 (ADM) | 跨平台音频硬件抽象 |
| | `modules/audio_processing/` | 音频处理 (APE) | AEC 回声消除 / NS 降噪 / AGC 自动增益 / VAD 语音检测 |
| | `modules/audio_coding/` | 音频编码 | Opus / G722 / iSAC 编解码调度 |
| | `modules/video_capture/` | 视频采集 | 跨平台摄像头采集抽象 |
| | `modules/video_coding/` | 视频编码 | VP8/VP9/H264 编解码调度 + JitterBuffer + NACK + FEC |
| | `modules/video_processing/` | 视频处理 (VPM) | 帧裁剪 / 旋转 / 缩放 |
| | `modules/congestion_controller/` | 拥塞控制 | GCC / Remote Bitrate Estimator / Generic Rate Control |
| | `modules/pacing/` | 数据包整形 | 令牌桶 pacing，平滑发送速率 |
| | `modules/rtp_rtcp/` | RTP/RTCP | RTP 封包/解包、RTCP 报告生成 |
| | `modules/desktop_capture/` | 桌面捕获 | 屏幕/窗口捕获抽象 |
| | `modules/remote_bitrate_estimator/` | 远程带宽估计 | 基于 RTCP 反馈的带宽估计 |
| **L1 基础设施** | `rtc_base/` | 基础设施层 | 线程/消息/Socket/SSL/日志/同步/时间 |
| | `p2p/` | P2P 网络层 | STUN 协议 / ICE 候选收集 |
| | `video/` | 视频工具 | VideoStreamEncoder / 视频适配 / 质量观测 |
| | `audio/` | 音频工具 | 音频流封装 / 重采样 / 混音 |
| | `common_audio/` | 公共音频工具 | signal_processing / resampler / FIR 滤波 / VAD |
| | `common_video/` | 公共视频工具 | I420 缓冲池 / libyuv 集成 / 帧率估计 |
| | `logging/` | 日志子系统 | LogMessage / LogSink |
| | `system_wrappers/` | 系统封装 | Clock / FieldTrial / Metrics |

---

## 第 1 章：工程概览

### 1.1 工程定位与架构分层总览

WebRTC 原生库是一个约 150 万行 C++ 代码的大型项目，提供浏览器和移动端应用的实时通信（RTC）能力。其核心目标是让不同设备、不同平台的应用能够通过 P2P 或转发方式，实现低延迟的音视频通话和数据传输。

整个工程按 **架构分层** 可分为以下五层（自顶向下）：

```
┌─────────────────────────────────────────────────────────────────┐
│  第 5 层：应用层 (examples/, sdk/)                               │
│  示例应用 (peerconnection example)、Android JNI、Objective-C 桥接 │
├─────────────────────────────────────────────────────────────────┤
│  第 4 层：标准 API 层 (api/, pc/)                                 │
│  PeerConnectionInterface (W3C/IETF 标准 API)、SDP 协商、ICE 状态机│
├─────────────────────────────────────────────────────────────────┤
│  第 3 层：呼叫管理层 (call/)                                      │
│  Call 类 — 音视频流的统一调度中心，管理 Send/Receive Stream 生命周期│
├─────────────────────────────────────────────────────────────────┤
│  第 2 层：核心处理模块层 (modules/, video/, audio/)               │
│  音频编解码、音频处理(AEC/NS/AGC)、视频编解码、拥塞控制、RTP/RTCP │
│  视频采集/桌面捕获、视频处理、 pacing                             │
├─────────────────────────────────────────────────────────────────┤
│  第 1 层：基础设施层 (rtc_base/, p2p/, logging/, system_wrappers/│
│  线程、消息队列、Socket、SSL、日志、同步原语、时间、NAT 类型定义    │
└─────────────────────────────────────────────────────────────────┘
```

**关键设计原则：**
- **分层解耦**：上层通过抽象接口调用下层，不依赖具体实现
- **线程隔离**：不同层运行在不同线程上，通过 Proxy 模式跨线程访问对象
- **Observer 模式**：模块间广泛使用回调接口进行事件通知
- **零拷贝**：音视频帧在管道中传递时尽量使用 `scoped_refptr<VideoFrame>` 零拷贝

### 1.2 文件夹与模块对应关系表

| 文件夹路径 | 模块名称 | 核心职责 | 关键字/类 |
|---|---|---|---|
| **api/** | API 接口层 | 对外暴露的标准接口（WebRTC C++ API） | `PeerConnectionInterface`, `MediaStreamInterface`, `RtpSenderInterface`, `RtpReceiverInterface`, `DataChannelInterface` |
| **pc/** | PeerConnection 实现 | 信令管理、SDP 协商、ICE 状态机、媒体路由 | `PeerConnection`, `JsepTransportController`, `RtpTransceiver`, `MediaSession`, `SctpTransport` |
| **call/** | 呼叫管理层 | 音视频流的统一调度，RTP/RTCP 收发 | `Call`, `AudioSendStream`, `VideoSendStream`, `AudioReceiveStream`, `VideoReceiveStream`, `RtpDemuxer` |
| **modules/audio_coding/** | 音频编码模块 | 音频编解码调度（G722/Opus/iSAC） | `AudioCodingImpl`, `AudioEncoderFactory`, `AudioDecoderFactory` |
| **modules/audio_device/** | 音频设备模块 | 音频硬件抽象层（跨平台） | `AudioDeviceModule` (ADM) |
| **modules/audio_processing/** | 音频处理模块 | AEC(回声消除)/NS(降噪)/AGC(自动增益)/VAD | `AudioProcessing` (APE) |
| **modules/video_coding/** | 视频编码模块 | 视频编解码调度（VP8/VP9/H264）+ JitterBuffer + NACK + FEC | `VideoCodingImpl`, `JitterBuffer`, `NackModule`, `FrameBuffer` |
| **modules/video_processing/** | 视频处理模块 | 帧缓冲、旋转、裁剪、缩放 | `VideoProcessingModule` (VPM) |
| **modules/video_capture/** | 视频采集模块 | 摄像头采集抽象（跨平台） | `VideoCaptureModule` |
| **modules/congestion_controller/** | 拥塞控制模块 | 发送端/接收端拥塞控制、带宽估计 | `ReceiveSideCongestionController`, `GenericRateControl` |
| **modules/pacing/** | 数据包整形模块 | 控制数据包发送节奏，模拟管道带宽 | `PacedPacketRouter`, `BitrateCounter` |
| **modules/rtp_rtcp/** | RTP/RTCP 模块 | RTP 封包/解包、RTCP 报告生成 | `RtpRtcp`, `RtpPacketizer`, `RtcpHeader` |
| **modules/desktop_capture/** | 桌面捕获模块 | 屏幕/窗口捕获抽象 | `DesktopCapturer` |
| **modules/remote_bitrate_estimator/** | 远程带宽估计 | 基于 RTCP 反馈的带宽估计 | `RemoteBitrateEstimator` |
| **media/engine/** | 媒体引擎桥接 | 连接 pc/call 层与 modules 层的关键桥接 | `WebRTCMediaEngine`, `WebRTCVoiceEngine`, `WebRTCVideoEngine` |
| **rtc_base/** | 基础设施层 | 线程、消息、Socket、SSL、日志、同步 | `Thread`, `Socket`, `SignalThread`, `sigslot`, `scoped_refptr` |
| **p2p/** | P2P 网络层 | STUN 协议、ICE 候选收集 | `StunServer`, `StunProber`, `Candidate` |
| **video/** | 视频工具层 | 视频流编码、质量观测、帧处理 | `VideoStreamEncoder`, `VideoQualityObserver`, `CallStats` |
| **audio/** | 音频工具层 | 音频流封装、重采样、混音 | `AudioSendStream`, `AudioReceiveStream`, `RemixResample` |
| **common_audio/** | 公共音频工具 | 信号处理、Resampler、VAD、FIR 滤波 | `signal_processing`, `resampler`, `fir_filter` |
| **common_video/** | 公共视频工具 | I420 缓冲池、libyuv 集成、帧率估计 | `I420BufferPool`, `libyuv` |
| **sdk/** | SDK 平台适配 | Android JNI、Objective-C 桥接 | JNI 绑定代码 |
| **examples/peerconnection/** | 示例应用 | 完整的 PeerConnection 使用示例 | `main.cc`, `PeerConnectionApp` |
| **logging/** | 日志子系统 | 结构化日志 | `LogMessage` |
| **system_wrappers/** | 系统封装 | 操作系统 API 的跨平台封装 | `Clock`, `FieldTrial`, `Metrics` |

### 1.3 核心概念速查

| 概念 | 说明 | 所在层 |
|---|---|---|
| **PeerConnection** | WebRTC 标准 API 的核心对象，代表一次 P2P 连接。负责 SDP 协商、ICE 管理、媒体轨道添加/移除 | API + pc |
| **Call** | 内部类，管理实际的数据收发流。一个 PeerConnection 内部创建一个 Call 实例 | call |
| **RtpTransceiver** | 封装一个 RtpSender + RtpReceiver，代表一个方向的媒体传输（含音频或视频） | pc |
| **MediaStream / Track** | 媒体流的逻辑容器。一个 Stream 包含多个 Track（音频 Track、视频 Track） | api |
| **Channel** | pc 层内部概念，代表一个 RTP/RTCP 传输通道，绑定到具体网络接口 | pc |
| **JsepTransportController** | 管理所有传输层（ICE、DTLS、SCTP）的生命周期 | pc |
| **Module** | 所有 modules/ 下的模块都实现 Module 接口（`Init`/`RegisterSink`/`RegisterSource`/`Process`） | modules |
| **scoped_refptr** | WebRTC 自实现的引用计数智能指针，类似 `std::shared_ptr` 但线程安全 | rtc_base |
| **Proxy** | 跨线程对象访问代理，保证对象在其所属线程上被访问 | api/pc |
| **sigslot** | WebRTC 自实现的信号槽机制，类似 Qt 的 signals/slots | rtc_base |
| **ProcessThread** | 模块专用的工作线程，模块在 `Process()` 回调中处理音视频帧 | modules |

---

## 第 2 章：底层基础设施 —— rtc_base

`rtc_base/` 是整个 WebRTC 库的地基，所有上层模块都依赖它。它提供了线程、消息、网络、同步、时间、日志等基础能力。

### 2.1 线程与消息系统

WebRTC 采用 **单线程模型 + 消息队列** 的并发范式，而非传统的多线程共享内存模式。

**核心组件：**

- **`Thread`** (`thread.h/cc`): 代表一个线程及其消息队列。每个线程有唯一的消息队列，消息通过 `Post()` 投递。
  ```cpp
  // 典型用法：将函数投递到指定线程执行
  thread_->Post(RTC_FROM_HERE, this, &MyClass::DoWork, 0);
  ```
  每个类需要实现 `MessageHandler` 接口（`OnMessage` 虚函数）来接收消息。

- **`SignalThread`** (`signal_thread.h/cc`): `Thread` 的子类，支持信号槽机制。可以绑定回调函数，当消息到达时自动触发。

- **`PhysicalSocketServer`** (`physical_socket_server.h/cc`): 管理所有 Socket 的集合。`Thread::Process()` 内部调用 `SocketServer::Select()` 来多路复用 Socket I/O。

- **`ProcessThread`** (`modules/utility/include/process_thread.h`): 模块专用的工作线程，模块通过 `RegisterModule()` 注册自己，ProcessThread 周期性调用每个模块的 `Process()` 方法。这是音视频处理模块的核心调度器。

**消息投递流程：**
```
用户线程 A                          Thread B 的消息队列
┌──────────────┐                   ┌──────────────────────┐
│ PeerConnection│                  │ 消息队列 (MessageList)│
│               │── Post() ──────▶ │  - OnIceCandidate    │
│  (任意线程)    │                  │  - UpdateIceState    │
└──────────────┘                  │  - ProcessAudio      │
                                  │                      │
                                  │  ┌───────────────┐   │
                                  │  │ ProcessLoop() │   │
                                  │  │   OnMessage() │   │
                                  │  └───────────────┘   │
                                  └──────────────────────┘
```

**C++ 知识点 — 消息处理模式：**
WebRTC 的 `MessageHandler` 模式类似于 C++11 的 `std::function` + `std::async`，但做了线程安全的封装。核心思想是 **将函数调用转化为消息对象**，投递到目标线程的消息队列中，由目标线程的顺序执行来避免竞态条件。这比共享锁更简单、性能更好。

### 2.2 网络抽象层

WebRTC 将网络 Socket 抽象为跨平台的统一接口：

- **`Socket`** (`socket.h`): 抽象基类，定义 `Send`/`SendTo`/`ReceiveFrom` 接口。
- **`AsyncPacketSocket`** (`async_packet_socket.h`): 异步数据包 Socket，支持 UDP。
- **`AsyncTcpSocket`** (`async_tcp_socket.h`): 异步 TCP Socket。
- **`AsyncUdpSocket`** (`async_udp_socket.h`): 异步 UDP Socket 的具体实现。
- **`SocketFactory`** (`socket_factory.h`): 工厂接口，用于创建 Socket。
- **`VirtualSocketServer`** (`virtual_socket_server.h`): **虚拟 Socket 实现**，用于单元测试。它拦截所有 Socket 操作，在内存中模拟网络行为（延迟、丢包、带宽限制），是测试框架的核心组件。
- **`FirewallSocketServer`** (`firewall_socket_server.h`): 过滤 Socket 连接，用于安全检查。

**SSL/TLS 支持：**
- `openssl_adapter.h/cc`: 基于 OpenSSL 的 SSL Socket 适配
- `ssl_stream_adapter.h/cc`: SSL 流式传输适配
- `ssl_roots.h`: 内嵌的 SSL 根证书（约 200KB 的 C 数组）

### 2.3 同步原语与内存管理

**同步原语：**
- **`CriticalSection`** (`critical_section.h/cc`): 互斥锁封装，RAII 风格（`rtc::CritScope cs(&crit_)` 自动加锁/解锁）。
- **`Event`** (`event.h/cc`): 条件变量封装，用于线程间同步。
- **`ThreadChecker`** (`thread_checker.h`): 调试用线程检查器，确保对象只在创建它的线程上被访问。
- **`race_checker.h`**: 检测数据竞争的工具。

**引用计数与智能指针：**
- **`RefCountedBase`** (`ref_counted_base.h`): 引用计数基类，线程安全的 `AddRef()`/`Release()`。
- **`scoped_refptr<T>`** (`scoped_refptr.h`): 类似 `std::shared_ptr<T>`，但：
  - 引用计数操作是原子的（`rtc::AtomicOps`）
  - 指向的对象必须在特定线程上销毁（通过 `Release()` 返回 nullptr 时触发）
  - 支持 `Adopt()` 从裸指针创建
  ```cpp
  scoped_refptr<VideoFrame> frame = new VideoFrame(...);
  frame->AddRef();  // 引用计数 +1
  frame->Release(); // 引用计数 -1，为 0 时自动 delete
  ```

**sigslot 信号槽机制** (`callback.h`, `sigslot*`):
WebRTC 自实现的观察者模式，类似 Qt 的 signals/slots 或 C++11 的 `std::signal`（但 C++11 标准库没有 signal）。

```cpp
// 发布者
class Source {
 public:
  rtc::signal<void(int value)> *MySignal() { return &my_signal_; }
 private:
  rtc::signal<int> my_signal_;
  void Emit() { my_signal_.Emit(42); }
};

// 订阅者（通过继承 sigslot::has_slots<> 保证线程安全）
class Receiver : public sigslot::has_slots<> {
  void OnValue(int v) { /* 处理 */ }
};

// 连接
Source src;
Receiver recv;
src.MySignal()->Connect(&recv, &Receiver::OnValue);
```

**C++ 知识点 — sigslot 的实现原理：**
`sigslot` 使用 **头指针链表** 存储订阅者列表，`signal::Emit()` 遍历链表调用每个槽函数。关键设计是 `has_slots<>` 基类会在构造函数中将自己注册到一个全局的 slot 管理器中，析构时自动断开所有连接，防止悬空指针。这比 `std::function` 更安全（自动断开连接），但性能略低（遍历链表）。

### 2.4 时间、日志、其他工具

**时间：**
- **`Clock`** (`system_wrappers/include/clock.h`): 抽象时钟接口。测试中使用 `FakeClock`，生产中使用基于系统调用的 RealClock。
- **`timestamp_aligner.h/cc`**: RTP 时间戳对齐工具。
- **`time_utils.h/cc`**: 时间转换工具（微秒 <-> 毫秒 <-> RTP 时间戳）。

**日志：**
- **`LogMessage`** (`logging.cc`, `rtc_base/logging.h`): 分级日志系统（LS_VERBOSE/LS_INFO/LS_WARNING/LS_ERROR）。支持将日志输出到文件、网络或自定义 Sink。
- **`LogSink`** (`log_sinks.h`): 日志接收器接口，可注册多个 Sink。
- **`trace_event.h`**: 性能追踪事件宏，集成到 Chrome Tracing 系统。

**其他工具：**
- **`Random`** (`random.h`): 随机数生成。
- **`RateLimiter`** (`rate_limiter.h`): 令牌桶速率限制器。
- **`BitBuffer`** (`bit_buffer.h/cc`): 位操作缓冲区，用于 RTP/RTCP 包构建。
- **`CopyOnWriteBuffer`** (`copy_on_write_buffer.h/cc`): 写时复制缓冲区，零拷贝传递小数据。
- **`Location`** (`location.h/cc`): 记录代码位置（文件名 + 行号），用于错误报告。
- **`WeakPtr`** (`weak_ptr.h/cc`): 弱引用指针，对象销毁后自动置空，防止悬空指针。

### 2.5 任务队列系统 (TaskQueue)

`task_queue/` 和 `task_queue/` (api/) 提供了跨平台的异步任务执行器：

- **`TaskQueue`** (`rtc_base/task_queue.h`): 抽象任务队列，支持 `Post()` 投递函数。
- **`TaskQueueStdlib`** (`task_queue_stdlib.cc`): 基于 `std::thread` + `std::queue` 的实现。
- **`TaskQueueGcd`** (`task_queue_gcd.cc`): 基于 macOS/iOS GCD (Grand Central Dispatch) 的实现。
- **`TaskQueueLibevent`** (`task_queue_libevent.cc`): 基于 libevent 的实现。

**C++ 知识点 — 任务队列与 std::function：**
`TaskQueue::Post()` 接受 `std::function<void()>` 作为参数，通过类型擦除将任意可调用对象（lambda、bind、函数指针）统一封装。这是 C++11 引入的核心特性，WebRTC 大量使用它来实现回调传递。

```cpp
task_queue_->Post([this, data = std::move(data)]() {
  this->ProcessData(std::move(data));
});
```

### 2.6 rtc_base 依赖关系图

```
rtc_base/ (基础设施层)
├── Thread / Message        → 所有上层模块的线程基础
├── Socket / SocketServer   → 所有网络通信基础
├── CriticalSection / Event → 同步原语
├── scoped_refptr           → 引用计数智能指针
├── sigslot                 → 信号槽机制
├── Clock                   → 时间抽象
├── LogMessage              → 日志系统
└── TaskQueue               → 异步任务执行

被以下层直接依赖：
  api/  → 依赖 scoped_refptr, ref_counted_base, callback, thread
  pc/   → 依赖 Thread, Socket, sigslot, TaskQueue
  call/ → 依赖 ProcessThread, Clock, scoped_refptr
  modules/ → 依赖 Module 接口, ProcessThread, Clock
```

---

## 第 3 章：API 层 —— api/

`api/` 是 WebRTC 库对外暴露的标准 C++ API 接口层。根据 `native-api.md` 的规范，只有 `api/` 目录下的头文件属于正式 API，其他目录的文件可能在任何版本中发生不兼容变更。

### 3.1 PeerConnectionInterface（标准 API 入口）

`peer_connection_interface.h` 是整个 WebRTC 库最大的头文件（约 69KB），定义了 W3C WebRTC API 的 C++ 映射：

```cpp
// 核心接口
class PeerConnectionInterface {
 public:
  struct Config {                       // 配置参数
    rtc::ArrayView<const IceServer> ice_servers;
    RtcConfiguration rtc_config;
    // ... STUN/TURN 服务器、TLS 配置等
  };

  // 生命周期
  static absl::UniquePtr<PeerConnection> Create(
      const PeerConnectionInterface::Config& config,
      PeerConnectionObserver* observer);

  // SDP 操作
  virtual void CreateOffer(CreateSessionDescriptionObserver* observer) = 0;
  virtual void CreateAnswer(CreateSessionDescriptionObserver* observer) = 0;
  virtual void SetLocalDescription(
      SessionDescriptionObserver* observer) = 0;
  virtual void SetRemoteDescription(
      absl::UniquePtr<SessionDescription> desc,
      SessionDescriptionObserver* observer) = 0;

  // 媒体管理
  virtual absl::UniquePtr<RtpSenderInterface> AddTrack(
      absl::UniquePtr<MediaStreamTrackInterface> track,
      const std::vector<std::string>& stream_ids) = 0;
  virtual absl::UniquePtr<DataChannelInterface> CreateDataChannel(
      const std::string& label,
      const DataChannelInit* config) = 0;

  // 状态查询
  virtual PeerConnectionInterface::SignalingState GetSignalingState() const = 0;
  virtual void GetStats(RtcEventLog* event_log,
                        PeerConnectionObserver* observer) = 0;

  virtual PeerConnectionObserver* observer() = 0;
};
```

**关键设计：**
- **工厂模式 + Observer**：`PeerConnection::Create()` 创建对象，通过 `PeerConnectionObserver` 回调通知状态变化（ICE 候选、连接状态、媒体轨道等）。
- **异步操作**：所有耗时操作（SDP 生成、ICE 收集）都是异步的，通过 Observer 接口回调结果。
- **absl::UniquePtr**：大量使用 absl 智能指针管理所有权转移。

### 3.2 MediaStream / MediaStreamTrack

```cpp
// media_stream_interface.h
class MediaStreamInterface {
 public:
  virtual std::vector<MediaStreamTrackInterface*> GetTracks() = 0;
  virtual AudioTrackVector GetAudioTracks() = 0;
  virtual VideoTrackVector GetVideoTracks() = 0;
  virtual void RemoveTrack(MediaStreamTrackInterface* track) = 0;
};

class MediaStreamTrackInterface {
 public:
  virtual const std::string& id() const = 0;
  virtual MediaStreamTrackInterface::State state() const = 0;
  virtual bool enabled() const = 0;
  virtual void set_enabled(bool enabled) = 0;
};
```

一个 `MediaStream` 包含多个 `MediaStreamTrack`（音频 Track + 视频 Track）。Track 是只读引用计数的，通过 `set_enabled()` 可以静音/暂停。

### 3.3 RTP/RTCP 参数接口

```cpp
// rtp_parameters.h
struct RtpParameters {
  std::string transaction_id;
  std::vector<RtpHeaderExtension> header_extensions;
  RtpEncodings encodings;        // 编码参数（码率、分辨率等）
  RtcpParameters rtcp;           // RTCP 参数
  std::vector<RtpCodecParameters> codecs;  // 支持的编解码器
};

struct RtpEncodingParameters {
  std::string rid;               // 流标识（用于 Simulcast）
  uint32_t max_bitrate_bps;      // 最大码率
  uint32_t max_framerate;        // 最大帧率
  uint32_t scale_resolution_down_by; // 缩放因子
};
```

### 3.4 Proxy 模式（跨线程对象访问）

WebRTC 采用严格的 **线程亲和性（thread affinity）** 模型：每个对象只能在其创建的线程上被访问。Proxy 模式通过代理对象实现跨线程调用：

```cpp
// proxy.h
template <typename WrapType, typename UnwrapType, typename Tag>
class Proxy;

// 使用示例：
// 1. 在目标线程上创建代理
auto proxy = Proxy<RtpSender, RtpSenderInternal, RtpSenderTag>::Create(
    worker_thread_, new RtpSenderInternal(...));

// 2. 在主线程上调用 proxy->Call()，自动切换到 worker 线程
proxy->Call(RTC_FROM_HERE, [proxy, params]() {
  proxy->internal()->SetParameters(params);
});
```

**工作原理：**
- `Proxy<T>` 持有 `worker_thread_` 的引用
- `Call()` 方法将 lambda 投递到 `worker_thread_` 的消息队列
- 目标线程收到消息后，执行 lambda 中的内部方法调用
- 调用结果通过返回值或回调函数传回

**C++ 知识点 — Proxy 模式的模板技巧：**
Proxy 使用 **Tag 模式** 区分不同类型的对象（`RtpSenderTag`、`AudioTrackTag` 等），`UnwrapType` 是内部实现类，`WrapType` 是对外接口。`Proxy::Call()` 使用 `std::function` 将回调封装为消息，投递到目标线程。这种模式在 Java 的 `Handler` 模式和 Android 的 `Looper` 模式中也有类似应用。

### 3.5 其他重要 API 接口

- **`data_channel_interface.h`**: DataChannel 接口，支持可靠/不可靠传输。
- **`dtls_transport_interface.h`**: DTLS 传输接口。
- **`ice_transport_interface.h`**: ICE 传输接口。
- **`jsep.h`**: JSEP（JavaScript Session Establishment Protocol）的 C++ 映射，定义 SDP 和 ICE 候选的 C++ 结构。
- **`media_types.h`**: 媒体类型定义（audio/video）和 SDP 属性。
- **`rtp_receiver_interface.h` / `rtp_sender_interface.h`**: RTP 收发接口。
- **`rtp_transceiver_interface.h`**: RTP 收发器接口（发送 + 接收合一）。
- **`stats_types.h`**: 统计指标的数据结构定义。
- **`rtc_error.h`**: 错误类型定义（`RTCError` 类）。
- **`ref_counted_base.h`**: 引用计数基类（也在 rtc_base 中，api 层也使用）。
- **`scoped_refptr.h`**: 引用计数智能指针（也在 rtc_base 中，api 层也使用）。
- **`proxy.h`**: 跨线程代理模板（api 层核心组件）。

### 3.6 API 层依赖关系

```
api/ (标准 API 层)
├── peer_connection_interface.h  → 对外核心入口
├── media_stream_interface.h     → 媒体流抽象
├── rtp_*.h                      → RTP 参数接口
├── jsep.h                       → SDP/ICE 数据结构
├── proxy.h                      → 跨线程访问
├── scoped_refptr.h              → 引用计数
└── stats_types.h                → 统计数据结构

直接依赖: rtc_base/ (thread, ref_count, callback, scoped_refptr)
被以下层依赖:
  pc/   → 实现 api 接口
  examples/ → 使用 api 接口
```

---

## 第 4 章：信令与媒体控制层 —— pc/

`pc/` 是整个 WebRTC 库的 **核心控制层**，实现了 PeerConnection 的全部逻辑，包括 SDP 协商、ICE 管理、媒体路由、DataChannel 等。它是连接 API 层（api/）和呼叫管理层（call/）的桥梁。

### 4.1 PeerConnection 实现

`peer_connection.cc`（约 314KB，最大的源文件）是 `PeerConnectionInterface` 的具体实现。

**核心职责：**

1. **SDP 协商状态机**：维护 `SignalingState`（stable, have-local-offer, have-remote-offer 等），按照 JSEP 模型管理 Offer/Answer 流程。
2. **创建和初始化底层对象**：创建 `Channel`、`RtpSender`、`RtpReceiver`、`RtpTransceiver` 等。
3. **管理媒体轨道的生命周期**：`AddTrack()` / `RemoveTrack()`。
4. **ICE 状态机**：跟踪 ICE 连接状态（new, connecting, connected, completed, failed, disconnected）。
5. **生成统计信息**：通过 `RtcStatsCollector` 收集。

**关键数据成员：**
```cpp
class PeerConnection : public PeerConnectionInternal {
 private:
  // SDP 协商
  SessionDescription* local_description_;      // 当前本地描述
  SessionDescription* pending_local_description_; // 待确认的本地描述
  SessionDescription* remote_description_;     // 远程描述

  // 传输层
  JsepTransportController* jsep_transport_controller_;

  // 媒体通道
  std::map<std::string, RtpTransceiver*> transceivers_;  // 按 mid 索引
  std::map<std::string, MediaStreamInterface*> streams_;  // 按 stream_id 索引

  // 数据通道
  DataChannelController data_channel_controller_;

  // 工厂
  PeerConnectionFactory* factory_;
};
```

### 4.2 JsepTransportController（传输层管理）

`jsep_transport_controller.h/cc`（约 65KB）管理所有传输层组件：

```
JsepTransportController
├── JsepTransport (ICE + DTLS) × N    // 每个媒体流一个传输
│   ├── IceTransport                  // ICE 协议
│   ├── DtlsTransport                 // DTLS 加密
│   └── RtpTransport / RtcpTransport  // RTP/RTCP 传输
├── SctpTransport                     // DataChannel 传输
└── BundleGroup                         // Bundle 组管理（多个媒体流复用一个 UDP 连接）
```

**关键功能：**
- **ICE 候选管理**：收集本地候选、添加远程候选、候选优先级排序
- **DTLS 握手**：管理 DTLS 连接状态
- **Bundle 支持**：WebRTC 的 Bundle 特性允许多个媒体流共享同一个 UDP 端口
- **传输选择**：根据 SDP 中的 `mid` 将 RTP/RTCP 包路由到正确的传输

### 4.3 RtpTransceiver / RtpSender / RtpReceiver

```
RtpTransceiver (pc/rtp_transceiver.h/cc)
├── RtpSender (pc/rtp_sender.h/cc)      // 发送方向
│   ├── MediaStreamTrack                // 媒体源
│   ├── RtpParameters                   // RTP 参数
│   └── Proxy → worker_thread_          // 跨线程代理
├── RtpReceiver (pc/rtp_receiver.h/cc)  // 接收方向
│   ├── MediaStreamTrack                // 产生的媒体轨道
│   └── Proxy → worker_thread_
└── Direction (sendonly/recvonly/active...)
```

一个 `RtpTransceiver` 封装了一个方向的完整传输链路。它既包含发送也包含接收，因为 WebRTC 的传输通常是双向的。

### 4.4 DataChannel（SCTP over DTLS）

```
DataChannel (pc/data_channel.cc/h)
├── DataChannelController (pc/data_channel_controller.cc/h)  // 管理所有 DataChannel
├── SctpTransport (pc/sctp_transport.cc/h)                   // SCTP 协议实现
│   ├── SctpDataChannelTransport                              // SCTP 到 DataChannel 的适配
│   └── 基于 DTLS 传输
├── 可靠模式 (ordered=true)：SCTP 保证顺序和完整性
└── 不可靠模式 (ordered=false)：类似 UDP，允许乱序和丢包
```

DataChannel 使用 **SCTP（Stream Control Transmission Protocol）** 作为传输协议，SCTP 运行在 DTLS 之上。这提供了：
- 多流传输（避免队头阻塞）
- 可靠/不可靠两种模式
- 消息边界保留

### 4.5 MediaSession（媒体会话管理）

`media_session.h/cc`（约 120KB）管理媒体会话的 SDP 生成和解析：

```cpp
class MediaSession {
  // SDP 属性
  std::string mid_;              // 媒体流标识
  std::string direction_;        // 方向 (sendrecv/sendonly/...)
  std::vector<std::string> msid_; // 媒体流 ID
  std::vector<MediaDescription> media_descriptions_; // 媒体描述

  // 编解码器协商
  std::vector<RtpCodecParameters> codecs_;
  std::vector<RtpHeaderExtension> header_extensions_;
};
```

**SDP 协商流程：**
```
PeerConnection::CreateOffer()
  └── PeerConnection::GenerateOffer()
        └── JsepTransportController::CreateTransceivers()
              └── MediaSession::CreateSdp()
                    └── WebRtcSdpGenerator (pc/webrtc_sdp.cc)
                          生成 SDP 文本

PeerConnection::SetRemoteDescription()
  └── JsepSessionDescription::Parse()
        └── WebRtcSdpParser (pc/webrtc_sdp.cc)
              解析 SDP 文本
                └── MediaSession::SetRemoteSdp()
                      └── 创建/更新 RtpTransceiver
```

### 4.6 控制流分析：从 API 调用到内部对象的完整链路

以 `AddTrack()` 为例，展示完整的控制流：

```
用户线程                                    PeerConnection 线程 (pc_thread_)
    │                                             │
    ├─ AddTrack(track, stream_ids)                │
    │  └─ Proxy::Call() ──────────────────────▶ │
    │                                             ├─ PeerConnection::AddTrack()
    │                                             │   ├─ 创建 RtpSender
    │                                             │   │   └─ Proxy::Create(RtpSender, ...)
    │                                             │   ├─ 创建 RtpTransceiver
    │                                             │   │   ├─ sender_ = RtpSender
    │                                             │   │   └─ receiver_ = RtpReceiver (pending)
    │                                             │   ├─ 添加到 transceivers_ map
    │                                             │   └─ 通知 MediaSession
    │                                             │       └─ 标记需要重新生成 SDP
    │                                             │
    ├─ CreateOffer(observer)                      │
    │  └─ Proxy::Call() ──────────────────────▶ │
    │                                             ├─ PeerConnection::GenerateOffer()
    │                                             │   ├─ 遍历所有 transceivers_
    │                                             │   │   └─ 为每个 transceiver 创建 SDP media line
    │                                             │   └─ WebRtcSdpGenerator::GenerateSdp()
    │                                             │       └─ 生成 SDP 文本
    │                                             │
    │◀── observer->OnCreateOffer() ──────────────┤
    │      (SDP text)                             │
```

**关键观察：**
1. API 层的调用总是通过 `Proxy::Call()` 切换到 `pc_thread_` 执行
2. `PeerConnection` 是单线程对象，所有操作必须在 pc_thread_ 上执行
3. 媒体数据流（RTP 包收发）运行在独立的 `worker_thread_` 上，与信令线程分离

---

## 第 5 章：Call 层 —— call/

`call/` 是整个 WebRTC 库的 **呼叫管理层**，是连接 pc 层（控制）和 modules 层（处理）的关键枢纽。`Call` 类管理所有实际的音视频数据收发流。

### 5.1 Call 类：音视频流的统一调度中心

`Call` 是一个工厂类，负责创建和销毁 `AudioSendStream`、`VideoSendStream`、`AudioReceiveStream`、`VideoReceiveStream` 等流对象。

```cpp
class Call {
 public:
  // 工厂方法：创建/销毁各类流
  AudioSendStream* CreateAudioSendStream(const AudioSendStream::Config&);
  void DestroyAudioSendStream(AudioSendStream*);
  AudioReceiveStream* CreateAudioReceiveStream(const AudioReceiveStream::Config&);
  void DestroyAudioReceiveStream(AudioReceiveStream*);
  VideoSendStream* CreateVideoSendStream(VideoSendStream::Config, VideoEncoderConfig);
  void DestroyVideoSendStream(VideoSendStream*);
  VideoReceiveStream* CreateVideoReceiveStream(VideoReceiveStream::Config);
  void DestroyVideoReceiveStream(VideoReceiveStream*);

  // 接收 RTP/RTCP 包的入口
  virtual PacketReceiver* Receiver() = 0;

  // 获取发送传输控制器
  RtpTransportControllerSendInterface* GetTransportControllerSend() = 0;

  // 获取统计信息
  Stats GetStats() const;
};
```

**关键设计：**
- 一个 `Call` 实例对应一次完整的通话（一个 remote endpoint）
- 所有流共享同一个带宽估计（`GetStats().send_bandwidth_bps`）
- `Call` 运行在独立的 **call thread** 上，通过 `ProcessThread` 调度模块处理

### 5.2 AudioSendStream / AudioReceiveStream

```
AudioSendStream (call/audio_send_stream.h/cc)
├── ChannelSend (modules/audio_processing 层)
│   ├── 音频编码 (audio_coding module)
│   ├── RTP 封包 (rtp_rtcp module)
│   └── 拥塞控制反馈
├── AudioState
└── RtpVideoSender (复用视频发送的传输层)

AudioReceiveStream (call/audio_receive_stream.h/cc)
├── ChannelReceive
│   ├── RTP 解包 (rtp_rtcp module)
│   ├── 音频解码 (audio_coding module)
│   └── 音频渲染回调
└── AudioState
```

**音频发送流程：**
```
应用层 (音频帧)
    │
    ▼
AudioSendStream::EncodeAndEncodeCallback()
    │
    ├── 1. 音频编码 (audio_coding module: Opus/G722/iSAC)
    │     └─ 原始 PCM → 编码后的音频数据
    │
    ├── 2. 拥塞控制检查 (congestion_controller)
    │     └─ 根据带宽估计决定是否发送
    │
    ├── 3. RTP 封包 (rtp_rtcp module)
    │     └─ 编码数据 + RTP 头 → RTP 包
    │
    └── 4. 发送 (RtpTransportControllerSend)
          └─ 通过 Socket 发送出去
```

### 5.3 VideoSendStream / VideoReceiveStream

```
VideoSendStream (call/video_send_stream.h/cc)
├── VideoSendStreamImpl
│   ├── 视频编码 (video_coding module: VP8/VP9/H264)
│   ├── 帧适配 (adaptation: 分辨率/码率自适应)
│   ├── RTP 封包 (rtp_rtcp module)
│   ├── NACK 重传 (video_coding: NackModule)
│   ├── FEC 生成 (video_coding: Forward Error Correction)
│   └── Pacing (pacing module)
│
VideoReceiveStream (call/video_receive_stream.h/cc)
├── VideoReceiveStreamImpl
│   ├── RTP 解包 (rtp_rtcp module)
│   ├── JitterBuffer (video_coding: 乱序重组 + 抖动缓冲)
│   ├── NACK 请求 (video_coding: NackModule)
│   ├── 视频解码 (video_coding module)
│   ├── FlexFEC 恢复 (flexfec_receive_stream)
│   └── 帧输出回调 → 渲染层
```

**视频发送的关键特性：**

1. **Simulcast（ simulcast ）**：同时以多个分辨率/码率发送同一视频流
   ```cpp
   // 三个 simulcast 层：低/中/高
   RtpEncodingParameters low;  low.scale_resolution_down_by = 4;
   RtpEncodingParameters mid;  mid.scale_resolution_down_by = 2;
   RtpEncodingParameters high; // 原始分辨率
   ```
   实现：`SimulcastEncoderAdapter`（media/engine/）将一帧视频复制并编码为多个分辨率。

2. **视频适配（Adaptation）**：根据网络状况自动降低视频分辨率
   - `video/adaptation/` 目录中的 `VideoAdaptationController`
   - 监控带宽估计，当带宽下降时降低分辨率

3. **NACK（负确认重传）**：丢包时请求重传
   - `NackModule` 维护已发送包的列表
   - 收到 RTCP NACK 后重新发送指定包

4. **FEC（前向纠错）**：发送冗余数据包，丢包时可直接恢复
   - `FlexFEC` 是 WebRTC 的 FEC 方案

### 5.4 RTP/RTCP Demuxer

```cpp
// rtp_demuxer.cc
class RtpDemuxer : public PacketReceiver {
 public:
  // 所有收到的 RTP 包先到这里
  bool ReceivePacket(PacketType type, const Packet& packet) override;
  // 根据 RTP header 中的 SSRC 和 payload type 分发到对应的接收流
};

// rtcp_demuxer.cc
class RtcpDemuxer : public RtcpPacketSinkInterface {
 public:
  // 根据 RTCP 包类型分发：
  // - RR (Receiver Report) → 对应的 RtpReceiver
  // - FIR (Full Intra Request) → 对应的 VideoReceiver
  // - NACK → NackModule
  // - REMB (Receiver Estimated Maximum Bitrate) → 拥塞控制
};
```

**RTP 包分发流程：**
```
网络 Socket 收到 RTP 包
    │
    ▼
Call::Receiver() → RtpDemuxer::ReceivePacket()
    │
    ├── SSRC 匹配 → RtpReceiver (音频/视频)
    │     └─ AudioReceiveStream / VideoReceiveStream
    │
    └── 未匹配 → 丢弃或记录日志
```

### 5.5 数据流：Call 如何连接 pc 层与 modules 层

```
pc/ 层                                    call/ 层                              modules/ 层
────────────                                ──────────                              ─────────
PeerConnection                              Call                                  AudioCodingImpl
  │                                           │                                       AudioProcessing
  ├─ 创建 RtpTransceiver                       │                                       VideoCodingImpl
  │   └─ 创建 AudioSendStream                  │                                       RtpRtcp
  │       └─ 传入 Config                       │                                       CongestionController
  │           ├─ ssrc                          │                                       PacedPacketRouter
  │           ├─ audio_mixer                   │                                       VideoCapture
  │           ├─ audio_decoder                 │                                       DesktopCapture
  │           └─ network_state                 │
  │                                           │
  │                                           │  音频发送:                            │
  │                                           ├─ AudioSendStream::Process()          │
  │                                           │   ├─ audio_coding_->Encode()        │◀── 编码
  │                                           │   ├─ rtp_rtcp_->SendRtp()          │◀── RTP 封包
  │                                           │   └─ transport_controller_->Send() │◀── 发送
  │                                           │
  │                                           │  音频接收:                            │
  │                                           ├─ RtpDemuxer → AudioReceiveStream    │
  │                                           │   ├─ rtp_rtcp_->ProcessRtp()        │◀── RTP 解包
  │                                           │   ├─ audio_coding_->Decode()        │◀── 解码
  │                                           │   └─ audio_decoder_->Decode()       │◀── 渲染回调
```

**核心观察：**
- `Call` 是 **数据平面（data plane）** 的核心，所有 RTP/RTCP 包的处理都经过它
- `pc/` 是 **控制平面（control plane）**，负责建立/拆除连接、协商参数
- `modules/` 是 **处理平面（processing plane）**，执行实际的编解码、音频处理、拥塞控制等
- 三层通过 **回调接口** 和 **模块注册** 机制连接，松耦合

---

## 第 6 章：核心处理模块 —— modules/

`modules/` 是整个 WebRTC 库的 **处理平面**，包含所有实际的音视频处理、网络传输和拥塞控制逻辑。每个模块都实现 `Module` 接口：

```cpp
class Module {
 public:
  virtual int Init() = 0;
  virtual int RegisterSink(PacketSinkInterface* sink) = 0;
  virtual int RegisterSource(PacketSource* source) = 0;
  virtual int Process() = 0;  // 被 ProcessThread 周期性调用
};
```

### 6.1 audio_coding（音频编码模块）

`modules/audio_coding/` 管理所有音频编解码器的调度和生命周期。

```
AudioCodingImpl
├── AudioEncoder (编码器实例)
│   ├── AudioEncoderOpus       (Opus 编解码器)
│   ├── AudioEncoderG722       (G722 编解码器)
│   ├── AudioEncoderIsac       (iSAC 编解码器)
│   └── AudioEncoderNone       (无编码，透传)
├── AudioDecoder (解码器实例)
│   ├── AudioDecoderOpus
│   ├── AudioDecoderG722
│   ├── AudioDecoderIsac
│   └── AudioDecoderGeneric    (通用 PCM 解码器)
├── CodecInst                   // 编解码器实例描述
└── WebRtcVoiceModule             // 与 VoE 层的桥接
```

**关键流程：**
```
Encode():
  输入: AudioFrame (16kHz/48kHz PCM, 10ms 帧)
    │
    ├── 重采样 (如果输入采样率与编码器不匹配)
    ├── 编码 (调用具体编码器)
    │   └─ PCM → 编码后的字节流
    │
    └─ 输出: 编码后的数据 + 时间戳 + SSRC
```

**C++ 知识点 — 工厂模式 + 策略模式：**
`AudioCodingImpl` 使用 **工厂模式** 创建编码器/解码器实例，通过 `CodecInst` 结构体描述编解码器参数（名称、采样率、通道数、payload type）。编码器和解码器是 **策略对象**，可以在运行时动态替换（通过 `SetChannelParams()`）。

### 6.2 audio_device（音频设备模块）

`modules/audio_device/` 提供跨平台的音频硬件抽象层（ADM = AudioDeviceModule）。

```
AudioDeviceModule (ADM)
├── Platform-specific 实现
│   ├── LinuxAlsa  (ALSA - Advanced Linux Sound Architecture)
│   ├── LinuxPulse (PulseAudio)
│   ├── MacCoreAudio (Core Audio)
│   ├── WindowsWave (Windows Wave API)
│   └── WindowsCoreAudio (Windows Core Audio)
├── 录音 (Recording)
│   ├── StartRecording() / StopRecording()
│   ├── PlayoutAudioData (回调：从模块获取播放音频数据)
│   └── RecordingAudioData (回调：模块产生的录音数据)
├── 播放 (Playout)
│   ├── StartPlayout() / StopPlayout()
│   └── Volume 控制
└── 事件通知 (Event)
    ├── AudioProcessingModule (APM) 回调
    └── BufferLevel 通知
```

**数据流：**
```
麦克风 → ADM (录音回调) → APE (音频处理) → audio_coding (编码)
扬声器 ← ADM (播放回调) ← APE (音频处理) ← audio_coding (解码)
```

### 6.3 audio_processing（音频处理模块 — APE）

`modules/audio_processing/` 是 WebRTC 音频处理的核心，包含多个处理单元：

```
AudioProcessing (APE)
├── AudioBuffer               // 音频帧缓冲与混音
│   ├── Mix()                 // 混入本地播放音频（AEC 需要）
│   ├── Push()                // 推送麦克风音频
│   └── Pull()                // 拉取处理后的音频
│
├── EchoControlMobile (AEC)   // 回声消除
│   ├── AECM (Mobile 版本，低质量低 CPU)
│   ├── AEC3 (高级版本，高质量)
│   │   └─ 需要参考信号（扬声器播放的音频）
│   └─ 原理：从麦克风信号中减去扬声器回声
│
├── NoiseSuppression (NS)     // 噪声抑制
│   └─ 基于频谱减法，识别并抑制非语音噪声
│
├── GainControl (AGC)         // 自动增益控制
│   ├── AGC1 (经典版本)
│   └── AGC2 (高级版本，自适应)
│       ├── VoiceIsolation    // 语音隔离
│       └─ 根据语音电平自动调整增益
│
├── VoiceDetection (VAD)      // 语音活动检测
│   └─ 判断当前帧是否包含语音
│
├── HighPassFilter            // 高通滤波（去除低频噪声）
├── TransientSuppressor       // 瞬态噪声抑制
├── LevelEstimator            // 信号电平估计
└── VoiceDetection            // 语音检测
```

**AEC（回声消除）原理：**
```
麦克风信号 = 远端回声 + 本地说话声 + 环境噪声
参考信号 = 扬声器播放的音频（已知）

AEC 工作流程：
1. 对齐：计算参考信号和麦克风信号的时间延迟
2. 滤波：使用自适应 FIR 滤波器模拟回声路径
3. 相减：从麦克风信号中减去估算的回声
4. 残余回声抑制：进一步降低残余回声
```

**C++ 知识点 — AudioBuffer 的零拷贝设计：**
`AudioBuffer` 内部维护一个环形缓冲区，存储多通道音频帧。各个处理单元（AEC、NS、AGC）通过 `AudioFrameView`（只读视图）访问音频数据，避免复制。`AudioFrameView` 本质是一个 **非拥有型视图（non-owning view）**，类似 `absl::Span<const int16_t>`。

### 6.4 video_coding（视频编码模块）

`modules/video_coding/` 管理视频编解码器和相关功能。

```
VideoCodingImpl
├── VideoEncoder (编码器实例)
│   ├── VideoEncoderVP8  (VP8 编码器)
│   ├── VideoEncoderVP9  (VP9 编码器)
│   └── VideoEncoderH264 (H.264 编码器)
├── VideoDecoder (解码器实例)
│   ├── VideoDecoderVP8
│   ├── VideoDecoderVP9
│   └── VideoDecoderH264
├── DecoderDatabase            // 解码器数据库
├── JitterBuffer               // 抖动缓冲
│   ├── 乱序重组
│   ├── 丢失检测
│   └─ 根据网络抖动动态调整缓冲大小
├── NackModule                 // NACK 重传管理
│   ├── 维护已发送包列表
│   └─ 处理 RTCP NACK 请求
├── FecController              // FEC 控制器
│   └─ FlexFEC 参数管理
├── FrameBuffer                // 帧缓冲（用于参考帧管理）
└── RtpFrameReferenceFinder    // RTP 帧引用查找
```

**JitterBuffer 工作原理：**
```
收到的 RTP 包 (可能乱序、有间隔)
    │
    ▼
JitterBuffer::IncomingPacket()
    │
    ├── 按 seq_num 排序
    ├── 检测丢失的包
    ├── 延迟交付（等待丢失包的重传或超时）
    │
    ▼
JitterBuffer::GetPacket()
    │
    └─ 输出连续、有序的帧
```

### 6.5 video_processing（视频处理模块 — VPM）

`modules/video_processing/` 提供视频帧的后处理功能：

```
VideoProcessingModule (VPM)
├── FrameCropping            // 帧裁剪
├── Rotation                 // 帧旋转 (90/180/270度)
├── Scaling                  // 帧缩放
├── ImageEnhancement         // 图像增强
├── FrameBuffer              // 帧缓冲管理
└── RenderVideoFrame         // 帧渲染
```

### 6.6 congestion_controller（拥塞控制模块）

`modules/congestion_controller/` 是 WebRTC 网络自适应的核心。

```
ReceiveSideCongestionController (接收端拥塞控制)
├── RemoteBitrateEstimator   // 远程带宽估计器
│   ├── 基于到达时间 (Bbr/Rtt)
│   ├── 基于 AbsSendTime header extension
│   └─ 输出: 估计的带宽值
│
├── GenericRateControl       // 通用速率控制
│   ├── 发送端速率控制
│   ├── 码率调整 (增加/降低)
│   └─ 输出: 目标码率
│
├── PacedPacketRouter        // 数据包整形路由
│   └─ 控制数据包发送速率
│
└── GenericControllerSend    // 综合控制器
    └─ 整合接收端和发送端估计

goog_cc/                     // Google 拥塞控制算法
└── 基于 RTT 和丢包的 PID 控制器

pcc/                         // Packet Conservation Congestion Control
└── 更先进的拥塞控制算法
```

**拥塞控制闭环：**
```
发送端                          网络                          接收端
  │                               │                               │
  │  ┌──── RTP 包 ──────────────▶ │ ──────────────▶              │
  │  │                           │ (拥塞/丢包)                    │
  │  │                           │                               │
  │  │                           │                               │
  │  │◀── RTCP RR ───────────────│ ◀── RTCP RR ─────────────────┤
  │  │◀── RTCP REMB ─────────────│ ◀── REMB 计算 ───────────────┤
  │  │                           │                               │
  │  │  RemoteBitrateEstimator   │                               │
  │  │  → 估计带宽下降            │                               │
  │  │                           │                               │
  │  │  GenericRateControl       │                               │
  │  │  → 降低发送码率            │                               │
  │  │                           │                               │
  │  └── 降低发送速率 ──────────▶ │                               │
  │                               │                               │
  │  (网络恢复，带宽增加)          │                               │
  │  │  → 缓慢增加发送码率         │                               │
  │  └──── 增加发送速率 ─────────▶ │                               │
```

### 6.7 pacing（数据包整形模块）

`modules/pacing/` 控制数据包的发送节奏，模拟一个固定带宽的管道：

```
PacedPacketRouter
├── PacedStream                  // 单个媒体的 pacing 流
│   ├── 维护发送队列
│   ├── 计算发送时间 (令牌桶)
│   └─ 按目标速率发送数据包
├── BitrateCounter               // 码率计数器
└── PacedSource                  // Pacing 数据源接口
```

**为什么需要 Pacing？**
- 避免突发发送（Burst）导致路由器缓冲区填满
- 平滑的发送速率使拥塞控制更准确
- 类似 TCP 的 **令牌桶算法 (Token Bucket)**

### 6.8 rtp_rtcp（RTP/RTCP 模块）

`modules/rtp_rtcp/` 实现 RTP 和 RTCP 协议的完整功能。

```
RtpRtcp (核心类)
├── RtpPacketSender              // RTP 发送接口
│   ├── SendRtp()                // 发送 RTP 包
│   ├── SendRtcp()               // 发送 RTCP 包
│   └─ 调用 RtpGenerator 构建 RTP 头
│
├── RtpGenerator                 // RTP 包生成
│   ├── 构建 RTP Header
│   ├── 添加 RTP Extension
│   └─ 管理 SSRC / seq_num / timestamp
│
├── RtcpGenerator                // RTCP 包生成
│   ├── SR (Sender Report)
│   ├── RR (Receiver Report)
│   ├── SDES (Source Description)
│   ├── BYE (Termination)
│   ├── APP (Application-specific)
│   └─ FIR / PLI / NACK / REMB / RTCP FB
│
├── RtcpReceiver                 // RTCP 接收处理
│   ├── 解析 RTCP 包
│   └─ 触发对应回调 (RR/FIR/PLI/NACK/REMB)
│
├── RtcpTransport                // RTCP 传输接口
└── RtcpStatistics               // RTCP 统计信息
```

### 6.9 video_capture（视频采集模块）

`modules/video_capture/` 提供跨平台的视频采集抽象。

```
VideoCaptureModule (VCM)
├── Platform-specific 实现
│   ├── LinuxV4L2       (Linux Video for Linux 2)
│   ├── MacAVFoundation   (macOS AVFoundation)
│   ├── MacCoreMedia      (macOS Core Media)
│   ├── WindowsDirectShow (Windows DirectShow)
│   └── WindowsMediaFoundation (Windows Media Foundation)
├── 摄像头控制
│   ├── StartCapture() / StopCapture()
│   ├── 分辨率/帧率设置
│   └─ 帧回调 (CaptureData)
└── 设备管理
    ├── EnumerateDevices()
    └─ 选择摄像头
```

### 6.10 desktop_capture（桌面捕获模块）

`modules/desktop_capture/` 提供屏幕/窗口捕获抽象。

```
DesktopCapturer (抽象基类)
├── DesktopFrame               // 桌面帧 (宽度/高度/像素数据)
├── ScreenCapturer             // 屏幕捕获
│   ├── LinuxX11
│   ├── LinuxWayland
│   ├── MacScreenCaptureKit
│   └── WindowsGraphicsCapture
└── WindowCapturer             // 窗口捕获
    └── Windows
```

### 6.11 模块间协作关系图

```
                    ┌─────────────────────────────────────┐
                    │         ProcessThread               │
                    │   (周期性调用各模块的 Process())       │
                    └──────┬──────────────────┬───────────┘
                           │                  │
              ┌────────────▼──────┐   ┌───────▼──────────┐
              │  Audio Processing  │   │ Video Processing  │
              │  Pipeline         │   │ Pipeline          │
              │                   │   │                   │
              │ ADM → APE → AC → │   │ VCM → VC → RTP →  │
              │ (录音→处理→编码→)  │   │ (采集→编码→RTP→)  │
              └───────────────────┘   └───────────────────┘

                    ┌─────────────────────────────────────┐
                    │     Congestion Control Loop         │
                    │                                     │
                    │  CallStats → GCC → Pacing → Socket  │
                    │  (统计 → 带宽估计 → 速率控制 → 发送)  │
                    └─────────────────────────────────────┘
```

**C++ 知识点 — Module 接口设计：**
`Module` 接口使用 **回调（Callback）** 和 **Sink/Source** 模式实现模块间的数据传递：
- `RegisterSink(PacketSinkInterface*)`: 注册数据包接收者
- `RegisterSource(PacketSource*)`: 注册数据包提供者
- `Process()`: 模块的主处理循环，由 ProcessThread 周期性调用

这种设计类似于 Linux 的 **管道（pipe）** 模型：模块通过注册 sink/source 形成数据处理链。每个模块只关心自己的输入和输出，不关心上下游模块的具体实现。

---

## 第 7 章：编解码实现 —— video/ + common_audio/ + common_video/

这一章介绍编解码的具体实现层，包括视频编码适配、音频信号处理工具和视频处理工具。

### 7.1 video/ — 视频流编码与质量观测

`video/` 目录包含视频流编码的核心实现和质量观测工具。

```
video/
├── video_stream_encoder.cc/h         // 视频流编码器
│   ├── 接收原始视频帧
│   ├── 调用编码器编码
│   ├── 管理编码后的帧
│   └─ 输出: 编码后的 EncodedFrame
│
├── video_send_stream_impl.cc/h       // 视频发送流实现
│   ├── 视频适配 (Adaptation)
│   ├── 编码调度
│   └─ 与 VideoStreamEncoder 协作
│
├── video_receive_stream2.cc/h        // 视频接收流实现
│   ├── 解码调度
│   ├── 帧输出
│   └─ 与解码器协作
│
├── call_stats.cc/h                   // 呼叫统计
│   ├── RTT 计算
│   ├── 丢包率统计
│   └─ 带宽估计辅助
│
├── video_quality_observer.cc/h       // 视频质量观测
│   ├── PSNR/SSIM 计算
│   └─ 视频质量评估
│
├── adaptation/                       // 视频适配
│   ├── VideoAdaptationController     // 分辨率自适应控制
│   └─ 根据带宽估计调整分辨率
│
└── video/
    ├── i420_buffer_pool.cc/h         // I420 缓冲池
    ├── video_frame_buffer.cc/h       // 视频帧缓冲
    └── libyuv/                       // libyuv 集成 (Google 的图像转换库)
```

**VideoStreamEncoder 工作流程：**
```
输入: VideoFrame (原始 YUV 帧)
    │
    ▼
VideoStreamEncoder::Encode()
    │
    ├── 1. 帧缓冲 (保存参考帧)
    ├── 2. 适配决策 (是否需要降低分辨率)
    │     └─ VideoAdaptationController
    │
    ├── 3. 帧转换 (I420 → 编码器需要的格式)
    │     └─ libyuv: 裁剪/旋转/缩放
    │
    ├── 4. 编码 (调用 VideoEncoder)
    │     └─ 原始帧 → EncodedFrame
    │
    └─ 输出: EncodedFrame (VP8/VP9/H264 编码数据)
```

### 7.2 common_audio/ — 公共音频工具

`common_audio/` 提供音频信号处理的基础工具。

```
common_audio/
├── signal_processing/                // 信号处理库 (SP)
│   ├── SPL_resample_fractional       // 分数倍重采样
│   ├── SPL_VoiceDetection            // 语音检测
│   ├── SPL_bitextraction             // 位提取
│   ├── SPL_convert_frame_fix_to_float // 定点/浮点转换
│   └─ 大量 DSP 原语 (乘加、滤波、FFT)
│
├── resampler/                        // 重采样器
│   ├── Resample                      // 任意采样率转换
│   └─ 支持 8kHz ~ 48kHz 转换
│
├── fir_filter/                       // FIR 滤波器
│   ├── FIRFilter                     // 通用 FIR 滤波器
│   ├── fir_filter_sse.cc             // SSE 加速 (x86)
│   ├── fir_filter_neon.cc            // NEON 加速 (ARM)
│   └─ 多平台 SIMD 实现
│
├── vad/                              // 语音活动检测
│   ├── WebRtc VadInit/VadProcess     // WebRTC VAD
│   └─ 高准确率的语音检测
│
├── ring_buffer.cc/h                  // 环形缓冲区
│   └─ 线程安全的 FIFO 缓冲区
│
├── wav_file.cc/h                     // WAV 文件读写
│   └─ 用于测试和调试
│
└── audio_converter.cc/h              // 音频格式转换
    └─ 通道数/采样率/位深转换
```

**C++ 知识点 — SIMD 优化：**
`common_audio/signal_processing/` 中的核心 DSP 操作（乘加、滤波、卷积）都有多个平台实现：
- 纯 C 实现（通用）
- SSE/SSE2 实现（x86）
- NEON 实现（ARM）
- NEON64 实现（ARM64）

通过 **条件编译** 选择最优实现：
```cpp
#if defined(WEBRTC_ARCH_X86) || defined(WEBRTC_ARCH_X86_64)
  #include "fir_filter_sse.h"
#elif defined(WEBRTC_ARCH_ARM_NEON)
  #include "fir_filter_neon.h"
#endif
```

### 7.3 common_video/ — 公共视频工具

`common_video/` 提供视频处理的基础工具。

```
common_video/
├── i420_buffer_pool.cc/h             // I420 缓冲池
│   ├── 预分配 I420 帧缓冲
│   └─ 避免频繁 malloc/free
│
├── libyuv/                           // libyuv 集成
│   ├── I420Rotate                    // I420 旋转
│   ├── I420Scale                     // I420 缩放
│   ├── I420ToI420                    // I420 复制
│   └─ 大量 YUV/RGB 转换和变换
│
├── frame_rate_estimator.cc/h         // 帧率估计器
│   └─ 根据时间戳计算实际帧率
│
├── bitrate_adjuster.cc/h             // 码率调整器
│   └─ 平滑调整码率
│
└── generic_frame_descriptor/         // 通用帧描述
    └─ 帧的元数据描述 (宽度/高度/编码格式等)
```

### 7.4 视频编解码器适配层

视频编解码器（VP8/VP9/H264）的具体实现在 `modules/video_coding/codecs/` 中：

```
modules/video_coding/codecs/
├── VP8/                              // VP8 编码器/解码器
│   ├── vp8_encoder.cc/h              // VP8 编码器实现
│   ├── vp8_decoder.cc/h              // VP8 解码器实现
│   └── include/vp8.h                 // VP8 外部接口
│
├── VP9/                              // VP9 编码器/解码器
│   ├── vp9_encoder.cc/h
│   ├── vp9_decoder.cc/h
│   └── include/vp9.h
│
└── H264/                             // H.264 编码器/解码器
    ├── h264_encoder.cc/h
    ├── h264_decoder.cc/h
    └── include/h264.h
```

**编解码器接口统一：**
```cpp
// GenericEncoder / GenericDecoder 是所有编解码器的基类
class GenericEncoder {
 public:
  virtual int InitEncode(const EncoderInstance& instance,
                         const EncoderSettings& settings) = 0;
  virtual int Encode(const VideoFrame& frame,
                     const std::vector<VideoFrameType>* frame_types) = 0;
  virtual int Release() = 0;
};

class GenericDecoder {
 public:
  virtual int Init(const DecoderInstance& instance) = 0;
  virtual int Decode(const uint8_t* inputData,
                     size_t inputLength,
                     const uint8_t* qpString,
                     int64_t timeSinceSdpTime = -1,
                     int64_t current_time_ms = -1,
                     int64_t render_time_ms = -1,
                     bool /*missingFrames*/ = false) = 0;
  virtual int Release() = 0;
};
```

**C++ 知识点 — 模板与多态的平衡：**
WebRTC 在编解码器层使用 **虚函数多态**（因为编解码器接口需要在运行时动态选择），而在信号处理层使用 **模板 + 内联**（因为 DSP 操作是确定性的且需要极致性能）。这是典型的 **运行时多态 vs 编译时多态** 的权衡：编解码器切换频率低，适合运行时；DSP 操作频率高，适合编译时。

---

## 第 8 章：P2P 与网络层 —— p2p/

`p2p/` 实现 P2P 连接所需的所有网络协议，主要是 STUN 和 ICE。

### 8.1 STUN 协议实现

```
p2p/
├── base/                             // STUN 基础
│   ├── stun_server.cc/h              // STUN 服务器实现
│   ├── stun_request.cc/h             // STUN 请求
│   ├── stun_binding_request.cc/h     // STUN Binding 请求
│   └─ STUN 消息解析 (Binding Request/Response/Allocate Response)
│
├── client/                           // STUN 客户端
│   ├── stun_prober.cc/h              // STUN 探测
│   └─ 探测 STUN 服务器的延迟和可达性
│
└── stunprober/                       // STUN 探测工具
    └─ 用于网络质量测试
```

**STUN 工作流程：**
```
客户端                          STUN 服务器
  │                                  │
  │  STUN Binding Request             │
  │  (发送到 STUN 服务器)             │
  │ ──────────────────────────────▶  │
  │                                  │
  │                                  │  解析源 IP/Port
  │                                  │  生成 STUN Binding Response
  │                                  │  (包含 XOR-MAPPED-ADDRESS)
  │                                  │
  │  STUN Binding Response ◀─────────│
  │  (XOR-MAPPED-ADDRESS = 公网IP:Port)│
  │                                  │
  │  → 获得自己的公网地址              │
  │  → 判断 NAT 类型                  │
```

### 8.2 ICE Candidate 收集与候选类型

`api/candidate.h` 定义了 ICE Candidate 的结构：

```cpp
class Candidate {
  std::string foundation;       // 候选标识
  int component;                // 组件 (RTP=1, RTCP=2)
  std::string protocol;         // 协议 (udp/tcp/tls)
  std::string type;             // 候选类型
  std::string address;          // IP 地址
  int port;                     // 端口
  std::string transport_address; // IP:Port 字符串
  int priority;                 // 优先级
  std::string rel_address;      // 中继地址
  int rel_port;                 // 中继端口
};
```

**ICE 候选类型：**

| 类型 | 说明 | 获取方式 |
|---|---|---|
| **Host** | 本地地址（内网 IP） | 直接从网卡获取 |
| **Server-Reflexive** | STUN 获得的公网地址 | 通过 STUN 服务器获取 |
| **Relay** | TURN 中继地址 | 通过 TURN 服务器获取 |
| **Peer-Reflexive** | 对端看到的本地地址 | 通过连接发现 |

### 8.3 NAT 穿透原理在代码中的体现

```
NAT 类型判断流程：
  │
  ├─ Step 1: 发送 STUN Binding Request 到 STUN 服务器
  │   │
  │   ├─ 收到响应 → 有公网地址 (Server-Reflexive)
  │   └─ 未收到响应 → NAT 可能阻塞 STUN
  │
  ├─ Step 2: 判断 NAT 类型
  │   │
  │   ├─ Public Network: 无需 NAT 穿透
  │   ├─ Full Cone: 任何外部地址可以直接访问
  │   ├─ Restricted Cone: 只有已通信的外部地址可以访问
  │   ├─ Port Restricted: Restricted + 端口限制
  │   └─ Symmetric: 不同目标地址获得不同映射
  │
  └─ Step 3: ICE 候选排序与连接检查
      │
      ├─ 优先尝试 Host 候选 (最低延迟)
      ├─ 其次 Server-Reflexive
      └─ 最后 Relay (TURN，最高延迟但最可靠)
```

**C++ 知识点 — NAT 类型枚举：**
WebRTC 使用 `enum class`（强类型枚举，C++11 特性）来表示 NAT 类型：
```cpp
enum class IceCandidateType { kHost, kServerReflexive, kRelay, kPeerReflexive };
```
这比传统的 `#define` 或 `enum` 更安全，因为不允许隐式转换为整数。

---

## 第 9 章：媒体引擎桥接层 —— media/engine/

`media/engine/` 是整个 WebRTC 架构中 **最关键的桥接层**，它将 pc/call 层的控制逻辑与 modules 层的处理逻辑连接起来。

### 9.1 WebRTCMediaEngine（统一媒体引擎）

`webrtc_media_engine.h/cc` 是所有媒体引擎的统一入口：

```cpp
class WebRTCMediaEngine {
 public:
  // 获取语音引擎（音频）
  WebRTCVoiceEngine* voice_engine() { return &voice_engine_; }

  // 获取视频引擎（视频）
  WebRTCVideoEngine* video_engine() { return &video_engine_; }

  // 创建音频编码器工厂
  absl::UniquePtr<webrtc::AudioEncoderFactory> CreateAudioEncoderFactory();

  // 创建音频解码器工厂
  absl::UniquePtr<webrtc::AudioDecoderFactory> CreateAudioDecoderFactory();

  // 创建视频编码器工厂
  absl::UniquePtr<webrtc::VideoEncoderFactory> CreateVideoEncoderFactory();

  // 创建视频解码器工厂
  absl::UniquePtr<webrtc::VideoDecoderFactory> CreateVideoDecoderFactory();

  // 初始化/关闭
  int Initialize();
  void Close();
};
```

**关键设计：**
`WebRTCMediaEngine` 是 **组合模式（Composition Pattern）** 的典型应用：它组合了 `WebRTCVoiceEngine` 和 `WebRTCVideoEngine`，统一管理所有媒体相关资源的生命周期。

### 9.2 WebRTCVoiceEngine（VoE 到现代 API 的桥接）

`webrtc_voice_engine.h/cc` 是旧版 VoE (Voice Engine) API 到现代 API 的桥接：

```
WebRTCVoiceEngine
├── WebRtcVoiceModule (音频模块封装)
│   ├── ADM (AudioDeviceModule)       → 音频设备
│   ├── AudioCodingImpl               → 音频编解码
│   ├── AudioProcessing               → 音频处理 (AEC/NS/AGC/VAD)
│   └── RtpRtcp                       → RTP/RTCP
│
├── Channel (音频通道)
│   ├── ChannelSend                   → 音频发送通道
│   └── ChannelReceive                → 音频接收通道
│
└── 桥接功能:
    ├── 将 modules 层的 ADM 暴露给 call 层
    ├── 将 call 层的 AudioSendStream 连接到 ADM
    └─ 将 call 层的 AudioReceiveStream 连接到 ADM
```

**桥接流程：**
```
WebRTCVoiceEngine::Init()
    │
    ├─ 初始化 ADM (音频设备)
    │   └─ 选择平台特定的音频后端 (ALSA/PulseAudio/CoreAudio)
    │
    ├─ 初始化 AudioCodingImpl
    │   └─ 创建 Opus/G722/iSAC 编码器/解码器
    │
    ├─ 初始化 AudioProcessing
    │   └─ 创建 AEC/NS/AGC/VAD 处理单元
    │
    └─ 注册回调
        ├─ ADM → 录音回调 → APE → audio_coding
        └─ audio_coding → 播放回调 ← APE ← ADM
```

### 9.3 WebRTCVideoEngine（VoViE 到现代 API 的桥接）

`webrtc_video_engine.h/cc` 类似地桥接视频部分：

```
WebRTCVideoEngine
├── WebRtcVoiceModule (复用)
├── VideoCaptureModule (VCM)          → 视频采集
├── VideoCodingImpl                   → 视频编解码
├── RtpRtcp                           → RTP/RTCP
├── Channel (视频通道)
│   ├── ChannelSend                   → 视频发送通道
│   └── ChannelReceive                → 视频接收通道
└── 编码器工厂
    ├── VP8EncoderFactory
    ├── VP9EncoderFactory
    └── H264EncoderFactory
```

### 9.4 编码器仿真代理（SimulcastEncoderAdapter）

`simulcast_encoder_adapter.h/cc` 实现 Simulcast 功能：

```cpp
class SimulcastEncoderAdapter : public VideoEncoder {
 public:
  // 创建多个 simulcast 编码器
  int InitEncode(const VideoEncoder::Config& config,
                 const std::vector<VideoEncoder::FrameType>* frame_types);

  // 将一帧视频复制为多个分辨率并编码
  int Encode(const VideoFrame& frame,
             const std::vector<VideoEncoder::FrameType>* frame_types) override;

 private:
  std::vector<absl::UniquePtr<VideoEncoder>> encoders_;  // 多个编码器
  std::vector<RtpEncodingParameters> encodings_;         // 每个编码层的参数
};
```

**Simulcast 编码流程：**
```
输入: 一帧原始视频 (例如 1280x720)
    │
    ▼
SimulcastEncoderAdapter::Encode()
    │
    ├── 第 1 层 (high): 1280x720 → VP8 编码
    ├── 第 2 层 (mid):  640x360 → VP8 编码 (缩放后)
    └── 第 3 层 (low):  320x180 → VP8 编码 (缩放后)
          │
          ▼
    输出: 3 组编码帧，每组有不同的 SSRC
```

**C++ 知识点 — 编码器适配器的桥接模式：**
`SimulcastEncoderAdapter` 使用 **适配器模式（Adapter Pattern）** 和 **组合模式**：它将多个 `VideoEncoder` 组合在一起，对外暴露单一的 `VideoEncoder` 接口。上层（VideoSendStream）不知道有多个编码器在背后工作，它只是调用 `Encode()`，适配器自动将帧复制并分发给所有子编码器。

### 9.5 桥接层的整体架构

```
                    pc/ + call/ 层                           media/engine/ 层
                    ─────────────────                        ───────────────────

  PeerConnection                                    WebRTCMediaEngine
    │                                                   │
    ├─ AddTrack() ──▶ 创建 AudioSendStream              │
    │                    │                              │
    │                    │  Config:                     │
    │                    │  - audio_coding              │◀── 从 MediaEngine 获取
    │                    │  - audio_device              │◀── 从 MediaEngine 获取
    │                    │  - audio_processing          │◀── 从 MediaEngine 获取
    │                    │                              │
    ├─ CreateOffer() ──▶ 编解码器协商                   │
    │                    │                              │
    │                    │  编码器工厂:                  │
    │                    │  - CreateAudioEncoderFactory()│◀── Opus/G722/iSAC
    │                    │  - CreateVideoEncoderFactory()│◀── VP8/VP9/H264
    │                    │                              │
  Call                                                  │
    │                                                   │
    ├─ CreateAudioSendStream() ──▶ 创建 Channel          │
    │                    │                              │
    │                    │  Channel 内部:                │
    │                    │  - ChannelSend                │
    │                    │    ├─ audio_coding_           │
    │                    │    ├─ rtp_rtcp_               │
    │                    │    └─ network_state_          │
    │                    │                              │
    │                    │  ChannelReceive               │
    │                    │    ├─ audio_coding_           │
    │                    │    └─ rtp_rtcp_               │
```

**核心观察：**
- `media/engine/` 是 **资源管理中心**：所有 modules 层的模块在这里统一创建和初始化
- 它充当 **配置转换器**：将 pc/call 层的配置参数转换为 modules 层需要的格式
- 它管理 **生命周期**：确保所有模块在正确的时机创建和销毁

---

## 第 10 章：SDK 与平台适配 —— sdk/

`sdk/` 提供将 WebRTC C++ 库封装为各平台 SDK 的桥接代码。

### 10.1 Android JNI 桥接

```
sdk/android/
├── jni/                              // JNI 绑定
│   ├── PeerConnectionFactory.jni.cc  // 工厂类 JNI
│   ├── PeerConnection.jni.cc         // PeerConnection JNI
│   └─ 所有 API 类的 JNI 绑定
│
├── java/org/webrtc/                  // Java API
│   ├── PeerConnection.java           // Java 版 PeerConnection
│   ├── MediaStreamTrack.java         // Java 媒体轨道
│   ├── EglBase.java                  // OpenGL ES 上下文
│   └─ SurfaceTextureHelper            // 纹理渲染
│
└── AppRTCMobile/                     // Android 示例应用
```

**JNI 桥接流程：**
```
Java 应用层 (Android App)
    │
    ├─ new PeerConnection(rtcConfig)
    │
    ▼
JNI: PeerConnection_jni.cc
    │
    ├─ 调用 C++: PeerConnectionFactory::Create()
    │   └─ 返回 scoped_refptr<PeerConnection>
    │
    └─ 将 C++ 指针包装为 Java 对象
        └─ 通过 nativeRef 字段持有 C++ 指针
```

### 10.2 Objective-C 桥接

```
sdk/objc/
├── sources/                          // Objective-C 实现
│   ├── RTCPeerConnection.m           // OC 版 PeerConnection
│   ├── RTCMediaStreamTrack.m         // OC 媒体轨道
│   └─ RTCVideoSource.m              // 视频源
│
└── interfaces/                       // Objective-C 接口
    ├── RTCPeerConnection.h            // OC 头文件
    ├── RTCMediaStreamTrack.h
    └─ RTCVideoSource.h
```

**桥接模式：**
JNI 和 Objective-C 桥接都使用 **指针包装** 模式：C++ 对象通过裸指针传递给平台层，平台层将其包装为平台对象（Java 对象 / OC 对象）。平台对象持有 C++ 指针，所有方法调用通过 JNI/OC 调用回到 C++ 层。

---

## 第 11 章：完整业务流程分析

本章追踪一个完整的 WebRTC 通话从建立到数据传输的全流程，展示各模块间的数据流和控制流。

### 11.1 呼叫建立全流程

```
阶段 1: 初始化 (所有在应用层完成)
────────────────────────────────────────
应用线程:
  1. 创建 PeerConnectionFactory
     └─ media/engine/WebRTCMediaEngine::Create()
       ├─ 初始化 ADM (音频设备)
       ├─ 初始化 AudioCodingImpl
       ├─ 初始化 AudioProcessing
       ├─ 初始化 VideoCaptureModule
       ├─ 初始化 VideoCodingImpl
       └─ 创建编码器/解码器工厂

  2. 创建 PeerConnection
     └─ PeerConnectionFactory::CreatePeerConnection()
       ├─ 创建 Call 实例 (call/Call::Create())
       │   └─ 创建 RTP 传输控制器
       ├─ 创建 JsepTransportController
       │   ├─ 创建 ICE 传输 (p2p/base/port)
       │   ├─ 创建 DTLS 传输
       │   └─ 创建 SCTP 传输
       ├─ 创建 PeerConnection 对象
       └─ 创建 RtcEventLog

阶段 2: 添加媒体轨道 (应用线程 → pc_thread)
────────────────────────────────────────
应用线程:
  3. 创建 VideoSource / AudioSource
  4. 创建 VideoTrack / AudioTrack
  5. peerConnection->AddTrack(track, {stream_id})
     └─ Proxy::Call() → pc_thread
       ├─ PeerConnection::AddTrack()
       │   ├─ 创建 RtpSender
       │   │   └─ 关联 VideoSource/AudioSource
       │   ├─ 创建 RtpTransceiver
       │   │   ├─ sender = RtpSender
       │   │   └─ receiver = RtpReceiver (pending)
       │   └─ 添加到 transceivers_ map

阶段 3: SDP 协商 (应用线程 → pc_thread)
────────────────────────────────────────
应用线程:
  6. peerConnection->CreateOffer(&observer)
     └─ Proxy::Call() → pc_thread
       ├─ PeerConnection::GenerateOffer()
       │   ├─ 遍历所有 transceivers_
       │   │   └─ 为每个 transceiver 生成 SDP media line
       │   │     ├─ 选择编解码器 (从 EncoderFactory)
       │   │     ├─ 生成 SSRC
       │   │     └─ 添加 RTP header extensions
       │   └─ WebRtcSdpGenerator::GenerateSdp()
       │     └─ 生成完整 SDP 文本
       └─ observer->OnCreateOffer(success, SDP)

  7. (信令服务器转发 SDP 到对端)

对端:
  8. peerConnection->SetRemoteDescription(desc)
     └─ Proxy::Call() → pc_thread
       ├─ JsepSessionDescription::Parse()
       │   └─ 解析 SDP 文本
       ├─ MediaSession::SetRemoteSdp()
       │   ├─ 解析 codecs / header_extensions / mid
       │   └─ 匹配本地 transceivers_
       └─ 触发 OnRemoteDescriptionSet

  9. peerConnection->CreateAnswer(&observer)
     └─ 与 CreateOffer 类似，生成 Answer SDP

  10. (信令服务器转发 Answer 到发起端)

阶段 4: ICE 候选收集 (pc_thread → worker_thread)
────────────────────────────────────────
JsepTransportController:
  11. ICE 开始收集候选
      ├─ Host 候选: 直接从 Socket 获取本地 IP
      ├─ Server-Reflexive: 通过 STUN 服务器获取公网 IP
      └─ Relay: 通过 TURN 服务器获取中继地址

  12. 每获得一个候选:
      └─ observer->OnIceCandidate(candidate)
        └─ (通过信令服务器转发到对端)

阶段 5: DTLS 握手 (worker_thread)
────────────────────────────────────────
JsepTransportController:
  13. DTLS 连接建立
      ├─ 交换 DTLS CertificateFingerprint
      ├─ DTLS Handshake (ClientHello/ServerHello/Finished)
      └─ 生成 SRTP 密钥

  14. 连接建立:
      └─ observer->OnIceConnectionChange(RTC_PEER_CONNECTION_ICE_CONNECTION_CONNECTED)
```

### 11.2 音频发送数据流（完整路径）

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 音频发送: 麦克风 → 扬声器 (远端)                                          │
└─────────────────────────────────────────────────────────────────────────┘

  [1] 麦克风采集
      │
      ▼
  ADM (AudioDeviceModule)
  ├── 平台音频后端 (ALSA/PulseAudio/CoreAudio)
  ├── 采集 10ms 音频帧 (PCM, 48kHz, 16-bit)
  └─ 通过回调推送: RecordingAudioData()
      │
      ▼
  [2] 音频处理 (AudioProcessing - APE)
      │
      ├── AudioBuffer::Push()          // 放入处理缓冲
      │
      ├── HighPassFilter               // 高通滤波 (去除 <300Hz 低频噪声)
      │
      ├── EchoControlMobile (AEC)      // 回声消除
      │   ├── 需要参考信号 (扬声器播放的音频)
      │   └─ 自适应 FIR 滤波消除回声
      │
      ├── NoiseSuppression (NS)        // 噪声抑制
      │   └─ 频谱减法抑制背景噪声
      │
      ├── GainControl (AGC)            // 自动增益控制
      │   └─ 根据语音电平自动调整增益
      │
      └── VoiceDetection (VAD)         // 语音活动检测
          └─ 标记当前帧是否为语音
          │
          ▼
      AudioBuffer::Pull()              // 拉取处理后的音频
      │
      ▼
  [3] 音频编码 (AudioCoding)
      │
      ├── 重采样 (如果需要: 48kHz → 48kHz Opus)
      │
      ├── AudioEncoderOpus::Encode()   // Opus 编码
      │   ├── 10ms PCM → ~200 bytes
      │   └─ 输出: 编码后的音频数据
      │
      └─ 通过回调返回: EncodeCallback()
          │
          ▼
  [4] RTP 封包 (RtpRtcp)
      │
      ├── RtpRtcp::BuildRtpHeader()    // 添加 RTP 头
      │   ├── SSRC
      │   ├── seq_num (递增)
      │   ├── timestamp (递增)
      │   └─ payload_type (从 SDP 协商获得)
      │
      └─ 输出: 完整 RTP 包
          │
          ▼
  [5] 拥塞控制检查 (CongestionController)
      │
      ├── GetTargetBitrate()           // 查询目标码率
      │   └─ 如果当前码率 > 目标码率 → 丢弃/延迟发送
      │
      └─ PacedPacketRouter::Enqueue() // 入队到 pacing
          │
          ▼
  [6] 网络发送 (RtpTransportControllerSend)
      │
      ├── 通过 Socket 发送 RTP 包
      └─ 发送 RTCP SR (Sender Report)
          │
          ▼
  [7] 通过网络传输到对端
```

### 11.3 音频接收数据流（完整路径）

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 音频接收: 网络 → 扬声器                                                  │
└─────────────────────────────────────────────────────────────────────────┘

  [1] 网络接收 RTP 包
      │
      ▼
  [2] RTP Demuxer (call/rtcp_demuxer)
      │
      ├── 根据 SSRC 分发到对应的 AudioReceiveStream
      └─ 根据 RTCP 类型分发:
          ├── RR → 发送端
          ├── REMB → 拥塞控制
          └─ FIR/PLI → (音频不需要)
          │
          ▼
  [3] RTP 解包 (RtpRtcp)
      │
      ├── 解析 RTP 头
      ├── 检查 seq_num (检测丢包)
      ├── 去除 RTP 头
      └─ 输出: 编码后的音频数据
          │
          ▼
  [4] 音频解码 (AudioCoding)
      │
      ├── AudioDecoderOpus::Decode()   // Opus 解码
      │   ├── 200 bytes → 480 samples (10ms PCM)
      │   └─ 输出: 48kHz PCM 音频
      │
      └─ 通过回调返回: Decode()
          │
          ▼
  [5] 音频后处理 (AudioProcessing)
      │
      ├── AudioBuffer::Push()          // 放入处理缓冲
      │
      ├── 可能的后处理 (NS/AGC)
      │
      └── AudioBuffer::Pull()          // 拉取处理后的音频
          │
          ▼
  [6] 音频渲染 (ADM)
      │
      ├── PlayoutAudioData()           // ADM 回调请求音频数据
      │   └─ 提供处理后的 PCM 数据
      │
      └─ 平台音频后端播放
          └─ ALSA/PulseAudio/CoreAudio → 扬声器
```

### 11.4 视频发送数据流（完整路径）

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 视频发送: 摄像头 → 网络                                                  │
└─────────────────────────────────────────────────────────────────────────┘

  [1] 视频采集 (VideoCaptureModule)
      │
      ├── V4L2 / AVFoundation / DirectShow
      ├── 采集原始帧 (NV12/I420)
      └─ 帧回调: CaptureData()
          │
          ▼
  [2] 视频处理 (VideoProcessingModule - VPM)
      │
      ├── FrameCropping              // 裁剪
      ├── Rotation                   // 旋转 (摄像头方向补偿)
      └── Scaling                    // 缩放 (如果需要)
          │
          ▼
  [3] 视频编码 (VideoCodingImpl)
      │
      ├── VideoEncoder::Encode()
      │   ├── I420 → VP8/VP9/H264 编码
      │   ├── 生成 I 帧 / P 帧 / B 帧
      │   └─ 输出: EncodedFrame
      │
      └─ 编码帧回调: EncodeCallback()
          │
          ▼
  [4] NACK / FEC 管理 (video_coding)
      │
      ├── NackModule::AddSentPacket() // 记录已发送包
      └─ FecController::CreateFec()   // 生成 FEC 包
          │
          ▼
  [5] RTP 封包 (RtpRtcp)
      │
      ├── 将 EncodedFrame 分割为 RTP 包
      │   └─ 如果帧 > MTU, 使用 RTP 分片
      ├── 添加 RTP 头 + VP8/VP9/H264 RTP 头
      └─ 输出: RTP 包
          │
          ▼
  [6] Pacing + 拥塞控制
      │
      ├── PacedPacketRouter::Enqueue() // 入队
      └─ CongestionController 检查带宽
          │
          ▼
  [7] 网络发送
      │
      └─ Socket::SendTo() → 对端
```

### 11.5 视频接收数据流（完整路径）

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 视频接收: 网络 → 渲染                                                   │
└─────────────────────────────────────────────────────────────────────────┘

  [1] 网络接收 RTP 包
      │
      ▼
  [2] RTP Demuxer → VideoReceiveStream
      │
      ▼
  [3] RTP 解包 (RtpRtcp)
      │
      └─ 输出: 编码的视频数据 (VP8/VP9/H264 字节流)
          │
          ▼
  [4] JitterBuffer (video_coding)
      │
      ├── IncomingPacket()             // 接收乱序包
      │   ├── 按 seq_num 排序
      │   ├── 检测丢失的包
      │   └─ 延迟交付 (等待重传或超时)
      │
      ├── NackModule::GetNacks()       // 获取需要重传的包
      │   └─ 发送 RTCP NACK
      │
      └─ GetPacket()                   // 输出连续帧
          │
          ▼
  [5] 视频解码 (VideoCodingImpl)
      │
      ├── VideoDecoder::Decode()
      │   ├── VP8/VP9/H264 → I420
      │   ├── 处理参考帧依赖
      │   └─ 输出: VideoFrame (I420)
      │
      └─ 解码帧回调: DecodedImage()
          │
          ▼
  [6] 视频后处理 (VideoProcessingModule)
      │
      ├── Rotation                     // 方向补偿
      ├── FrameCropping                // 裁剪黑边
      └── Scaling                      // 缩放 (渲染需要)
          │
          ▼
  [7] 渲染
      │
      └─ SurfaceTexture / OpenGL ES / Direct3D → 屏幕
```

### 11.6 DataChannel 数据流

```
应用层数据
    │
    ▼
DataChannel::Send()
    │
    ▼
SctpTransport::Send()
    │
    ├── SCTP 封装
    │   ├── 添加 SCTP Header
    │   ├── Stream ID
    │   ├── TSNU (Transmission Sequence Number)
    │   └─ Payload Type (可靠/不可靠)
    │
    ▼
DTLS 加密 (DtlsTransport)
    │
    ▼
RTP Transport (复用音频/视频的 DTLS 连接)
    │
    ▼
Socket 发送 (通过网络)
```

### 11.7 拥塞控制闭环

```
┌──────────────────────────────────────────────────────────────────────┐
│                        拥塞控制闭环                                    │
└──────────────────────────────────────────────────────────────────────┘

发送端 (Sender)                          接收端 (Receiver)
──────────────                           ───────────────

VideoSendStream                         VideoReceiveStream
    │                                         │
    ├─ 发送 RTP 包                             │  接收 RTP 包
    │    │                                    │  记录到达时间
    │    ▼                                    │  计算 RTT
  Socket  │                                    │  计算丢包率
    │    │                                    │
    │                                    RemoteBitrateEstimator
    │    │                                    │
    │    │                                    ├─ 基于到达时间估计带宽
    │    │                                    ├─ 基于 AbsSendTime 估计带宽
    │    │                                    └─ 输出: estimated_bitrate
    │    │                                         │
    │    │                                    RTCP REMB 包
    │    │                                    (Receiver Estimated Max Bitrate)
    │    │                                         │
    │    │◀────────────────────────────────────────┤
    │    │                                    RTCP RR 包
    │    │                                    (Receiver Report)
    │    │    (包含丢包率、RTT)                    │
    │    │◀────────────────────────────────────────┤
    │    │                                         │
RtcpReceiver                       RtcpReceiver
    │    │                                    RtcpReceiver
    │    ├─ 解析 RTCP 包                         ├─ 解析 REMB
    │    │   │                                  │  → 通知 GCC
    │    │   ▼                                  │
    │    │  ReceiveSideCongestionController     │
    │    │  │                                  GenericRateControl
    │    │  │                                  │
    │    │  ├─ 更新带宽估计                      ├─ 根据估计带宽调整目标码率
    │    │  ├─ 计算目标码率                      │  ├─ 带宽充足 → 增加码率
    │    │  └─ 输出: target_bitrate              │  └─ 带宽不足 → 降低码率
    │    │        │                              │
    │    │        ▼                              │
    │    │     PacedPacketRouter                 │
    │    │        │                              │
    │    │        ▼                              │
    │    │     调整发送速率                        │
    │    │                                         │
    │    ▼                                         │
  VideoSendStream                                   │
    │    │                                          │
    │    ├─ 调整编码质量 (QP)                        │
    │    ├─ 触发视频适配 (降低分辨率)                 │
    │    └─ 调整 pacing 速率                        │
    │                                                 │
    └───────────── 下一轮反馈循环 ─────────────────────┘
```

### 11.8 控制流总结图（分层调用关系）

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        完整调用层次结构                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  应用层 (App)                                                            │
│  ├── PeerConnectionFactory (创建工厂)                                    │
│  ├── PeerConnection (创建连接)                                           │
│  ├── MediaStream (创建媒体流)                                            │
│  └── DataChannel (创建数据通道)                                          │
│       │                                                                  │
│       ▼                                                                  │
│  pc/ 层 (信令控制)                                                       │
│  ├── PeerConnection (SDP 协商, ICE 管理)                                 │
│  ├── JsepTransportController (传输层管理)                                │
│  ├── RtpTransceiver (RTP 收发器)                                         │
│  ├── MediaSession (媒体会话)                                             │
│  └── DataChannelController (数据通道管理)                                │
│       │                                                                  │
│       ▼                                                                  │
│  media/engine/ 层 (桥接)                                                 │
│  ├── WebRTCMediaEngine (统一引擎)                                        │
│  ├── WebRTCVoiceEngine (音频引擎)                                        │
│  └── WebRTCVideoEngine (视频引擎)                                        │
│       │                                                                  │
│       ▼                                                                  │
│  call/ 层 (呼叫管理)                                                     │
│  ├── Call (流调度中心)                                                   │
│  ├── AudioSendStream / AudioReceiveStream                                │
│  ├── VideoSendStream / VideoReceiveStream                                │
│  ├── RtpDemuxer / RtcpDemuxer                                           │
│  └── RtpTransportControllerSend (发送传输控制)                            │
│       │                                                                  │
│       ▼                                                                  │
│  modules/ 层 (处理)                                                      │
│  ├── audio_device (音频设备)                                             │
│  ├── audio_processing (音频处理: AEC/NS/AGC/VAD)                        │
│  ├── audio_coding (音频编码: Opus/G722/iSAC)                            │
│  ├── video_capture (视频采集)                                            │
│  ├── video_coding (视频编码: VP8/VP9/H264 + JitterBuffer + NACK + FEC) │
│  ├── video_processing (视频处理: 裁剪/旋转/缩放)                          │
│  ├── congestion_controller (拥塞控制)                                     │
│  ├── pacing (数据包整形)                                                 │
│  └── rtp_rtcp (RTP/RTCP 协议)                                           │
│       │                                                                  │
│       ▼                                                                  │
│  rtc_base/ 层 (基础设施)                                                  │
│  ├── Thread / Message (线程与消息)                                       │
│  ├── Socket / SocketServer (网络)                                        │
│  ├── ProcessThread (模块调度)                                            │
│  ├── sigslot (信号槽)                                                    │
│  └── scoped_refptr (引用计数)                                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 第 12 章：C++ 高级技巧在 WebRTC 中的应用

本章总结 WebRTC 代码中使用的 C++ 高级特性，适合有 C/C++ 基础但想深入了解工业级代码中 C++ 用法的读者。

### 12.1 零拷贝设计与 Copy-on-Write Buffer

WebRTC 在音视频管道中大量使用 **零拷贝（Zero-Copy）** 技术，避免不必要的内存复制。

**核心机制：**

```cpp
// scoped_refptr<T> — 引用计数智能指针
scoped_refptr<VideoFrame> frame = ...;
// 传递 frame 时只增加引用计数，不复制帧数据
scoped_refptr<VideoFrame> frame2 = frame;  // 零拷贝

// CopyOnWriteBuffer — 写时复制
class CopyOnWriteBuffer {
 private:
  uint8_t* data_;     // 共享数据
  size_t size_;
  rtc::AtomicRefCounts ref_count_;  // 引用计数

 public:
  // 复制时只增加引用计数
  CopyOnWriteBuffer(const CopyOnWriteBuffer& other)
      : data_(other.data_), size_(other.size_) {
    data_->AddRef();  // 不复制数据
  }

  // 修改时先复制数据 (Copy-on-Write)
  void Set(size_t index, uint8_t value) {
    if (ref_count_ == 1) {
      // 独占访问，直接修改
      data_[index] = value;
    } else {
      // 共享访问，先复制
      uint8_t* new_data = CopyData();
      new_data->AddRef();
      data_->Release();
      data_ = new_data;
      data_[index] = value;
    }
  }
};
```

**C++ 知识点 — 引用计数与内存管理：**
`scoped_refptr` 使用 **引用计数 + RAII** 模式管理内存。`Release()` 返回 nullptr 时触发销毁，这保证了最后一个使用者离开时自动释放。与 `std::shared_ptr` 的区别是：`scoped_refptr` 的引用计数操作是原子的，但对象销毁必须在 **特定线程** 上执行（通过 `Release()` 的线程安全检查保证）。

### 12.2 跨线程编程模式

WebRTC 采用 **线程亲和性（Thread Affinity）** 模型，这是其最核心的并发编程范式。

**核心模式：**

```cpp
// 1. Proxy 模式 — 跨线程调用
template <typename WrapType, typename UnwrapType, typename Tag>
class Proxy {
 public:
  static Proxy* Create(rtc::Thread* target_thread, UnwrapType* internal) {
    Proxy* proxy = new Proxy(target_thread, internal);
    target_thread->Invoke<void>(RTC_FROM_HERE, [proxy, internal]() {
      // 在目标线程上执行
    });
    return proxy;
  }

  void Call(rtc::Location origin, std::function<void()> task) {
    target_thread_->Post(origin, [task]() { task(); });
  }

 private:
  Proxy(rtc::Thread* thread, UnwrapType* internal)
      : target_thread_(thread), internal_(internal) {}
};

// 2. WeakPtr 模式 — 安全的弱引用
class MyClass : public rtc::MessageHandler, public rtc::WeakPointer {
 public:
  rtc::WeakPtr<MyClass> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

  void Start() {
    weak_ptr_ = GetWeakPtr();
    // 投递任务，即使对象被销毁也不会触发悬空指针
    thread_->Post(RTC_FROM_HERE, this, &MyClass::DoWork, 0);
  }

  void OnMessage(rtc::Message* msg) {
    if (!weak_ptr_) return;  // 对象已被销毁
    DoWork();
  }

 private:
  rtc::WeakPtrFactory<MyClass> weak_factory_;
  rtc::WeakPtr<MyClass> weak_ptr_;
};
```

**C++ 知识点 — WeakPtr 的实现原理：**
`WeakPtrFactory<T>` 内部维护一个 **生成令牌（generation counter）**。每次 `GetWeakPtr()` 生成一个包含令牌的 `WeakPtr`。当 `WeakPtrFactory` 销毁时，它撤销所有已生成的令牌（将令牌设为 0）。`WeakPtr` 在解引用时检查令牌是否有效，无效则返回 nullptr。这比 `std::shared_ptr` 的 `weak_ptr` 更轻量，因为不需要共享所有权。

### 12.3 模板与类型擦除在编解码适配中的应用

WebRTC 在编解码器工厂中使用 **类型擦除 + 模板** 实现灵活的编解码器管理。

```cpp
// 抽象工厂接口
class AudioEncoderFactory {
 public:
  virtual ~AudioEncoderFactory() = default;
  virtual std::unique_ptr<AudioEncoder> CreateAudioEncoder(
      const Codec& codec) = 0;
};

class AudioDecoderFactory {
 public:
  virtual ~AudioDecoderFactory() = default;
  virtual std::unique_ptr<AudioDecoder> CreateAudioDecoder(
      const Codec& codec) = 0;
  virtual std::vector<SupportedCodec> GetSupportedCodecs() = 0;
};

// 具体实现
class OpusEncoderFactory : public AudioEncoderFactory {
 public:
  std::unique_ptr<AudioEncoder> CreateAudioEncoder(
      const Codec& codec) override {
    if (strcmp(codec.name, "opus") != 0) return nullptr;
    return std::make_unique<OpusEncoder>(codec.channels, codec.clockrate);
  }
};

// 仿真代理 — 组合多个编码器
class SimulcastEncoderFactory : public VideoEncoderFactory {
 public:
  SimulcastEncoderFactory(
      std::unique_ptr<VideoEncoderFactory> encoder_factory,
      std::vector<RtpEncodingParameters> encodings)
      : encoder_factory_(std::move(encoder_factory)),
        encodings_(std::move(encodings)) {}

 private:
  std::unique_ptr<VideoEncoderFactory> encoder_factory_;
  std::vector<RtpEncodingParameters> encodings_;
};
```

**C++ 知识点 — 类型擦除与策略模式：**
`AudioEncoderFactory` 是一个 **抽象基类接口**，通过虚函数实现类型擦除。调用者只知道 `AudioEncoderFactory` 接口，不知道具体的编码器类型。这是 **策略模式** 的 C++ 实现：编解码器策略在运行时通过工厂创建。

### 12.4 性能关键路径的优化技巧

**1. 内存池（Frame Buffer Pool）：**
```cpp
// I420BufferPool — 避免频繁分配/释放
class I420BufferPool {
 public:
  // 从池中获取缓冲，如果池中没有则创建新的
  rtc::scoped_refptr<I420Buffer> GetBuffer(
      uint32_t width, uint32_t height) {
    rtc::CritScope cs(&crit_sect_);
    auto it = pool_.find(key);
    if (it != pool_.end()) {
      auto buffer = it->second;
      it->second = nullptr;  // 从池中移除
      return buffer;
    }
    return I420Buffer::Create(width, height);
  }

  // 归还缓冲到池中
  void PutBuffer(rtc::scoped_refptr<I420Buffer> buffer) {
    rtc::CritScope cs(&crit_sect_);
    pool_[buffer->width() * buffer->height()] = buffer;
  }

 private:
  std::map<uint32_t, rtc::scoped_refptr<I420Buffer>> pool_;
  rtc::CriticalSection crit_sect_;
};
```

**2. SIMD 内联汇编：**
```cpp
// common_audio/signal_processing/correlation_sse.cc
#ifdef WEBRTC_ARCH_X86_64
int64_t correlation_sse(const int16_t* x, const int16_t* y, int len) {
  int64_t result;
  __asm__ volatile (
    "pxor %%xmm0, %%xmm0\n\t"        // 清零累加器
    "movq %0, %%rax\n\t"             // x 指针
    "movq %1, %%rdx\n\t"             // y 指针
    "movq %2, %%rcx\n\t"             // len
    // ... SSE 指令序列
    : "=m"(result)
    : "r"(x), "r"(y), "r"(len)
    : "rax", "rdx", "rcx", "xmm0"
  );
  return result;
}
#endif
```

**3. 缓存友好性（Cache-Friendly）设计：**
- `AudioBuffer` 使用连续内存存储音频数据
- `FrameBuffer` 使用对象池减少内存碎片
- 小对象（如 RTP Header）使用栈分配而非堆分配

**C++ 知识点 — 性能优化的 C++ 技巧总结：**

| 技巧 | 用途 | 对应代码 |
|---|---|---|
| **RAII** | 自动资源管理 | `CritScope`, `CopyOnWriteBuffer` |
| **移动语义** | 避免深拷贝 | `std::move(data)`, `EncodedFrame&&` |
| **内联函数** | 消除函数调用开销 | `inline int GetTimestamp()` |
| **SIMD 内联汇编** | 向量加速 | `signal_processing/` 中的 DSP 原语 |
| **内存池** | 减少 malloc/free | `I420BufferPool`, `AudioFrame` 缓冲池 |
| **栈分配优先** | 减少堆分配 | 小结构体直接栈分配 |
| **constexpr** | 编译期计算 | `static constexpr int kMaxCodecs = 10` |

### 12.5 线程安全注解

WebRTC 使用 **编译期线程安全检查**（通过 `thread_annotations.h`）：

```cpp
// thread_annotations.h
#define EXCLUSIVE_LOCKS_REQUIRED(...)
#define SHARED_LOCKS_REQUIRED(...)
#define LOCKS_EXCLUDED(...)
#define LOCK_RETURNED(x)
#define LOCKS_CAPABILITY(x)
#define GUARDED_BY(x)
#define THREAD_SAFE

class AudioChannel {
 private:
  rtc::CriticalSection crit_ GUARDED_BY(lock_);  // crit_ 受 lock_ 保护
  rtc::CriticalSection lock_;

 public:
  void SendData(const uint8_t* data, size_t len)
      EXCLUSIVE_LOCKS_REQUIRED(lock_) {  // 调用者必须持有 lock_
    rtc::CritScope cs(&crit_);
    // 安全地访问共享数据
  }
};
```

**C++ 知识点 — 编译期线程安全注解：**
这些注解使用 **编译器扩展（Clang Thread Safety Analysis）**，在编译时检查锁的使用是否正确。例如，如果 `SendData()` 被调用时没有持有 `lock_`，Clang 会发出警告。这比运行时检测（如 ThreadSanitizer）更轻量，且能在开发阶段发现问题。

### 12.6 总结：WebRTC 的 C++ 编程哲学

1. **所有权清晰**：每个对象都有明确的所有者，通过 `scoped_refptr` 或 `unique_ptr` 管理
2. **线程隔离**：对象只在创建的线程上访问，跨线程通过 Proxy 模式
3. **零拷贝优先**：音视频帧通过 `scoped_refptr<VideoFrame>` 传递，避免复制
4. **接口抽象**：所有模块通过抽象接口交互，实现高度解耦
5. **性能敏感**：关键路径（DSP、网络发送）使用 SIMD 和优化算法
6. **编译期检查**：大量使用模板、constexpr、thread annotations 在编译期发现问题
