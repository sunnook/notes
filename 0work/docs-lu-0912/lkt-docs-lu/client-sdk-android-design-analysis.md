# LiveKit Android SDK 设计分析

> 目标读者：有 C/C++ 经验但对 Android/Java/Kotlin 不熟悉的开发者。

---

## 第 1 章：项目概览与专业背景

### 1.1 项目简介

LiveKit Android SDK 是一个基于 [WebRTC](https://webrtc.org/) 的实时音视频通信 SDK，用于在 Android 应用中实现多人视频会议、直播、屏幕共享等功能。它以 Kotlin 编写，遵循响应式编程范式，使用协程（Coroutines）管理异步流程，通过 Dagger 2 进行依赖注入。

### 1.2 Gradle 多模块架构

项目使用 Gradle 管理，共有以下核心模块：

| 模块名 | 职责 |
|--------|------|
| `livekit-android-sdk` | **核心 SDK**，包含 Room、RTCEngine、信号管理、参与者管理、Track 等 |
| `livekit-android-camerax` | CameraX 集成，提供基于 AndroidX CameraX 的摄像头采集器 |
| `livekit-android-track-processors` | 音视频帧处理插件，当前实现为虚拟背景（OpenGL ES Shader） |
| `livekit-lint` | 自定义 Lint 规则（编译时静态检查） |
| `livekit-detekt-rules` | 自定义 Detekt 规则（代码风格检查） |
| `sample-app*` | 多种示例应用（标准版、Compose 版、基础版、本地录制版） |

### 1.3 专业背景补充

对于 C/C++ 开发者，以下是 Android 开发中的关键概念：

#### 1.3.1 Kotlin 核心概念速查

| 概念 | 说明 | C/C++ 类比 |
|------|------|------------|
| `data class` | 数据类，自动合成 `equals`/`hashCode`/`toString`/`copy` | 类似 struct + 自动生成工具函数 |
| `sealed class` | 密封类，所有子类在编译期已知 | 类似 enum 的广义版，可携带数据 |
| `interface` | 接口，方法可以有默认实现（default method） | C++ 纯虚类 + 混入（mixin） |
| `inline class / @JvmInline value class` | 内联类，零运行时开销的类型包装 | 类似 C++ `std::optional<T>` 的包装类型，但无分配 |
| `suspend fun` | 挂起函数，可被挂起和恢复的异步函数 | 类似 C++20 `co_await`/generator 的 Kotlin 实现 |
| `coroutineScope` | 结构化并发，子协程生命周期绑定到父协程 | 类似 RAII 风格的并发作用域管理 |
| `flow<T>` | 响应式数据流，支持背压 | 类似 C++ Ranges 或 RxJava Observable |
| `StateFlow<T>` | 状态流，始终保留最新值，新观察者立即可获取 | 类似带缓冲的广播信号量 |
| `by flowDelegate(null)` | Kotlin Property Delegate，属性值变化时触发回调 | 类似 C++ 的 property 封装（get/set hook） |
| `@AssistedInject` | Dagger 辅助注入，运行时传入参数 | 类似工厂模式 + 依赖注入的结合 |
| `::flow` | 属性转 Flow 的语法糖 | C++ 无直接对应 |

#### 1.3.2 Dagger 2 依赖注入

Dagger 是一个编译时依赖注入框架：

```
Dagger 类比：类似 C++ 的 "控制反转容器"（IoC Container）
- @Component：容器，定义可注入哪些类型
- @Module：提供具体实现
- @Inject：标记需要注入的构造函数
- @Singleton：单例（Dagger 作用域，非 javax）
- @AssistedInject：运行时动态注入某些参数（需配合 Factory 接口）
```

#### 1.3.3 Android 组件生命周期

| 组件 | 生命周期 | C/C++ 类比 |
|------|----------|------------|
| `Application` | 进程启动到销毁 | 类似 global static constructor/destructor |
| `Context` | 应用上下文（ApplicationContext）存活于整个进程 | 类似全局上下文/单例 |
| `Activity` | onCreate → onStart → onResume → onPause → onDestroy | 类似窗口生命周期的回调链 |
| `LifecycleOwner` | 提供生命周期感知的事件流 | 类似观察者模式 + 生命周期钩子 |

#### 1.3.4 Java/Kotlin 内存模型

- **所有对象都在堆上分配**（无 C++ 的栈对象，基本类型除外）
- **GC（Garbage Collection）** 自动回收内存，开发者关注「引用生命周期」
- **`lateinit var`**：延迟初始化的非空变量，类似 C++ 的「后置初始化」
- **`internal` 可见性**：模块内可见，类似 C++ 的 `static` 链接但作用于模块级

---

## 第 2 章：入口与生命周期

### 2.1 入口：`LiveKit.create()`

SDK 的唯一公开入口是 `LiveKit` 单例对象中的 `create()` 方法：

```kotlin
// 调用入口
val room = LiveKit.create(
    context = applicationContext,
    options = RoomOptions(/* ... */),
    overrides = LiveKitOverrides(/* ... */)
)
```

`LiveKit` 是一个 Kotlin `object`（单例），内部维护全局状态：

```
LiveKit (object 单例)
├── loggingLevel      : 全局日志级别
├── logger            : 全局日志接口（可替换）
├── enableWebRTCLogging : 是否开启底层 WebRTC 日志
└── create()          : 创建 Room 实例 ← 主要入口
```

### 2.2 Dagger 依赖注入

`create()` 内部执行以下初始化流程：

```
LiveKit.create()
  │
  ├─ 1. DaggerLiveKitComponent.factory().create(context, overrides)
  │       │
  │       └─ 初始化 Dagger 容器，注入所有 @Singleton 对象：
  │           ├── EglBase              : OpenGL ES 上下文
  │           ├── PeerConnectionFactory  : WebRTC 工厂（native 层）
  │           ├── AudioDeviceModule      : 音频设备模块
  │           ├── SignalClient           : WebSocket 信令客户端
  │           ├── RTCEngine              : 连接引擎
  │           ├── CloseableManager       : 资源管理
  │           ├── E2EEManager.Factory    : 加密管理器
  │           └── ... 各种 Manager 和 Provider
  │
  └─ 2. component.roomFactory().create(context)
          │
          └─ 创建 Room 实例，注入所有依赖
```

**关键依赖树：**

```
LiveKitComponent (Dagger Container)
├── CoroutinesModule        → 协程调度器 (Default / IO)
├── RTCModule               → WebRTC 核心 (PeerConnectionFactory, ADM)
├── WebModule               → OkHttp, WebSocket 工厂
├── JsonFormatModule        → Kotlinx Serialization JSON
├── OverridesModule         → 用户自定义覆盖（如 AudioHandler）
├── AudioHandlerModule      → 音频处理器（默认 AudioSwitchHandler）
├── MemoryModule            → CloseableManager, 资源清理
└── InternalBindsModule     → 内部绑定
```

> **专业补充：为什么用 Dagger？** Dagger 在**编译时**生成依赖图代码，运行时零反射开销。类似 C++ 的「编译时模板元编程」解决运行时多态问题——用空间换时间。

### 2.3 Room 对象生命周期

`Room` 是整个 SDK 的核心对象，其生命周期如下：

```
 Room 创建 (LiveKit.create)
        │
        ▼
 ┌──────────────┐
 │ State:       │
 │ DISCONNECTED │ ← 初始状态
 └──────┬───────┘
        │
        │ room.connect(url, token)
        ▼
 ┌──────────────┐
 │ State:       │
 │   CONNECTING │ ← WebSocket 连接中
 └──────┬───────┘
        │
        ▼ (成功)
 ┌──────────────┐
 │ State:       │
 │   CONNECTED  │ ← WebRTC 连接建立，可收发音视频
 └──────┬───────┘
        │
        │ 网络中断
        ▼
 ┌──────────────┐
 │ State:       │
 │ RECONNECTING │ ← 自动重连尝试
 └──────┬───────┘
        │
        ▼ (成功)
 ┌──────────────┐
 │ State:       │
 │   CONNECTED  │ ← 重连成功
 └──────┬───────┘
        │
        │ room.disconnect() / 服务器主动断开
        ▼
 ┌──────────────┐
 │ State:       │
 │ DISCONNECTED │ ← 连接断开
 └──────┬───────┘
        │
        │ room.release()
        ▼
    [ 资源释放，对象不可再用 ]
```

### 2.4 connect() 流程详解

`room.connect(url, token)` 是核心操作，按以下顺序执行：

```
connect(url, token)
  │
  ├─ 1. 状态检查（mutex 锁保护）
  ├─ 2. 创建新的 CoroutineScope（SupervisorJob）
  ├─ 3. 初始化 LocalParticipant（自身参与者）
  ├─ 4. 设置 E2EE 加密（如果配置）
  │
  ├─ 5. 音频预处理
  │   ├─ 认证 AudioProcessingController（如果启用）
  │   └─ 启动 AudioPreconnect 预加热
  │
  ├─ 6. 区域选择（LiveKit Cloud）
  │   └─ RegionUrlProvider 选择最优 Edge DC
  │
  ├─ 7. RTCEngine.join()
  │   ├─ SignalClient.join() → WebSocket 连接 + Auth
  │   ├─ 收到 JoinResponse
  │   ├─ 配置 PeerConnection（Publisher + Subscriber）
  │   ├─ 创建 DataChannel（_reliable / _lossy）
  │   └─ Publisher ICE 协商（如果是 subscriber primary 模式）
  │
  ├─ 8. 自动启用麦克风/摄像头
  │   ├─ options.audio  → setMicrophoneEnabled(true)
  │   └─ options.video → setCameraEnabled(true)
  │
  └─ 9. 启动 Metrics 采集
```

### 2.5 资源释放

```kotlin
// 方式 1：断开 + 清理
room.disconnect()     // 发送 Leave 信令
room.release()        // 关闭所有资源

// 方式 2：直接释放
room.release()        // 内部会先 disconnect()
```

`release()` 内部清理顺序：
1. `disconnect()` — 发送 WebSocket Leave 消息
2. `CloseableManager.close()` — 关闭所有已注册的 Closeable 资源
3. Room 内部 cleanupRoom() — 清理所有 Participant、Track、E2EE、Event

> **重要**：与 C++ 的 RAII 不同，Android 的 GC 不保证对象立即销毁。需要显式调用 `release()` 释放 native 资源（WebRTC PeerConnection、AudioTrack 等），否则会内存泄漏。

---

## 第 3 章：整体架构分层

### 3.1 三层架构

整个 SDK 可以划分为三层：

```
┌─────────────────────────────────────────────────────────────────┐
│                    第 3 层：应用层 (App)                          │
│  MyApp Activity / ViewModel                                      │
│  - 调用 Room.connect(), setCameraEnabled()                       │
│  - 监听 room.events Flow                                         │
│  - 关联 SurfaceViewRenderer 显示视频                             │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                    第 2 层：SDK 层 (LiveKit)                      │
│                                                                  │
│  ┌──────────┐  ┌────────────┐  ┌──────────────┐  ┌──────────┐  │
│  │  Room    │  │ RTCEngine  │  │ SignalClient │  │Participant│  │
│  │ (控制面)  │  │ (连接引擎)  │  │ (WebSocket)  │  │ (参与者)  │  │
│  └────┬─────┘  └─────┬──────┘  └──────────────┘  └────┬─────┘  │
│       │              │                                 │         │
│  ┌────┴──────────────┴─────────────────────────────────┴────┐  │
│  │                    辅助子系统                              │  │
│  │  AudioHandler │ E2EEManager │ EventBus │ RpcManager       │  │
│  │  DataStream   │ Metrics     │ Network  │ TokenSource      │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │                    Track 体系                             │ │
│  │  Track (abstract)                                        │ │
│  │  ├── LocalAudioTrack / LocalVideoTrack / LocalScreencast │ │
│  │  ├── RemoteAudioTrack / RemoteVideoTrack                 │ │
│  │  └── TrackPublication (元数据)                           │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                    第 1 层：WebRTC 层 (Google)                    │
│                                                                  │
│  webrtc.aar (Google WebRTC Native Library)                       │
│  ├── PeerConnectionFactory   : 工厂 (创建 PeerConnection)        │
│  ├── PeerConnection          : 核心连接 (ICE/DTLS/SRTP)          │
│  ├── MediaStreamTrack        : 音视频轨道                         │
│  ├── VideoCapturer           : 采集接口                           │
│  ├── VideoRenderer           : 渲染接口                           │
│  ├── DataChannel             : 数据通道                           │
│  └── Native (C/C++)          : JNI 桥接                         │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                    平台层                                         │
│  Android Camera API / CameraX / MediaProjection / AudioRecord   │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 控制面 vs 数据面

SDK 内部严格区分两条通道：

```
  控制面 (Control Plane)                数据面 (Data Plane)
  ─────────────────────                ─────────────────────
  用途：信令、管理、配置                用途：音视频流、用户数据

  传输协议                            传输协议
  ┌─────────────┐                     ┌─────────────┐
  │   WebSocket  │                     │   WebRTC    │
  │ (Signal)     │                     │ (UDP/ICE)   │
  └──────┬──────┘                     └──────┬──────┘
         │                                   │
  消息类型                            数据类型
  • Join/Leave/Ready                • 视频帧 (VideoFrame)
  • ICE Candidate                   • 音频采样 (AudioBuffer)
  • SDP Offer/Answer                • DataChannel bytes
  • Participant Update              • RTC Stats

  关键类                            关键类
  • SignalClient                    • PeerConnection
  • RTCEngine                       • LocalTrack / RemoteTrack
  • Room                            • DataChannel
```

### 3.3 分层控制流图

从应用层调用的完整控制流：

```
Application
    │
    │ 1. LiveKit.create()
    ▼
┌─────────────────────────────────────────┐
│  Room (State: DISCONNECTED)              │
│  └─ Dagger 注入: engine, audioHandler,  │
│       eglBase, e2eeManagerFactory ...   │
└────────────┬────────────────────────────┘
             │
             │ 2. room.connect(url, token)
             ▼
┌─────────────────────────────────────────┐
│  Room.connect()                         │
│  ├─ 创建 CoroutineScope                  │
│  ├─ 初始化 LocalParticipant              │
│  └─ 启动 ioDispatcher 协程              │
└────────────┬────────────────────────────┘
             │
             │ 3. engine.join(url, token)
             ▼
┌─────────────────────────────────────────┐
│  RTCEngine                              │
│  ├─ client.join() → SignalClient        │
│  ├─ 收到 JoinResponse                   │
│  └─ configure() → 创建 PeerConnection   │
└────────────┬────────────────────────────┘
             │
             │ 3a. SignalClient
             ▼
┌─────────────────────────────────────────┐
│  SignalClient (WebSocket)               │
│  ├─ WebSocket.connect(wsUrl)            │
│  ├─ 发送 Authorization + Join Request   │
│  └─ 收到 Join Response (SDP/ICE)        │
└────────────┬────────────────────────────┘
             │
             │ 3b. PeerConnection 配置
             ▼
┌─────────────────────────────────────────┐
│  PeerConnectionTransport                │
│  ├─ Publisher PC (发送)                  │
│  ├─ Subscriber PC (接收)                 │
│  ├─ DataChannel: _reliable              │
│  └─ DataChannel: _lossy                 │
└────────────┬────────────────────────────┘
             │
             │ 4. ICE 连接建立
             ▼
┌─────────────────────────────────────────┐
│  Connection State → CONNECTED            │
│  ├─ Room.state = CONNECTED              │
│  ├─ EventBus: RoomEvent.Connected        │
│  └─ 开始收发音视频                       │
└─────────────────────────────────────────┘
```
---

## 第 4 章：核心模块详细分析

### 4.1 Room — 房间管理与事件中枢

`Room` 是 SDK 对外暴露的**主要 API 对象**，负责管理以下职责：

```
Room
├── 连接管理
│   ├── connect(url, token)          : 建立 WebSocket + WebRTC
│   ├── disconnect()                  : 断开连接
│   ├── prepareConnection(url)        : 预连接（DNS + TLS 预热）
│   └── state: DISCONNECTED/CONNECTING/CONNECTED/RECONNECTING
│
├── 参与者管理
│   ├── localParticipant: LocalParticipant
│   ├── remoteParticipants: Map<Identity, RemoteParticipant>
│   ├── getParticipantBySid()
│   └── getParticipantByIdentity()
│
├── 事件系统
│   ├── events: BroadcastEventBus<RoomEvent>
│   ├── onEngineConnected/Reconnecting/Reconnected
│   ├── onJoinResponse()              : 处理服务器 Join 响应
│   ├── onUpdateParticipants()        : 处理参与者变更
│   ├── handleActiveSpeakersUpdate()  : 处理活跃发言人
│   ├── onConnectionQuality()         : 处理连接质量
│   ├── onUserPacket()               : 处理用户数据
│   └── onDataStreamPacket()          : 处理 DataStream
│
├── Track 管理
│   ├── adaptiveStream: Boolean       : 自适应分辨率
│   ├── dynacast: Boolean             : 动态码率（按需暂停未消费 Layer）
│   ├── audioTrackCaptureDefaults
│   ├── videoTrackCaptureDefaults
│   ├── audioTrackPublishDefaults
│   └── videoTrackPublishDefaults
│
├── 音视频控制
│   ├── setSpeakerMute(Boolean)       : 静音所有输出
│   ├── setMicrophoneMute(Boolean)    : 静音麦克风输入
│   └── audioHandler: AudioHandler    : 音频设备管理
│
├── RPC 管理
│   ├── registerRpcMethod()           : 注册服务端 RPC
│   └── performRpc()                  : 发起 RPC 调用
│
├── 加密
│   └── e2eeManager: E2EEManager?
│
├── 视频渲染初始化
│   ├── initVideoRenderer(SurfaceViewRenderer)
│   └── initVideoRenderer(TextureViewRenderer)
│
├── 统计
│   ├── getPublisherRTCStats()
│   └── getSubscriberRTCStats()
│
└── 重连
    ├── reconnect()
    ├── sendSyncState()               : 同步状态（重连时）
    └── handleDisconnect()
```

**关键设计决策：**
- `Room` 实现 `RTCEngine.Listener` 接口，直接接收引擎层的所有事件
- `Room` 实现 `ParticipantListener` 接口，接收参与者级别事件
- `Room` 通过 `by incomingDataStreamManager` 委托实现 `IncomingDataStreamManager`
- 所有属性使用 `flowDelegate` 包装，变化自动推送给 Flow 观察者

### 4.2 RTCEngine — 连接引擎

`RTCEngine` 是 SDK 的「引擎核心」，管理 WebRTC 连接的生命周期：

```
RTCEngine (@Singleton)
├── 双 PeerConnection 设计
│   ├── publisher: PeerConnectionTransport    : 上行（发送）
│   └── subscriber: PeerConnectionTransport   : 下行（接收）
│
├── 信令桥接
│   ├── client: SignalClient                  : WebSocket 客户端
│   ├── 实现 SignalClient.Listener
│   │   ├── onServerAnswer/offer()           : SDP 协商
│   │   ├── onTrickle()                      : ICE Candidate
│   │   ├── onParticipantUpdate()            : 参与者变更
│   │   ├── onLeave()                        : 服务器要求离开
│   │   └── onMessage(onDataChannel)         : DataChannel 消息分发
│   └── listener: RTCEngine.Listener          : 向上通知 Room
│
├── DataChannel 管理
│   ├── reliableDataChannel / reliableDataChannelSub  : 有序可靠
│   ├── lossyDataChannel / lossyDataChannelSub         : 无序低延迟
│   ├── reliableDataChannelManager  : 自动重传 + bufferedAmount 监控
│   └── lossyDataChannelManager
│
├── 重连机制
│   ├── reconnectPolicy: ReconnectPolicy         : 退避策略
│   ├── reconnect()                               : 触发重连
│   │   ├── Soft Reconnect (Resume)               : 仅重建 WebSocket + ICE
│   │   └── Full Reconnect                        : 销毁所有 PC，重新 SDP 协商
│   ├── maxRetries: 30 次
│   └── maxTimeout: 60 秒
│
├── Track 发布
│   ├── addTrack()                                : 注册新 Track
│   ├── createSenderTransceiver()                 : 创建发送 Transceiver
│   ├── negotiatePublisher()                      : 触发 Publisher 协商
│   └── pendingTrackResolvers: Map<CID, Continuation> : 发布等待
│
├── 数据发送
│   ├── sendData(DataPacket)                      : 发送数据帧
│   ├── E2EE 加密包装
│   ├── Reliable 消息重传（序列号 + TTLMap）
│   └── 大消息分片（bufferedAmount 监控）
│
├── ICE/SDP 协商
│   ├── PublisherObserver / SubscriberObserver    : 状态监听
│   ├── makeRTCConfig()                           : 构建 RTC 配置
│   ├── 支持 subscriber-primary 模式
│   └── ICE 重启（reconnect 场景）
│
└── 统计
    ├── getPublisherRTCStats()
    └── getSubscriberRTCStats()
```

> **专业补充：双 PeerConnection 设计**
>
> WebRTC 中，每个 PeerConnection 只能有一个 SDP 端（Offerer 或 Answerer）。LiveKit 采用**双连接架构**：
> - **Publisher**：客户端作为 Offerer，向服务器发送音视频
> - **Subscriber**：客户端作为 Answerer，从服务器接收音视频
>
> 这与 C++ 中一个 socket 同时做 read 和 write 类似——将两个方向逻辑分离，简化了 SDP 协商复杂度。

### 4.3 SignalClient — WebSocket 信令

`SignalClient` 管理与服务器的 WebSocket 通信：

```
SignalClient (@Singleton)
├── 连接管理
│   ├── WebSocket (OkHttp)
│   ├── join(url, token) → JoinResponse
│   ├── reconnect(url, token) → ReconnectResponse
│   └── close()
│
├── 请求/响应队列
│   ├── requestFlow: MutableSharedFlow<SignalRequest>   : 发送队列
│   ├── responseFlow: MutableSharedFlow<Pair<WS, Response>> : 接收队列
│   └── skipQueueTypes: 紧急消息（ICE/SDP）跳过队列直接发送
│
├── 信令方法
│   ├── sendOffer/Answer()          : SDP 协商
│   ├── sendCandidate()             : ICE Trickle
│   ├── sendAddTrack()              : 注册新 Track
│   ├── sendMuteTrack()             : 静音通知
│   ├── sendUpdateSubscription()    : 订阅变更
│   ├── sendUpdateLocalMetadata()   : 元数据更新
│   ├── sendSyncState()             : 状态同步（重连）
│   ├── sendLeave()                 : 离开房间
│   └── sendPing()                  : 保活
│
├── 信令响应处理
│   ├── handleSignalResponse()      : 主分发器
│   │   ├── JOIN → 建立连接，启动 ping 任务
│   │   ├── ANSWER → 通知 RTCEngine 设置远程 SDP
│   │   ├── OFFER → RTCEngine 创建 Answer
│   │   ├── TRICKLE → 添加 ICE Candidate
│   │   ├── UPDATE → 参与者变更
│   │   ├── LEAVE → 处理服务器断开指令
│   │   ├── MUTE → 更新静音状态
│   │   ├── SPEAKERS_CHANGED → 活跃发言人
│   │   ├── CONNECTION_QUALITY → 连接质量
│   │   ├── STREAM_STATE_UPDATE → 流状态
│   │   ├── SUBSCRIBED_QUALITY_UPDATE → 订阅质量
│   │   ├── REFRESH_TOKEN → 刷新 Token
│   │   └── PONG → 重置 ping 超时
│   └── 实现 WebSocketListener
│
├── 心跳保活
│   ├── startPingJob()              : 周期性发送 Ping
│   ├── startPingTimeout()          : Ping 超时检测
│   └── rtt: 往返延迟（毫秒）
│
└── 协议版本
    ├── ProtocolVersion: v1-v13     : 与服务器的信令协议
    └── ClientProtocolVersion: DEFAULT/DATA_STREAM_RPC : 对等端协商
```

### 4.4 LocalParticipant / RemoteParticipant — 参与者管理

#### LocalParticipant

```
LocalParticipant : Participant
├── Track 创建
│   ├── createAudioTrack() / getOrCreateDefaultAudioTrack()
│   ├── createVideoTrack() (自定义 Capturer)
│   ├── createVideoTrack() (默认 Camera)
│   └── createScreencastTrack() (屏幕共享)
│
├── Track 控制
│   ├── setCameraEnabled(Boolean)       : 开关摄像头
│   ├── setMicrophoneEnabled(Boolean)   : 开关麦克风
│   └── setScreenShareEnabled(Boolean, params)
│
├── Track 发布
│   ├── publishAudioTrack()             : 发布音频
│   ├── publishVideoTrack()             : 发布视频（含 Simulcast）
│   ├── publishData()                   : 发送用户数据
│   └── publishDtmf()                   : DTMF 音频信号
│
├── Track 管理
│   ├── unpublishTrack()                : 取消发布
│   ├── getTrackPublication(source)     : 按源获取
│   └── trackPublications: Map<Sid, TrackPublication>
│
├── 订阅控制
│   └── setTrackSubscriptionPermissions() : 精细控制谁能订阅
│
├── RPC
│   ├── registerRpcMethod()             : 注册 RPC 服务端
│   ├── performRpc()                    : 发起 RPC 客户端
│   └── handleDataPacket()              : 处理收到的 RPC
│
├── 元数据
│   ├── updateMetadata()
│   ├── updateName()
│   └── updateAttributes()
│
└── 重连恢复
    ├── prepareForFullReconnect()        : 记录待重发 Tracks
    └── republishTracks()               : 重连后重新发布
```

#### RemoteParticipant

```
RemoteParticipant : Participant
├── trackPublications: Map<Sid, RemoteTrackPublication>
├── addSubscribedMediaTrack()           : 添加接收到的 Track
├── unpublishTrack()                    : 服务器通知取消订阅
├── onDataReceived()                    : 接收用户数据回调
└── onTranscriptionReceived()           : 接收语音转文字
```

### 4.5 Track 体系

```
Track (abstract, sealed class Source)
├── 通用属性
│   ├── rtcTrack: MediaStreamTrack        : 底层 WebRTC 轨道
│   ├── name / kind / sid
│   ├── streamState: ACTIVE/PAUSED/UNKNOWN
│   ├── enabled: Boolean
│   ├── statsGetter: RTCStatsGetter
│   ├── events: BroadcastEventBus<TrackEvent>
│   └── getRTCStats()
│
├── LocalAudioTrack
│   ├── 封装 AudioTrack (WebRTC Java 封装)
│   └── features: Set<AudioTrackFeature>  : DTX/Preconnect
│
├── LocalVideoTrack
│   ├── 封装 VideoTrack (WebRTC)
│   ├── capturer: VideoCapturer           : 采集器接口
│   ├── simulcastTracks: List             : 多码率副本
│   ├── transceiver: RtpTransceiver       : RTP 收发器
│   ├── codec: String                     : 视频编码
│   ├── startCapture()/stopCapture()
│   └── addSimulcastTrack()               : 添加 Simulcast Layer
│
├── LocalScreencastVideoTrack
│   └── 继承 LocalVideoTrack，特殊处理前台服务
│
├── RemoteAudioTrack
│   └── 接收到的音频轨道
│
├── RemoteVideoTrack
│   ├── 多 Layer 管理
│   └── streamState 控制
│
└── TrackPublication (Track 的元数据包装)
    ├── sid / name / kind / source
    ├── muted / stream
    ├── track: Track?                     : 实际 Track 引用
    ├── statsGetter
    └── RemoteTrackPublication 扩展
        ├── subscribed: Boolean
        ├── videoQuality: VideoQuality
        └── sendUpdateTrackSettings()
```

 **专业补充：Transceiver 概念**
>
> WebRTC 的 Transceiver 对应「一条双向 RTP 通道」：
> ```
> RtpTransceiver
> ├── sender: RtpSender   → 编码 + 发送
> ├── receiver: RtpReceiver → 接收 + 解码
> ├── direction: SEND_ONLY / RECV_ONLY / SEND_RECV
> └── parameters: RtpParameters (码率、编码、Simulcast RIDs...)
> ```
> 类似 C++ 中的 `struct RTP_Transceiver { Encoder* sender; Decoder* receiver; Direction dir; }`。
> SDK 在每个 Track 发布时创建一个 `SEND_ONLY` Transceiver。


---

## 第 5 章：数据流

### 5.1 上行数据流（发布音视频）

```
应用层
  │
  │ localParticipant.setCameraEnabled(true)
  ▼
LocalParticipant.setTrackEnabled(CAMERA, true)
  │
  ├─ 创建 LocalVideoTrack（调用 LocalVideoTrack.createCameraTrack）
  │   └─ 创建 CameraCapturer（Camera2 API / CameraX）
  │       └─ VideoCapturer 产生 VideoFrame → SurfaceTextureHelper → OpenGL ES
  │
  ├─ track.start() → enabled = true
  ├─ track.startCapture() → 启动采集
  │
  └─ publishVideoTrack(track)
      │
      ├─ 1. 计算编码参数
      │   ├── computeVideoEncodings() → 单路 / Simulcast / SVC
      │   │   ├── Simulcast: 3 路 (QVGA@15, HVGA@15, HD@30)
      │   │   └── SVC: L3T3_KEY / L1T3 (VP9/AV1)
      │   └── videoLayersFromEncodings()
      │
      ├─ 2. 创建 Transceiver
      │   └─ engine.createSenderTransceiver(rtcTrack, transInit)
      │       └─ publisherPeerConnection.addTransceiver(rtcTrack, init)
      │
      ├─ 3. 发送 Signal 请求
      │   └─ engine.addTrack(cid, name, kind, builder)
      │       └─ SignalClient.sendAddTrack() → WebSocket → Server
      │
      ├─ 4. 触发 Publisher 协商
      │   └─ RTCEngine.negotiatePublisher()
      │       └─ publisher.negotiate() → SDP Offer
      │           └─ SignalClient.sendOffer() → WebSocket → Server
      │
      └─ 5. 发布成功回调
          └─ SignalClient.onLocalTrackPublished()
              └─ engine.addTrack 的 Continuation.resume(trackInfo)
                  └─ 创建 LocalTrackPublication → 添加到 trackPublications
```

### 5.2 下行数据流（订阅音视频）

```
服务器推送新 Track
  │
  │ WebSocket: SignalResponse (UPDATE / TRACK_SUBSCRIBED)
  ▼
SignalClient.handleSignalResponseImpl()
  │
  ├─ case UPDATE → listener.onParticipantUpdate()
  │   └─ RTCEngine.onParticipantUpdate()
  │       └─ Room.onUpdateParticipants()
  │           └─ getOrCreateRemoteParticipant()
  │               └─ RemoteParticipant.updateFromInfo()
  │
  └─ case TRACK_SUBSCRIBED → listener.onLocalTrackSubscribed()
      └─ Room.onLocalTrackSubscribed()

PeerConnection 收到 RTP 数据
  │
  │ UDP (ICE + DTLS)
  ▼
Subscriber PeerConnection
  │
  ├── RtpReceiver.onFrame() → VideoFrame
  └── RtpReceiver.onData() → AudioBuffer
      │
      └─ RTCEngine 检测到新 Track
          │
          └─ listener.onAddTrack(receiver, mediaStreamTrack, streams)
              │
              └─ Room.onAddTrack()
                  │
                  ├─ 通过 streamId 找到 RemoteParticipant
                  ├─ 创建 statsGetter
                  └─ participant.addSubscribedMediaTrack()
                      │
                      ├─ 创建 RemoteVideoTrack / RemoteAudioTrack
                      ├─ 附加 Renderer（TextureViewRenderer / SurfaceViewRenderer）
                      │   └─ VideoSink.onFrame() → OpenGL ES 绘制
                      ├─ 注册到 e2eeManager（如果启用加密）
                      └─ 触发 ParticipantEvent.TrackSubscribed
                          └─ Room 转发 RoomEvent.TrackSubscribed
                              └─ app 的 Flow 观察者收到事件
```

### 5.3 信令数据流（WebSocket 协议消息）

```
┌─────────────────────── 下行方向（Server → Client）───────────────────────┐
│                                                                        │
│  SignalResponse.Join          → 房间信息 + ICE Servers + SDP           │
│  SignalResponse.Answer        → Subscriber PC 的远程 SDP               │
│  SignalResponse.Offer         → Publisher PC 的远程 SDP（server primary）│
│  SignalResponse.Trickle       → ICE Candidate                        │
│  SignalResponse.Update        → ParticipantInfo[] 变更                  │
│  SignalResponse.SpeakersChanged → SpeakerInfo[] 活跃发言人              │
│  SignalResponse.Leave         → 服务器要求离开/重连                    │
│  SignalResponse.Mute          → Track 静音状态                         │
│  SignalResponse.RoomUpdate    → 房间元数据变更                          │
│  SignalResponse.ConnectionQuality → 连接质量信息                       │
│  SignalResponse.Pong          → Ping 响应                              │
│  SignalResponse.TrackPublished → Track 发布确认                         │
│  SignalResponse.TrackSubscribed → Track 订阅确认                        │
│  SignalResponse.StreamStateUpdate → 流状态更新                          │
│  SignalResponse.SubscribedQualityUpdate → 订阅质量变更                   │
│  SignalResponse.SubscriptionPermissionUpdate → 订阅权限变更              │
│  SignalResponse.RefreshToken  → Token 刷新                             │
│                                                                        │
└─────────────────────── 上行方向（Client → Server）───────────────────────┘
│                                                                        │
│  SignalRequest.Join           → 加入房间请求                            │
│  SignalRequest.SyncState      → 重连状态同步                            │
│  SignalRequest.Offer          → SDP Offer (Publisher)                   │
│  SignalRequest.Answer         → SDP Answer (Subscriber)                 │
│  SignalRequest.Trickle        → ICE Candidate                          │
│  SignalRequest.AddTrack       → 注册新 Track                            │
│  SignalRequest.Mute           → Track 静音通知                          │
│  SignalRequest.UpdateSubscription → 订阅变更                            │
│  SignalRequest.UpdateMetadata → 元数据更新                              │
│  SignalRequest.Leave          → 离开房间                                 │
│  SignalRequest.Ping           → 心跳 Ping                              │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### 5.4 DataChannel 数据流

DataChannel 是 WebRTC 提供的应用层数据通道，SDK 使用两个 Channel：

```
┌──────────────────── Publisher DataChannel (Client → Server) ─────────────┐
│                                                                          │
│  _reliable (有序, 确保送达)                                               │
│  ├── UserPacket (用户数据, ≤64KB)                                         │
│  │   ├── data: ByteArray                                                 │
│  │   ├── participantSid: String                                          │
│  │   └── topic: String? (可选)                                           │
│  ├── Speaker (活跃发言人信令)                                              │
│  │   └── SpeakerInfo[]                                                   │
│  ├── Transcription (语音转文字)                                            │
│  ├── RPC (v1: RpcRequest/RpcAck/RpcResponse)                               │
│  ├── DataStream (v2: StreamHeader/Chunk/Trailer)                          │
│  └── EncryptedPacket (E2EE 加密数据)                                      │
│                                                                          │
│  _lossy (无序, 低延迟)                                                    │
│  └── 同上（但不保证送达）                                                   │
│                                                                          │
└──────────────────── Subscriber DataChannel (Server → Client) ─────────────┘
│                                                                          │
│  _reliable / _lossy (由服务器打开，Client 接收)                              │
│  └─ 消息格式同上，方向相反                                                  │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**DataChannel 关键实现：**

```kotlin
// Reliable 消息的发送 + 重传
RTCEngine.sendData()
  ├─ 序列号递增
  ├─ 放入 reliableMessageBuffer（环形缓冲区）
  ├─ 监控 bufferedAmount（如果缓冲区满，背压等待）
  └─ 如果 reconnecting，仅入队不发送

// 重连恢复
RTCEngine.resendReliableMessagesForResume()
  ├─ 从 reliableMessageBuffer 弹出未确认消息
  └─ 重发序列号 > lastMessageSeq 的消息
```

### 5.5 事件数据流（EventBus）

SDK 使用 `BroadcastEventBus<EventType>` 实现发布-订阅事件系统：

```
┌─────────────────────────────────────────────────────────────┐
│                    Event Bus 层次                            │
│                                                             │
│  BroadcastEventBus<RoomEvent>  (Room 级别)                  │
│  │                                                          │
│  │  postEvent(RoomEvent.Connected)                           │
│  │  postEvent(RoomEvent.TrackPublished)                      │
│  │  postEvent(RoomEvent.ParticipantConnected)                │
│  │  postEvent(RoomEvent.Disconnected)                        │
│  │  ... (30+ 种 RoomEvent)                                   │
│  │                                                          │
│  └─→ app: room.events.collect { event -> ... }              │
│                                                             │
│  BroadcastEventBus<ParticipantEvent>  (参与者级别)           │
│  │                                                          │
│  │  postEvent(TrackPublished / TrackSubscribed)             │
│  │  postEvent(MetadataChanged / NameChanged)                │
│  │  ...                                                    │
│  │                                                          │
│  └─→ app: participant.events.collect { event -> ... }       │
│                                                             │
│  BroadcastEventBus<TrackEvent>  (Track 级别)               │
│  │                                                          │
│  │  postEvent(StreamStateChanged)                            │
│  │  ...                                                    │
│  │                                                          │
│  └─→ app: track.events.collect { event -> ... }             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**事件传播链路：**

```
原始事件源                      中转层                        最终事件
─────────                      ──────                        ────────

SignalClient
  │ onServerAnswer
  ▼
RTCEngine                        RoomRTCEngine.Listener
  │ onServerAnswer()             │ onEngineConnected()
  ▼                              ▼
(设置 Remote SDP)               state = CONNECTED
                               └─→ eventBus.postEvent(RoomEvent.Connected)

PeerConnection
  │ 新 Track 数据到达
  ▼
RTCEngine                        RoomRTCEngine.Listener
  │ onAddTrack()                 │ onAddTrack()
  ▼                              ▼
(设置 RTP Receiver)             addSubscribedMediaTrack()
                               └─→ eventBus.postEvent(RoomEvent.TrackSubscribed)
```

### 5.6 数据流总览图

将所有数据流合并为一个端到端全景图：

```
                    ┌──────────────────────────────────────┐
                    │           应 用 层                     │
                    │  Activity / ViewModel / Compose       │
                    │                                      │
                    │  room.connect()                       │
                    │  room.events.collect { ... }          │
                    │  localParticipant.setCameraEnabled()  │
                    │  localParticipant.publishData()       │
                    │  localParticipant.setMicrophoneEnabled()│
                    └──────┬───────────────────┬───────────┘
                           │                   │
              ┌────────────┘                   └────────────┐
              ▼                                              ▼
┌──────────────────────────┐              ┌──────────────────────────┐
│        控 制 面          │              │        数 据 面          │
│  (WebSocket + SDP)       │              │  (WebRTC RTP/RTCP)       │
│                          │              │                          │
│  Room.connect()          │              │  LocalVideoTrack         │
│    │                     │              │    ├── CameraCapturer     │
│    ▼                     │              │    ├── VideoEncoder       │
│  SignalClient            │              │    └── RtpSender          │
│    │ WebSocket            │              │                          │
│    │                      │              │  LocalAudioTrack         │
│    ▼                     │              │    ├── AudioRecord        │
│  Server (LiveKit)        │              │    ├── OpusEncoder        │
│                          │              │    └── RtpSender          │
│                          │              │                          │
│                          │              │  RemoteVideoTrack        │
│                          │              │    ├── RtpReceiver        │
│                          │              │    └── VideoDecoder       │
│                          │              │        └── VideoSink      │
│                          │              │           (Renderer)      │
│                          │              │                          │
│                          │              │  RemoteAudioTrack        │
│                          │              │    ├── RtpReceiver        │
│                          │              │    └── OpusDecoder        │
│                          │              │        └── AudioTrack     │
└──────────────────────────┘              └──────────────────────────┘
           │                                           │
           ▼                                           ▼
    WebSocket (wss://)                        UDP (ICE + DTLS)
    信令协议 (protobuf)                       RTP/RTCP (音视频)
```

---

## 第 6 章：关键子系统

### 6.1 音频子系统

音频子系统是整个 SDK 中最复杂的子系统之一，涉及 Android 平台音频管理的方方面面。

```
音频子系统架构
│
├── AudioHandler (接口)                          ← 抽象层
│   ├── start() / stop()                         ← 生命周期钩子
│   │
│   └── AudioSwitchHandler (默认实现)             ← 设备管理
│       ├── 基于 Twilio AudioSwitch 库
│       ├── HandlerThread 隔离音频操作线程
│       ├── 设备优先级：Bluetooth → Wired → Speaker → Earpiece
│       ├── 音频焦点管理 (AudioManager)
│       ├── 设备变更监听 (AudioDeviceChangeListener)
│       └── 音频焦点监听 (OnAudioFocusChangeListener)
│       │
│       └── SDK 版本适配
│           ├── >= S: CommDeviceAudioSwitch       ← 蓝牙 SCO 修复
│           ├── >= M: AudioSwitch                  ← 标准音频切换
│           └── < M:  LegacyAudioSwitch            ← 旧设备兼容
│
├── AudioProcessingController (接口)              ← 音频信号处理
│   ├── capturePostProcessor                     ← 采集后处理（降噪、回声消除）
│   ├── renderPreProcessor                       ← 渲染前处理（增益控制）
│   ├── bypassCapturePostProcessing
│   └── bypassRenderPreProcessing
│   │
│   └── AuthedAudioProcessingController (扩展)    ← 远程音频处理（需要认证）
│       └── authenticate(url, token)
│
├── AudioRecordPrewarmer                         ← 采集预热
│   └── startPreconnectAudioJob()                ← connect() 前预加热 AudioRecord
│       └── 解决首次采集 1-2 秒延迟问题
│
├── PreconnectAudioBuffer                        ← 预连接缓冲区
│   └── 在 ICE 连接建立期间收集音频数据，避免首帧丢失
│
├── AudioBufferCallbackDispatcher                 ← 音频帧分发
│   └── 分发采集/渲染音频帧到处理链
│
├── MixerAudioBufferCallback                      ← 音频混合
│   └── 将远程音频与本地处理链混合
│
└── CommunicationWorkaround                      ← 通信模式兼容
    └── 在不同 Android 版本间统一音频模式
```

**专业补充：Android 音频模式**

Android 有两种主要音频模式：
- `MODE_NORMAL`：普通通话，蓝牙 SCO 不可用
- `MODE_IN_COMMUNICATION`：通信模式（SDK 默认），支持蓝牙/耳机/扬声器切换

这与 C++ 中的「模式切换」类似——SDK 在连接时自动切换到通信模式，断开后恢复，应用层无需关心。

**音频数据流（上行）：**

```
麦克风 (AudioRecord)
  │
  ▼
AudioRecordPrewarmer (预热，避免首次延迟)
  │
  ▼
AudioProcessingController.capturePostProcessor  ← 可插入降噪/回声消除
  │
  ▼
PreconnectAudioBuffer (连接期间缓冲)
  │
  ▼
Opus Encoder (WebRTC 底层)
  │
  ▼
RtpSender → Publisher PeerConnection → 网络
```

### 6.2 视频子系统

视频子系统涵盖了采集、处理、编码、发送全链路：

```
视频子系统架构
│
├── 采集层
│   ├── VideoCapturer (抽象接口)                  ← 采集抽象
│   │   ├── startCapture() / stopCapture()
│   │   └── VideoSink (帧回调)
│   │
│   ├── Camera2Capturer (默认)                    ← Camera2 API
│   │   └── 通过 CameraCapturer 实现
│   │
│   ├── CameraXCapturer (livekit-android-camerax) ← CameraX 集成
│   │   └── 基于 ImageAnalysis + Segmentation API
│   │
│   └── ScreencastVideoTrack                      ← 屏幕共享
│       └── ScreenCaptureConnection
│           └── ScreenCaptureService (前台服务)
│
├── 处理层
│   ├── VideoProcessor (接口)                     ← 帧处理插件
│   │   ├── onFrameCaptured(frame)                 ← 采集后回调
│   │   ├── onFrameCapturedWithSize(frame, size, rotation, bypass)
│   │   ├── onFrameProcessed(frame)                ← 处理后回调
│   │   └── setSink(sink)                          ← 链式连接
│   │
│   ├── NoDropVideoProcessor (基类)                ← 保证不丢帧
│   │   └── VirtualBackgroundVideoProcessor        ← 虚拟背景
│   │       ├── MLKit SelfieSegmentation           ← 人体分割
│   │       ├── VirtualBackgroundTransformer       ← OpenGL ES 渲染
│   │       ├── EglRenderer                        ← 帧渲染
│   │       └── SurfaceTextureHelper               ← GPU 线程通信
│   │
│   ├── ScaleCropVideoProcessor                   ← 缩放裁剪
│   ├── ChainVideoProcessor                       ← 多处理器链
│   └── BitmapFrameCapturer                       ← Bitmap → VideoFrame
│
├── 编码层
│   ├── VideoEncoder (WebRTC 底层)                ← H.264/VP8/VP9/AV1
│   ├── SimulcastVideoEncoderFactoryWrapper        ← 多码率编码
│   │   └── 多路编码（不同分辨率/码率）
│   │
│   └── 码率计算
│       ├── computeVideoEncodings()                ← 单路/Simulcast/SVC
│       ├── videoLayersFromEncodings()             ← VideoLayer[]
│       │
│       └── 编码策略
│           ├── Simulcast: 3 路 (QVGA@15, HVGA@15, HD@30)
│           ├── SVC: L3T3_KEY (VP9), L1T3 (AV1)
│           └── Dynacast: 按需暂停未消费 Layer
│
├── 发送层
│   ├── LocalVideoTrack                           ← Track 封装
│   │   ├── capturer: VideoCapturer
│   │   ├── transceiver: RtpTransceiver
│   │   ├── simulcastTracks: List<LocalVideoTrack>
│   │   └── codec: String
│   │
│   └── addSimulcastTrack()                       ← 添加 Simulcast 副本
│
└── 渲染层
    ├── VideoSink (接口)                          ← 帧消费端
    │   ├── onFrame(frame)
    │   └── VideoSinkVisibility                   ← 可见性感知
    │
    ├── SurfaceViewRenderer (OpenGL)              ← SDK 提供
    └── TextureViewRenderer (SDK 封装)            ← TextureView 封装
```

**专业补充：OpenGL ES 在 Android 中的应用**

Android 的视频采集和渲染大量使用 OpenGL ES（类似于桌面 OpenGL 的嵌入式版本）：
- **EglBase**：OpenGL ES 上下文管理器（类似 C++ 的 EGLContext）
- **SurfaceTextureHelper**：将 Camera/SurfaceTexture 帧传递到 OpenGL 线程
- **EglRenderer**：将 VideoFrame 渲染到 Surface

虚拟背景通过 OpenGL Shader（Fragment Shader）实现模糊/抠图效果，这是 GPU 密集型操作，SDK 将其放在单独的线程执行以避免阻塞主线程。

### 6.3 重连机制

重连是 SDK 最关键的容错机制，分为两个级别：

```
重连策略
│
├── ReconnectPolicy (接口)                       ← 退避策略抽象
│   └── getNextRetryDelay(context)               ← 每次重试前调用
│       ├── retryCount: 当前重试次数
│       └── elapsedTime: 距断连的总时间
│       └── 返回 Duration? (null = 取消重连)
│
├── DefaultReconnectPolicy (默认实现)
│   ├── retryDelays: 预定义退避延迟列表
│   │   [100ms, 300ms, 300ms, 500ms, 500ms, 500ms,
│   │    1200ms, 2700ms, 4800ms, 5000ms×9]
│   │
│   │   └─ 设计思路：
│   │       - 前几次激进重试（WiFi→LTE 切换可能只需几百 ms）
│   │       - 之后指数退避（2^n * 300ms）
│   │       - 上限 5 秒
│   │
│   ├── maxReconnectionTimeout: 60 秒            ← 总超时
│   └── 最大重试次数：30 次                       ← 硬限制
│
├── ReconnectType (重连类型)
│   ├── DEFAULT
│   ├── FORCE_SOFT_RECONNECT                     ← 强制软重连
│   └── FORCE_FULL_RECONNECT                     ← 强制全量重连
│
├── 重连流程
│   │
│   ├── 触发条件
│   │   ├── WebSocket close                      ← 信令断开
│   │   ├── PeerConnection ICE disconnected      ← 数据通道断开
│   │   ├── LeaveRequest.action = RECONNECT      ← 服务器主动要求
│   │   └── Network lost → available              ← 系统网络回调
│   │
│   ├── Soft Reconnect (Resume)
│   │   ├── 保留现有 PeerConnection
│   │   ├── 重建 WebSocket 连接
│   │   ├── 接收新的 ICE Candidates
│   │   ├── 重启 Publisher ICE（如果需要）
│   │   ├── 重传未确认的 Reliable 数据
│   │   ├── 恢复订阅状态
│   │   └── 状态：RESUMING → CONNECTED
│   │
│   └── Full Reconnect (Full)
│       ├── 关闭所有 PeerConnection
│       ├── 重新执行 join() 流程
│       ├── 重新协商 SDP
│       ├── 重新发布 Tracks
│       ├── 清理所有 RemoteParticipant
│       └── 状态：RECONNECTING → CONNECTED
│
└── 状态流转
    DISCONNECTED → CONNECTING → CONNECTED
                          ↓ (网络断开)
                    ← RECONNECTING / RESUMING → CONNECTED
                    ← DISCONNECTED (重连超时 60s / 30 次重试)
```

**专业补充：Soft Resume vs Full Reconnect**

这与 C++ 中的「热重启」和「冷重启」概念类似：
- **Soft Resume**：只重建连接层，保留数据面。类似 TCP Fast Reconnect，节省约 2-5 秒。
- **Full Reconnect**：完全重建所有状态。类似断开重连，保证状态一致性。

### 6.4 端到端加密 (E2EE)

```
E2EE 架构
│
├── E2EEOptions                                    ← 配置
│   └── keyProvider: KeyProvider                  ← 密钥管理
│
├── KeyProvider                                    ← 密钥提供者
│   ├── sharedKey: String                         ← 共享密钥
│   ├── keyIndex: Int                             ← 密钥版本
│   ├── ratchetSharedKey()                        ← 密钥滚动（向前安全）
│   └── rtcKeyProvider (WebRTC Native 接口)
│
├── E2EEManager                                    ← 加密管理器
│   ├── enabled: Boolean                          ← 总开关
│   ├── dataChannelEncryptionEnabled              ← DataChannel 加密
│   ├── algorithm: AES_GCM (默认)
│   │
│   ├── 帧加密 (RTP 层)
│   │   ├── addPublishedTrack() → FrameCryptor (Sender)
│   │   ├── addSubscribedTrack() → FrameCryptor (Receiver)
│   │   ├── removePublishedTrack()
│   │   └── removeSubscribedTrack()
│   │
│   │   └─ FrameCryptor (WebRTC Native)
│   │       ├── isEnabled: Boolean
│   │       ├── keyIndex
│   │       └── Observer: onFrameCryptionStateChanged()
│   │           ├── OK
│   │           ├── KEY_RATCHETED               ← 密钥已滚动
│   │           ├── MISSING_KEY                 ← 密钥缺失
│   │           └── DECRYPTION_FAILED            ← 解密失败
│   │
│   └── DataChannel 加密
│       ├── encrypt(payload) → EncryptedPacket
│       └── decrypt(encryptedPacket) → ByteArray
│           └── 通过 DataPacketCryptorManager 实现
│
├── 加密粒度
│   ├── RTP 帧：音视频数据 (FrameCryptor)
│   └── DataChannel：用户数据、RPC、DataStream (DataPacketCryptor)
│
└── 事件通知
    └── RoomEvent.TrackE2EEStateEvent             ← 每 Track 的加密状态变化
```

**AES-GCM 密钥滚动 (Ratchet)**

E2EE 使用 AES-GCM 模式，并支持密钥滚动（Ratchet）——即使当前密钥泄露，之前的通信也不会被解密。这与 C++ 的 Signal Protocol 的 Double Ratchet 算法类似（简化版）。

### 6.5 RPC 与 DataStream

#### RPC (Remote Procedure Call)

SDK 支持两种 RPC 实现：

```
RPC 架构 (v1)
│
├── RpcManager (接口)
│   ├── registerRpcMethod(method, handler)        ← 注册服务端
│   ├── unregisterRpcMethod(method)
│   └── performRpc(destination, method, payload)  ← 发起客户端调用
│
├── RpcClientManager                             ← 客户端管理
│   ├── 基于 DataChannel Reliable 发送
│   ├── 超时控制 (默认 15s, 最小 8s)
│   ├── RTT 缓冲 (默认 7s)
│   └── 序列化：Request → Ack → Response
│
├── RpcServerManager                             ← 服务端管理
│   ├── 方法注册表：Map<method, RpcHandler>
│   ├── 处理 incoming RPC → 调用 handler
│   └── 返回 String 结果
│
└── RPC 消息流
    ClientA                           Server/ClientB
       │                                  │
       │── RpcRequest(method, payload)───▶│
       │◀── RpcAck(ACK)──────────────────│  ← 确认收到
       │                                  │
       │                            handler.invoke()
       │                            return "result"
       │                                  │
       │◀── RpcResponse(result)──────────│
```

**DataStream (v2 大数据传输)**

```
DataStream 架构
│
├── OutgoingDataStreamManager                      ← 发送端
│   ├── streamText(options) → TextStreamSender     ← 发送文本流
│   ├── streamBytes(options) → ByteStreamSender    ← 发送字节流
│   ├── sendText(text, options)                     ← 一次性发送
│   └── sendFile(file, options)                     ← 发送文件
│   │
│   └─ 实现：OutgoingDataStreamManagerImpl
│       ├── Header → Chunk → Trailer 三段式协议
│       ├── bufferedAmount 背压控制
│       └── 多目的地分发 (destinationIdentities)
│
├── IncomingDataStreamManager                      ← 接收端
│   ├── registerTextStreamHandler(topic, handler)   ← 注册文本处理器
│   ├── registerByteStreamHandler(topic, handler)   ← 注册字节处理器
│   │
│   └─ 实现：IncomingDataStreamManagerImpl
│       ├── Header 解析 → StreamInfo
│       ├── Chunk 接收 → Channel<ByteArray> 管道
│       ├── Trailer 验证 → 完整性检查
│       ├── 加密类型匹配
│       └── 长度校验（totalSize 一致性）
│
└── Stream 协议
    ┌─────────────────────────────────────────────┐
    │ Header                                       │
    │  ├── streamId (UUID)                         │
    │  ├── topic (string)                          │
    │  ├── timestampMs                             │
    │  ├── totalSize?                              │
    │  ├── attributes (Map<String, String>)        │
    │  ├── mimeType (byte stream)                  │
    │  └── operationType / version (text stream)   │
    ├─────────────────────────────────────────────┤
    │ Chunk[0]                                      │
    │ Chunk[1]                                      │
    │ ...                                           │
    │ Chunk[n]                                      │
    ├─────────────────────────────────────────────┤
    │ Trailer                                       │
    │  ├── streamId                                 │
    │  └── reason? (error)                         │
    └─────────────────────────────────────────────┘
```

### 6.6 网络感知与自动重连

```
网络感知架构
│
├── NetworkCallbackManager                      ← Android NetworkCallback 封装
│   ├── registerCallback()                      ← 连接时注册
│   └── unregisterCallback()                    ← 断开时注销
│   │
│   ├── onAvailable(network)                    ← 网络可用
│   │   └─ 如果 hasLostConnectivity → 触发 reconnect()
│   │
│   └── onLost(network)                         ← 网络断开
│       └─ 设置 hasLostConnectivity = true
│
├── RegionUrlProvider                           ← 区域选择
│   ├── fetchRegionSettings()                   ← 获取所有 Edge DC 列表
│   ├── getNextBestRegionUrl()                  ← 选择最优 DC
│   ├── setServerReportedRegions()              ← 服务器推送区域信息
│   └── token: String                           ← Token 更新同步
│   │
│   └─ 工作流程：
│       1. 解析 token 中的 region 信息
│       2. 获取所有可用 Edge DC 的健康状态
│       3. 选择延迟最低的 DC
│       4. 连接失败时自动切换到下一最优 DC
│
├── ConnectionWarmer                            ← 连接预热
│   ├── fetch(url)                              ← 提前建立 TCP/TLS
│   │   └─ prepareConnection() 调用此方法
│   └─ 类似浏览器 preconnect，减少首次连接延迟
│
├── PublisherTransportObserver                  ← Publisher 传输层监听
│   ├── ICE 状态变化
│   ├── DataChannel 状态变化
│   └── 触发重连（连接断开时）
│
└── SubscriberTransportObserver                 ← Subscriber 传输层监听
    ├── ICE 状态变化
    ├── DataChannel 状态变更（服务器打开）
    └── MediaStream 变化
```

**网络重连决策树：**

```
网络断开
  │
  ├── 持续时间 < 1 秒
  │   └─ Soft Resume (几乎无感知)
  │
  ├── 持续时间 1-5 秒
  │   └─ Soft Resume (短暂卡顿)
  │
  ├── 持续时间 > 5 秒 或 WiFi→LTE 切换
  │   └─ Full Reconnect (2-5 秒)
  │
  └── 网络完全不可用
      └─ NetworkCallback → onAvailable → 触发重连
```

---

## 第 7 章：类图与交互关系

### 7.1 核心类图

由于文本类图无法表达完整的 UML 语义，以下以结构化文本描述核心类关系。

#### 7.1.1 Room 及其直接依赖

```
class Room {
    // 状态
    - state: State {CONNECTING|CONNECTED|DISCONNECTED|RECONNECTING}
    - sid: Sid?
    - name: String?
    - metadata: String?
    - isRecording: Boolean
    - eventBus: BroadcastEventBus<RoomEvent>

    // 参与者
    + localParticipant: LocalParticipant
    + remoteParticipants: Map<Identity, RemoteParticipant>
    + activeSpeakers: List<Participant>

    // 配置
    + adaptiveStream: Boolean
    + dynacast: Boolean
    + e2eeManager: E2EEManager?
    + audioHandler: AudioHandler
    + audioProcessingController: AudioProcessingController
    + reconnectPolicy: ReconnectPolicy
    + audioTrackCaptureDefaults: LocalAudioTrackOptions
    + videoTrackCaptureDefaults: LocalVideoTrackOptions

    // 内部引用
    - engine: RTCEngine
    - eglBase: EglBase
    - closeableManager: CloseableManager
    - e2eeManagerFactory: E2EEManager.Factory
    - communicationWorkaround: CommunicationWorkaround
    - rpcClientManager: RpcClientManager
    - rpcServerManager: RpcServerManager
    - incomingDataStreamManager: IncomingDataStreamManager

    // 生命周期
    + connect(url, token, options): suspend Unit
    + disconnect()
    + release()
    + prepareConnection(url, token): suspend Unit

    // 控制
    + setSpeakerMute(muted: Boolean)
    + setMicrophoneMute(muted: Boolean)
    + setRoomOptions(options: RoomOptions)

    // 查询
    + getParticipantBySid(sid): Participant?
    + getParticipantByIdentity(identity): Participant?
    + getPublisherRTCStats(callback)
    + getSubscriberRTCStats(callback)

    // 事件分发
    - emitWhenConnected(event): suspend Unit  ← 确保只在 CONNECTED 状态广播
}

Room implements:
    ├── RTCEngine.Listener          ← 接收引擎层所有事件
    ├── ParticipantListener         ← 接收参与者级别事件
    ├── RpcManager                  ← 代理 RPC 调用
    └── IncomingDataStreamManager   ← by delegate，透流传入流
```

#### 7.1.2 RTCEngine 及其直接依赖

```
class RTCEngine {
    // 信令
    - client: SignalClient                          ← 实现 SignalClient.Listener
    - connectionState: ConnectionState

    // 传输层
    - publisher: PeerConnectionTransport?
    - subscriber: PeerConnectionTransport?
    - publisherObserver: PublisherTransportObserver
    - subscriberObserver: SubscriberTransportObserver

    // DataChannel
    - reliableDataChannel: DataChannel?
    - lossyDataChannel: DataChannel?
    - reliableDataChannelManager: DataChannelManager?
    - lossyDataChannelManager: DataChannelManager?
    - reliableDataChannelSub: DataChannel?
    - lossyDataChannelSub: DataChannel?

    // 可靠消息缓冲
    - reliableMessageBuffer: DataPacketBuffer
    - reliableDataSequence: Int
    - reliableReceivedState: TTLMap<Sid, Int>

    // E2EE
    - e2EEManager: E2EEManager?

    // 重连
    - reconnectPolicy: ReconnectPolicy
    - reconnectingJob: Job?
    - fullReconnectOnNext: Boolean
    - reconnectType: ReconnectType

    // 回调
    + listener: RTCEngine.Listener?                 ← 向上通知 Room

    // 生命周期
    + join(url, token, options, roomOptions): JoinResponse
    + close(reason: String)
    + reconnect()                                   ← 触发重连
    + sendData(dataPacket): Result<Unit>

    // Track 管理
    + addTrack(cid, name, kind, stream, builder): TrackInfo
    + createSenderTransceiver(rtcTrack, transInit): RtpTransceiver?
    + removeTrack(rtcTrack)
    + stopTransceivers(transceivers)

    // 统计
    + getPublisherRTCStats(callback)
    + getSubscriberRTCStats(callback)
    + createStatsGetter(sender/receiver): RTCStatsGetter
}
```

#### 7.1.3 Participant 体系

```
class Participant (abstract base) {
    // 标识
    - sid: Sid
    - identity: Identity
    - name: String?
    - metadata: String?
    - attributes: Map<String, String>

    // 状态
    + trackPublications: Map<Sid, TrackPublication>
    - events: BroadcastEventBus<ParticipantEvent>
    - connectionQuality: ConnectionQuality
    - audioLevel: Float
    - isSpeaking: Boolean

    // 事件分发
    - eventBus: BroadcastEventBus<ParticipantEvent>
}

class LocalParticipant : Participant {
    // Track 创建
    + createAudioTrack(options): LocalAudioTrack
    + createVideoTrack(capturer): LocalVideoTrack
    + createVideoTrack(source, options): LocalVideoTrack
    + createScreencastTrack(params): LocalScreencastVideoTrack

    // Track 控制
    + setMicrophoneEnabled(enabled): Boolean
    + setCameraEnabled(enabled): Boolean
    + setScreenShareEnabled(enabled, params): Boolean

    // Track 发布/取消
    + publishAudioTrack(track): LocalTrackPublication
    + publishVideoTrack(track): LocalTrackPublication
    + unpublishTrack(sid): Boolean

    // 数据
    + publishData(data, topic, reliability): Result<Unit>
    + publishDtmf(digits: String)

    // 订阅控制
    + setTrackSubscriptionPermissions(...)
    + handleSubscribedQualityUpdate(...)

    // RPC
    + registerRpcMethod(method, handler)
    + unregisterRpcMethod(method)
    + performRpc(destination, method, payload, ...)
    + handleDataPacket(dp)

    // 元数据
    + updateMetadata(metadata)
    + updateName(name)
    + updateAttributes(attributes)

    // 重连恢复
    + prepareForFullReconnect()
    + republishTracks()
    + dispose()
}

class RemoteParticipant : Participant {
    // Track 管理
    + addSubscribedMediaTrack(track, trackSid, autoManageVideo, ...)
    + unpublishTrack(sid, force: Boolean)

    // 数据
    + onDataReceived(event: DataReceived)
    + onTranscriptionReceived(event: TranscriptionReceived)

    // 状态更新
    + updateFromInfo(info: ParticipantInfo)
}
```

#### 7.1.4 Track 体系

```
sealed class Track(sealed class Source) {
    // 通用
    - rtcTrack: MediaStreamTrack          ← WebRTC 底层
    - name: String
    - kind: Kind {AUDIO, VIDEO}
    - source: Source
    - sid: Sid?
    - streamState: StreamState
    - enabled: Boolean
    - statsGetter: RTCStatsGetter
    - events: BroadcastEventBus<TrackEvent>
    + getRTCStats(): String?
}

sealed class Track.Source {
    CAMERA, MICROPHONE, SCREEN_SHARE, SCREEN_SHARE_AUDIO, INTERNAL_TEST, UNKNOWN
}

class LocalAudioTrack : Track {
    - audioTrack: AudioTrack             ← WebRTC Java 封装
    - features: Set<AudioTrackFeature>
    + sender: RtpSender                  ← 用于 E2EE
}

class LocalVideoTrack : Track {
    - capturer: VideoCapturer
    - transceiver: RtpTransceiver?
    - simulcastTracks: List<LocalVideoTrack>
    - codec: String?
    + sender: RtpSender
    + startCapture()
    + stopCapture()
    + addSimulcastTrack(track)
}

class RemoteVideoTrack : Track {
    - receiver: RtpReceiver              ← 用于 E2EE
    - videoQualities: List<VideoQuality>
    - streamState: StreamState
    - videoTrackCapabilities: List<VideoTrackCapability>
    - videoFeatures: List<VideoFeature>
}

class TrackPublication {
    - track: Track?                      ← 实际 Track 引用
    - sid: Sid
    - name: String
    - kind: Track.Kind
    - source: Track.Source
    - muted: Boolean
    - stream: Boolean
    - statsGetter: RTCStatsGetter
    - isEncrypted: Boolean
}

class RemoteTrackPublication : TrackPublication {
    - subscribed: Boolean
    - videoQuality: VideoQuality
    + sendUpdateTrackSettings()           ← 发送订阅配置更新
    - isDesired: Boolean                  ← 订阅意图（不受实际状态影响）
}
```

#### 7.1.5 信号与传输

```
class SignalClient {
    - webSocket: WebSocket               ← OkHttp
    - requestFlow: MutableSharedFlow<SignalRequest>    ← 发送队列
    - responseFlow: MutableSharedFlow<Pair<WS, Response>>  ← 接收队列
    - pingJob: Job?
    - serverVersion: Semver?
    - serverInfo: ServerInfo?

    + join(url, token, options, roomOptions): JoinResponse
    + reconnect(url, token, participantSid): Response
    + close()

    // 信令方法
    + sendOffer/Answer(sessionDescription)
    + sendCandidate(candidate, target)
    + sendAddTrack(...)
    + sendMuteTrack(sid, muted)
    + sendUpdateSubscription(...)
    + sendSyncState(syncState)
    + sendLeave()
    + sendPing()
}
SignalClient implements: WebSocketListener    ← OkHttp 回调

class PeerConnectionTransport {
    - peerConnection: PeerConnection     ← WebRTC 核心
    - eglBase: EglBase                   ← OpenGL 上下文
    - dataChannels: List<DataChannel>
    - rtpTransceivers: List<RtpTransceiver>

    + negotiate()                        ← SDP Offer
    + setRemoteDescription(sdp, id)
    + addIceCandidate(candidate)
    + updateRTCConfig(config)
    + prepareForIceRestart()             ← 重连时准备
    + isConnected(): Boolean
    + iceConnectionState(): IceState
    + close()

    // 内部
    - configurationLock: Mutex
}

class DataChannelManager {
    - dataChannel: DataChannel
    - observer: DataChannelObserver
    - bufferedAmount: StateFlow<Long>    ← 背压监控
    + send(buffer: DataChannel.Buffer): Boolean
    + waitForBufferedAmountLow(threshold): suspend Unit
}
```

### 7.2 关键类交互序列图

#### 7.2.1 连接流程序列图

```
App                 Room                RTCEngine            SignalClient         Server
 │                    │                    │                     │                   │
 │  connect(url)      │                    │                     │                   │
 │───────────────────▶│                    │                     │                   │
 │                    │  engine.join()     │                     │                   │
 │                    │───────────────────▶│                     │                   │
 │                    │                    │  join()             │                   │
 │                    │                    │───────────────────▶│                   │
 │                    │                    │  Authorization      │──────────────────▶│
 │                    │                    │                     │                   │
 │                    │                    │  JoinResponse       │                   │
 │                    │                    │◀────────────────────│◀──────────────────│
 │                    │                    │                     │                   │
 │                    │  configure()       │                     │                   │
 │                    │                    │─────────────────────│                   │
 │                    │                    │  [创建 PC, DC]      │                   │
 │                    │                    │                     │                   │
 │                    │                    │  sendOffer()        │                   │
 │                    │                    │───────────────────▶│──────────────────▶│
 │                    │                    │                     │  [SDP Answer]     │
 │                    │                    │                     │                   │
 │                    │                    │  ICE Candidates     │                   │
 │                    │                    │◀────────────────────│◀──────────────────│
 │                    │                    │                     │                   │
 │                    │  [ICE 连接建立]    │                     │                   │
 │                    │                    │─────────────────────│                   │
 │                    │                    │  onEngineConnected()│                   │
 │                    │◀───────────────────│                     │                   │
 │  RoomEvent.Connected│                    │                     │                   │
 │◀───────────────────│                    │                     │                   │
 │                    │                    │                     │                   │
 │  autoEnable audio  │                    │                     │                   │
 │───────────────────▶│                    │                     │                   │
 │                    │  setMicrophoneEnabled(true)              │                   │
 │                    │                    │                     │                   │
 │                    │                    │  [创建 AudioTrack]  │                   │
 │                    │                    │  [发布 Track]       │                   │
 │                    │                    │                     │                   │
```

#### 7.2.2 Track 发布序列图

```
App              LocalParticipant        Room                RTCEngine            SignalClient      Server
 │                    │                     │                    │                     │              │
 │  publishAudioTrack │                     │                    │                     │              │
 │───────────────────▶│                     │                    │                     │              │
 │                    │ createAudioTrack()   │                    │                     │              │
 │                    │─────────────────────│                    │                     │              │
 │                    │ LocalAudioTrack      │                    │                     │              │
 │                    │◀────────────────────│                    │                     │              │
 │                    │                     │                    │                     │              │
 │                    │ publishAudioTrack() │                    │                     │              │
 │                    │─────────────────────│                    │                     │              │
 │                    │                     │ addTrack()         │                     │              │
 │                    │                     │───────────────────▶│                     │              │
 │                    │                     │                    │  sendAddTrack()     │              │
 │                    │                     │                    │───────────────────▶│              │
 │                    │                     │                    │                     │─────────────▶│
 │                    │                     │                    │  TrackPublished     │              │
 │                    │                     │                    │◀────────────────────│◀─────────────│
 │                    │                     │                    │  Continuation.resume│              │
 │                    │                     │◀───────────────────│                     │              │
 │                    │  negotiatePublisher()│                    │                     │              │
 │                    │─────────────────────│───────────────────▶│                     │              │
 │                    │                     │  sendOffer()       │                     │              │
 │                    │                     │                    │───────────────────▶│              │
 │                    │                     │                    │                     │─────────────▶│
 │                    │                     │                    │  onLocalTrackPublished│              │
 │                    │                     │                    │◀────────────────────│◀─────────────│
 │                    │                     │                    │  Continuation.resume│              │
 │                    │◀────────────────────│                    │                     │              │
 │  TrackPublished    │                     │                    │                     │              │
 │◀──────────────────│                    │                    │                     │              │
```

#### 7.2.3 重连序列图

```
Room                RTCEngine              SignalClient         NetworkCallback    Server
 │                    │                      │                     │                  │
 │                    │                      │                     │  onLost()        │
 │                    │                      │                     │─────────────────▶│
 │                    │                      │                     │  hasLostConnectivity = true
 │                    │                      │                     │                  │
 │                    │  ICE disconnected    │                     │                  │
 │                    │◀─────────────────────│                     │                  │
 │                    │                      │                     │                  │
 │                    │  reconnect()         │                     │                  │
 │                    │─────────────────────▶│                     │                  │
 │                    │                      │  [等待 delay]       │                  │
 │                    │                      │                     │                  │
 │                    │                      │  reconnect(url)     │─────────────────▶│
 │                    │                      │                     │                  │
 │                    │  [Soft Resume]       │                     │                  │
 │                    │  RESUMING state      │                     │                  │
 │                    │                      │  ReconnectResponse  │◀─────────────────│
 │                    │                      │◀────────────────────│                  │
 │                    │                      │  ICE Restart        │                  │
 │                    │                      │                     │                  │
 │                    │  ICE reconnected     │                     │                  │
 │                    │                      │                     │                  │
 │                    │  onEngineResumed()   │                     │                  │
 │                    │◀─────────────────────│                     │                  │
 │  RoomEvent.Reconnected│                   │                     │                  │
 │◀───────────────────│                     │                     │                  │
 │                    │                      │                     │                  │
 │                    │                      │                     │  onAvailable()   │
 │                    │                      │                     │◀─────────────────│
 │                    │                      │                     │  触发 reconnect  │
 │                    │                      │                     │                  │
```

---

## 第 8 章：其他模块

### 8.1 livekit-android-camerax

```
livekit-android-camerax 模块
│
├── CameraXEnumerator                     ← CameraX 摄像头枚举
│   └── getCameraXEnumerator()            ← 替代传统 Camera2Enumerator
│
├── CameraXProvider                        ← CameraX 集成
│   ├── CameraXSession                     ← 管理 CameraX Session
│   ├── CameraXHelper                      ← 工具方法
│   └── CameraXCapturer                    ← VideoCapturer 实现
│       ├── startCapture()                 ← 启动 CameraX 采集
│       └── stopCapture()                  ← 停止采集
│
├── 数据流
│   └── ImageAnalysis.Analyzer
│       └── ImageProxy → ImageAnalysis.ImageReader
│           └─ 帧格式: YUV_420_888
│               └─ VideoFrame.create() → NV21 → I420
│
└── 适用场景
    ├── 需要 CameraX 的 API（与 Jetpack 生态兼容）
    ├── 需要 ImageAnalysis 管线（如 AI 处理）
    └── 需要在 CameraX 框架内管理生命周期
```

### 8.2 livekit-android-track-processors

```
livekit-android-track-processors 模块
│
├── VirtualBackgroundVideoProcessor         ← 虚拟背景处理器
│   ├── 基于 Google ML Kit SelfieSegmentation
│   │   └─ Segmentation.Client
│   │       └─ 输出：Mask (二值化/概率图)
│   │
│   ├── VirtualBackgroundTransformer        ← OpenGL ES 变换
│   │   ├── CompositeShader               ← 合成着色器
│   │   ├── BoxBlurShader                 ← 盒式模糊
│   │   ├── ResamplerShader               ← 图像重采样
│   │   └── BlurShader                    ← 高斯模糊
│   │
│   └── 工作流程
│       ├── 1. CameraC → VideoProcessor chain → 输入帧
│       ├── 2. ML Kit 异步生成 mask
│       ├── 3. OpenGL ES 合成前景 + 背景
│       └── 4. VideoSink 输出
│
├── VideoProcessor (接口)                  ← 帧处理插件链
│   ├── onCapturerStarted/Stopped
│   ├── onFrameCaptured(frame)             ← 捕获回调
│   ├── onFrameCapturedWithSize(frame, size, rotation, bypass)
│   ├── onFrameProcessed(frame)            ← 处理完成
│   └── setSink(sink)                      ← 链式连接
│
├── NoDropVideoProcessor                   ← 不丢帧基类
│   └─ 保证处理速度慢时不丢弃帧（通过 Flow 背压）
│
├── ScaleCropVideoProcessor                ← 缩放裁剪
│   └─ 将帧缩放到目标分辨率
│
├── ChainVideoProcessor                    ← 处理器链
│   └─ 将多个 VideoProcessor 串联
│
└── Shader 目录
    ├── DefaultVertexShader                ← 通用顶点着色器
    ├── BlurShader / BoxBlurShader         ← 模糊效果
    ├── CompositeShader                    ← 前景/背景合成
    └── ResamplerShader                    ← 图像缩放/旋转
```

### 8.3 sample-app 示例

```
sample-app 模块                              ← 标准示例应用
│   ├── MainActivity                        ← 房间列表
│   ├── CallActivity                        ← 主通话界面
│   ├── ParticipantItem                     ← 参与者卡片组件
│   ├── ViewModelLazyExt                    ← ViewModel 工具
│   └── SampleApplication                   ← Application 类
│
sample-app-compose                          ← Jetpack Compose 示例
│   └─ 使用 Compose UI 重写 sample-app
│
sample-app-baseline                         ← 基础示例（无 UI 框架）
│   └─ 最小可用示例，仅用 XML
│
sample-app-recorder                         ← 本地录制示例
│   └─ 使用 MediaRecorder 本地录制音视频
│
dialog/                                     ← 示例工具对话框
    ├── AudioProcessorSwitchDialog          ← 音频处理器切换
    ├── DebugMenuDialog                     ← 调试菜单
    ├── SelectAudioDeviceDialog             ← 音频设备选择
    └── RpcTestDialogFragment               ← RPC 测试界面
```

### 8.4 livekit-lint / detekt-rules

```
livekit-lint                               ← 自定义 Lint 规则
│   ├── FlowDelegateUsageDetector          ← 检测 flowDelegate 误用
│   │   └─ 要求：必须配合 @FlowObservable 注解
│   │
│   └── MediaTrackEqualsDetector           ← 检测 Track 比较误用
│       └─ MediaStreamTrack 没有实现 equals()，不能用 == 比较
│
livekit-detekt-rules                       ← 自定义 Detekt 规则
│   └─ 代码风格检查（按项目约定配置）
│
```

---

> 本文档已完成对 LiveKit Android SDK 的全景分析。
> 核心架构可概括为：**Room 作为控制面**，**RTCEngine 作为执行引擎**，**SignalClient 作为信令通道**，**PeerConnection 作为数据传输管道**。
> 所有功能模块通过 **EventBus 事件系统**和 **Coroutines 协程**连接。
