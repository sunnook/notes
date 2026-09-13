# WebRTC 信令与媒体流程分析 — 规划文档

> 项目：LiveKit Android SDK（`client-sdk-android-main`）
> 底层：WebRTC m144（以 AAR 依赖形式被 SDK 使用，源码不在本环境）
> 目标读者：有 C/C++ 经验、对 Android/Kotlin 与 WebRTC 不熟悉的开发者
> 日期：2026-09-02

---

## 一、任务目标

> **更新（2026-09-02）：交付物改为 2 个文档** —— 一个以 LiveKit 为主，一个以 WebRTC 原生为主。

梳理 **LiveKit Android SDK** 与 **WebRTC m144 原生源码** 中的 **信令流程** 与 **媒体流程**：

1. 从**接口（API）到内部**的调用链（调用方向：上层 → 下层）
2. 从**内部到底层**的回调链（回调方向：底层 → 上层）
3. 熟悉两个工程框架（LiveKit SDK + WebRTC 原生）

**两个文档：**
- **文档 A（LiveKit 为主）**：`docs-lu-0902/wrt-sig-analysis-0902.md`
- **文档 B（WebRTC 原生为主）**：`docs-lu-0902/webrtc-internal-analysis-0902.md`

每个文档都包含 3 张图（1 分层框架图 + 2 流程图[简图+细图]），并围绕图介绍流程与源码架构。

产出 3 张图：
- **1 张分层框架图**：SDK 各层（接口层 / 信令层 / 传输层 / WebRTC 封装层 / 原生 WebRTC AAR）
- **2 张流程图**：
  - 一张**简图**（宏观：初始化 → 注册 → 信令协商 → 媒体流 → QoS → 通话结束）
  - 一张**细图**（微观：每个关键步骤的类/方法级调用链与回调链）

流程图的约定：
- **横轴**：接口 → 各层目录 → 底层网络/硬件/库（WebRTC AAR）
- **纵轴**：流程（初始化、注册、信令协商、媒体流、QoS、建立→通话→结束）

---

## 二、章节大纲

### 文档 A：`docs-lu-0902/wrt-sig-analysis-0902.md`（LiveKit 为主）

#### 第 0 章 文档说明与阅读指引
- 目的、范围、术语表（SDP/ICE/PeerConnection/Transceiver/Simulcast/SVC/QoS 等）
- 代码路径索引（核心文件 → 行号）
- 3 张图的位置说明

#### 第 1 章 总体架构与分层框架图（图 1）
- LiveKit 双 PeerConnection 架构（publisher 上行 / subscriber 下行）
- 分层框架图（Mermaid）
- 各层职责与关键类

#### 第 2 章 初始化流程（接口 → 内部）
- `LiveKit.create()` → `Room`（Dagger DI）
- `Room.connect()` 流程
- PeerConnectionFactory 创建、RTC 线程模型（`RTCThreadUtils`）
- 音频设备初始化（`AudioSwitchHandler` / `AudioDeviceModule`）
- 视频编码器工厂（`SimulcastVideoEncoderFactoryWrapper`）

#### 第 3 章 信令流程（重点）
- 3.1 信令建立：`SignalClient.join()` → WebSocket → `JoinResponse`
- 3.2 双 PC 配置：`RTCEngine.configure()` 创建 publisher/subscriber
- 3.3 SDP 协商：offer/answer 全链路（`PeerConnectionTransport.createAndSendOffer` → `sendOffer` → 服务端 answer → `onServerAnswer`）
- 3.4 ICE trickle 流程（`onIceCandidate` → `sendCandidate` → `onTrickle`）
- 3.5 数据通道（`_reliable` / `_lossy`）
- 3.6 信令消息分发（`SignalClient.handleSignalResponseImpl` → `RTCEngine` → `Room`）
- 3.7 重连/恢复（soft/full reconnect）

#### 第 4 章 媒体流程（重点）
- 4.1 上行：采集 → 编码 → 发送
  - 视频：`LocalVideoTrack`（CameraCapturer → VideoSource → VideoTrack）→ `LocalParticipant.publishVideoTrack` → `publishTrackImpl` → `addTransceiver` + `addTrack` → 协商 → 编码发送
  - 音频：`LocalAudioTrack`（AudioSource → AudioTrack）→ `publishAudioTrack`
  - Simulcast / SVC 编码配置
- 4.2 下行：接收 → 解码 → 渲染
  - `SubscriberTransportObserver.onAddTrack` → `Room.onAddTrack` → `RemoteParticipant.addSubscribedMediaTrack` → `RemoteVideoTrack`/`RemoteAudioTrack` → 渲染
  - 订阅控制（`RemoteTrackPublication.setSubscribed` / `setVideoQuality` / `setVideoDimensions`）
- 4.3 数据通道媒体（DataPacket：user / RPC / datastream / metrics）

#### 第 5 章 QoS 与统计（重点）
- 5.1 getStats 采集链路（`RTCStatsExt` / `getFilteredStats` / `RTCStatsGetter`）
- 5.2 指标上报（`RTCMetricsManager.collectMetrics` → DataChannel）
- 5.3 连接质量（`onConnectionQuality` / ConnectionQuality）
- 5.4 订阅质量与 dynacast（`SubscribedQualityUpdate` → `LocalVideoTrack.setPublishingLayers`）
- 5.5 自适应码率 / SVC 起始码率（SDP munge `ensureCodecBitrates`）

#### 第 6 章 通话生命周期（建立 → 通话 → 结束）
- 建立：connect → join → 协商 → ICE 连通 → `RoomEvent.Connected`
- 通话中：发布/订阅、mute、speaker 更新、track 事件
- 结束：`Room.disconnect()` → `sendLeave` → 清理 → `RoomEvent.Disconnected`
- 异常：断线重连、网络切换

#### 第 7 章 流程图（图 2 简图 + 图 3 细图）
- 7.1 宏观简图（Mermaid flowchart，纵轴流程 / 横轴分层）
- 7.2 微观细图（Mermaid sequence/flowchart，类/方法级调用链 + 回调链）

#### 第 8 章 附录
- 关键文件清单（路径 + 职责 + 行号）
- 术语对照表
- 参考

---

### 文档 B：`docs-lu-0902/webrtc-internal-analysis-0902.md`（WebRTC 原生为主）

> 源码：`/data1/luhonghao/codes/adrtc/webrtc/webrtc-m144_release`（即用户 Windows 路径 `F:\codes\adrtc\webrtc\webrtc-m144_release`）

#### 第 0 章 文档说明与阅读指引
- 目的、范围（只讲信令 + 媒体 + QoS 相关模块）、术语表
- WebRTC 源码目录索引（api / pc / p2p / media / call / modules / sdk/android）

#### 第 1 章 WebRTC 总体架构与分层框架图（图 1）
- WebRTC 分层：API 层 → PeerConnection 层(pc) → 传输层(p2p/dtls/srtp) → 媒体层(media/call) → 模块层(modules)
- 三线程模型（signaling / worker / network）
- 分层框架图（Mermaid）

#### 第 2 章 PeerConnection 与信令协商（重点）
- `PeerConnection` 状态机（New→HaveLocalOffer→HaveRemoteOffer→Stable→Closed）
- SDP offer/answer：`SdpOfferAnswer` → `JsepTransportController` → ICE/DTLS
- Transceiver/Sender/Receiver 创建与媒体接线
- DataChannel（SCTP）
- 回调链（Observer：onTrack/onIceCandidate/onIceConnectionChange）

#### 第 3 章 ICE 与传输（p2p）
- ICE agent、候选收集（host/srflx/relay，STUN/TURN）
- 连通性检查、nomination、候选对选择
- DTLS/SRTP 建立
- 传输层如何承载 RTP

#### 第 4 章 媒体上行路径（采集 → 编码 → RTP 发送）
- 视频：VideoSource → VideoStreamEncoder → 编码器 → simulcast → packetizer → RTP sender → pacer → ICE
- 音频：AudioSource → AudioProcessing → AudioCodingModule → RTP
- 码率分配（BitrateAllocator）与编码器码率控制

#### 第 5 章 媒体下行路径 + QoS（重点）
- 视频：ICE → RTP demuxer → jitter buffer（FrameBuffer）→ 解码 → 渲染
- 音频：NetEq（抖动缓冲+丢包隐藏）
- QoS：NACK / FEC / 丢包处理 / 抖动缓冲
- 拥塞控制：Transport-CC/REMB 反馈 → NetworkController 带宽估计 → 调整码率（闭环）

#### 第 6 章 Android 封装与 JNI（sdk/android）
- `org.webrtc.PeerConnection` 等 Java 类如何映射原生 C++（JNI）
- Java ↔ native 回调桥接
- 与 LiveKit `livekit.org.webrtc` 的关系

#### 第 7 章 流程图（图 2 简图 + 图 3 细图）
- 7.1 宏观简图
- 7.2 微观细图（信令 + 媒体 + QoS 的类/方法级调用链与回调链）

#### 第 8 章 附录
- 关键文件清单（路径 + 职责 + 行号）
- 术语对照表
- 参考

---

## 三、写作与交付流程

1. 先写本规划文档（已完成）
2. 先写 **文档 A（LiveKit 为主）**：`docs-lu-0902/wrt-sig-analysis-0902.md`
   - 按章节顺序逐章写入，每章完成后确认文件已持久化，然后进行上下文压缩
   - 每章之间先读取已写内容确认完整性，再继续下一章
3. 再写 **文档 B（WebRTC 原生为主）**：`docs-lu-0902/webrtc-internal-analysis-0902.md`
   - 依赖 WebRTC 源码阅读（`/data1/luhonghao/codes/adrtc/webrtc/webrtc-m144_release`）
4. 长章节分多次写入（先前半段，再追加后半段）
5. 若文档过大，提示用户分多个文件
6. 顺序执行，不创建过多任务对象
7. 上下文过多时及时 compact 或提醒用户
8. 适时写入 memory 防止网络故障恢复不了
9. 每个文档完成后，在**文档开头插入目录（带索引）**

---

## 四、已阅读的关键文件（截至 2026-09-02）

| 文件 | 职责 |
|------|------|
| `room/Room.kt` | 入口，connect/disconnect，事件分发 |
| `room/RTCEngine.kt` | 信令 + 双 PC 传输核心 |
| `room/SignalClient.kt` | WebSocket 信令客户端 |
| `room/PeerConnectionTransport.kt` | PC 封装、SDP munge、offer |
| `room/PublisherTransportObserver.kt` / `SubscriberTransportObserver.kt` | PC 回调 |
| `room/participant/LocalParticipant.kt` | 发布流程 |
| `room/participant/RemoteParticipant.kt` | 订阅流程 |
| `room/track/LocalVideoTrack.kt` / `LocalAudioTrack.kt` | 采集/发布封装 |
| `room/track/RemoteTrackPublication.kt` | 远端订阅控制 |
| `room/track/Track.kt` | Track 基类 |
| `webrtc/SimulcastVideoEncoderFactoryWrapper.kt` | 编码器工厂 |
| `webrtc/PeerConnectionFactoryManager.kt` / `peerconnection/RTCThreadUtils.kt` | 工厂与线程模型 |
| `webrtc/RTCStatsExt.kt` | getStats 过滤 |
| `room/metrics/RTCMetricsManager.kt` | 指标采集上报 |
