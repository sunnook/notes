# LiveKit Android SDK — 架构 / 初始化 / 信令 / 媒体 深读指南

> 配合 `lkt-overview.md`（总览）、`lkt-deep-dive.md`（协商/QoS/发布订阅速查）、`lkt-init-procss.md`（初始化流程）阅读。
> 本文面向想**逐行读懂代码**的开发者：把工程拆成四条主线——**系统架构、初始化、信令交互、媒体处理**——每条线都给出真实代码位置（`文件:行号`）和阅读顺序。
> 目标读者：有 C/C++ 经验、对 Android/Kotlin 不熟。Kotlin 语法对照见 `lkt-init-procss.md` 末尾。

---

## 阅读路径总览（先看这张图，再按章节往下读）

```
第 0 步  入口与装配     LiveKit.kt → LiveKitComponent → RTCModule
                         （本文 §2 初始化）
第 1 步  连接总调度     Room.connect()  ← 状态机 + 协程作用域
                         （本文 §3.1）
第 2 步  信令握手        SignalClient.join/connect → WebSocket → JoinResponse
                         （本文 §3 信令交互）
第 3 步  引擎配置        RTCEngine.joinImpl → configure() → 两条 PeerConnection
                         （本文 §4.1）
第 4 步  协商           negotiatePublisher / onServerOffer / onTrickle
                         （本文 §4.2 协商）
第 5 步  发布           LocalParticipant.setMicrophoneEnabled → publishTrackImpl
                         （本文 §4.3 发布）
第 6 步  订阅           SubscriberTransportObserver.onAddTrack → Room.onTrackSubscribed
                         （本文 §4.4 订阅）
第 7 步  事件回流        RTCEngine.Listener → Room → BroadcastEventBus → Flow
                         （本文 §5 事件）
第 8 步  重连/数据通道   RTCEngine.reconnect / sendData / DataChannel
                         （本文 §6）
```

> **建议**：打开编辑器，按上面 0→8 的顺序，每读一节就跳到对应源码看一遍真实实现。本文不是替代读码，而是给你一张"现在该看哪个文件第几行"的地图。

---

## 一、系统架构（分层 + 线程模型）

### 1.1 四层架构

```
┌──────────────────────────────────────────────────────────────┐
│  L1  应用层    sample-app-basic/MainActivity.kt              │  你的代码
│             room.connect() / room.events.collect{}          │
├──────────────────────────────────────────────────────────────┤
│  L2  房间层    Room.kt                                       │  状态机 + 事件分发
│             State: DISCONNECTED→CONNECTING→CONNECTED→...    │  Facade，用户直接交互
├──────────────────────────────────────────────────────────────┤
│  L3  引擎层    RTCEngine.kt                                  │  编排信令+媒体
│             持有 publisher/subscriber 两条 PeerConnection  │  实现 SignalClient.Listener
├──────────────────────┬───────────────────────────────────────┤
│  L4a 信令通道         │  L4b 媒体通道                         │
│  SignalClient.kt      │  PeerConnectionTransport.kt           │
│  (WebSocket+protobuf)│  (WebRTC PeerConnection)              │
│  控制消息              │  音视频 RTP 流                        │
├──────────────────────┴───────────────────────────────────────┤
│  L5  基础设施  dagger/(DI)  webrtc/(原生封装)  audio/  e2ee/  │  装配与底层能力
└──────────────────────────────────────────────────────────────┘
```

**关键认知**：L3 `RTCEngine` 是整个工程的"心脏"。它同时实现 `SignalClient.Listener`（收信令）和持有两条 `PeerConnectionTransport`（传媒体），把"信令"和"媒体"两条通道在这里汇合。读代码时，`RTCEngine.kt` 是反复要回来翻的中心文件。

### 1.2 核心类的持有关系（谁 new 了谁）

```
LiveKit(object) ──create()──▶ DaggerLiveKitComponent (DI 容器，编译期生成)
                                  │
                                  ├─ roomFactory() ──▶ Room  (@AssistedInject, 运行时传 context)
                                  │                      │
                                  │                      ├─ engine: RTCEngine  (@Inject 单例)
                                  │                      │      ├─ client: SignalClient  (@Inject 单例)
                                  │                      │      ├─ publisher: PeerConnectionTransport (每次连接新建)
                                  │                      │      ├─ subscriber: PeerConnectionTransport (每次连接新建)
                                  │                      │      ├─ publisherObserver: PublisherTransportObserver
                                  │                      │      └─ subscriberObserver: SubscriberTransportObserver
                                  │                      ├─ localParticipant: LocalParticipant
                                  │                      └─ remoteParticipants: Map<Sid, RemoteParticipant>
                                  │
                                  ├─ peerConnectionFactory() ──▶ PeerConnectionFactory (WebRTC 工厂,单例)
                                  └─ eglBase() ──▶ EglBase (OpenGL 上下文,单例)
```

> C++ 类比：`DaggerLiveKitComponent` ≈ 一个编译期生成的 IoC 容器，相当于自动写好了所有 `new` 和构造函数注入。`@Singleton` 的对象全局唯一（≈ 全局静态单例），`@AssistedInject` 的对象需要运行时参数（≈ 工厂函数 `make_room(ctx)`）。

### 1.3 线程模型（理解并发的前提，非常重要）

LiveKit 同时跑在**四类线程**上，读代码时必须时刻意识到"这段代码在哪个线程跑"：

| 线程/调度器 | 来源 | 跑什么 | C++ 类比 |
|---|---|---|---|
| **IO Dispatcher** | `Dispatchers.IO` (`CoroutinesModule.kt:36`) | 连接、WebSocket 收发、协商、发布等大部分协程 | 线程池，IO 密集 |
| **Default Dispatcher** | `Dispatchers.Default` (`CoroutinesModule.kt:32`) | Room 的 `coroutineScope` 默认调度器 | CPU 密集线程池 |
| **Main Dispatcher** | `Dispatchers.Main` (`CoroutinesModule.kt:40`) | UI 线程（渲染、回调 App） | 主线程 |
| **RTC Thread** | WebRTC 原生线程 | 所有 `PeerConnection.*` 调用**必须**在此线程 | 专用 native 线程 |

**RTC 线程是最大的坑**：WebRTC 的 `PeerConnection` API 不是线程安全的，所有对它的调用必须切到 RTC 线程。SDK 用 `executeOnRTCThread` / `executeBlockingOnRTCThread` / `launchBlockingOnRTCThread` 三个工具函数封装（`webrtc/peerconnection/` 包）。

看 `RTCModule.kt:104`：
```kotlin
executeBlockingOnRTCThread(LibWebrtcInitializationThreadToken) {
    PeerConnectionFactory.initialize(...)   // 必须在 RTC 线程
}
```
再看 `RTCEngine.kt:280`：
```kotlin
launchBlockingOnRTCThread(rtcThreadToken) {   // 切到 RTC 线程
    configurationLock.withCheckLock(...) {
        publisher = pctFactory.create(rtcConfig, publisherObserver, ...)  // 创建 PC，RTC 线程
    }
}
```

> **读代码心法**：看到 `executeOnRTCThread` / `launchBlockingOnRTCThread`，就是"从协程线程切到 RTC 线程执行"；`runBlocking` 是"把协程阻塞等待结果"（在 RTC 线程回调里用，因为回调不是 suspend 函数）。

### 1.4 锁的层级（避免死锁的关键）

`RTCEngine` 里有几把锁，注释明确说明了顺序（`RTCEngine.kt:219-229`）：

```kotlin
private var configurationLock = Mutex()        // 保护 publisher/subscriber 的创建/销毁
private val negotiatePublisherMutex = Mutex() // 串行化 publisher 协商，防 ICE 收集竞态
// reliableStateLock = Object()                // 普通 synchronized，保护可靠数据通道序号
```

注释原话（`RTCEngine.kt:219`）：
> If this lock is ever used in conjunction with the RTC thread, this must be grabbed on the RTC thread to prevent deadlocks.

> C++ 类比：锁有获取顺序约束，跨线程持锁要小心死锁。`withCheckLock` 是"先检查条件再锁"的模式（≈ `condition_variable.wait` + 双重检查）。

---

## 二、初始化过程（从 `LiveKit.create` 到 Room 就绪）

> 本节是全文最细致的一节。初始化分**三个阶段**：① DI 装配（编译期生成 + 运行时建图）→ ② Room 构造与回调接线 → ③ 选项应用。理解初始化的关键是搞清"**哪些对象是单例、谁 new 了谁、运行时参数怎么传进去、选项怎么生效**"。

### 2.0 初始化全景：三阶段 + 两类参数

```
LiveKit.create(appContext, options=RoomOptions, overrides=LiveKitOverrides)
   │
   ├─ 阶段①  DI 装配   DaggerLiveKitComponent.factory().create(ctx, overrides)
   │           └─ 8 个 Module 运行时求值，建出整张依赖图（单例对象此时诞生）
   │
   ├─ 阶段②  Room 构造  component.roomFactory().create(ctx)
   │           └─ @AssistedInject：DI 注入依赖 + 运行时传 context → new Room(...)
   │           └─ init 块：engine.listener=this + 注册 RPC 数据流处理器
   │
   └─ 阶段③  选项应用   room.setRoomOptions(options)
                └─ 把 RoomOptions 里的非 null 字段写入 DefaultsManager / Room 属性
```

**两类参数要分清**（这是读初始化代码最容易混的地方）：

| 参数类型 | 代表 | 何时生效 | 能改什么 |
|---|---|---|---|
| **Overrides**（`LiveKitOverrides`） | 自定义 OkHttp/编解码工厂/EglBase/AudioDeviceModule | **阶段① DI 装配时** | 替换底层组件实现（影响整个依赖图） |
| **Options**（`RoomOptions` / `ConnectOptions`） | adaptiveStream/dynacast/e2ee/采集发布默认值/autoSubscribe | **阶段③ + connect 时** | 调行为参数（不改实现） |

> 关键区别：**Overrides 改"用什么零件"，Options 改"零件怎么调"**。比如想换硬件编解码实现 → `LiveKitOverrides`；想改视频采集分辨率 → `RoomOptions.videoTrackCaptureDefaults`。Overrides 必须在 `create()` 时传入（之后改不了，因为对象已 new 出来），Options 可以 `setRoomOptions` 反复改。

### 2.1 入口：`LiveKit.create()`（`LiveKit.kt:80`）

```kotlin
fun create(
    appContext: Context,
    options: RoomOptions = RoomOptions(),
    overrides: LiveKitOverrides = LiveKitOverrides(),
): Room {
    val ctx = appContext.applicationContext          // 1. 取 Application 上下文（防 Activity 泄漏）
    if (ctx !is Application) LKLog.w { ... }          // 2. 警告：非 Application 上下文可能泄漏
    val component = DaggerLiveKitComponent
        .factory().create(ctx, overrides)            // 3. ★ 阶段①：Dagger 装配整张依赖图
    val room = component.roomFactory().create(ctx)    // 4. ★ 阶段②：用工厂创建 Room
    room.setRoomOptions(options)                      // 5. ★ 阶段③：应用房间配置
    return room
}
```

**逐行解读**：

- **第 1 行 `applicationContext`**：Android 的 `Context` 有两种——Activity 级（随 Activity 销毁）和 Application 级（App 全局）。SDK 要持有 Context 长期使用，若用 Activity 的会泄漏（Activity 被销毁但 SDK 还引用它，GC 回收不了）。`applicationContext` 取全局的，安全。

- **第 2 行 `ctx !is Application`**：`is` 是 Kotlin 类型检查（C++ 类比 `dynamic_cast`）。如果连 `applicationContext` 都不是 Application（罕见，比如某些测试环境），给个警告。

- **第 3 行**：`DaggerLiveKitComponent` 是 Dagger **编译期生成**的类（你搜不到源码，build 后才出现）。`.factory().create(ctx, overrides)` 触发整张依赖图的运行时构建——所有 `@Provides` 方法在此刻被调用，单例对象诞生。`ctx` 通过 `@BindsInstance` 绑定进图（`LiveKitComponent.kt:55`），`overrides` 包成 `OverridesModule`（`LiveKitComponent.kt:61` 的扩展函数）。

- **第 4 行**：`roomFactory()` 返回 `Room.Factory`（`@AssistedFactory`，`Room.kt:1108`），`.create(ctx)` 用运行时的 `ctx` + DI 注入的依赖造出 Room。注意 `ctx` 这里**第二次**出现——第一次是绑进 DI 图（供其他对象用），第二次是作为 Room 的 `@Assisted` 参数。

- **第 5 行**：把 `RoomOptions` 应用到已造好的 Room（详见 2.6）。

> **此刻没有任何网络连接**。Room 是个装配好的对象，`state == DISCONNECTED`，没有 WebSocket、没有 PeerConnection。网络活动要等用户调 `room.connect()`。

### 2.2 阶段①：Dagger 装配 —— 8 个 Module 各管什么

`LiveKitComponent.kt:32` 声明了 8 个 Module。**建议读法**：先看 `LiveKitComponent.kt`（69 行，看全貌），再按"重→轻"顺序读各 Module。

```
@Module 列表及职责（按重要性排序）：
┌─────────────────────┬──────────────────────────────────────────────────────┐
│ RTCModule           │ ★最重。WebRTC 初始化、PeerConnectionFactory、EglBase、 │
│                     │   音视频编解码工厂、AudioDeviceModule、SDP 工厂        │
├─────────────────────┼──────────────────────────────────────────────────────┤
│ WebModule           │ OkHttpClient(单例)、WebSocket.Factory、网络回调工厂、  │
│                     │   ConnectivityManager、ConnectionWarmer(连接预热)      │
├─────────────────────┼──────────────────────────────────────────────────────┤
│ AudioHandlerModule   │ AudioHandler(默认 AudioSwitchHandler)、AudioType、    │
│                     │   CommunicationWorkaround(Android 11 音频模式修复)    │
├─────────────────────┼──────────────────────────────────────────────────────┤
│ CoroutinesModule    │ 4 个协程调度器 (Default/IO/Main/Unconfined)            │
├─────────────────────┼──────────────────────────────────────────────────────┤
│ OverridesModule     │ 把 LiveKitOverrides 的字段暴露成 @Named 注入项         │
├─────────────────────┼──────────────────────────────────────────────────────┤
│ MemoryModule        │ CloseableManager(统一释放资源的注册表，单例)           │
├─────────────────────┼──────────────────────────────────────────────────────┤
│ JsonFormatModule    │ kotlinx.serialization Json 实例(ignoreUnknownKeys)    │
├─────────────────────┼──────────────────────────────────────────────────────┤
│ InternalBindsModule  │ 接口→实现的 @Binds 绑定(DataStreamManager 等)        │
└─────────────────────┴──────────────────────────────────────────────────────┘
```

#### 2.2.1 `RTCModule` 详解（`RTCModule.kt`，433 行，初始化核心）

这是唯一需要精读的 Module。它管理 WebRTC 所有"重对象"，理解创建顺序很关键：

**A. WebRTC 原生库初始化**（`RTCModule.kt:99` `libWebrtcInitialization`）：
```kotlin
@Provides @Singleton @Named(LIB_WEBRTC_INITIALIZATION)
fun libWebrtcInitialization(appContext): LibWebrtcInitialization {
    if (!hasInitializedWebrtc) {
        executeBlockingOnRTCThread(LibWebrtcInitializationThreadToken) {  // ★必须在 RTC 线程
            if (!hasInitializedWebrtc) {                                   // 双重检查
                hasInitializedWebrtc = true
                PeerConnectionFactory.initialize(                          // ★加载原生库
                    InitializationOptions.builder(appContext)
                        .setNativeLibraryName("lkjingle_peerconnection_so") // LiveKit 改名的 webrtc 库
                        .setInjectableLogger({ s, severity, s2 -> ... }, ...) // 注入日志桥接
                        .createInitializationOptions()
                )
            }
        }
    }
    return LibWebrtcInitialization   // 返回空 object，仅作依赖占位
}
```
- **`hasInitializedWebrtc` 是普通 boolean**（注释说只在 RTC 线程写），双重检查防重复初始化。
- **返回 `LibWebrtcInitialization`（空 object）**：它的唯一作用是当**依赖占位符**——别的 `@Provides` 方法把它列进参数，Dagger 就会先执行初始化再创建它们，从而强制顺序（详见 2.2.1 末尾的 DI 技巧）。
- **`LibWebrtcInitializationThreadToken`**（`:430`）是个特殊 `RTCThreadToken`，只用于初始化阶段（不需要真正的 PC 线程）。

> **DI 技巧：用参数依赖强制初始化顺序**。Dagger 没有"先 A 后 B"的语法。看 `videoEncoderFactory`（`:284`）：
> ```kotlin
> fun videoEncoderFactory(
>     @Suppress("UNUSED_PARAMETER")
>     @Named(LIB_WEBRTC_INITIALIZATION) webrtcInitialization: LibWebrtcInitialization,  // 占位
>     ...
> ): VideoEncoderFactory { ... }
> ```
> `webrtcInitialization` 参数被 `@Suppress("UNUSED_PARAMETER")` 标注——**根本不用它**，但列在参数里，Dagger 必须先造出它（即先跑 `libWebrtcInitialization`）才能造 `videoEncoderFactory`。C++ 类比：用构造函数依赖关系强制初始化顺序，而不是靠手动 `init()` 调用顺序。

**B. 音频设备模块**（`RTCModule.kt:154` `audioModule`）：
```kotlin
fun audioModule(audioDeviceModuleOverride, moduleCustomizer, audioOutputAttributes, appContext,
                closeableManager, communicationWorkaround,
                audioRecordSamplesDispatcher, audioBufferCallbackDispatcher): AudioDeviceModule {
    if (audioDeviceModuleOverride != null) return audioDeviceModuleOverride  // ★Overrides 优先
    // 配置一堆回调（录音/播放的错误、状态、样本回调）
    val useHardwareAudioProcessing = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q  // Android 10+ 用硬件回声消除
    val builder = JavaAudioDeviceModule.builder(appContext)
        .setUseHardwareAcousticEchoCanceler(useHardwareAudioProcessing)
        .setUseHardwareNoiseSuppressor(useHardwareAudioProcessing)
        .setSamplesReadyCallback(audioRecordSamplesDispatcher)   // ★录音样本分发（本地录制用）
        .setAudioSource(VOICE_COMMUNICATION)                     // ★通信模式（回声消除需要）
        .setAudioAttributes(audioOutputAttributes)
        .setAudioBufferCallback(audioBufferCallbackDispatcher)
    moduleCustomizer?.invoke(builder)   // ★用户自定义 builder 的钩子
    return builder.createAudioDeviceModule()
        .apply { closeableManager.registerClosable { release() } }  // ★注册到 CloseableManager，退出时释放
}
```
- **`audioDeviceModuleOverride`**：来自 `OverridesModule.audioDeviceModule()`（`:39`），即 `LiveKitOverrides.audioOptions?.audioDeviceModule`。非 null 则整个替换。
- **`moduleCustomizer`**：`LiveKitOverrides.audioOptions?.javaAudioDeviceModuleCustomizer`，在默认 builder 配置完后再让用户改（比整个替换更轻量）。
- **`closeableManager.registerClosable { release() }`**：这是个贯穿全 SDK 的资源管理模式——所有需要释放的重对象都注册到 `CloseableManager`，`Room.release()` 时统一 close。C++ 类比：RAII 析构链，但手动注册。

**C. EglBase**（`RTCModule.kt:270`）：
```kotlin
fun eglBase(eglBaseOverride, memoryManager): EglBase =
    eglBaseOverride ?: EglBase.create().apply { memoryManager.registerClosable { release() } }
```
OpenGL ES 上下文，视频渲染和硬件编解码都需要。同样支持 Overrides，同样注册到 CloseableManager。

**D. 视频编解码工厂**（`RTCModule.kt:284` / `:328`）：
```kotlin
fun videoEncoderFactory(webrtcInit, videoHwAccel, eglContext, videoEncoderFactoryOverride): VideoEncoderFactory =
    videoEncoderFactoryOverride ?: if (videoHwAccel) {
        CustomVideoEncoderFactory(eglContext, enableIntelVp8Encoder=true, enableH264HighProfile=false)
    } else {
        SoftwareVideoEncoderFactory()   // 纯软件编解码
    }
```
`videoHwAccel`（`:412`）默认 `true`，即默认走硬件编解码（`CustomVideoEncoderFactory`/`CustomVideoDecoderFactory`），性能远好于软件。

**E. PeerConnectionFactory（WebRTC 总工厂，单例）**（`RTCModule.kt:347`）：
```kotlin
@Singleton
fun peerConnectionFactoryManager(webrtcInit, audioDeviceModule, videoEncoderFactory, videoDecoderFactory,
                                 peerConnectionFactoryOptions, memoryManager, audioProcessingFactory): PeerConnectionFactoryManager {
    return executeBlockingOnRTCThread(LibWebrtcInitializationThreadToken) {  // ★RTC 线程
        val peerConnectionFactory = PeerConnectionFactory.builder()
            .setAudioDeviceModule(audioDeviceModule)
            .setAudioProcessingFactory(audioProcessingFactory)
            .setVideoEncoderFactory(videoEncoderFactory)
            .setVideoDecoderFactory(videoDecoderFactory)
            .apply { if (peerConnectionFactoryOptions != null) setOptions(it) }  // Overrides
            .createPeerConnectionFactory()
        PeerConnectionFactoryManager(peerConnectionFactory).apply {
            memoryManager.registerClosable { executeOnRTCThread(...) { dispose() } }  // RTC 线程 dispose
        }
    }!!
}
```
这是 WebRTC 的"总工厂"，后续所有 `PeerConnection` 都由它创建（`connectionFactory.createPeerConnection(...)` 见 `PeerConnectionTransport.kt:86`）。**单例**——整个 App 生命周期共享一个。

**F. 其他**：`audioPrewarmer`（`:252`，录音预热，可禁用）、`customAudioProcessingFactory`（`:307`，自定义音频处理插件点）、`rtcThreadToken`（`:396`，RTC 线程令牌）、`senderCapabilitiesGetter`（`:404`，查询编解码能力）、`sdpFactory`（`:416`，SDP 解析工厂）。

#### 2.2.2 `OverridesModule`（`:88`）—— Overrides 如何注入

```kotlin
class OverridesModule(private val overrides: LiveKitOverrides) {
    @Provides @Named(OVERRIDE_OKHTTP)            fun okHttpClient() = overrides.okHttpClient
    @Provides @Named(OVERRIDE_AUDIO_DEVICE_MODULE) fun audioDeviceModule() = overrides.audioOptions?.audioDeviceModule
    @Provides @Named(OVERRIDE_VIDEO_ENCODER_FACTORY) fun videoEncoderFactory() = overrides.videoEncoderFactory
    @Provides @Named(OVERRIDE_EGL_BASE)          fun eglBase() = overrides.eglBase
    @Provides @Named(OVERRIDE_PEER_CONNECTION_FACTORY_OPTIONS) fun peerConnectionFactoryOptions() = overrides.peerConnectionFactoryOptions
    // ... 还有 audioProcessorOptions / javaAudioDeviceModuleCustomizer / audioHandler / audioOutputType / disableAudioPrewarm / disableCommunicationWorkaround
}
```
机制：`LiveKitOverrides` 是个普通 data class（`LiveKitOverrides.kt:41`），用户填好字段传入 `create()`。`LiveKitComponent.kt:61` 的扩展函数把它包成 `OverridesModule` 注入 DI 图。各 `@Provides` 方法把字段暴露成 `@Named` 限定符，其他 Module 的方法用同名 `@Named` 参数接收（非 null 即覆盖）。

> `LiveKitOverrides` 能覆盖什么（`LiveKitOverrides.kt:41-76`）：`okHttpClient`、`videoEncoderFactory`、`videoDecoderFactory`、`audioOptions`（含 audioDeviceModule/audioHandler/audioOutputType/audioProcessorOptions 等）、`eglBase`、`peerConnectionFactoryOptions`。**全是底层组件，不是行为参数**。

#### 2.2.3 其余 5 个 Module（都很短，快速过）

- **`CoroutinesModule`**（`CoroutinesModule.kt:29`）：4 个 `@Provides`，分别返回 `Dispatchers.Default/IO/Main/Unconfined`，用 `@Named(DISPATCHER_*)` 限定。所有需要调度器的对象都注入这些（不直接用 `Dispatchers.X`，便于测试替换）。
- **`WebModule`**（`WebModule.kt:39`）：`okHttpClient`（默认 `globalOkHttpClient`，`by lazy` 单例，`:86`）、`websocketFactory`（就是 OkHttpClient，OkHttp 本身实现 `WebSocket.Factory`）、`connectionWarmer`（连接预热，DNS+TLS 预建）、`networkInfo`（网络类型查询）、`connectivityManager`、`networkCallbackManagerFactory`（网络变化监听工厂）。
- **`AudioHandlerModule`**（`AudioHandlerModule.kt:39`）：`audioOutputType`（默认 `CallAudioType`，`:46`）、`audioOutputAttributes`、`audioHandler`（默认 `AudioSwitchHandler`，可 Override，`:58`）、`communicationWorkaround`（Android 11+ 通信模式 6 秒无音频会自动重置的修复，`:75`，用静音轨保活）。
- **`MemoryModule`**（`MemoryModule.kt:28`）：就一个 `closeableManager()` 返回 `CloseableManager` 单例。所有重对象注册到这里，`Room.release()` → `closeableManager.close()` 统一释放。
- **`JsonFormatModule`**（`JsonFormatModule.kt:28`）：`kotlinx.serialization` 的 `Json { ignoreUnknownKeys = true }`（解析 ICE candidate JSON 用，容忍服务器多字段）。
- **`InternalBindsModule`**（`InternalBindsModule.kt:30`）：`@Binds` 把接口绑到实现（`IncomingDataStreamManager`→`Impl`、`OutgoingDataStreamManager`→`Impl`）。`@Binds` 比 `@Provides` 简洁，只做接口→实现的映射。

### 2.3 阶段②：Room 构造与回调接线

#### 2.3.1 `@AssistedInject` 与 `Room.Factory`

`Room` 用 `@AssistedInject`（不是普通 `@Inject`），因为它需要一个**运行时参数** `context`，其余依赖由 Dagger 注入。所以通过 `@AssistedFactory` 的 `Room.Factory` 创建（`Room.kt:1108`）：

```kotlin
@AssistedFactory
interface Factory {
    fun create(context: Context): Room   // context 是 @Assisted 运行时参数
}
```

> C++ 类比：`@Inject` 构造函数 ≈ 所有参数都由 IoC 容器提供；`@AssistedInject` ≈ 大部分参数由容器提供，少数运行时参数（`@Assisted`）由调用者传，相当于 `std::make_shared<Room>(container_deps..., ctx)`，Dagger 生成这个 `make` 函数。

#### 2.3.2 Room 构造函数注入了什么（`Room.kt:115-156`）

```kotlin
class Room @AssistedInject constructor(
    @Assisted private val context: Context,          // 运行时参数
    internal val engine: RTCEngine,                  // ★单例，WebRTC 引擎
    private val eglBase: EglBase,                    // 单例，渲染用
    localParticipantFactory: LocalParticipant.Factory, // 工厂（造本地参与者）
    private val defaultsManager: DefaultsManager,   // ★单例，采集/发布默认值容器
    @Named(DISPATCHER_DEFAULT) defaultDispatcher,    // 协程调度器
    @Named(DISPATCHER_IO) ioDispatcher,
    val audioHandler: AudioHandler,                  // 音频设备管理（默认 AudioSwitchHandler）
    private val closeableManager: CloseableManager,  // 资源释放注册表
    private val e2EEManagerFactory: E2EEManager.Factory, // E2EE 工厂
    private val communicationWorkaround: CommunicationWorkaround,
    val audioProcessingController: AudioProcessingController,
    val lkObjects: LKObjects,
    networkCallbackManagerFactory: NetworkCallbackManagerFactory,
    private val audioDeviceModule: AudioDeviceModule,
    private val regionUrlProviderFactory: RegionUrlProvider.Factory, // 区域选路工厂
    private val connectionWarmer: ConnectionWarmer,
    private val audioRecordPrewarmer: AudioRecordPrewarmer,
    private val incomingDataStreamManager: IncomingDataStreamManager,
    private val rpcClientManager: RpcClientManager,
    private val rpcServerManager: RpcServerManager,
    private val remoteParticipantFactory: RemoteParticipant.Factory,
) : RTCEngine.Listener, ParticipantListener, RpcManager, IncomingDataStreamManager by incomingDataStreamManager
```

注意 Room 实现的接口：`RTCEngine.Listener`（收引擎回调）、`ParticipantListener`（收参与者回调）、`RpcManager`（RPC）、`IncomingDataStreamManager by incomingDataStreamManager`（委托模式，把数据流管理委托给注入的 manager）。

> **`by` 委托**（C++ 类比）：`IncomingDataStreamManager by incomingDataStreamManager` 表示 Room 把 `IncomingDataStreamManager` 接口的所有方法调用转发给 `incomingDataStreamManager` 对象。相当于 Room 自动生成了所有接口方法的 `return incomingDataStreamManager.xxx()` 转发代码。

#### 2.3.3 `init` 块：回调接线（`Room.kt:162-185`）

构造函数执行完，`init` 块跑，这是初始化的关键一步——**建立事件回流通道 + 注册内部处理器**：

```kotlin
init {
    engine.listener = this   // ★① 接通引擎→Room 的回调通道

    // ② 注册 RPC v2 的内部文本流处理器（占用 lk.rpc_request / lk.rpc_response 两个 topic）
    incomingDataStreamManager.registerTextStreamHandler(RPC_REQUEST_DATA_STREAM_TOPIC) { receiver, fromIdentity ->
        coroutineScope.launch { rpcServerManager.handleIncomingDataStream(receiver, fromIdentity) }
    }
    incomingDataStreamManager.registerTextStreamHandler(RPC_RESPONSE_DATA_STREAM_TOPIC) { receiver, fromIdentity ->
        coroutineScope.launch { rpcClientManager.handleIncomingDataStreamResponse(receiver, fromIdentity) }
    }

    // ③ 给 RPC 管理器接上"查远端客户端协议版本"的回调
    val getRemoteClientProtocol: (Participant.Identity) -> Int = { id ->
        remoteParticipants[id]?.clientProtocol ?: ClientProtocolVersion.DEFAULT.value
    }
    rpcClientManager.getRemoteClientProtocol = getRemoteClientProtocol
    rpcServerManager.getRemoteClientProtocol = getRemoteClientProtocol
}
```

**第 ① 行 `engine.listener = this` 是整个事件系统的根基**：RTCEngine 持有 `listener: Listener?`（`RTCEngine.kt:123`），Room 把自己注册进去。此后引擎层所有事件（连接成功、收到 track、有人进房、收到数据…）都通过 `listener.onXxx()` 回调到 Room，Room 再转成 `RoomEvent` 发给 App。

> 注意 `RTCEngine` 自己也在构造时接了 SignalClient 的回调（`RTCEngine.kt:231` `init { client.listener = this }`）。所以完整回调链是：`SignalClient → RTCEngine → Room → App`，每一层 `init`/构造时接线。

#### 2.3.4 `state` 属性委托的副作用（`Room.kt:239`）

Room 的 `state` 用 `flowDelegate` 委托，**值改变时触发副作用**——这是初始化时埋下的"状态机钩子"：

```kotlin
var state: State by flowDelegate(State.DISCONNECTED) { new, old ->
    if (new != old) {
        when (new) {
            State.CONNECTING -> {
                audioHandler.start()              // ★进入连接：启动音频设备管理
                communicationWorkaround.start()  // ★启动通信模式修复
            }
            State.DISCONNECTED -> {
                audioHandler.stop()              // 断开：停止音频管理
                communicationWorkaround.stop()
                audioRecordPrewarmer.stop()       // 停止录音预热
            }
            else -> {}
        }
    }
}
```

> 这意味着：`Room.connect()` 里 `state = State.CONNECTING`（`Room.kt:476`）这一行不只是改状态，还会**自动启动音频设备**。C++ 类比：属性 setter hook，赋值即触发副作用。`flowDelegate` 同时把状态变化暴露成 Flow，App 可以 `room::state.flow.collect` 监听。

### 2.4 `RTCEngine` 与 `SignalClient` 的构造（单例，DI 时已建好）

Room 构造时注入的 `engine: RTCEngine` 是 `@Singleton`（`RTCEngine.kt:112`），在 DI 阶段就已建好：

```kotlin
@Singleton
class RTCEngine @Inject internal constructor(
    val client: SignalClient,                       // ★SignalClient 也是单例，DI 时建好
    private val pctFactory: PeerConnectionTransport.Factory,  // PC 工厂（@AssistedFactory）
    @Named(DISPATCHER_IO) ioDispatcher,
    private val rtcThreadToken: RTCThreadToken,
    private val dataPacketCryptorFactory: DataPacketCryptorManager.Factory,
) : SignalClient.Listener {                          // ★实现信令回调接口
    init { client.listener = this }                  // 接通 SignalClient → RTCEngine 回调
    ...
}
```

`SignalClient` 同样 `@Singleton @Inject`（`SignalClient.kt:74`），注入 `websocketFactory`、`json`、`okHttpClient`、`ioDispatcher`、`networkInfo`。

> **单例的含义**：即使你 `LiveKit.create()` 多次造多个 Room，`RTCEngine`/`SignalClient`/`PeerConnectionFactory`/`EglBase` 等 `@Singleton` 对象**全局只有一个**，Room 之间共享。但 `publisher`/`subscriber` 两条 PC 是 Room 各自的（每次 `configure` 新建）。

### 2.5 `LocalParticipant` 的创建与 `reinitialize`

`LocalParticipant` 也是 `@AssistedInject`（`LocalParticipant.kt:94`），通过 `LocalParticipant.Factory.create(dynacast)` 创建（`:1421`）。它注入了 `engine`、`peerConnectionFactory`、`eglBase`、各类 track 工厂（`videoTrackFactory`/`audioTrackFactory`/`screencastVideoTrackFactory`）、`defaultsManager`、`capabilitiesGetter` 等。

注意它的几个默认值属性**委托给 `DefaultsManager`**（`LocalParticipant.kt:118-123`）：
```kotlin
var audioTrackCaptureDefaults: LocalAudioTrackOptions by defaultsManager::audioTrackCaptureDefaults
var videoTrackPublishDefaults: VideoTrackPublishDefaults by defaultsManager::videoTrackPublishDefaults
// ... 共 6 个默认值属性
```
> `by defaultsManager::audioTrackCaptureDefaults` 是**属性委托**——LocalParticipant 的这个属性的读写直接转发到 `defaultsManager` 的同名字段。所以 Room、LocalParticipant 改的是**同一个 `DefaultsManager` 单例**里的值，保持同步。`DefaultsManager`（`DefaultsManager.kt:31`）是 `@Singleton`，存所有采集/发布默认值。

`reinitialize`（`LocalParticipant.kt:143`）在 `Room.connect` 里被调用：
```kotlin
internal fun reinitialize(connectOptions: ConnectOptions) {
    reinitialize()                                    // 父类 Participant.reinitialize()
    clientProtocol = connectOptions.clientProtocol.value  // 设客户端协议版本
}
```
父类 `Participant.reinitialize()`（`Participant.kt:500`）只做一件事：若协程作用域 `scope` 不活跃则重建。即重置参与者的协程上下文，为新一轮连接做准备。

### 2.6 阶段③：选项应用 `setRoomOptions`（`Room.kt:624`）

```kotlin
fun setRoomOptions(options: RoomOptions) {
    options.audioTrackCaptureDefaults?.let { audioTrackCaptureDefaults = it }   // 非空才覆盖
    options.videoTrackCaptureDefaults?.let { videoTrackCaptureDefaults = it }
    options.audioTrackPublishDefaults?.let { audioTrackPublishDefaults = it }
    options.videoTrackPublishDefaults?.let { videoTrackPublishDefaults = it }
    options.screenShareTrackCaptureDefaults?.let { screenShareTrackCaptureDefaults = it }
    options.screenShareTrackPublishDefaults?.let { screenShareTrackPublishDefaults = it }
    options.reconnectPolicy?.let { reconnectPolicy = it }
    adaptiveStream = options.adaptiveStream      // 这两个直接覆盖（非可空）
    dynacast = options.dynacast
    e2eeOptions = options.e2eeOptions
}
```

**关键设计：`RoomOptions` 的可空字段 = "不覆盖"**。注释原话（`:620`）："Any null values in options will not overwrite existing values."。这样 `setRoomOptions(RoomOptions(adaptiveStream=true))` 只改 adaptiveStream，其余保持默认。`?.let { }` 是 Kotlin 惯用法——非空才执行块。

写入的这些属性大多委托到 `DefaultsManager`（见 2.5），所以改的是全局单例的值，`LocalParticipant` 发布 track 时会读这些默认值。

> `RoomOptions`（`RoomOptions.kt:27`）字段：`adaptiveStream`（自适应码流）、`dynacast`（动态调整发布层）、`e2eeOptions`（端到端加密）、6 个采集/发布默认值、`reconnectPolicy`（重连策略）。`ConnectOptions`（`ConnectOptions.kt:27`）字段：`autoSubscribe`、`iceServers`、`rtcConfig`、`audio`/`video`（是否自动开麦/开摄像头）、`protocolVersion`、`clientProtocol`。两者区别：`RoomOptions` 管"房间级行为"，`ConnectOptions` 管"这次连接的参数"（connect 时传）。

### 2.7 连接预热（可选，初始化后、connect 前）

`Room.prepareConnection`（`Room.kt:420`）是个优化 API，App 可在页面加载时就调用，提前做 DNS 解析 + TLS 握手 + Cloud 区域选路，缩短首次连接耗时：

```kotlin
suspend fun prepareConnection(url: String, token: String? = null) {
    if (state != State.DISCONNECTED) return
    val urlActual = URI(url)
    if (urlActual.isLKCloud() && token != null) {
        val regionUrlProvider = regionUrlProviderFactory.create(urlActual, token)
        this.regionUrlProvider = regionUrlProvider
        val regionUrl = regionUrlProvider.getNextBestRegionUrl()   // 提前选区域
        if (regionUrl != null && state == State.DISCONNECTED) {
            this.regionUrl = regionUrl
            connectionWarmer.fetch(regionUrl)   // ★预热：DNS + TLS
        }
    } else {
        connectionWarmer.fetch(url)              // 非 Cloud 也预热
    }
}
```
`connectionWarmer`（`WebModule.kt:50`，默认 `OkHttpConnectionWarmer`）用 OkHttp 提前建连接、缓存 DNS 和 TLS 会话。之后 `room.connect()` 复用这些缓存，连接更快。

### 2.8 初始化完成态总结

`LiveKit.create()` 返回后，系统处于这个状态：

```
✅ 已建好（单例，全局共享）：
   PeerConnectionFactory（WebRTC 总工厂，原生库已加载）
   EglBase（OpenGL 上下文）
   AudioDeviceModule（音频设备）
   RTCEngine + SignalClient（引擎，但未连接）
   DefaultsManager（默认值容器，已应用 RoomOptions）
   CloseableManager（资源释放注册表，已登记所有重对象）

✅ 已建好（Room 级）：
   Room（state=DISCONNECTED，已接通 engine.listener=this）
   LocalParticipant（已 reinitialize，协程作用域就绪）

❌ 尚未发生：
   WebSocket 连接（等 connect）
   PeerConnection（等 configure，connect 时才建）
   任何网络活动
   音频设备启动（等 state→CONNECTING 时由 flowDelegate 副作用触发）
```

> 下一步：用户调 `room.connect(url, token)`，进入 §3 信令交互。

### 2.9 初始化读码清单（按依赖图自底向上）

> 建议按"被依赖者先读"的顺序，理解对象怎么一层层造出来：

1. `dagger/InjectionNames.kt`（66 行）—— 所有 `@Named` 限定符常量，先认名字
2. `dagger/LiveKitComponent.kt`（69 行）—— 8 Module 总览 + `@BindsInstance` + 扩展函数
3. `dagger/MemoryModule.kt`（33 行）—— CloseableManager（最底层，被所有人依赖）
4. `dagger/CoroutinesModule.kt`（45 行）—— 4 个调度器
5. `dagger/JsonFormatModule.kt`（35 行）—— Json 实例
6. `dagger/InternalBindsModule.kt`（36 行）—— 接口绑定
7. `LiveKitOverrides.kt`（216 行）—— Overrides 与 AudioOptions 定义（看能覆盖什么）
8. `dagger/OverridesModule.kt`（88 行）—— Overrides 如何暴露成 `@Named`
9. `dagger/WebModule.kt`（86 行）—— OkHttp/WebSocket/网络回调
10. `dagger/AudioHandlerModule.kt`（94 行）—— 音频管理/通信模式修复
11. `dagger/RTCModule.kt`（433 行）—— ★重头戏，WebRTC 初始化与所有重对象
12. `LiveKit.kt`（100 行）—— `create()` 串联三阶段
13. `room/Room.kt:115-185` —— Room 构造函数 + `init` 块（回调接线）
14. `room/Room.kt:239-256` —— `state` 委托的副作用钩子
15. `room/Room.kt:624-650` —— `setRoomOptions` 选项应用
16. `room/participant/LocalParticipant.kt:94-146` —— LocalParticipant 构造 + reinitialize
17. `room/participant/Participant.kt:500` —— 父类 reinitialize
18. `room/DefaultsManager.kt`（42 行）—— 默认值容器
19. `room/Room.kt:420-448` —— `prepareConnection` 预热（可选）

---

## 三、信令交互过程（WebSocket + protobuf）

> 本节深入信令通道。信令是 LiveKit 的"控制平面"——所有协商、订阅、静音、心跳等控制消息都走它，与传音视频的"媒体平面"分离。读信令代码的核心是理解 **WebSocket 生命周期 + 两条 SharedFlow 解耦收发 + JoinResponse 握手 + 协议表**。

### 3.0 信令通道全景

```
Room.connect()                          [Room.kt:461]  连接总调度
    │
    └─ engine.join() → joinImpl()       [RTCEngine.kt:235/250]  四步曲
          │
          ├─ ① client.join()             [SignalClient.kt:131]  信令握手
          │     └─ connect()            [:167]  建 WebSocket，挂起等 JoinResponse
          ├─ ② configure(joinResponse)  [RTCEngine.kt:279]     建 PC（见 §4）
          ├─ ③ negotiatePublisher()      [:716]                发起 publisher 协商
          └─ ④ client.onReadyForResponses() [:254]             开放后续消息处理

运行期：
  收：WebSocket.onMessage → handleSignalResponse → responseFlow → handleSignalResponseImpl → Listener.onXxx
  发：sendXxx() → sendRequest → (skipQueue? 直发 : requestFlow 排队) → WebSocket.send
  心跳：pingJob 周期发 ping → 服务器回 pong → resetPingTimeout
```

### 3.1 连接总调度：`Room.connect()`（`Room.kt:461`）

这是整个连接流程的入口，建议逐行读。我把它分成"锁内准备"和"锁外连接"两段：

**锁内（`Room.kt:466-497`）—— 状态机 + 装配**：
```kotlin
stateLock.withLock {
    // 双重检查，防竞态
    if (state != DISCONNECTED) throw IllegalStateException(...)
    // 取消旧协程作用域（如果有）
    if (::coroutineScope.isInitialized) { coroutineScope.cancel(); job.join() }
    state = State.CONNECTING                          // ★ 状态机翻转（触发 audioHandler.start() 副作用）
    coroutineScope = CoroutineScope(defaultDispatcher + SupervisorJob())  // 新作用域
    roomOptions = getCurrentRoomOptions()             // 收集当前 RoomOptions 快照
    localParticipant.reinitialize(options)            // 重置本地参与者协程 + 设 clientProtocol
    setupLocalParticipantEventHandling()               // 挂本地事件监听（见 3.1.2）
    if (roomOptions.e2eeOptions != null) {             // 可选：端到端加密
        e2eeManager = e2EEManagerFactory.create(roomOptions.e2eeOptions.keyProvider).apply {
            setup(this@Room) { event -> coroutineScope.launch { emitWhenConnected(event) } }
        }
        engine.e2EEManager = e2eeManager
    }
}
```

> **`getCurrentRoomOptions()`（`Room.kt:398`）**：把 Room 当前各属性（adaptiveStream/dynacast/e2eeOptions/6 个默认值）打包成一个 `RoomOptions` 快照。之后 `engine.join` 用这个快照，保证连接期间配置一致。

> **`setupLocalParticipantEventHandling()`（`Room.kt:700`）**：启动一个协程收集 `localParticipant.events`，把参与者级事件（`TrackPublished`/`LocalTrackPublicationFailed`/`TrackUnpublished`/`ParticipantPermissionsChanged`/`MetadataChanged`）转成 `RoomEvent` 发出。这是"参与者层 → 房间层"的事件桥接。

**锁外（`Room.kt:502-582`）—— 真正连接（IO 协程）**：
```kotlin
val connectJob = coroutineScope.launch(ioDispatcher + emptyExceptionHandler) {
    // 0. 可选：音频处理认证
    if (audioProcessingController is AuthedAudioProcessingController)
        audioProcessingController.authenticate(url, token)

    // 1. 区域选路：如果是 LiveKit Cloud，创建 RegionUrlProvider 并预取区域设置
    if (regionUrlProvider?.serverUrl.toString() != url) { regionUrl = null; regionUrlProvider = null }  // URL 变了，重置
    val urlObj = URI(url)
    if (urlObj.isLKCloud()) {
        if (regionUrlProvider == null) regionUrlProvider = regionUrlProviderFactory.create(urlObj, token)
        else regionUrlProvider?.token = token
        launch { regionUrlProvider?.fetchRegionSettings() }   // 预取区域列表，不阻塞主流程
    }

    // 2. ★ 连接循环：失败则换区域 URL 重试
    var nextUrl = regionUrl ?: url
    regionUrl = null
    while (nextUrl != null) {
        val connectUrl = nextUrl
        nextUrl = null
        try {
            engine.regionUrlProvider = regionUrlProvider
            engine.join(connectUrl, token, options, roomOptions)   // ★★ 核心，抛异常则进 catch
        } catch (e: Exception) {
            e.rethrowIfCancellationSignal()                       // 协程取消不重试
            nextUrl = regionUrlProvider?.getNextBestRegionUrl()    // 换区域
            if (nextUrl != null) LKLog.d { "retrying with another region: $nextUrl" }
            else throw e                                           // 没有备用区域，抛出
        }
    }

    // 3. 连上后：注册网络回调、自动开麦/开摄像头、启动指标采集
    ensureActive()
    networkCallbackManager.registerCallback()                     // 监听网络变化（触发重连）
    if (options.audio) {
        var cancelPreconnect: (() -> Unit)? = null
        if (audioTrackPublishDefaults.preconnect) cancelPreconnect = startPreconnectAudioJob(coroutineScope)  // 预连接音频
        if (!localParticipant.setMicrophoneEnabled(true)) cancelPreconnect?.invoke()  // ★ 自动开麦
    }
    ensureActive()
    if (options.video) localParticipant.setCameraEnabled(true)     // ★ 自动开摄像头
    coroutineScope.launch { if (enableMetrics) collectMetrics(room=this@Room, rtcEngine=engine) }  // 指标采集
}
connectJob.join()   // 挂起等待连接完成
error?.let { handleDisconnect(DisconnectReason.JOIN_FAILURE); throw it }  // 失败处理
```

> **读码要点**：`Room.connect` 本身不直接碰 WebSocket，它把活全交给 `engine.join()`。Room 层只管**状态机 + 协程调度 + 区域选路 + 自动发布**。区域选路循环是 Cloud 多机房容错的关键——某个区域连不上自动换下一个。

### 3.1.1 区域选路（RegionUrlProvider）

`Room.connect` 里的 `regionUrlProvider`（`Room.kt:517`）是 LiveKit Cloud 专属优化。`isLKCloud()` 判断 URL 是否是官方 Cloud（`wss://xxx.livekit.cloud`）。若是：
- `regionUrlProviderFactory.create(urlObj, token)` 创建选路器
- `fetchRegionSettings()` 异步拉取所有区域节点列表（带延迟测速）
- `getNextBestRegionUrl()` 返回当前最优区域 URL（连不上时换下一个）

非 Cloud（自建服务器）直接用原 URL。`prepareConnection`（§2.7）可提前触发选路，缩短首次连接耗时。

### 3.2 引擎层：`RTCEngine.joinImpl()`（`RTCEngine.kt:250`）

```kotlin
suspend fun joinImpl(url, token, options, roomOptions): JoinResponse = coroutineScope {
    if (connectionState == DISCONNECTED) connectionState = ConnectionState.CONNECTING
    val joinResponse = client.join(url, token, options, roomOptions)  // ★ 1. 信令握手
    ensureActive()
    listener?.onJoinResponse(joinResponse)                            // 通知 Room（设 sid/name/metadata）
    isClosed = false
    listener?.onSignalConnected(false)                               // 通知 Room 信令已连
    isSubscriberPrimary = joinResponse.subscriberPrimary               // 服务器决定谁先协商
    configure(joinResponse, options)                                    // ★ 2. 创建两条 PC
    if (!isSubscriberPrimary || joinResponse.fastPublish) {
        negotiatePublisher()                                             // ★ 3. 客户端发起 publisher 协商
    }
    client.onReadyForResponses()                                         // ★ 4. 开始处理后续信令
    return@coroutineScope joinResponse
}
```

这四步是连接的核心：**信令握手 → 配置 PC → 发起协商 → 开放响应处理**。

> **`isSubscriberPrimary` 与 `fastPublish`**：服务器在 JoinResponse 里告知协商模式。`subscriberPrimary=true` 表示服务器先发 subscriber offer（客户端先应答下行），publisher 延后协商；`fastPublish=true` 则即使 subscriber primary 也立即协商 publisher（快速发布场景）。这两个标志决定第 3 步是否执行。

> **`join()`（`RTCEngine.kt:235`）与 `joinImpl()` 的区别**：`join()` 是公开入口，先重建 `coroutineScope` + 保存 session 信息（url/token/options/roomOptions），再调 `joinImpl()`。重连时直接调 `joinImpl()` 复用保存的信息。

### 3.3 信令握手：`SignalClient.connect()`（`SignalClient.kt:167`）

```kotlin
private suspend fun connect(url, token, options, roomOptions): ConnectResult {
    close(reason="Starting new connection", shouldClearQueuedRequests=false)  // 清理旧连接（保留排队请求）
    // 1. 拼 WebSocket URL：wss://xxx/rtc?protocol=...&auto_subscribe=...&sdk=android&...
    val wsUrlString = "${url.toWebsocketUrl()}/rtc${createConnectionParams(...)}"
    isReconnecting = options.reconnect
    coroutineScope = CloseableCoroutineScope(SupervisorJob() + ioDispatcher)
    lastUrl = wsUrlString; lastOptions = options; lastRoomOptions = roomOptions
    // 2. 构造 HTTP 请求（带 Bearer token 头）
    val request = Request.Builder().url(wsUrlString)
        .addHeader("Authorization", "Bearer $token").build()
    // 3. ★ 挂起等待 JoinResponse（带 10s 超时）
    return withDeadline(SIGNAL_CONNECT_TIMEOUT.milliseconds) {       // 10s
        suspendCancellableCoroutine { cont ->
            joinContinuation = cont                          // 保存续体，等 onMessage 回调 resume
            cont.invokeOnCancellation { joinContinuation = null; currentWs?.cancel() }  // 取消则关 WS
            currentWs = websocketFactory.newWebSocket(request, this@SignalClient)  // ★ 发起 WS，this 是 WebSocketListener
        }
    }
}
```

**握手是"挂起 + 回调 resume"模式**：`connect()` 用 `suspendCancellableCoroutine` 挂起当前协程，把续体存进 `joinContinuation`。WebSocket 连上后服务器发 `JoinResponse`，`onMessage` 回调里 `joinContinuation?.resume(...)` 唤醒协程，`connect()` 返回。这是 Kotlin 把"异步回调"转成"同步挂起"的标准手法（C++ 类比：promise + future，回调里 set value，await 处阻塞）。

**`join()`（`SignalClient.kt:131`）** 是 `connect()` 的封装：`connect()` 返回 `ConnectResult`（密封类：`Join`/`Reconnect`/`OtherResponse`），`join()` 只接受 `Join` 分支，否则抛异常。

**连接参数**（`SignalClient.kt:207` `createConnectionParams`）拼到 URL query 里：
- `protocol` — 信令协议版本（`ProtocolVersion`，当前 v13，`SignalClient.kt:1034`）
- `auto_subscribe` — 是否自动订阅他人 track
- `adaptive_stream` — 自适应码流（按渲染尺寸调画质）
- `sdk=android` / `version` / `device_model` / `os` / `os_version` — 客户端信息
- `client_protocol` — 客户端协议版本（`ClientProtocolVersion`，RPC v2 等特性协商，`:1062`）
- `network` — 网络类型（wifi/cellular/...，`networkInfo.getNetworkType()`）
- 重连时额外：`reconnect=1` & `sid=参与者sid`（`createConnectionParams` 里 `options.reconnect` 分支）

### 3.4 WebSocket 收发：两条 Flow 解耦

`SignalClient` 用两个 `MutableSharedFlow` 把"收"和"发"做成异步队列，这是理解信令层的关键（`SignalClient.kt:108-117`）：

```kotlin
private val requestFlow = MutableSharedFlow<SignalRequest>(Int.MAX_VALUE)   // 发送队列
private val responseFlow = MutableSharedFlow<Pair<WebSocket, SignalResponse>>(Int.MAX_VALUE) // 接收队列
```

> **`MutableSharedFlow(Int.MAX_VALUE)`**：无限缓冲的共享流。`tryEmit` 投递，`collect` 消费。相当于一个无界异步队列，把生产者和消费者解耦。C++ 类比：线程安全的有界/无界阻塞队列，但用协程 Flow 表达。

**发送侧**（`SignalClient.kt:644`）：
```kotlin
private fun sendRequest(request: SignalRequest) {
    val skipQueue = skipQueueTypes.contains(request.messageCase)  // offer/answer/trickle/sync/leave/simulate 不排队
    if (skipQueue) sendRequestImpl(request)          // 直接发
    else requestFlow.tryEmit(request)                 // 进队列，等 onPCConnected 后消费
}
private fun sendRequestImpl(request) {
    if (!isConnected || currentWs == null) { LKLog.w{...}; return }  // 没连上，丢弃
    val message = request.toByteArray().toByteString()
    currentWs?.send(message)                          // ★ OkHttp WebSocket 发二进制帧
}
```
> 为什么有 `skipQueue`？协商消息（offer/answer/trickle）必须立即发，不能排队等 PC 连上——它们本身就是建立 PC 的消息。普通消息（mute/subscribe 等）可以排队，等 PC 连上再发，避免重连时丢消息。`skipQueueTypes` 定义在 `:1006`。

**发送队列的消费**（`startRequestQueue` `:271`）：只在 `onPCConnected()`（`:291`）后启动——即 PC 真正连上才开始消费排队请求。重连时这保证排队消息在 PC 恢复后才发出。

**接收侧**（`SignalClient.kt:668` `handleSignalResponse`）：
- 第一条消息必须是 `Join`（`SignalClient.kt:679`）：`isConnected = true`，`startRequestQueue()`，`startPingJob()`，解析 `serverVersion`/`serverInfo`，`joinContinuation.resume(ConnectResult.Join(response.join))`（让 `connect()` 挂起返回）。
- 重连场景（`isReconnecting`，`:704`）：任何消息都视为信令重连成功，`isReconnecting=false; isConnected=true`，重启 ping。若有 `Reconnect` 响应则 resume `ConnectResult.Reconnect`，否则 `ConnectResult.OtherResponse`。
- 之后的消息进 `responseFlow`，但**只有调用 `onReadyForResponses()` 后才开始消费**（`SignalClient.kt:254`）——这保证了 RTCEngine 先 `configure()` 完 PC，再处理后续信令（避免收到 offer 时 PC 还没建好）。

> **`onReadyForResponses()` 的精妙**（`:254`）：它启动 `responseFlow.collect` 消费循环。在 `joinImpl` 里，`configure()`（建 PC）完成后才调它。这样如果服务器在 JoinResponse 之后立刻发了个 offer，会被 `responseFlow` 缓存，等 `onReadyForResponses` 后才处理——此时 PC 已就绪。这是"先建好消费者依赖的资源，再开放消费"的典型模式。

### 3.5 信令协议：SignalRequest / SignalResponse

protobuf 定义在 `protocol/` 目录，生成的类是 `LivekitRtc.SignalRequest` / `SignalResponse`。读 `handleSignalResponseImpl`（`SignalClient.kt:743`）能看到所有信令类型的分发：

**客户端→服务器（SignalRequest）**，看 `sendXxx` 方法：
| 方法 | 信令 | 用途 |
|---|---|---|
| `sendOffer` (:422) | offer | publisher 协商，发 SDP offer |
| `sendAnswer` (:431) | answer | subscriber 协商，回 SDP answer |
| `sendCandidate` (:440) | trickle | 发 ICE candidate（带 target: PUBLISHER/SUBSCRIBER） |
| `sendAddTrack` (:475) | addTrack | 通知服务器"我要发布一个 track"（带 cid/类型/加密类型） |
| `sendMuteTrack` (:459) | mute | 静音/取消静音某 track |
| `sendUpdateSubscription` (:534) | subscription | 订阅/取消订阅（带 participantTracks） |
| `sendUpdateTrackSettings` (:501) | trackSetting | 调订阅画质/启停/尺寸/fps |
| `sendUpdateSubscriptionPermissions` (:551) | subscriptionPermission | 设置谁能订阅自己的 track |
| `sendUpdateLocalMetadata` (:566) | updateMetadata | 改自己的 metadata/名字/属性 |
| `sendSyncState` (:579) | syncState | 重连后同步本地状态给服务器 |
| `sendLeave` (:595) | leave | 主动离开（带 reason/action） |
| `sendPing` (:609) | ping/pingReq | 心跳（pingReq 带 rtt） |
| `sendUpdateLocalAudioTrack` (:631) | updateAudioTrack | 更新本地音频 track 特性 |
| `sendSimulateScenario` (:587) | simulate | 模拟故障（测试用） |

**服务器→客户端（SignalResponse）**，看 `handleSignalResponseImpl` 的 `when` 分支（`SignalClient.kt:749`）：
| 分支 | 回调 | 上层处理 |
|---|---|---|
| `ANSWER` (:750) | `onServerAnswer` | publisher.setRemoteDescription |
| `OFFER` (:756) | `onServerOffer` | subscriber 协商应答 |
| `TRICKLE` (:762) | `onTrickle` | addIceCandidate（带 target） |
| `UPDATE` (:773) | `onParticipantUpdate` | 参与者进/出房间 |
| `TRACK_PUBLISHED` (:781) | `onLocalTrackPublished` | 发布 track 的服务器确认（分配 trackSid） |
| `TRACK_SUBSCRIBED` (:777) | `onLocalTrackSubscribed` | 自己的 track 被他人订阅 |
| `SPEAKERS_CHANGED` (:785) | `onSpeakersChanged` | 谁在说话 |
| `ROOM_UPDATE` (:801) | `onRoomUpdate` | 房间元数据变化 |
| `CONNECTION_QUALITY` (:805) | `onConnectionQuality` | 连接质量（每参与者） |
| `SUBSCRIBED_QUALITY_UPDATE` (:813) | `onSubscribedQualityUpdate` | 服务器告诉该发哪档画质（simulcast） |
| `LEAVE` (:793) | `onLeave` | 服务器要求离开/重连（带 action: RESUME/RECONNECT） |
| `MUTE` (:797) | `onRemoteMuteChanged` | 服务器要求静音某 track |
| `STREAM_STATE_UPDATE` (:809) | `onStreamStateUpdate` | 流状态（PAUSED/ACTIVE） |
| `SUBSCRIPTION_PERMISSION_UPDATE` (:821) | `onSubscriptionPermissionUpdate` | 订阅权限变化 |
| `REFRESH_TOKEN` (:825) | `onRefreshToken` | 服务器刷新 token |
| `TRACK_UNPUBLISHED` (:829) | `onLocalTrackUnpublished` | 服务器确认取消发布 |
| `PONG`/`PONG_RESP` (:833) | resetPingTimeout | 心跳回应（PONG_RESP 带 rtt 计算） |
| `RECONNECT` (:842) | （握手阶段处理） | 重连握手响应 |
| `SUBSCRIPTION_RESPONSE` (:847) | `onSubscriptionError` | 订阅错误 |

> 注释 `// TODO` 的分支（`:851` 之后：REQUEST_RESPONSE/ROOM_MOVED/MEDIA_SECTIONS_REQUIREMENT 等）是协议已定义但 SDK 尚未实现的信令。

### 3.6 心跳与超时（`SignalClient.kt:887`）

```kotlin
private fun startPingJob() {
    if (pingJob == null && pingIntervalDurationMillis != 0L) {
        pingJob = coroutineScope.launch {
            while (true) {
                delay(pingIntervalDurationMillis)    // 服务器在 JoinResponse 里告知间隔
                val pingTimestamp = sendPing()       // 发 ping + pingReq(带 rtt)
                startPingTimeout(pingTimestamp)      // 启动超时计时
            }
        }
    }
}
private fun startPingTimeout(timestamp) {
    if (pongJob != null) return
    pongJob = coroutineScope.launch {
        delay(pingTimeoutDurationMillis)             // 服务器告知超时时长
        LKLog.d { "Ping timeout reached for ping sent at $timestamp." }
        currentWs?.close(CLOSE_REASON_PING_TIMEOUT, "Ping timeout")  // 超时关 WS → 触发重连
    }
}
private fun resetPingTimeout() { pongJob?.cancel(); pongJob = null }  // 收到 pong 取消超时
```
> 心跳超时会关 WebSocket，进而触发 `onClose` → `RTCEngine.reconnect()`。这是重连的一个触发源。`pingInterval`/`pingTimeout` 由服务器在 JoinResponse 里下发（`:682-683`），客户端据此配速。`PONG_RESP` 还会算 RTT（`:838`），回传给服务器做网络质量评估。

### 3.7 WebSocket 生命周期与错误处理

`SignalClient` 继承 `WebSocketListener`（OkHttp），重写关键回调（`SignalClient.kt:296-409`）：

- **`onMessage(bytes)`（`:305`）**：收到二进制消息（protobuf）。先检查 `webSocket != currentWs`（旧 WS 消息丢弃），再 `mergeFrom` 解析成 `SignalResponse`，调 `handleSignalResponse`。注意 `onMessage(text)`（`:296`）直接拒绝——本版本只支持二进制 protobuf，不支持 JSON。
- **`onClosed`（`:318`）**：WS 正常关闭，调 `handleWebSocketClose`（清状态、通知 listener）。
- **`onFailure`（`:329`）**：WS 异常。会尝试 HTTP `validate` 请求拿错误原因（`:337`），然后 `resumeWithException` 唤醒 `joinContinuation`（若在握手），并 `handleWebSocketClose` 通知上层重连。
- **`handleWebSocketClose`（`:399`）**：`isConnected=false`，`listener?.onClose(reason, code)`（→ `RTCEngine.reconnect()`），清两个 Flow 的 replay 缓存，取消 ping/pong job。

> **`currentWs` 检查**贯穿所有回调（`if (webSocket != currentWs) return`）：重连时新旧 WS 可能并存，丢弃旧 WS 的消息避免状态错乱。这是异步重连的常见防御。

### 3.8 信令读码清单

1. `SignalClient.kt:131` `join()` / `:148` `reconnect()` — 握手入口
2. `SignalClient.kt:167` `connect()` — ★建 WS、挂起等 JoinResponse
3. `SignalClient.kt:207` `createConnectionParams` — URL query 参数
4. `SignalClient.kt:108-117` 两个 SharedFlow — 收发解耦
5. `SignalClient.kt:644` `sendRequest` / `:654` `sendRequestImpl` — 发送 + skipQueue
6. `SignalClient.kt:271` `startRequestQueue` / `:291` `onPCConnected` — 队列消费时机
7. `SignalClient.kt:254` `onReadyForResponses` — 接收开放时机
8. `SignalClient.kt:668` `handleSignalResponse` — 握手/重连消息处理
9. `SignalClient.kt:743` `handleSignalResponseImpl` — ★所有信令 `when` 分支
10. `SignalClient.kt:296-409` WebSocketListener 回调 — WS 生命周期
11. `SignalClient.kt:887` `startPingJob` — 心跳
12. `SignalClient.kt:953` `interface Listener` — 信令回调接口（21 个方法）

---

## 四、媒体处理过程（WebRTC 双 PeerConnection）

> 本节深入媒体通道。媒体是 LiveKit 的"数据平面"——真正的音视频 RTP 流走它，与传控制消息的信令通道分离。读媒体代码的核心是理解 **双 PC 模型 + 协商（Offer/Answer/Trickle）+ SDP munge + 发布（加 transceiver）+ 订阅（onAddTrack）+ 采集/渲染**。

### 4.0 媒体通道全景

```
                    客户端
   ┌─────────────────────────────────────────┐
   │  publisher PC (上行)                    │  本地采集 → 服务器
   │   - 只发 (SEND_ONLY)                    │   音视频推流
   │   - 客户端主动 createOffer              │
   │   - 含 2 条 DataChannel (reliable/lossy)│  发数据消息/RPC
   ├─────────────────────────────────────────┤
   │  subscriber PC (下行)                   │  服务器 → 本地
   │   - 只收 (RECV_ONLY)                    │   订阅他人音视频
   │   - 服务器主动 createOffer              │
   └─────────────────────────────────────────┘
                    │  两条 PC 各自独立协商、各自有独立 ICE
              LiveKit 服务器 (SFU)

发布: 采集(LocalAudioTrack/LocalVideoTrack) → addTransceiver → negotiatePublisher → SDP 交换 → 推流
订阅: 服务器发 offer → onServerOffer 应答 → onAddTrack 回调 → 包装成 RemoteTrack → 渲染
数据: App → sendData → DataChannel(reliable/lossy) → 服务器转发 → 对端 onMessage
```

### 4.1 配置两条 PeerConnection：`configure()`（`RTCEngine.kt:279`）

这是媒体通道的诞生地，必须在 RTC 线程执行：

```kotlin
private suspend fun configure(joinResponse, connectOptions) {
    launchBlockingOnRTCThread(rtcThreadToken) {                    // ★切到 RTC 线程
        configurationLock.withCheckLock(
            { ensureActive(); if (publisher!=null && subscriber!=null) return },  // 已配置则跳过
        ) {
            participantSid = if (joinResponse.hasParticipant()) joinResponse.participant.sid else null
            // 1. 用 JoinResponse 里的 ICE 服务器构造 RTCConfig
            val rtcConfig = makeRTCConfig(Either.Left(joinResponse), connectOptions)

            // 2. ★ 创建 publisher PC（上行，本地→服务器）
            publisher?.close()   // 先关旧的（重连场景）
            publisher = pctFactory.create(rtcConfig, publisherObserver, publisherObserver)
            // 3. ★ 创建 subscriber PC（下行，服务器→本地）
            subscriber?.close()
            subscriber = pctFactory.create(rtcConfig, subscriberObserver, null)  // listener=null：publisher 才需要 onOffer 回调

            // 4. 注册连接状态监听（决定谁触发"已连接/断开"）
            val connectionStateListener = { newState ->
                if (newState.isConnected()) connectionState = ConnectionState.CONNECTED
                else if (newState.isDisconnected()) connectionState = ConnectionState.DISCONNECTED
            }
            if (joinResponse.subscriberPrimary) {
                subscriberObserver.connectionChangeListener = connectionStateListener  // sub 主导连接状态
                subscriberObserver.dataChannelListener = onDataChannel@{ dc ->          // sub 模式服务器开 datachannel
                    when (dc.label()) { RELIABLE_DATA_CHANNEL_LABEL -> reliableDataChannelSub = dc
                                        LOSSY_DATA_CHANNEL_LABEL -> lossyDataChannelSub = dc
                                        else -> return@onDataChannel }
                    dc.registerObserver(DataChannelObserver(dc))
                }
                publisherObserver.connectionChangeListener = { if (it.isDisconnected()) reconnect() }  // pub 断也重连
            } else {
                publisherObserver.connectionChangeListener = connectionStateListener    // pub 主导
            }

            // 5. ★ 在 publisher PC 上创建两条 DataChannel（可靠 + 尽力）
            ensureActive()
            val reliableInit = DataChannel.Init(); reliableInit.ordered = true
            reliableDataChannel = publisher?.withPeerConnection {
                createDataChannel(RELIABLE_DATA_CHANNEL_LABEL, reliableInit).also { dc ->
                    reliableDataChannelManager = DataChannelManager(dc, DataChannelObserver(dc), rtcThreadToken)
                    dc.registerObserver(reliableDataChannelManager)
                    // 监控缓冲水位，背压时 trim reliableMessageBuffer
                    reliableBufferedAmountJob = coroutineScope.launch {
                        reliableDataChannelManager::bufferedAmount.flow.collect { bufferedAmount ->
                            synchronized(reliableStateLock) { reliableMessageBuffer.trim(bufferedAmount) }
                        }
                    }
                }
            }
            ensureActive()
            val lossyInit = DataChannel.Init(); lossyInit.ordered = false; lossyInit.maxRetransmits = 0
            lossyDataChannel = publisher?.withPeerConnection {
                createDataChannel(LOSSY_DATA_CHANNEL_LABEL, lossyInit).also { dc ->
                    lossyDataChannelManager = DataChannelManager(dc, DataChannelObserver(dc), rtcThreadToken)
                    dc.registerObserver(lossyDataChannelManager)
                }
            }
        }
    }
}
```

> **`pctFactory.create(rtcConfig, pcObserver, listener)`**（`PeerConnectionTransport.kt:389` `@AssistedFactory`）：`pcObserver` 是 `PeerConnection.Observer`（收 ICE/状态/onAddTrack 等原生事件），`listener` 是 `PeerConnectionTransport.Listener`（收 `onOffer` 回调——publisher 需要它把生成的 offer 送出去，subscriber 不需要所以传 null）。

> **`withPeerConnection { ... }`**（`PeerConnectionTransport.kt:115`）：把对 `PeerConnection` 的操作切到 RTC 线程执行并等待结果。所有 PC 操作都通过它，保证线程安全。

**双 PC 模型**（这是 LiveKit 区别于普通 WebRTC demo 的核心）：
```
              客户端
   ┌─────────────────────────────┐
   │ publisher PC (上行)         │  本地采集 → 服务器
   │  - SEND_ONLY               │  客户端主动 createOffer
   │  - 含 2 条 DataChannel     │  (reliable + lossy，发数据消息)
   ├─────────────────────────────┤
   │ subscriber PC (下行)       │  服务器 → 本地
   │  - RECV_ONLY                │  服务器主动 createOffer
   └─────────────────────────────┘
              │
        LiveKit 服务器 (SFU)
```

> **为什么分两条？** 上行下行解耦：发布新 track 只重协商 publisher，不影响下行订阅；服务器推新流只重协商 subscriber，不影响上行。互不阻塞。

#### 4.1.1 `makeRTCConfig`（`RTCEngine.kt:943`）—— ICE 服务器配置

```kotlin
private fun makeRTCConfig(serverResponse, connectOptions): RTCConfiguration {
    // 1. 转换 protobuf ice servers → WebRTC IceServer
    val serverIceServers = responseServers.map { it.toWebrtc() }
    if (servers.isEmpty()) servers.addAll(SignalClient.DEFAULT_ICE_SERVERS)  // 兜底：Google STUN

    // 2. 合并 ICE 服务器：用户自定义优先
    val rtcConfig = connectOptions.rtcConfig?.copy()?.apply {
        val mergedServers = iceServers.toMutableList()
        connectOptions.iceServers?.forEach { if (!mergedServers.contains(it)) mergedServers.add(it) }
        if (mergedServers.isEmpty()) { iceServers.forEach { if (!mergedServers.contains(it)) mergedServers.add(it) } }
        iceServers = mergedServers
    } ?: RTCConfiguration(serverIceServers).apply {
        sdpSemantics = UNIFIED_PLAN                              // ★统一计划（现代 WebRTC）
        continualGatheringPolicy = GATHER_CONTINUALLY           // ★持续收集 ICE candidate
    }

    // 3. 服务器可强制 RELAY（强制走 TURN，隐私场景）
    val clientConfig = serverResponse.clientConfiguration
    if (clientConfig?.forceRelay == ENABLED) rtcConfig.iceTransportsType = RELAY
    return rtcConfig
}
```
- **ICE 服务器优先级**：用户 `ConnectOptions.rtcConfig`/`iceServers` > 服务器下发 > 默认 Google STUN。
- **`GATHER_CONTINUALLY`**：网络变化时持续收集新 candidate，支持 ICE 重启无缝迁移。
- **`forceRelay`**：服务器可强制客户端只走 TURN 中继（隐藏真实 IP），用于隐私场景。

### 4.2 协商过程（Offer/Answer + Trickle ICE）

#### 4.2.1 Publisher 协商（客户端发起）

入口 `negotiatePublisher()`（`RTCEngine.kt:716`）：
```kotlin
internal fun negotiatePublisher() {
    hasPublished = true                       // 标记"有东西要发"（重连时据此重协商）
    if (!client.isConnected) return           // 信令没连上，等连上再补
    coroutineScope.launch {
        negotiatePublisherMutex.withLock {    // ★ 串行化，防并发协商
            publisher?.negotiate?.invoke(getPublisherOfferConstraints())
        }
    }
}
```

`publisher.negotiate` 是个 `debounce` 包装的函数（`PeerConnectionTransport.kt:146`）——20ms 防抖，多次触发合并成一次协商。真正干活的是 `createAndSendOffer`（`PeerConnectionTransport.kt:155`）：

```kotlin
private suspend fun createAndSendOffer(constraints) {
    offerLock.withLock {
        launchRTCIfNotClosed {
            val iceRestart = constraints.findConstraint(ICE_RESTART) == TRUE
            if (iceRestart) { restartingIce = true; LKLog.d{"restarting ice"} }
            // 1. 如果已有本地 offer 等待对方应答，且非 ICE 重启 → 标记 renegotiate，等下次
            if (signalingState == HAVE_LOCAL_OFFER) {
                if (iceRestart && remoteDescription != null) {
                    peerConnection.setRemoteDescription(remoteDescription)  // ICE 重启：重设 remote 触发新 offer
                } else {
                    renegotiate = true; return@launchRTCIfNotClosed           // 等当前 offer 应答后再重协商
                }
            }
            // 2. 递增 offerId（用于识别新旧 offer，防乱序）
            offerId = latestOfferId.incrementAndGet()
            // 3. ★ WebRTC 生成 SDP offer
            val sdpOffer = when (val outcome = peerConnection.createOffer(constraints)) {
                is Either.Left -> outcome.value
                is Either.Right -> { LKLog.d{"error: ${outcome.value}"}; return@launchRTCIfNotClosed }
            }
            if (isClosed()) return@launchRTCIfNotClosed
            // 4. ★ SDP munge（改写）：给 video 媒体行加 DD 扩展、设编码码率
            val sdpDescription = sdpFactory.createSessionDescription(sdpOffer.description)
            for (mediaDesc in mediaDescs) {
                if (mediaDesc.media.mediaType == "video") {
                    ensureVideoDDExtensionForSVC(mediaDesc)   // SVC 依赖描述扩展
                    ensureCodecBitrate(mediaDesc, trackBitrates)  // 按 track 设编码码率
                }
            }
            finalSdp = setMungedSdp(sdpOffer, sdpDescription.toString())  // setLocalDescription(munged)
        }
        // 5. ★ 通过信令发给服务器
        if (currentOfferId > offerId) return  // 并发产生了更新的 offer，丢弃这个
        finalSdp?.let { listener.onOffer(it, offerId) }   // → PublisherTransportObserver.onOffer → client.sendOffer
    }
}
```

> **SDP munge** 是 LiveKit 的特色：WebRTC 生成的 SDP 不完全满足需求（simulcast/SVC 码率），所以在 `setLocalDescription` 前手动改写 SDP 文本。`setMungedSdp`（`:238`）先尝试设 munged 版本，失败则回退原版（容错）。C++ 类比：拿到序列化结果后正则改字符串再反序列化回去，有点 hack 但可控。

> **`renegotiate` 标志**（`:94`）：当已有 `HAVE_LOCAL_OFFER`（上一轮 offer 还没收到 answer）时，新的协商请求不能直接发（会冲突），于是设 `renegotiate=true`。在 `setRemoteDescription`（收到 answer）后检查这个标志，若为 true 则立刻 `createAndSendOffer` 补一轮（`:138`）。这是"协商排队"机制。

Offer 约束（`getPublisherOfferConstraints` `RTCEngine.kt:916`）：`OFFER_TO_RECV_AUDIO/FALSE`、`OFFER_TO_RECV_VIDEO/FALSE`（publisher 只发不收），重连时加 `ICE_RESTART=TRUE`。

#### 4.2.2 收到服务器 Answer：`onServerAnswer`（`RTCEngine.kt:1088`）

```kotlin
override fun onServerAnswer(sessionDescription, offerId) {
    coroutineScope.launch {
        when (val outcome = publisher?.setRemoteDescription(sessionDescription, offerId).nullSafe()) {
            is Either.Left -> { /* 协商完成 */ }
            is Either.Right -> LKLog.e { "error setting remote description: ${outcome.value}" }
        }
    }
}
```
`setRemoteDescription`（`PeerConnectionTransport.kt:121`）会检查 offerId 是否过期（`currentOfferId > offerId` 则丢弃旧 answer，防乱序覆盖），成功后把暂存的 `pendingCandidates` 喂给 PC，并清 `restartingIce`，若 `renegotiate=true` 则触发下一轮 offer。

#### 4.2.3 Subscriber 协商（服务器发起）：`onServerOffer`（`RTCEngine.kt:1103`）

```kotlin
override fun onServerOffer(sessionDescription, offerId) {
    coroutineScope.launch {
        // 1. 接收服务器 offer（setRemoteDescription）
        when (val outcome = subscriber?.setRemoteDescription(sessionDescription, offerId).nullSafe()) {
            is Either.Right -> { LKLog.e{...}; return@launch }  // 失败则中止
            else -> {}
        }
        if (isClosed) return@launch
        // 2. 生成 answer
        val answer = when (val outcome = subscriber?.withPeerConnection { createAnswer(MediaConstraints()) }.nullSafe()) {
            is Either.Left -> outcome.value
            is Either.Right -> { LKLog.e{...}; return@launch }
        }
        if (isClosed) return@launch
        // 3. 设本地 description
        when (val outcome = subscriber?.withPeerConnection { setLocalDescription(answer) }.nullSafe()) {
            is Either.Right -> { LKLog.e{...}; return@launch }
            else -> {}
        }
        if (isClosed) return@launch
        // 4. 回传服务器
        client.sendAnswer(answer, offerId)
    }
}
```
每步都检查 `isClosed`（重连/关闭时中途退出，避免操作已销毁的 PC）。

#### 4.2.4 ICE Candidate 交换：`onTrickle`（`RTCEngine.kt:1152`）

```kotlin
override fun onTrickle(candidate, target) {
    when (target) {
        PUBLISHER  -> publisher?.addIceCandidate(candidate) ?: LKLog.w{"no publisher"}
        SUBSCRIBER -> subscriber?.addIceCandidate(candidate) ?: LKLog.w{"no subscriber"}
        else -> LKLog.i{"unknown target?"}
    }
}
```
`addIceCandidate`（`PeerConnectionTransport.kt:105`）：若 `remoteDescription != null && !restartingIce` → 直接 `peerConnection.addIceCandidate`；否则暂存到 `pendingCandidates`，等 `setRemoteDescription` 成功后批量加入（`:129`）。这是 Trickle ICE 的标准做法——candidate 可能在 SDP 交换前后任意时刻到达。

> **反向**（本地 ICE candidate → 服务器）：`PublisherTransportObserver.onIceCandidate`（:48）→ `client.sendCandidate(target=PUBLISHER)`；`SubscriberTransportObserver.onIceCandidate`（:52）→ `client.sendCandidate(target=SUBSCRIBER)`。`sendCandidate`（`SignalClient.kt:440`）把 candidate 序列化成 JSON（`IceCandidateJSON`），包进 `TrickleRequest`（带 target）发送。

#### 4.2.5 协商触发时机

- **publisher**：`PublisherTransportObserver.onRenegotiationNeeded`（:56）→ `engine.negotiatePublisher()`。每次 `addTransceiver`（发布 track）都会触发 WebRTC 的 `onRenegotiationNeeded`，从而自动协商。也支持手动调 `negotiatePublisher()`（如重连时）。
- **subscriber**：服务器主动发 offer，客户端被动应答。`SubscriberTransportObserver.onRenegotiationNeeded`（:117）是空实现——subscriber 不主动协商。

> **`negotiatePublisherMutex`（RTCEngine）vs `offerLock`（PeerConnectionTransport）**：前者防多次 `negotiatePublisher()` 调用并发（跨 PC 层），后者防同一 PC 上 `createAndSendOffer` 并发（PC 内部）。两层串行化保证协商不冲突。加上 `debounce(20ms)`，高频触发（连续发布多个 track）会合并成一次协商。

### 4.3 发布过程（LocalParticipant）

#### 4.3.1 开麦/开摄像头：`setMicrophoneEnabled`（`LocalParticipant.kt:306`）

```kotlin
suspend fun setMicrophoneEnabled(enabled): Boolean = setTrackEnabled(Track.Source.MICROPHONE, enabled)
suspend fun setCameraEnabled(enabled): Boolean = setTrackEnabled(Track.Source.CAMERA, enabled)
suspend fun setScreenShareEnabled(enabled, screenCaptureParams): Boolean = setTrackEnabled(Track.Source.SCREEN_SHARE, enabled, screenCaptureParams)
```

`setTrackEnabled`（`LocalParticipant.kt:340`）逻辑：
```kotlin
val pubLock = sourcePubLocks[source]!!   // 每个 source 一把锁（:136），防并发开同源 track
pubLock.withLock {
    val pub = getTrackPublication(source)
    if (enabled) {
        if (pub != null) {
            // 已发布，直接取消静音（不重建 track）
            pub.muted = false
            if (source == CAMERA) (pub.track as? LocalVideoTrack)?.startCapture()  // 摄像头重新采集
            success = true
        } else {
            // 未发布，创建 track 并发布
            when (source) {
                MICROPHONE -> {
                    val track = getOrCreateDefaultAudioTrack()  // 创建 LocalAudioTrack
                    track.prewarm(); track.start()              // 预热 + 启动采集
                    if (publishAudioTrack(track)) success = true   // ★ 发布
                    else if (isTrackPublished(track)) success = true  // 并发竞态：别人已发了
                    else { track.stop(); track.stopPrewarm() }       // 失败清理
                }
                CAMERA -> {
                    val track = getOrCreateDefaultVideoTrack()
                    track.start(); track.startCapture()
                    if (publishVideoTrack(track)) success = true
                    else if (isTrackPublished(track)) success = true
                    else { track.stopCapture(); track.stop() }
                }
                SCREEN_SHARE -> {
                    // 需 MediaProjection 权限，创建 LocalScreencastVideoTrack
                    val track = createScreencastTrack(mediaProjectionPermissionResultData) { unpublishTrack(it); screenCaptureParams.onStop?.invoke() }
                    track.startForegroundService(notificationId, notification)  // 前台服务（Android 10+ 录屏需要）
                    track.startCapture()
                    if (!publishVideoTrack(track, options=VideoTrackPublishOptions(null, screenShareTrackPublishDefaults))) {
                        screenCaptureParams.onStop?.invoke(); track.stopCapture(); track.stop(); track.dispose()
                    } else success = true
                }
            }
        }
    } else { pub?.muted = true }          // 禁用 = 静音（不销毁 track，省重建开销）
}
```

> **`sourcePubLocks`（`:136`）**：`Track.Source.entries.associateWith { Mutex() }`，每种 source（MICROPHONE/CAMERA/SCREEN_SHARE…）一把独立锁。注释说明：没有它可能创建多个同源 track，Camera 多个 capturer 同时激活会死锁。

> **静音 vs 取消发布的区别**：`setMicrophoneEnabled(false)` 只是 `pub.muted = true`（track 还在，只是不发数据，省重建开销）；真正销毁要 `unpublishTrack`。C++ 类比：静音是关发送缓冲，取消发布是拆掉整个发送链路。

#### 4.3.2 Track 的创建（采集层）

`getOrCreateDefaultAudioTrack`（`:152`）→ `createAudioTrack`（`:175`）→ `LocalAudioTrack.createTrack`（`LocalAudioTrack.kt:222`）：
```kotlin
internal fun createTrack(context, factory, options, audioTrackFactory, name): LocalAudioTrack {
    // 权限检查（RECORD_AUDIO）
    val audioConstraints = MediaConstraints()
    audioConstraints.optional.addAll(listOf(
        KeyValuePair("googEchoCancellation", options.echoCancellation.toString()),
        KeyValuePair("googAutoGainControl", options.autoGainControl.toString()),
        KeyValuePair("googNoiseSuppression", options.noiseSuppression.toString()),
        // ... highpassFilter/typingNoiseDetection
    ))
    val audioSource = factory.createAudioSource(audioConstraints)   // ★WebRTC 创建音频源
    val rtcAudioTrack = factory.createAudioTrack(UUID.randomUUID().toString(), audioSource)  // ★创建 track
    return audioTrackFactory.create(name, rtcAudioTrack, options)    // 包装成 LocalAudioTrack
}
```

`createVideoTrack`（`:193`）→ `LocalVideoTrack.createTrack`（`LocalVideoTrack.kt:498`）：
```kotlin
internal fun createTrack(factory, context, name, capturer, options, rootEglBase, trackFactory, videoProcessor): LocalVideoTrack {
    val source = factory.createVideoSource(options.isScreencast)
    // 可选视频处理器（虚拟背景等），支持尺寸自适应
    val finalVideoProcessor = if (options.captureParams.adaptOutputToDimensions) ScaleCropVideoProcessor(...).apply{childVideoProcessor=videoProcessor} else videoProcessor
    source.setVideoProcessor(finalVideoProcessor)
    val surfaceTextureHelper = SurfaceTextureHelper.create("VideoCaptureThread", rootEglBase.eglBaseContext)  // ★采集线程 + EGL 上下文
    capturer.initialize(surfaceTextureHelper, context, source.capturerObserver)  // 初始化采集器（Camera2/屏幕）
    val rtcTrack = factory.createVideoTrack(UUID.randomUUID().toString(), source)  // ★创建 track
    return trackFactory.create(capturer, source, options, name, rtcTrack, ...)
}
```
> 采集层全是 WebRTC 原生 API：`createAudioSource`/`createAudioTrack`、`createVideoSource`/`createVideoTrack`、`SurfaceTextureHelper`（采集线程）、`VideoCapturer`（Camera2Helper 或屏幕采集器）。`videoProcessor` 是插件点（虚拟背景等 ML 处理，见 `track-processors` 模块）。

#### 4.3.3 发布核心：`publishTrackImpl`（`LocalParticipant.kt:631`）

这是发布最核心的函数，建议精读。流程：

```kotlin
private suspend fun publishTrackImpl(track, options, requestConfig, encodings, ...): LocalTrackPublication? {
    // 1. 前置检查：disposed / 权限(hasPermissionsToPublish) / 已发布 / 已连接
    if (track.isDisposed) return null
    if (!hasPermissionsToPublish(trackSource)) throw PublishException(...)   // ★token 权限检查
    if (isTrackPublished(track)) { onPublishFailure(...); return null }     // 已发过跳过
    if (engine.connectionState == DISCONNECTED) { onPublishFailure(...); return null }
    if (track is LocalVideoTrack) track.clearSimulcastCodecs()

    val cid = track.rtcTrack.id()         // ★WebRTC track id，用于关联信令与媒体

    // 2. ★ negotiate()：在 publisher PC 加 transceiver（触发 onRenegotiationNeeded → 协商）
    suspend fun negotiate() {
        if (engine.publisher == null) throw IllegalStateException("publisher not configured")
        val transInit = RtpTransceiverInit(SEND_ONLY, listOf(sid), encodings)  // 只发，带 simulcast encodings
        val transceiver = engine.createSenderTransceiver(track.rtcTrack, transInit)  // ★ publisher.addTransceiver
        when (track) { is LocalVideoTrack -> track.transceiver = transceiver
                       is LocalAudioTrack -> track.transceiver = transceiver }
        if (transceiver == null) throw PublishException("null sender")
        track.statsGetter = engine.createStatsGetter(transceiver.sender)   // 绑定统计采集
        // simulcast/SVC 码率信息
        if (encodings.isNotEmpty() && finalOptions is VideoTrackPublishOptions && isSVCCodec(...))
            engine.registerTrackBitrateInfo(cid, TrackBitrateInfo(codec, maxBitrate))  // 供 SDP munge 用
        if (finalOptions is VideoTrackPublishOptions) {
            transceiver.sortVideoCodecPreferences(finalOptions.videoCodec, capabilitiesGetter)  // ★设首选编码
            (track as LocalVideoTrack).codec = finalOptions.videoCodec
            transceiver.sender.parameters.degradationPreference = finalOptions.degradationPreference  // 降质策略
        }
        // onRenegotiationNeeded 自动触发 negotiatePublisher()，无需手动调
    }

    // 3. ★ requestAddTrack()：信令通知服务器，等服务器分配 trackSid
    suspend fun requestAddTrack(): TrackInfo? = try {
        engine.addTrack(cid, options.name ?: track.name, track.kind.toProto(), options.stream, builder)
    } catch (e: Exception) { onPublishFailure(...); null }

    // 4. ★ 并发执行 negotiate + requestAddTrack（fast publish 优化）
    val trackInfo: TrackInfo?
    if (enabledPublishVideoCodecs.isNotEmpty()) {
        // 现代路径：协商与请求并行（codec 已预验证）
        trackInfo = coroutineScope {
            val negotiateJob = launch { negotiate() }
            val publishJob = async { requestAddTrack() }
            negotiateJob.join(); return@coroutineScope publishJob.await()   // 并行，提速
        }
    } else {
        // legacy 路径：先 requestAddTrack，拿到服务器选的 codec 再 negotiate
        trackInfo = requestAddTrack()
        if (trackInfo != null && options is VideoTrackPublishOptions) {
            // 服务器可能不支持请求的 codec，回退到服务器选的
            val primaryCodecMime = trackInfo.codecsList.firstOrNull()?.mimeType
            if (primaryCodecMime != null && primaryCodecMime.mimeTypeToVideoCodec() != options.videoCodec) {
                options = options.copy(videoCodec = updatedCodec)
                encodings = computeVideoEncodings(...)   // 重算 encodings
            }
        }
        negotiate()
    }

    // 5. 创建 LocalTrackPublication，加入 trackPublications，发事件
    return if (trackInfo != null) {
        val publication = LocalTrackPublication(info=trackInfo, track, this, options)
        addTrackPublication(publication)
        publishListener?.onPublishSuccess(publication)
        internalListener?.onTrackPublished(publication, this)        // → Room.onTrackPublished → RoomEvent.TrackPublished
        eventBus.postEvent(ParticipantEvent.LocalTrackPublished(this, publication), scope)
        publication
    } else null
}
```

`engine.addTrack`（`RTCEngine.kt:387`）是**挂起函数**：发 `sendAddTrack` 信令后，用 `suspendCancellableCoroutine` 挂起，把续体存进 `pendingTrackResolvers[cid]`，等服务器回 `TrackPublishedResponse`（通过 `onLocalTrackPublished` `RTCEngine.kt:1169` 用 `cid` 找到续体并 resume）。带 20s 超时（`withDeadline(20.seconds)`）。

> **`onLocalTrackPublished`（`RTCEngine.kt:1169`）**：服务器确认发布后回调，用 `response.cid` 从 `pendingTrackResolvers` 取出续体，`cont.resume(response.track)` 唤醒 `addTrack`。这是"信令确认 → 唤醒发布协程"的关联点，`cid` 是关联键。

> **`computeVideoEncodings`（`:818`）**：根据分辨率/是否屏幕共享/simulcast/scalabilityMode 计算 `RtpParameters.Encoding` 列表（simulcast 多档分辨率，SVC 单档多层）。这是 simulcast 编码参数的核心。

> **发布 = 三件事**：① publisher PC 加 transceiver（媒体层） ② 重新协商（SDP 交换） ③ 信令通知服务器分配 sid（控制层）。三者通过 `cid`（WebRTC track id）关联。fast publish 让①②③并行，legacy 串行（因需等服务器选 codec）。

### 4.4 订阅过程（服务器驱动）

订阅是**服务器主动推**，客户端被动接收。入口在 `SubscriberTransportObserver.onAddTrack`（`SubscriberTransportObserver.kt:59`）：

```kotlin
override fun onAddTrack(receiver, streams) {
    executeOnRTCThread(rtcThreadToken) {
        val track = receiver.track() ?: return  // 取 MediaStreamTrack
        LKLog.v { "onAddTrack: ${track.kind()}, ${track.id()}, $streams" }
        engine.listener?.onAddTrack(receiver, track, streams)   // → Room.onAddTrack
    }
}
```

`Room.onAddTrack`（`Room.kt:1199`）：
```kotlin
override fun onAddTrack(receiver, track, streams) {
    if (streams.isEmpty()) { LKLog.i{"add track with empty streams?"}; return }
    var (participantSid, streamId) = unpackStreamId(streams.first().id)  // ★从 stream id 解出参与者 sid
    var trackSid = track.id()
    if (streamId != null && streamId.startsWith("TR")) trackSid = streamId  // track sid 优先用 streamId
    val participant = getParticipantBySid(participantSid) as? RemoteParticipant
    if (participant == null) { LKLog.e{"participant not present: $participantSid"}; return }
    val statsGetter = engine.createStatsGetter(receiver)
    participant.addSubscribedMediaTrack(track, trackSid, autoManageVideo=adaptiveStream, statsGetter, receiver)
}
```

> **`unpackStreamId`**：WebRTC 的 stream id 格式是 `participantSid|trackSid` 或 `participantSid`，解析出参与者 sid 和可选的 track sid。这是 LiveKit 把"哪个参与者的哪条流"编码进 WebRTC stream id 的方式。

`RemoteParticipant.addSubscribedMediaTrack`（`RemoteParticipant.kt:147`）：
```kotlin
fun addSubscribedMediaTrack(mediaTrack, sid, statsGetter, receiver, autoManageVideo=false, triesLeft=20) {
    val publication = getTrackPublication(sid)
    // ★可能先收到 track 再收到 publication（信令乱序），重试 20 次
    if (publication == null) {
        if (triesLeft == 0) {
            internalListener?.onTrackSubscriptionFailed(sid, exception, this)  // 放弃
            eventBus.postEvent(ParticipantEvent.TrackSubscriptionFailed(...), scope)
        } else {
            coroutineScope.launch { delay(150); addSubscribedMediaTrack(..., triesLeft-1) }  // 150ms 后重试
        }
        return
    }
    // ★按类型包装成 RemoteAudioTrack/RemoteVideoTrack
    val track: Track = when (mediaTrack.kind()) {
        KIND_AUDIO -> audioTrackFactory.create(rtcTrack=mediaTrack as AudioTrack, name="", receiver=receiver)
        KIND_VIDEO -> videoTrackFactory.create(rtcTrack=mediaTrack as VideoTrack, name="", autoManageVideo=autoManageVideo, receiver=receiver)
        else -> throw InvalidTrackTypeException(...)
    }
    track.statsGetter = statsGetter
    publication.track = track; publication.subscriptionAllowed = true
    track.name = publication.name; track.sid = publication.sid
    addTrackPublication(publication); track.start()
    internalListener?.onTrackSubscribed(track, publication, this)   // → Room.onTrackSubscribed → RoomEvent.TrackSubscribed
    eventBus.postEvent(ParticipantEvent.TrackSubscribed(...), scope)
}
```

> **重试机制**（`triesLeft=20`）：WebRTC 的 `onAddTrack`（媒体层）可能比服务器的 `UPDATE` 信令（带 publication 信息）先到。此时 `getTrackPublication(sid)` 返回 null，于是延迟 150ms 重试，最多 20 次（共 3 秒）。这是处理"媒体与信令时序错乱"的容错。

> **`autoManageVideo=adaptiveStream`**：若开启自适应码流，`RemoteVideoTrack` 会根据渲染视图尺寸自动调订阅画质（见 4.4.1）。

#### 4.4.1 主动订阅控制（`RemoteTrackPublication`）

客户端也可**主动控制订阅**（`RemoteTrackPublication.kt`）：

```kotlin
fun setSubscribed(subscribed: Boolean) {                    // :126 订阅/取消
    isDesired = subscribed
    val participant = participant.get() as? RemoteParticipant ?: return
    val participantTracks = ParticipantTracks.newBuilder().participantSid(participant.sid.value).addTrackSids(sid).build()
    participant.signalClient.sendUpdateSubscription(isDesired, participantTracks)  // ★发 subscription 信令
}

fun setEnabled(enabled: Boolean) {                         // :143 暂停/恢复（不解码，省带宽）
    if (isAutoManaged || !subscribed || enabled == !disabled) return
    disabled = !enabled
    sendUpdateTrackSettings.invoke()                        // ★发 trackSetting 信令
}

fun setVideoQuality(quality: VideoQuality) {                // :159 选画质档（LOW/MEDIUM/HIGH）
    if (isAutoManaged || !subscribed || quality == videoQuality || track !is VideoTrack) return
    videoQuality = quality; videoDimensions = null
    sendUpdateTrackSettings.invoke()
}

fun setVideoDimensions(dimensions: Track.Dimensions) {      // :177 按渲染尺寸订阅（adaptiveStream 用）
    if (isAutoManaged || !subscribed || videoDimensions == dimensions || track !is VideoTrack) return
    videoQuality = null; videoDimensions = dimensions
    sendUpdateTrackSettings.invoke()
}
```

> **`isAutoManaged`**：若 `adaptiveStream=true`，SDK 自动管理画质（按渲染视图尺寸），此时手动 `setVideoQuality`/`setVideoDimensions` 被忽略（`return`）。`sendUpdateTrackSettings` 最终调 `SignalClient.sendUpdateTrackSettings`（`:501`），把画质/尺寸/fps/disabled 发给服务器，服务器据此调转发码率。

> **订阅 vs 启停 vs 画质**三层控制：`setSubscribed` 控制是否要这条流（建/拆订阅），`setEnabled` 控制是否解码传输（暂停省带宽但保持订阅），`setVideoQuality`/`setVideoDimensions` 控制要哪档画质（simulcast 选层）。

### 4.5 媒体数据流全景

```
发布(上行):  麦克风/摄像头 → LocalAudioTrack/LocalVideoTrack(采集, WebRTC createAudioTrack/createVideoTrack)
             → publisher PC.addTransceiver(SEND_ONLY) → RTP 编码(硬件/软件) → SRTP 加密 → 服务器
订阅(下行):  服务器 → SRTP 解密 → subscriber PC → RTP 解码
             → onAddTrack 回调 → RemoteAudioTrack/RemoteVideoTrack(包装 MediaStreamTrack)
             → VideoSink(SurfaceViewRenderer/TextureViewRenderer) → GPU 渲染到屏幕
数据消息:    App → RTCEngine.sendData(DataPacket) → publisher DataChannel(reliable/lossy) → 服务器 → 对端
            对端 → subscriber DataChannel → RTCEngine.onMessage → 解析 DataPacket → 回调(LifecycleListener)
```

### 4.6 媒体读码清单

1. `RTCEngine.kt:279` `configure()` — ★建双 PC + DataChannel
2. `RTCEngine.kt:943` `makeRTCConfig()` — ICE 服务器配置
3. `PeerConnectionTransport.kt:70` 构造 — PC 创建（RTC 线程）
4. `PeerConnectionTransport.kt:155` `createAndSendOffer()` — ★SDP 生成 + munge + 发送
5. `PeerConnectionTransport.kt:121` `setRemoteDescription()` — offerId 防乱序 + pendingCandidates
6. `PeerConnectionTransport.kt:105` `addIceCandidate()` — Trickle ICE 暂存
7. `PeerConnectionTransport.kt:146` `negotiate` debounce — 协商合并
8. `RTCEngine.kt:716` `negotiatePublisher()` / `:916` `getPublisherOfferConstraints`
9. `RTCEngine.kt:1088` `onServerAnswer` / `:1103` `onServerOffer` / `:1152` `onTrickle`
10. `RTCEngine.kt:387` `addTrack()` / `:424` `createSenderTransceiver` / `:1169` `onLocalTrackPublished`
11. `PublisherTransportObserver.kt:48/56` — ICE candidate / onRenegotiationNeeded
12. `SubscriberTransportObserver.kt:52/59/117` — ICE candidate / onAddTrack / onRenegotiationNeeded(空)
13. `LocalParticipant.kt:306` `setMicrophoneEnabled` / `:340` `setTrackEnabled`
14. `LocalParticipant.kt:175` `createAudioTrack` / `:193` `createVideoTrack` — 采集层
15. `LocalAudioTrack.kt:222` `createTrack` / `LocalVideoTrack.kt:498` `createTrack` — WebRTC track 创建
16. `LocalParticipant.kt:631` `publishTrackImpl` — ★发布核心
17. `LocalParticipant.kt:818` `computeVideoEncodings` — simulcast 参数
18. `Room.kt:1199` `onAddTrack` — 订阅入口
19. `RemoteParticipant.kt:147` `addSubscribedMediaTrack` — ★包装 + 重试
20. `RemoteTrackPublication.kt:126/143/159/177` — 订阅控制（setSubscribed/setEnabled/setVideoQuality/setVideoDimensions）

---

## 五、事件回流机制（从引擎到 App）

### 5.1 三级回调链

```
WebRTC/WebSocket 原生事件
    │
    ▼ ①
TransportObserver / SignalClient.Listener   (L4 → L3)
    │  onAddTrack / onServerAnswer / onMessage ...
    ▼ ②
RTCEngine.Listener   (L3 → L2)   RTCEngine.kt:1015 接口，Room 实现
    │  onEngineConnected / onTrackSubscribed / onUpdateParticipants ...
    ▼ ③
Room → BroadcastEventBus → Flow<RoomEvent>   (L2 → L1)
    │  room.events.collect { event -> ... }
    ▼
App
```

### 5.2 关键回调对应关系

| 引擎层回调 (RTCEngine.Listener) | Room 实现 | 发出的 RoomEvent |
|---|---|---|
| `onEngineConnected` (`Room.kt:1175`) | `state = CONNECTED` | `RoomEvent.Connected` |
| `onEngineReconnected` (:1183) | `state = CONNECTED` | `RoomEvent.Reconnected` |
| `onEngineReconnecting` (:1191) | `state = RECONNECTING` | `RoomEvent.Reconnecting` |
| `onEngineDisconnected` (:1440) | `state = DISCONNECTED` | `RoomEvent.Disconnected` |
| `onAddTrack` (:1199) | 包装成 RemoteTrack | （经 RemoteParticipant）→ `TrackSubscribed` |
| `onUpdateParticipants` (:1231) | 创建/移除 Participant | `ParticipantConnected`/`Disconnected` |
| `onTrackSubscribed` (:1562) | e2ee + 转发 | `RoomEvent.TrackSubscribed` |
| `onSubscribedQualityUpdate` (:1415) | 调本地 simulcast 层 | （内部处理，调编码器） |

### 5.3 事件总线：`BroadcastEventBus`

`Room` 内部用 `eventBus: BroadcastEventBus<RoomEvent>`，对外暴露 `events: Flow<RoomEvent>`。App 用协程 `collect` 监听：
```kotlin
room.events.collect { event ->
    when (event) {
        is RoomEvent.TrackSubscribed -> // 渲染远端视频
        is RoomEvent.ParticipantConnected -> // 有人进房
        is RoomEvent.Disconnected -> // 掉线
    }
}
```
事件定义在 `events/RoomEvent.kt`、`ParticipantEvent.kt`、`TrackEvent.kt`（密封类，编译期穷举）。

---

## 六、重连与数据通道（QoS 补充）

### 6.1 重连：`RTCEngine.reconnect()`（`RTCEngine.kt:521`）

触发源：① WebSocket `onClose`（:1203）② ICE 断开（`connectionState` 变 DISCONNECTED，:147）③ 心跳超时 ④ 网络丢失恢复（`Room.kt:1145`）。

```kotlin
@Synchronized fun reconnect() {
    if (reconnectingJob?.isActive == true) return   // 防重入
    if (isClosed) return
    val job = coroutineScope.launch {
        for (retries in 0 until MAX_RECONNECT_RETRIES) {   // 最多 30 次
            if (retries != 0) url = regionUrlProvider?.getNextBestRegionUrl()  // 换区域
            val startDelay = reconnectPolicy.getNextRetryDelay(context)  // 指数退避
            if (startDelay == null) break                  // 策略放弃
            delay(startDelay)
            val isFullReconnect = when (reconnectType) {
                DEFAULT -> retries != 0 || forceFullReconnect   // 第一次软重连，之后全量
                FORCE_SOFT_RECONNECT -> false
                FORCE_FULL_RECONNECT -> true
            }
            if (isFullReconnect) {
                closeResources("Full Reconnecting"); joinImpl(url, token, ...)  // ★ 重新走完整 join
            } else {
                subscriber?.prepareForIceRestart()
                client.reconnect(url, token, participantSid)   // ★ 只重连信令，保留 PC
                if (hasPublished) negotiatePublisher()         // 重启 publisher ICE
            }
            // 等待 ICE 连上
            withTimeoutOrNull(MAX_ICE_CONNECT_TIMEOUT_MS) {
                listOfNotNull(publisherWaitJob, subscriberWaitJob).joinAll()
            }
            if (连上了) { resendReliableMessagesForResume(lastMessageSeq); return@launch }
            if (超时) break
        }
        close("Failed reconnecting"); listener?.onEngineDisconnected(UNKNOWN_REASON)
    }
}
```

- **软重连（resume）**：只重连 WebSocket，保留两条 PC（快，适合短暂抖动）。会补发 reliable 数据消息。
- **全量重连（full）**：`closeResources` 销毁 PC，重新 `joinImpl`（慢，彻底重建）。
- `ReconnectPolicy`（`network/ReconnectPolicy.kt`）是接口，`getNextRetryDelay(ReconnectContext)` 返回退避时长或 null（放弃）。

### 6.2 数据通道：reliable vs lossy（`RTCEngine.sendData` `:733`）

两条 DataChannel（`configure` 时创建）：
- `_reliable`：`ordered=true`，保证顺序到达。带序号 `reliableDataSequence`，重连后 `resendReliableMessagesForResume` 补发（`reliableMessageBuffer` 缓存）。
- `_lossy`：`ordered=false, maxRetransmits=0`，尽力传，丢了就丢（适合实时性高的场景）。

`sendData` 流程（`RTCEngine.kt:733`）：
```kotlin
internal suspend fun sendData(dataPacket): Result<Unit> {
    ensurePublisherConnected(dataPacket.kind)   // 确保 publisher PC + datachannel 就绪
    // 可选 E2EE 加密
    if (isReliable) dataPacket.setSequence(reliableDataSequence)
    if (packetBytes.size > MAX_DATA_PACKET_SIZE) return failure(...)  // 64KB 上限
    if (isReliable && connectionState == RECONNECTING) {
        reliableMessageBuffer.queue(...)        // 重连中，先缓存
        return success
    }
    val channel = dataChannelForKind(kind)      // reliable → _reliable, lossy → _lossy
    channel.send(Buffer(packetBytes, true))
    if (isReliable) reliableMessageBuffer.queue(...)  // 缓存以备重连补发
}
```

> 数据通道承载：用户消息（`UserPacket`）、RPC、数据流（`DataStream`）、转写（`Transcription`）等。E2EE 开启时对 payload 加密。

---

## 七、逐文件精读清单（按推荐顺序）

> 路径相对 `livekit-android-sdk/src/main/java/io/livekit/android/`。每行标注：**重点看什么**。

### 第一轮：入门（理解"怎么用"）
1. `sample-app-basic/.../MainActivity.kt` — 50 行，看 `LiveKit.create` + `room.connect` + `events.collect`
2. `LiveKit.kt`（100 行）— 入口，看 `create()` 怎么装配
3. `Room.kt:461` `connect()` — 连接总调度，状态机
4. `Room.kt:187` `enum class State` + `:239` `state` 委托 — 状态机定义

### 第二轮：初始化与装配（理解"对象怎么来"）
5. `dagger/LiveKitComponent.kt`（69 行）— 8 个 Module 总览
6. `dagger/RTCModule.kt`（433 行）— ★ WebRTC 初始化、PeerConnectionFactory、编解码工厂
7. `dagger/CoroutinesModule.kt` / `WebModule.kt` / `OverridesModule.kt` — 调度器、OkHttp、覆盖项
8. `Room` 构造函数 + `init` 块（`Room.kt:140-280`）— 看注入了哪些依赖、`engine.listener = this`

### 第三轮：信令（理解"控制通道"）
9. `SignalClient.kt:167` `connect()` — WebSocket 建立、URL 拼接、挂起等 JoinResponse
10. `SignalClient.kt:296` `onMessage` / `:668` `handleSignalResponse` — 收消息分发
11. `SignalClient.kt:743` `handleSignalResponseImpl` — ★ 所有信令类型的 `when` 分支
12. `SignalClient.kt:644` `sendRequest` / `:654` `sendRequestImpl` — 发消息、skipQueue 机制
13. `SignalClient.kt:887` `startPingJob` — 心跳
14. `SignalClient.kt:953` `interface Listener` — 信令回调接口

### 第四轮：引擎与协商（理解"媒体通道怎么建"）
15. `RTCEngine.kt:250` `joinImpl()` — 连接四步曲
16. `RTCEngine.kt:279` `configure()` — ★ 创建双 PC + DataChannel
17. `RTCEngine.kt:943` `makeRTCConfig()` — ICE 服务器配置
18. `RTCEngine.kt:716` `negotiatePublisher()` + `:916` `getPublisherOfferConstraints`
19. `PeerConnectionTransport.kt:155` `createAndSendOffer()` — ★ SDP 生成 + munge + 发送
20. `PeerConnectionTransport.kt:121` `setRemoteDescription()` — offerId 防乱序
21. `RTCEngine.kt:1088` `onServerAnswer` / `:1103` `onServerOffer` / `:1152` `onTrickle`
22. `PublisherTransportObserver.kt` / `SubscriberTransportObserver.kt` — PC 观察者，ICE/重协商/onAddTrack

### 第五轮：发布与订阅（理解"媒体怎么传"）
23. `LocalParticipant.kt:306` `setMicrophoneEnabled` / `:340` `setTrackEnabled`
24. `LocalParticipant.kt:631` `publishTrackImpl` — ★ 发布核心
25. `RTCEngine.kt:387` `addTrack` / `:424` `createSenderTransceiver` / `:1169` `onLocalTrackPublished`
26. `Track.kt` — 轨道抽象基类、Kind/Source 枚举
27. `LocalAudioTrack.kt` / `LocalVideoTrack.kt` — 本地采集
28. `Room.kt:1199` `onAddTrack` → `RemoteParticipant.addSubscribedMediaTrack` — 订阅
29. `RemoteTrackPublication.kt` — 订阅控制（setSubscribed/setEnabled/setVideoQuality）

### 第六轮：事件与 QoS（理解"怎么通知 + 怎么保活"）
30. `events/RoomEvent.kt` / `ParticipantEvent.kt` / `TrackEvent.kt` — 事件定义
31. `events/BroadcastEventBus.kt` — 事件总线
32. `Room.kt:1175-1590` `RTCEngine.Listener` 实现 — 回调→事件转换
33. `RTCEngine.kt:521` `reconnect()` — ★ 重连
34. `network/ReconnectPolicy.kt` / `DefaultReconnectPolicy` — 退避策略
35. `RTCEngine.kt:733` `sendData()` — 数据通道
36. `room/metrics/RTCMetricsManager.kt` + `collectMetrics` — 指标采集

### 第七轮：进阶（按需）
37. `room/datastream/` — 数据流（字节/文本流）
38. `room/rpc/` — RPC
39. `e2ee/E2EEManager.kt` — 端到端加密
40. `audio/AudioSwitchHandler.kt` — 音频设备管理
41. `renderer/TextureViewRenderer.kt` — 视频渲染
42. `dagger/RTCModule.kt` 的 `audioModule` — 音频设备模块

---

## 八、关键常量速查（`RTCEngine.kt:1046` companion）

| 常量 | 值 | 含义 |
|---|---|---|
| `RELIABLE_DATA_CHANNEL_LABEL` | `_reliable` | 可靠数据通道标签 |
| `LOSSY_DATA_CHANNEL_LABEL` | `_lossy` | 尽力数据通道标签 |
| `MAX_DATA_PACKET_SIZE` | 64KB-1 | 单条数据消息上限 |
| `MAX_RECONNECT_RETRIES` | 30 | 重连最大次数 |
| `MAX_RECONNECT_TIMEOUT` | 60s | 重连总超时 |
| `MAX_ICE_CONNECT_TIMEOUT_MS` | 20s | 单次 ICE 连接超时 |
| `SIGNAL_CONNECT_TIMEOUT` | 10s (`SignalClient.kt:1026`) | 首次信令连接超时 |

---

## 九、读码常见疑问解答

**Q1: 为什么 `Room.connect` 里要用 `stateLock.withLock` + 双重检查？**
A: 防止用户快速点击两次 connect 导致并发。外层无锁快速检查（常见情况不阻塞），内层加锁再检查（防竞态）。C++ 里经典的 double-checked locking。

**Q2: `flowDelegate` 是什么？**
A: Kotlin 属性委托，给 `var` 加变化回调。`Room.state`、`RTCEngine.connectionState` 都用它。值改变时触发闭包，相当于 C++ 里 setter hook。见 `util/flowDelegate.kt`。

**Q3: `Either.Left` / `Either.Right` 是什么？**
A: SDK 自定义的"成功/失败"联合类型（`util/Either.kt`）。`Left` 通常是成功（带结果），`Right` 是失败（带错误信息）。相当于 C++ 的 `std::expected<T, E>` 或 Rust 的 `Result`。

**Q4: `withPeerConnection { ... }` 为什么是 suspend？**
A: 它内部 `launchRTCIfNotClosed` 会切到 RTC 线程执行，需要挂起当前协程等待结果。所有 `PeerConnection` 操作都通过它序列化到 RTC 线程。

**Q5: `runBlocking` 为什么在回调里出现（如 `onServerAnswer`）？**
A: `SignalClient.Listener` 的回调不是 suspend 函数，但内部需要查 PC 状态（suspend API），所以用 `runBlocking` 阻塞等待。只用于查询，不阻塞长任务。

**Q6: `negotiatePublisherMutex` 和 `offerLock` 有什么区别？**
A: `negotiatePublisherMutex`（RTCEngine 层）防止多次 `negotiatePublisher()` 调用并发；`offerLock`（PeerConnectionTransport 层）防止同一个 PC 上 `createAndSendOffer` 并发。两层串行化保证协商不冲突。

---

## 附：四条主线一句话总结

- **初始化**：`LiveKit.create` → Dagger 装配 8 Module（RTCModule 初始化 WebRTC）→ `roomFactory.create` 造 Room → `engine.listener = this` 接通回调。无网络活动。
- **信令**：`Room.connect` → `engine.join` → `SignalClient.connect`（WebSocket + protobuf）→ 等 `JoinResponse` → `onReadyForResponses` 开放后续消息处理。心跳保活。
- **媒体**：`configure` 创建双 PC（publisher 发/subscriber 收）+ 2 条 DataChannel → publisher 客户端发起协商（createOffer→sendOffer→onServerAnswer）→ subscriber 服务器发起（onServerOffer→createAnswer→sendAnswer）→ ICE candidate 互发（onTrickle）。
- **事件**：原生事件 → TransportObserver/SignalClient.Listener → `RTCEngine.Listener`（Room 实现）→ `BroadcastEventBus` → `Flow<RoomEvent>` → App `collect`。
