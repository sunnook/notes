# LiveKit Android 客户端 SDK 工程梳理

> 这是 LiveKit 的 Android 客户端 SDK——一个基于 WebRTC 的实时音视频通信库，通过 WebSocket 信令与 LiveKit
> 服务器交互，建立 P2P/转发音视频流。用 Kotlin 写，依赖注入用 Dagger，异步用 Kotlin 协程。
>
> 配合 `lkt-deep-dive.md`（协商 / QoS / 发布订阅 / 重点模块速查）阅读。

---

## 一、模块结构（settings.gradle 定义）

```
livekit-android (根工程)
│
├─ 📦 livekit-android-sdk          ← 核心 SDK（你要重点看的）
├─ 📦 livekit-android-camerax       ← CameraX 采集支持
├─ 📦 livekit-android-track-processors ← 轨道处理器（虚拟背景等 ML 处理）
│
├─ 📦 livekit-lint                  ← 自定义 Android Lint 规则
├─ 📦 livekit-detekt-rules          ← 自定义 Detekt(静态分析) 规则
├─ 📦 livekit-android-test          ← 测试基础设施
│
├─ 📦 video-encode-decode-test      ← 编解码性能测试 app
│
├─ 📱 sample-app-basic              ← 最简示例（一个 Activity 搞定，入门必看）
├─ 📱 sample-app / sample-app-compose ← 完整示例（View / Compose 两版）
├─ 📱 sample-app-common             ← 示例共享代码（CallViewModel 等）
├─ 📱 sample-app-record-local       ← 本地录制示例
│
├─ 📱 examples/virtual-background   ← 虚拟背景示例
├─ 📱 examples/screenshare-audio     ← 屏幕共享音频示例
│
└─ 📁 protocol/                     ← protobuf 协议定义（生成 livekit_models/rtc/metrics）
```

**依赖关系**：所有 sample-app 都依赖 `livekit-android-sdk`；`track-processors` 和 `camerax` 是可选增强模块。

---

## 二、核心 SDK 内部包结构（io.livekit.android.*）

```
io.livekit.android
├─ LiveKit.kt              ← 🚪 全局入口（object 单例）
├─ ConnectOptions.kt       ← 连接参数
├─ RoomOptions.kt          ← 房间配置
│
├─ room/                   ← 🧠 核心引擎层
│   ├─ Room.kt             ←   顶层房间对象（用户直接交互）
│   ├─ RTCEngine.kt        ←   WebRTC 引擎（管理 PeerConnection）
│   ├─ SignalClient.kt      ←   信令客户端（WebSocket）
│   ├─ PeerConnectionTransport.kt ← 传输封装
│   └─ RegionUrlProvider.kt ←   云区域选路
│
├─ room/participant/       ← 参与者层
│   ├─ Participant.kt       ←   抽象基类
│   ├─ LocalParticipant.kt  ←   本地参与者（发布音视频）
│   └─ RemoteParticipant.kt ←   远端参与者（订阅音视频）
│
├─ room/track/             ← 媒体轨道层
│   ├─ Track.kt            ←   抽象轨道（音频/视频）
│   ├─ AudioTrack/VideoTrack.kt
│   ├─ LocalAudioTrack/LocalVideoTrack.kt   ← 本地采集
│   └─ RemoteAudioTrack/RemoteVideoTrack.kt ← 远端订阅
│
├─ room/datastream/        ← 数据流（发消息/字节流）
├─ room/rpc/               ← 远程过程调用
├─ room/network/           ← 网络监听/重连策略
├─ room/metrics/           ← 统计指标采集
│
├─ dagger/                 ← 🔧 依赖注入（Dagger Component/Module）
├─ events/                 ← 事件总线（RoomEvent/ParticipantEvent…）
├─ e2ee/                   ← 端到端加密
├─ audio/                  ← 音频设备管理（AudioSwitch）
├─ renderer/               ← 视频渲染（SurfaceView/TextureView）
├─ webrtc/                 ← WebRTC 原生封装
├─ token/ stats/ util/      ← Token/统计/工具
```

---

## 三、核心类关系图

```
                    ┌─────────────┐
   用户调用          │   LiveKit   │  (object 单例，入口)
                    └──────┬──────┘
                           │ create()
                           ▼
              ┌────────────────────────┐
              │  DaggerLiveKitComponent  │  ← 依赖注入容器
              │  (装配所有依赖)          │
              └────────────┬───────────┘
                           │ roomFactory().create()
                           ▼
                    ┌─────────────┐    持有    ┌──────────────────┐
                    │    Room     │───────────▶│  LocalParticipant│ (本地，发布)
                    │ (顶层对象)  │            └──────────────────┘
                    └──────┬──────┘    持有    ┌──────────────────┐
                           │─────────────────▶│ RemoteParticipant│ (远端，订阅)
                           │ 持有 engine      └──────────────────┘
                           ▼
                  ┌─────────────────┐
                  │   RTCEngine     │  ← WebRTC 引擎
                  │ (管理媒体传输)   │
                  └────────┬────────┘
                           │ 持有 client
                           ▼
                  ┌─────────────────┐         ┌─────────────────────┐
                  │  SignalClient   │◀────────│  WebSocket (OkHttp) │
                  │ (信令收发)       │         │  与 LiveKit 服务器通信│
                  └─────────────────┘         └─────────────────────┘
                           │
                           ▼ 配合
                  ┌─────────────────┐
                  │ PeerConnection  │ ← WebRTC 核心（publisher + subscriber 两条）
                  │ (WebRTC 媒体通道)│
                  └─────────────────┘
```

**C++ 类比**：
`LiveKit` ≈ 全局工厂；
`Dagger` ≈ 一个自动装配依赖的 IoC 容器（new 好所有对象并注入构造函数）；
`Room` ≈ 你直接操作的 Facade；
`RTCEngine` + `SignalClient` ≈ 底层引擎，分离了"信令"（WebSocket 控制消息）和"媒体"（WebRTC PeerConnection 传音视频）两条通道。

---

## 四、初始化流程

```
LiveKit.create(appContext, options)
    │
    │ 1. 取 applicationContext
    ▼
DaggerLiveKitComponent.factory().create(ctx, overrides)
    │
    │ 2. Dagger 编译期生成代码，装配 8 个 Module：
    │    RTCModule(WebRTC初始化/EglBase/PeerConnectionFactory)
    │    CoroutinesModule(协程调度器)  WebModule(OkHttp/WebSocket工厂)
    │    JsonFormatModule  AudioHandlerModule  MemoryModule ...
    ▼
component.roomFactory().create(ctx)
    │
    │ 3. 通过 @AssistedInject 构造 Room，注入：
    │    RTCEngine, EglBase, LocalParticipant.Factory, 调度器, AudioHandler...
    ▼
room.setRoomOptions(options)   ← 应用房间配置
    │
    ▼
返回 Room 实例（此时还未连接，只是装配好对象）
```

> WebRTC 原生库的初始化在 `RTCModule.libWebrtcInitialization()`，`LiveKit.init()` 可手动提前调用，正常情况 `create()` 会自动处理。

---

## 五、连接 & 运行流程（最关键）

以 `sample-app-basic/MainActivity.kt` 为例，用户代码就三步：

```kotlin
room = LiveKit.create(applicationContext)          // ① 创建
lifecycleScope.launch { room.connect(url, token) } // ② 连接
localParticipant.setMicrophoneEnabled(true)        // ③ 发布音视频
```

`room.connect()` 内部的完整流程：

```
room.connect(url, token, options)
│
├─ state: DISCONNECTED → CONNECTING
├─ 创建 coroutineScope（协程作用域，所有后续异步在此跑）
├─ localParticipant.reinitialize()   ← 初始化本地参与者
├─ (可选) e2eeManager.setup()        ← 端到端加密
│
└─ connectJob (在 IO 协程):
    │
    ├─ 若是 LiveKit Cloud → RegionUrlProvider 选最优区域 URL
    │
    └─ engine.join(connectUrl, token, options, roomOptions)   ★核心
        │
        ├─ client.join(url, token, ...)        ← SignalClient
        │     ├─ OkHttp 建立 WebSocket 连接到服务器
        │     ├─ 发送 SignalRequest(JoinRequest)
        │     └─ 等待 SignalResponse(JoinResponse)  ← 服务器返回房间信息/ICE服务器/其他参与者
        │
        ├─ configure(joinResponse)             ← RTCEngine
        │     ├─ makeRTCConfig()  (配置 ICE 服务器)
        │     └─ 创建两条 PeerConnection:
        │           publisher   (本地→服务器，发布媒体)
        │           subscriber  (服务器→本地，订阅媒体)
        │
        ├─ negotiatePublisher()                 ← WebRTC 协商
        │     ├─ publisher.createOffer()
        │     ├─ setLocalDescription
        │     └─ client.sendOffer()  → 通过 WebSocket 发给服务器
        │
        └─ onReadyForResponses()  ← 准备接收后续信令
    │
    ├─ networkCallbackManager.registerCallback() ← 监听网络变化（触发重连）
    │
    ├─ options.audio → localParticipant.setMicrophoneEnabled(true)  ← 发布麦克风
    ├─ options.video → localParticipant.setCameraEnabled(true)      ← 发布摄像头
    │
    └─ collectMetrics() ← 后台采集 WebRTC 统计
    │
    ▼
state: CONNECTED ✅
```

**运行中的双通道**（这是理解整个工程的关键）：

```
            ┌─────────────── App / Room ───────────────┐
            │                                          │
   信令通道  │   SignalClient ◀──WebSocket──▶ LiveKit服务器 │  控制消息：join/offer/answer/
   (控制)   │   (收发 JSON/protobuf 信令)                │           ICE candidate/mute/订阅
            │                                          │
   媒体通道  │   RTCEngine ◀──PeerConnection──▶ 服务器    │  实际音视频 RTP 流
   (数据)   │   (publisher 发 / subscriber 收)          │  (SRTP 加密传输)
            └──────────────────────────────────────────┘
```

- **信令通道**（SignalClient + WebSocket）：传控制信息，告诉双方"谁在房间、怎么连、谁静音了"。
- **媒体通道**（RTCEngine + WebRTC PeerConnection）：传真正的音视频数据，走 SRTP 加密的 UDP。

这跟 C++ 里做网络通信时"控制连接 + 数据连接"分离是同一个思路。

---

## 六、事件机制

Room 通过 **Kotlin Flow** 暴露事件，用户用 `room.events.collect { }` 监听：

```kotlin
room.events.collect { event ->
    when (event) {
        is RoomEvent.TrackSubscribed    -> // 远端轨道已订阅，可渲染
        is RoomEvent.ParticipantConnected -> // 有人进房
        is RoomEvent.ParticipantDisconnected -> // 有人离开
        is RoomEvent.Disconnected       -> // 自己掉线
        ...
    }
}
```

事件定义在 `events/RoomEvent.kt`、`ParticipantEvent.kt`、`TrackEvent.kt`，通过 `BroadcastEventBus` 分发。

---

## 七、建议阅读顺序（入门路径）

1. **`sample-app-basic/MainActivity.kt`** — 50 行看懂怎么用（最直观）
2. **`LiveKit.kt`** — 入口，看 `create()` 怎么装配
3. **`room/Room.kt`** — 看 `connect()` / `disconnect()`，理解状态机
4. **`room/RTCEngine.kt`** — 看 `join()` / `joinImpl()`，理解 WebRTC 协商
5. **`room/SignalClient.kt`** — 看 WebSocket 信令收发
6. **`room/participant/` + `room/track/`** — 理解音视频发布/订阅模型

**一句话总结**：
`LiveKit.create` 用 Dagger 装配好 `Room` →
 `Room.connect` 通过 `SignalClient`(WebSocket) 完成信令握手、通过 `RTCEngine`(WebRTC PeerConnection) 建立媒体通道 →
  `LocalParticipant` 发布、`RemoteParticipant` 订阅 →
   事件通过 Flow 回调给 App。
