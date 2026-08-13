# LiveKit Android SDK 设计分析 — 撰写规划

> 本文档是 `docs-lu/lkt-anaysis.md` 的章节大纲与撰写计划。先读关键文件理解代码，再按章节顺序逐章写入设计文档。

## 读者画像
- 有 C/C++ 经验，对 Kotlin / Java / Android 不太熟悉
- 需要在分析中补充 Kotlin/Java/Android 基础概念，以及 Kotlin ↔ Java ↔ C++(JNI/native WebRTC) 交互方式

## 源码范围
核心模块 `livekit-android-sdk`（160 个 .kt 文件），包根 `io.livekit.android`。已精读的关键文件：
- `LiveKit.kt` — 入口
- `room/Room.kt` — 主类
- `room/RTCEngine.kt` — 引擎
- `room/SignalClient.kt` — WebSocket 信令
- `room/PeerConnectionTransport.kt` — PeerConnection 封装
- `room/participant/Participant.kt` / `LocalParticipant.kt`
- `room/track/Track.kt` / `LocalVideoTrack.kt` / `LocalAudioTrack.kt` / `RemoteVideoTrack.kt`
- `dagger/LiveKitComponent.kt` — DI 组件
- `util/FlowDelegate.kt` — FlowObservable 机制
- `events/RoomEvent.kt` — 事件体系
- `audio/AudioSwitchHandler.kt` — 音频设备管理
- `e2ee/E2EEManager.kt` — 端到端加密
- `webrtc/PeerConnectionFactoryManager.kt` 等

## 章节大纲（lkt-anaysis.md）

### 第 0 章 阅读指南与前置知识（Kotlin/Java/Android 给 C++ 背景读者）
- Kotlin 速查：val/var、data class、sealed class、object、扩展函数、by 委托、协程(coroutine)/Flow、suspend
- Java 速查：interface、annotation、泛型、JVM 静态
- Android 速查：Context、Activity/Application、权限、Handler/HandlerThread、SurfaceView/TextureView、EGL、MediaProjection、AudioManager
- Kotlin ↔ Java 互操作：@JvmStatic、@JvmInline、null 平台类型、kotlin.reflect
- Kotlin/Java ↔ C++ 交互：JNI、WebRTC native 层(org.webrtc 包是对 native libwebrtc 的 Java 绑定)、RTC 线程模型
- 本仓库的特殊约定：`livekit.org.webrtc` 是 LiveKit 对 Google libwebrtc 的二次封装包

### 第 1 章 总览：工程定位、模块组成、入口
- 工程定位：LiveKit Android SDK 是 LiveKit 实时音视频平台的 Android 客户端
- 顶层 Gradle 模块组成（sdk / camerax / track-processors / test / lint / detekt / samples）
- 入口 `LiveKit.create()` → Dagger 组件 → Room
- 一句话架构：Room 是门面，RTCEngine 是内核，SignalClient 是信令，PeerConnectionTransport 是媒体传输

### 第 2 章 分层架构与文件组织
- 四层架构图：API 层 / Room 编排层 / Engine/Signal 传输层 / WebRTC 原生层
- 目录与架构映射表（每个目录的职责）
- 依赖方向（单向向下）

### 第 3 章 依赖注入（Dagger）与对象图
- Dagger 基础概念给 C++ 读者（对比 C++ 中的"工厂+注入"）
- LiveKitComponent、各 Module、@AssistedInject/@AssistedFactory
- 关键对象的提供链路：Room、RTCEngine、SignalClient、PeerConnectionFactory、EglBase、AudioHandler
- LiveKitOverrides：可替换实现的扩展点

### 第 4 章 连接生命周期与状态机
- Room.State 与 ConnectionState
- connect 流程时序（prepareConnection → regionUrl → signal join → configure PC → negotiate）
- 重连机制（soft resume / full reconnect / ReconnectPolicy）
- 断连与清理

### 第 5 章 信令层 SignalClient
- WebSocket 连接、protobuf 编解码
- 请求/响应队列（requestFlow/responseFlow SharedFlow）
- join/reconnect 握手
- ping/pong 心跳
- 各 SignalRequest/SignalResponse 消息映射

### 第 6 章 媒体传输层 RTCEngine + PeerConnectionTransport
- publisher/subscriber 双 PeerConnection 模型（subscriber primary）
- SDP 协商（offer/answer/ICE restart）、SDP munge（codec bitrate、DD extension for SVC）
- ICE/Trickle
- DataChannel（reliable/lossy）、可靠消息重放缓冲
- RTC 线程模型与 RTCThreadToken

### 第 7 章 参与者模型 Participant
- Participant 基类 / LocalParticipant / RemoteParticipant
- @FlowObservable 状态与事件
- 权限模型
- trackPublications 管理

### 第 8 章 轨道模型 Track 体系
- Track 继承体系（AudioTrack/VideoTrack → Local/Remote）
- TrackPublication（Local/Remote）
- 本地视频：capturer/source/SurfaceTextureHelper/VideoProcessor 链路
- 本地音频：AudioDeviceModule/AudioSource/AudioProcessing
- Simulcast / SVC / Dynacast / 备用编解码器(backup codec)
- 远端轨道：订阅、addRenderer、自适应流(adaptiveStream)、可见性管理

### 第 9 章 完整业务流程：音频发布与订阅
- 音频采集 → 编码 → RTP → publisher PC → 服务器 → subscriber PC → 解码 → 渲染
- 各模块/文件夹间的数据流与控制流
- 关键时序图

### 第 10 章 完整业务流程：视频发布与订阅
- 视频采集（Camera/Screencast）→ VideoProcessor → 编码 → Simulcast/SVC → publisher PC → 服务器 → subscriber PC → 解码 → 渲染(SurfaceView/TextureView)
- adaptiveStream / dynacast 控制回路
- 关键时序图

### 第 11 章 数据通道与数据流（DataChannel / DataStream / RPC）
- 可靠/不可靠 DataChannel
- 用户数据 publish/receive
- DataStream（文本/字节流，incoming/outgoing）
- RPC v1/v2 机制

### 第 12 章 事件体系
- BroadcastEventBus、RoomEvent/ParticipantEvent/TrackEvent
- 事件从底层到上层的传递路径
- FlowObservable 与 events 的关系

### 第 13 章 端到端加密 E2EE
- FrameCryptor（媒体帧加密）
- DataPacketCryptorManager（数据包加密）
- KeyProvider
- 与 Room/Track 的集成点

### 第 14 章 音频设备与音频处理子系统
- AudioHandler 接口与 AudioSwitchHandler 实现
- AudioFocus、音频路由
- AudioProcessingController、AudioProcessor
- CommunicationWorkaround、PreconnectAudioBuffer

### 第 15 章 工程特点总结与 Android SDK 分析方法论
- 工程特点：协程化、FlowObservable 响应式、Dagger DI、RTC 线程安全、错误防御式、可测试性
- 类比 C++ 的视角
- 通用的 Android SDK 分析思路与方法（入口追踪、依赖图、状态机、线程模型、事件流、native 边界）

## 撰写执行策略
1. 按章节顺序逐章写入 `docs-lu/lkt-anaysis.md`
2. 每章完成后确认文件已持久化（Read 校验或 Bash wc 校验）
3. 每章之间先读取已写内容确认完整性，再继续下一章
4. 长章节分多次写入（先写前半段，再 Edit 追加后半段）
5. 每写 2-3 章进行一次上下文压缩提示
