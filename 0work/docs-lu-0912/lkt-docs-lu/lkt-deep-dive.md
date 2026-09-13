# LiveKit Android SDK — 协商 / QoS / 发布订阅 / 重点模块速查

> 配合 `lkt-init-procss.md`（工程结构与初始化流程）阅读。本文深入协商、QoS、发布订阅，并给出重点模块速查表。

---

## 一、WebRTC 协商（Negotiation）深入

### 1.1 为什么要协商

WebRTC 建立媒体连接前，双方必须就"用什么编解码、传哪些媒体流、走哪个网络地址"达成一致。这个交换 SDP（Session Description Protocol）的过程就是**协商**，本质是经典的 **ICE + Offer/Answer** 模型。

LiveKit 里客户端只跟**服务器**协商（SFU 架构，不是纯 P2P）。关键在于：LiveKit 用了**两条独立的 PeerConnection**——这是它和普通 WebRTC demo 最大的区别。

### 1.2 双 PeerConnection 模型

```
                    客户端
        ┌───────────────────────────────┐
        │  publisher PC (上行)          │  本地采集 → 服务器
        │   - 只发 (SEND_ONLY)          │   音视频推流
        │   - 客户端主动 createOffer    │
        ├───────────────────────────────┤
        │  subscriber PC (下行)         │  服务器 → 本地
        │   - 只收 (RECV_ONLY)          │   订阅他人音视频
        │   - 服务器主动 createOffer    │
        └───────────────────────────────┘
                    │
                    ▼  两条 PC 各自独立协商、各自有独立 ICE
              LiveKit 服务器 (SFU)
```

- **publisher**：客户端→服务器，**客户端发起 Offer**（`negotiatePublisher()`）。本地每发布一个 track 就往这条 PC 加一个 transceiver，然后重新协商。
- **subscriber**：服务器→客户端，**服务器发起 Offer**（`onServerOffer`）。服务器决定给你推哪些远端流，客户端只负责 Answer。

> C++ 类比：两条 PC ≈ 两个独立的 socket 通道，各自握手。上行下行解耦，互不阻塞。

### 1.3 协商完整时序

**Publisher 协商（客户端发起）**：
```
negotiatePublisher()                          [RTCEngine.kt:716]
  │
  ├─ hasPublished = true                       ← 标记"有东西要发"
  ├─ 若 client 未连上 → return（等信令连上再补）
  └─ publisher.negotiate(getPublisherOfferConstraints())
        │
        ├─ publisher.createOffer()             ← WebRTC 生成 SDP offer
        ├─ publisher.setLocalDescription(offer)
        └─ client.sendOffer(offer, offerId)    ← 通过 WebSocket 发给服务器
                │                              [SignalClient.kt:422]
                ▼
          服务器处理... 返回 Answer
                │
        onServerAnswer(sd, offerId)            [RTCEngine.kt:1086]
        └─ publisher.setRemoteDescription(answer)  ← 协商完成
```

**Subscriber 协商（服务器发起）**：
```
服务器决定给你推流 → 发 Offer
        │
        ▼
onServerOffer(sd, offerId)                    [RTCEngine.kt:1102]
  ├─ subscriber.setRemoteDescription(offer)    ← 接收服务器 SDP
  ├─ subscriber.createAnswer()                ← 生成应答
  ├─ subscriber.setLocalDescription(answer)
  └─ client.sendAnswer(answer, offerId)       ← 回传服务器
```

**ICE Candidate 交换（贯穿全程）**：
```
onTrickle(candidate, target)                  [RTCEngine.kt:1150]
  ├─ target == PUBLISHER  → publisher.addIceCandidate()
  └─ target == SUBSCRIBER → subscriber.addIceCandidate()
```
ICE candidate 是"我能通过哪些网络路径连到你"的候选地址，双方互发、各自试探，选最优路径打通 NAT（Trickle ICE）。

### 1.4 关键点

- **publisher 协商由客户端驱动**，每发布/取消一个 track 都可能触发 `negotiatePublisher()`（有 `negotiatePublisherMutex` 串行化，避免并发协商冲突）。
- **subscriber 协商由服务器驱动**，客户端被动应答——服务器知道该给你哪些流。
- `isSubscriberPrimary`：某些模式下 subscriber 先协商，publisher 延后（`fastPublish` 时则 publisher 立即协商）。
- 协商消息全走 **SignalClient 的 WebSocket**（信令通道），媒体走 **PeerConnection**（媒体通道）——两条通道分离。

---

## 二、QoS（服务质量保障）

LiveKit 的 QoS 不是单一机制，而是多层叠加：

### 2.1 QoS 层级图

```
┌─────────────────────────────────────────────────┐
│  ① 重连机制 (Reconnect)                          │  网络断开自动恢复
│     RTCEngine.reconnect() + ReconnectPolicy      │
├─────────────────────────────────────────────────┤
│  ② 区域选路 (RegionUrlProvider)                  │  Cloud 多机房就近接入
├─────────────────────────────────────────────────┤
│  ③ 指标采集上报 (Metrics)                        │  WebRTC stats 每秒采集
│     RTCMetricsManager.collectMetrics()           │  通过 datachannel 回传服务器
├─────────────────────────────────────────────────┤
│  ④ 订阅质量调节 (SubscribedQualityUpdate)        │  服务器下发"该发哪档画质"
│     simulcast 多分辨率编码                        │
├─────────────────────────────────────────────────┤
│  ⑤ 网络监听 (NetworkCallbackManager)            │  Android 网络变化触发重连
├─────────────────────────────────────────────────┤
│  ⑥ 数据通道可靠性 (RELIABLE/LOSSY)               │  数据消息可选可靠/尽力传输
│     waitForBufferStatusLow / ensurePublisherConnected │
└─────────────────────────────────────────────────┘
```

### 2.2 重连机制（核心 QoS）

`RTCEngine.reconnect()` [RTCEngine.kt:521]：
```
reconnect()
  ├─ 若已有重连 job 在跑 → return（防重入）
  ├─ 若 engine 已关闭 → return
  └─ for (retries in 0 until MAX_RECONNECT_RETRIES):   ← 最多 30 次（硬上限）
        ├─ retries != 0 → 换区域 URL (getNextBestRegionUrl)
        ├─ reconnectPolicy.getNextRetryDelay(context)  ← 指数退避策略
        │     └─ 返回 null → 放弃重连
        ├─ delay(startDelay)                          ← 退避等待
        │
        ├─ 判断重连类型:
        │   - DEFAULT: 第一次软重连，之后全量重连
        │   - FORCE_SOFT_RECONNECT: 只重连信令
        │   - FORCE_FULL_RECONNECT: 全量重连
        │
        ├─ 软重连 (resume): 只重连信令，保留 PeerConnection
        │   └─ client.reconnect() + resendReliableMessagesForResume()
        │
        └─ 全量重连 (full): closeResources() + 重新 joinImpl()
            └─ 重新走完整 join + 协商流程
```

- **软重连（resume）**：网络抖动短暂断开，信令断了但媒体 PC 可能还活着，只重连 WebSocket，快。
- **全量重连（full）**：彻底重建，重新 join + 重新协商两条 PC。
- `ReconnectPolicy` [network/ReconnectPolicy.kt] 是接口，`getNextRetryDelay(ReconnectContext)` 决定每次退避时长，可自定义。`ReconnectContext` 含 `retryCount`、`elapsedTime`。

### 2.3 指标采集（Metrics）

`RTCMetricsManager.kt`：每秒从 publisher/subscriber 两条 PC 拉 WebRTC stats（丢包率、码率、RTT、抖动…），封装成 protobuf `MetricsBatch`，通过 **publisher 的 datachannel** 回传服务器。服务器据此做全局调度（比如切换转发节点）。

```
collectMetrics(room, rtcEngine)
  ├─ collectPublisherMetrics()  ← 每秒 delay(1000) 循环
  └─ collectSubscriberMetrics() ← 同上
        └─ getPublisherRTCStats / getSubscriberRTCStats
            → 封装 MetricsBatch → engine.sendData()
```

### 2.4 订阅质量调节（Simulcast）

`onSubscribedQualityUpdate` [Room.kt:1415]：服务器告诉本地参与者"对方订阅你时只需要 LOW/MEDIUM/HIGH 哪档"。配合 **simulcast**（同一视频编码多档分辨率），服务器按接收方带宽动态选档，避免上行浪费。

```
服务器 ──SubscribedQualityUpdate──▶ Room
   └─ localParticipant.handleSubscribedQualityUpdate()
        └─ 调整编码器输出哪几档 simulcast 层
```

### 2.5 数据通道可靠性

`sendData()` [RTCEngine.kt:733] 发数据消息时：
- `RELIABLE`：保证到达，带序号 `reliableDataSequence`，重连后 `resendReliableMessagesForResume` 补发。
- `LOSSY`：尽力传，丢了就丢了（适合实时性高的场景）。
- `waitForBufferStatusLow` / `ensurePublisherConnected`：发送前检查 publisher datachannel 缓冲，避免背压。

---

## 三、发布 / 订阅（Publish / Subscribe）是什么意思

### 3.1 概念

LiveKit 是 **SFU 架构**（Selective Forwarding Unit，选择性转发单元），不是网状 P2P：

```
   网状 P2P (mesh)              SFU (LiveKit 用的)
   每人直连其他所有人             每人只连服务器，服务器转发
   N人需 N*(N-1)/2 连接          N人只需 N 连接
   适合 2-3 人                   适合多人会议
```

- **发布（Publish）**：本地参与者把自己的音视频流**推到服务器**。`LocalParticipant` 负责。
- **订阅（Subscribe）**：从服务器**拉取其他参与者的音视频流**。`RemoteParticipant` 负责。
- 服务器只做转发，不混流——所以叫"选择性转发"，每路流独立。

### 3.2 发布流程（LocalParticipant）

`LocalParticipant.publishTrackImpl()` [LocalParticipant.kt:631]：

```
setMicrophoneEnabled(true) / setCameraEnabled(true)
  └─ setTrackEnabled() → 创建 LocalAudioTrack/LocalVideoTrack (WebRTC 采集)
        └─ publishTrackImpl(track, options)
              │
              ├─ 权限检查: hasPermissionsToPublish()   ← token 里带权限
              ├─ 重复检查: isTrackPublished()            ← 已发过就跳过
              ├─ 连接检查: engine.connectionState
              │
              ├─ negotiate():
              │   ├─ engine.createSenderTransceiver(track, SEND_ONLY)
              │   │     ← 在 publisher PC 上加一个发送 transceiver
              │   └─ engine.negotiatePublisher()        ← 触发重新协商(见上)
              │
              ├─ requestAddTrack() → client.sendAddTrack()  ← 信令通知服务器
              │     ← 服务器返回 TrackPublishedResponse(分配 trackSid)
              │
              └─ 创建 LocalTrackPublication，加入 trackPublications
                    └─ 发 ParticipantEvent.LocalTrackPublished 事件
```

> 关键：发布 = 在 publisher PC 加 transceiver + 重新协商 + 信令通知服务器分配 sid。

### 3.3 订阅流程（RemoteParticipant，服务器驱动）

订阅是**服务器主动推**的，客户端被动接收：

```
服务器决定把某远端 track 转发给你
  │
  ├─ 通过 subscriber PC 的 onTrack 回调收到 WebRTC MediaStreamTrack
  │
  └─ 信令通知: onTrackSubscribed(track, publication, participant)  [Room.kt:1562]
        ├─ 包装成 RemoteAudioTrack / RemoteVideoTrack
        ├─ 加入 RemoteParticipant.trackPublications
        └─ 发 RoomEvent.TrackSubscribed  ← App 收到后 addRenderer() 渲染
```

客户端也可**主动控制订阅**（`RemoteTrackPublication`）：
```
remoteTrackPublication.setSubscribed(true/false)   ← 订阅/取消订阅
remoteTrackPublication.setEnabled(true/false)      ← 暂停/恢复(不解码)
remoteTrackPublication.setVideoQuality(LOW/MEDIUM/HIGH)  ← 选画质档
  └─ client.sendUpdateSubscription() / sendUpdateTrackSettings()
```

### 3.4 数据类对比

| | LocalParticipant | RemoteParticipant |
|---|---|---|
| 角色 | 发布者（上行） | 订阅者（下行） |
| Track 类型 | LocalAudioTrack / LocalVideoTrack | RemoteAudioTrack / RemoteVideoTrack |
| Publication | LocalTrackPublication | RemoteTrackPublication |
| 关键操作 | setMicrophoneEnabled / setCameraEnabled / publishTrack | setSubscribed / setVideoQuality |
| 触发协商 | 主动 negotiatePublisher | 被动 onServerOffer |

---

## 四、重点模块速查表

按"看代码优先级"排序。路径相对 `livekit-android-sdk/src/main/java/io/livekit/android/`。

| # | 模块 | 作用 | 关键文件 | 建议阅读顺序 |
|---|------|------|----------|-------------|
| 1 | **入口** | 全局单例，创建 Room，初始化 WebRTC | `LiveKit.kt` | ① 最先看 |
| 2 | **配置** | 连接参数 / 房间选项 / E2EE 选项 | `ConnectOptions.kt` `RoomOptions.kt` `e2ee/E2EEOptions.kt` | ② |
| 3 | **Room** | 顶层房间对象，状态机，连接/断开/重连入口，事件分发 | `room/Room.kt` | ③ 核心 |
| 4 | **RTCEngine** | WebRTC 引擎，管理两条 PeerConnection，协商，收发数据 | `room/RTCEngine.kt` | ④ 核心 |
| 5 | **SignalClient** | 信令客户端，WebSocket 收发 protobuf 信令 | `room/SignalClient.kt` | ⑤ |
| 6 | **传输** | PeerConnection 封装，publisher/subscriber transport observer | `room/PeerConnectionTransport.kt` `room/PublisherTransportObserver.kt` `room/SubscriberTransportObserver.kt` | ⑥ |
| 7 | **LocalParticipant** | 本地参与者，发布音视频/数据/屏幕共享，RPC | `room/participant/LocalParticipant.kt` | ⑦ |
| 8 | **RemoteParticipant** | 远端参与者，管理订阅的远端 track | `room/participant/RemoteParticipant.kt` | ⑧ |
| 9 | **Participant 基类** | 公共属性(sid/identity/metadata)、trackPublications、事件 | `room/participant/Participant.kt` | 配合 7/8 |
| 10 | **Track 体系** | 轨道抽象，音频/视频，本地/远端，simulcast 编解码 | `room/track/Track.kt` `AudioTrack.kt` `VideoTrack.kt` `LocalAudioTrack.kt` `LocalVideoTrack.kt` `RemoteAudioTrack.kt` `RemoteVideoTrack.kt` `LocalScreencastVideoTrack.kt` | ⑨ |
| 11 | **TrackPublication** | 发布/订阅的元信息载体，订阅控制 | `room/track/TrackPublication.kt` `LocalTrackPublication.kt` `RemoteTrackPublication.kt` `VideoQuality.kt` | ⑩ |
| 12 | **事件系统** | RoomEvent/ParticipantEvent/TrackEvent 定义，BroadcastEventBus 分发 | `events/RoomEvent.kt` `ParticipantEvent.kt` `TrackEvent.kt` `BroadcastEventBus.kt` `EventListenable.kt` | ⑪ |
| 13 | **依赖注入** | Dagger 装配所有依赖，8 个 Module | `dagger/LiveKitComponent.kt` `RTCModule.kt` `CoroutinesModule.kt` `WebModule.kt` `AudioHandlerModule.kt` `OverridesModule.kt` `MemoryModule.kt` `InternalBindsModule.kt` `JsonFormatModule.kt` | ⑫ 理解装配 |
| 14 | **重连/网络** | 重连策略，区域选路，网络变化监听 | `room/network/ReconnectPolicy.kt` `room/RegionUrlProvider.kt` `room/network/NetworkCallbackManagerFactory.kt` | ⑬ QoS |
| 15 | **指标采集** | 每秒采 WebRTC stats 上报服务器 | `room/metrics/RTCMetricsManager.kt` | ⑭ QoS |
| 16 | **数据流** | 发送/接收字节流、文本流（大块数据传输） | `room/datastream/outgoing/BaseStreamSender.kt` `ByteStreamSender.kt` `TextStreamSender.kt` `room/datastream/incoming/BaseStreamReceiver.kt` `ByteStreamReceiver.kt` `TextStreamReceiver.kt` `IncomingDataStreamManager.kt` `OutgoingDataStreamManager.kt` | ⑮ |
| 17 | **RPC** | 远程过程调用，客户端间互调 | `room/rpc/RpcManager.kt` `RpcClientManager.kt` `RpcServerManager.kt` `RpcConstants.kt` `rpc/RpcError.kt` | ⑯ |
| 18 | **E2EE** | 端到端加密，密钥管理，数据包加解密 | `e2ee/E2EEManager.kt` `KeyProvider.kt` `DataPacketCryptorManager.kt` `E2EEState.kt` | ⑰ |
| 19 | **音频** | 音频设备切换(AudioSwitch)，通信模式 workaround，预处理 | `audio/AudioSwitchHandler.kt` `audio/AudioHandler.kt` `audio/CommunicationWorkaround.kt` `audio/AudioRecordPrewarmer.kt` `audio/AudioProcessingController.kt` | ⑱ |
| 20 | **渲染** | 视频渲染器，SurfaceView/TextureView | `renderer/TextureViewRenderer.kt` `renderer/`(包) | ⑲ |
| 21 | **WebRTC 封装** | 原生 WebRTC API 封装，Camera helper | `webrtc/`(包) `livekit/org/webrtc/Camera2Helper.kt` `Camera1Helper.kt` | ⑳ 底层 |
| 22 | **工具** | 日志、协程工具、Flow 委托、URL 工具 | `util/LKLog.kt` `CoroutineUtil.kt` `FlowDelegate.kt` `UrlUtils.kt` `MutexEx.kt` | 按需 |
| 23 | **协议** | protobuf 定义，生成 LivekitModels/Rtc/Metrics | `protocol/protobufs/` (根目录) | 参考 |
| 24 | **可选增强** | CameraX 采集 / 轨道 ML 处理(虚拟背景) | `livekit-android-camerax/` `livekit-android-track-processors/` | 按需 |
| 25 | **示例** | 最简示例 / 完整示例 / Compose / 录制 | `sample-app-basic/` `sample-app-common/` `sample-app-compose/` `sample-app-record-local/` | 入门先看 basic |

### 阅读路径建议

```
入门:  25(sample-basic) → 1(LiveKit) → 3(Room.connect) → 7/8(Participant)
        ↓
协商:  4(RTCEngine.join/negotiate) → 5(SignalClient) → 6(PeerConnectionTransport)
        ↓
QoS:   14(Reconnect) → 15(Metrics) → 11(VideoQuality/simulcast)
        ↓
进阶:  16(DataStream) → 17(RPC) → 18(E2EE) → 19(Audio)
        ↓
底层:  13(Dagger装配) → 21(WebRTC封装) → 23(protobuf协议)
```

---

## 五、核心数据流总览图

```
┌──────────────────── App 层 (你的代码) ────────────────────┐
│  LiveKit.create() → Room                                  │
│  room.events.collect { } 监听事件                         │
│  localParticipant.setMicrophoneEnabled(true) 发布          │
│  remoteTrackPublication.addRenderer() 渲染                │
└─────────────────────────┬────────────────────────────────┘
                          │
┌─────────────────────────▼ Room (状态机 + 事件分发) ───────┐
│  state: DISCONNECTED→CONNECTING→CONNECTED→RECONNECTING   │
│  events: BroadcastEventBus → Flow                        │
├──────────────┬───────────────────────────────────────────┤
│  上行(发布)   │              下行(订阅)                    │
│  LocalParticipant         RemoteParticipant               │
│   LocalAudioTrack          RemoteAudioTrack                │
│   LocalVideoTrack          RemoteVideoTrack                │
│   ↓ publishTrackImpl       ↑ onTrackSubscribed             │
├──┴──────────────────────────┴────────────────────────────┤
│                    RTCEngine                              │
│   ┌─ publisher PC ──┐    ┌─ subscriber PC ──┐             │
│   │  createOffer    │    │  onServerOffer    │             │
│   │  → sendOffer    │    │  → createAnswer   │             │
│   │  ← onServerAns  │    │  → sendAnswer     │             │
│   └────────┬───────┘    └─────────┬────────┘             │
│            │ ICE candidate 交换(onTrickle)                │
├────────────┴───────────────────────┴──────────────────────┤
│              SignalClient (WebSocket 信令)                │
│   join / offer / answer / trickle / mute / subscribe ...  │
└───────────────────────────┬───────────────────────────────┘
                            │ WebSocket (OkHttp)
                            ▼
                     LiveKit 服务器 (SFU)
                            │
              ┌─────────────┴──────────────┐
              │  publisher PC: 收你的流     │
              │  subscriber PC: 转发他人流   │
              │  QoS: 指标采集/质量调节/重连 │
              └────────────────────────────┘
```

---

## 附：关键代码位置索引

| 功能 | 文件:行 |
|------|---------|
| 创建 Room | `LiveKit.kt` create() |
| 连接 | `room/Room.kt:461` connect() |
| 断开 | `room/Room.kt:609` disconnect() |
| 重连入口 | `room/Room.kt:992` reconnect() |
| 引擎 join | `room/RTCEngine.kt:235` join() / `:250` joinImpl() |
| 配置 PC | `room/RTCEngine.kt:279` configure() |
| 发起协商 | `room/RTCEngine.kt:716` negotiatePublisher() |
| 收服务器 Answer | `room/RTCEngine.kt:1086` onServerAnswer() |
| 收服务器 Offer | `room/RTCEngine.kt:1102` onServerOffer() |
| ICE candidate | `room/RTCEngine.kt:1150` onTrickle() |
| 引擎重连 | `room/RTCEngine.kt:521` reconnect() |
| 发数据 | `room/RTCEngine.kt:733` sendData() |
| 信令 join | `room/SignalClient.kt:131` join() |
| 发 Offer/Answer | `room/SignalClient.kt:422/431` |
| 发布 track | `room/participant/LocalParticipant.kt:631` publishTrackImpl() |
| 发布音频 | `room/participant/LocalParticipant.kt:449` publishAudioTrack() |
| 发布视频 | `room/participant/LocalParticipant.kt:506` publishVideoTrack() |
| 订阅控制 | `room/track/RemoteTrackPublication.kt:126/143/159` |
| 订阅事件 | `room/Room.kt:1562` onTrackSubscribed() |
| 质量调节 | `room/Room.kt:1415` onSubscribedQualityUpdate() |
| 指标采集 | `room/metrics/RTCMetricsManager.kt` collectMetrics() |
| 重连策略 | `room/network/ReconnectPolicy.kt` |
| 区域选路 | `room/RegionUrlProvider.kt` |
