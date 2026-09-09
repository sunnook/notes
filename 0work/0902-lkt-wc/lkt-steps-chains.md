# LiveKit Android SDK — Publisher 侧连接建立 7 步调用链梳理

> 基于 `livekit-android-sdk` 源码（`src/main/java/io/livekit/android/`）。
> 路径约定：`room/` = `src/main/java/io/livekit/android/room/`，`util/` = `src/main/java/io/livekit/android/util/`。

## 0. 全局分层架构图（L1–L5）

```
┌──────────────────────────────────────────────────────────────────┐
│ L1 应用层   sample-app-basic/MainActivity.kt                      │ 你的代码
│             room.connect() / room.events.collect{}               │
├──────────────────────────────────────────────────────────────────┤
│ L2 房间层   Room.kt                                              │ 状态机+事件分发
│             State: DISCONNECTED→CONNECTING→CONNECTED→...         │ Facade，用户直接交互
├──────────────────────────────────────────────────────────────────┤
│ L3 引擎层   RTCEngine.kt                                         │ 编排信令+媒体
│             持有 publisher/subscriber 两条 PeerConnection        │
│             实现 SignalClient.Listener                           │
├───────────────────────┬──────────────────────────────────────────┤
│ L4a 信令通道           │ L4b 媒体通道                              │
│ SignalClient.kt       │ PeerConnectionTransport.kt               │
│ (WebSocket+protobuf)  │ (WebRTC PeerConnection)                  │
│                       │                                          │
│ ① 鉴权/进出房间        │ ① SRTP 音视频数据（RTP）                   │
│ ② SDP Offer/Answer    │ ② RTCP 反馈（QoS 闭环）★                  │
│    =媒体协商本身★       │    NACK / PLI / REMB / Transport-CC      │
│ ③ ICE candidate 交换   │ ③ 建立三步曲：                            │
│    =打洞信息交换★       │    STUN探测(打洞)→DTLS握手→SRTP传输       │
│    （注意：打洞信息交换   │    （打洞发生在这一侧！★）                 │
│      ≠打洞本身）        │                                          │
│ ④ 会中控制/参与者事件    │                                          │
├───────────────────────┴──────────────────────────────────────────┤
│ L5 基础设施  dagger/(DI)  webrtc/(原生封装)  audio/  e2ee/         │ 装配与底层能力
└──────────────────────────────────────────────────────────────────┘

★ = 与原版相比新增的精确化标注，也是接下来两个月的下钻入口
```

### 分层图与 7 步调用链的映射

| 步骤 | 所在层 | 走的通道 | 说明 |
|---|---|---|---|
| ① 信令连接建立 | L1→L2→L3→L4a | 信令（WS） | `MainActivity` → `Room.connect` → `RTCEngine.join` → `SignalClient.connect` |
| ② 创建 PeerConnection | L3→L4b | 媒体 | `RTCEngine.configure` → `pctFactory.create`（`negotiate` debounce 在此注册） |
| ③ 触发协商 | L3 | — | `negotiatePublisher()`，四个入口汇聚（见下） |
| ④ 生成并发送 offer | L3→L4b→L4a | 媒体→信令 | `createAndSendOffer`（L4b 生成 SDP）→ `onOffer` → `client.sendOffer`（L4a 发出） |
| ⑤ 接收 answer | L4a→L3→L4b | 信令→媒体 | `onServerAnswer` → `publisher.setRemoteDescription` |
| ⑥ ICE 协商 | L4a⇄L4b | 信令⇄媒体 | `onIceCandidate`（L4b 收集）→ `sendCandidate`（L4a 发出）；反向 `onTrickle` → `addIceCandidate` |
| ⑦ DTLS/SRTP | L4b→L5 | 媒体 | libwebrtc 原生（L5 `webrtc/` 封装），SDK 层只观察 `onConnectionChange` |

要点：**媒体协商的"内容"（SDP）在 L4b 生成/消费，但"交换"必须经 L4a 信令通道传输**——
这正是 L4a② 与 L4b 的分界：L4a 是协商消息的搬运工，L4b 是协商的执行者和媒体的实际承载者。
打洞信息（candidate）经 L4a 交换，但打洞本身（STUN 探测）发生在 L4b 的 PeerConnection 里。

---

## 0.1 negotiatePublisher() 是什么

`RTCEngine.negotiatePublisher()`（`room/RTCEngine.kt:716`）本身不直接创建 offer，而是调用
`publisher?.negotiate?.invoke(getPublisherOfferConstraints())`。

- `publisher` 是 `PeerConnectionTransport` 类型（`room/PeerConnectionTransport.kt`）。
- `negotiate` 是 `PeerConnectionTransport` 上的一个属性，在**构造时**通过
  `debounce<MediaConstraints?, Unit>(20, coroutineScope) { ... }`（`room/PeerConnectionTransport.kt:146`）
  注册的 20ms 防抖函数，内部调用 `createAndSendOffer()`。
- 它**不是** `LocalParticipant.kt:688` 里那个 `suspend fun negotiate()`。后者只负责把 track
  加入 PeerConnection（`engine.createSenderTransceiver`），加完后 WebRTC 自动触发
  `onRenegotiationNeeded()` → `engine.negotiatePublisher()`，间接走到前者。

### negotiate 协商的内容

协商内容是 **SDP（Session Description Protocol）**，即标准的 WebRTC 媒体协商：
编解码器、媒体轨道（audio/video）、码率、SSRC、RTP 扩展、ICE 参数等。

与 WHEP/WHIP 的对比：

| | WHEP/WHIP | LiveKit（本 SDK） |
|---|---|---|
| 协商内容 | SDP offer/answer | SDP offer/answer（相同） |
| 传输方式 | HTTP POST/PATCH | **WebSocket + Protobuf**（`SignalRequest`） |
| ICE 候选 | HTTP body / trickle | 同一条 WebSocket 用 `TrickleRequest` |

LiveKit 不是 WHEP/WHIP 的 HTTP request。SDP 被包进 `LivekitRtc.SignalRequest.setOffer(sd)`
protobuf 消息，通过 OkHttp WebSocket 发给服务器（`room/SignalClient.kt:422` `sendOffer()`）。

---

## 1. 总览：7 步流程

```
① 信令连接建立（WebSocket + JoinResponse）
② 创建 PeerConnection（publisher / subscriber 两个 transport）
③ 触发协商 negotiatePublisher()          ← 协商起点
④ createAndSendOffer()：生成 SDP offer 并通过 WS 发送
⑤ 接收服务器 answer → setRemoteDescription
⑥ ICE 协商（trickle candidate 双向交换，与 ④⑤ 并行交错）
⑦ DTLS/SRTP 握手 → 媒体真正开始传输
```

其中 ③④⑤ 是媒体协商核心；⑥ 是 ICE 协商；⑦ 由 WebRTC 原生栈自动完成，SDK 层只观察状态回调。

---

## 1.1 L1/L2 层补充调用链（应用层 → 房间层）

7 步调用链之上还有两层，补齐完整入口：

```
L1 应用层
sample-app-basic/src/main/java/io/livekit/android/sample/basic/MainActivity.kt
  ├─ room.events.collect { event -> ... }        Room.events（Flow，events/ 包 RoomEvent）
  │                                              MainActivity.kt:66
  └─ room.connect(url, token)                    MainActivity.kt:76

L2 房间层
Room.connect(url, token, options)                Room（Facade）           room/Room.kt:461
  ├─ state = State.CONNECTING                    Room.state（flowDelegate 状态机）
  │                                              room/Room.kt:239,476
  │    State 变化副作用：audioHandler.start() / communicationWorkaround.start()
  │                                              room/Room.kt:242-245
  └─ engine.join(connectUrl, token, options, roomOptions)
                                                 ↓ 进入 L3（即第 ① 步）
```

- **Room.State 状态机**（`room/Room.kt:187`）：`DISCONNECTED → CONNECTING → CONNECTED →
  RECONNECTING → DISCONNECTED`，通过 `flowDelegate` 暴露为 Flow，应用层可直接订阅。
- **事件分发**：`Room.events`（`io.livekit.android.events` 包，`RoomEvent`/`ParticipantEvent`
  sealed 类）由 L3 `RTCEngine.Listener` 回调 → L2 转换成事件 → L1 collect 消费。
- **初始化位置**：`Room` 由 `LiveKit.connect()`（`LiveKit.kt`）创建，内部经 `dagger/`（DI）
  装配 `RTCEngine`、`SignalClient`、`PeerConnectionTransport.Factory`、`audioHandler` 等。

---

## 2. 各步骤调用链（函数/操作 · 类/接口 · 文件/库 · 初始化位置）

### ① 信令连接建立

```
Room.connect(url, token)                              Room                     room/Room.kt:461
  └─ engine.join(connectUrl, token, options, roomOptions)   RTCEngine                room/RTCEngine.kt:235
       └─ joinImpl(...)                               RTCEngine                room/RTCEngine.kt:250
            └─ client.join(url, token, options, roomOptions)  SignalClient              room/SignalClient.kt:131
                 └─ connect(...)                      SignalClient（私有）      room/SignalClient.kt:167
                      ├─ Request.Builder().url(wsUrl).addHeader("Authorization", "Bearer $token")
                      │                                okhttp3.Request           okhttp3（OkHttp 库）
                      └─ websocketFactory.newWebSocket(request, this)  WebSocket.Factory      okhttp3（OkHttp 库）
                           └─ onMessage(ws, bytes)    SignalClient（WebSocketListener 回调） room/SignalClient.kt:305
                                └─ 解析出 JoinResponse，resume joinContinuation
```

- **库**：OkHttp `okhttp3.WebSocket` / `WebSocketListener`；protobuf 消息 `livekit.LivekitRtc.*`。
- **初始化位置**：
  - `Room` 由 `LiveKit.connect()`（`io.livekit.android.LiveKit`）创建，内部通过 Hilt/Dagger 注入
    `RTCEngine`、`SignalClient` 等。
  - `SignalClient` 的 `okHttpClient: OkHttpClient` 与 `websocketFactory: WebSocket.Factory`
    为构造注入（`room/SignalClient.kt:80`），由 `LiveKit` 工厂配置。
- **结果**：服务器返回 `JoinResponse`（含 `subscriberPrimary`、`fastPublish` 等标志），
  `joinImpl` 中触发 `listener?.onJoinResponse(joinResponse)`（`room/RTCEngine.kt:262`）。

### ② 创建 PeerConnection

```
RTCEngine.joinImpl
  └─ configure(joinResponse, options)                 RTCEngine（私有）         room/RTCEngine.kt:279
       └─ publisher = pctFactory.create(rtcConfig, publisherObserver, publisherObserver)
                                                     PeerConnectionTransport.Factory（@AssistedFactory）
                                                                              room/PeerConnectionTransport.kt:389-396
            └─ PeerConnectionTransport 构造函数中：
                 connectionFactory.createPeerConnection(config, pcObserver)
                                                     PeerConnectionFactory   webrtc（libwebrtc Android SDK）
                                                                              room/PeerConnectionTransport.kt:85
                 val negotiate = debounce<MediaConstraints?, Unit>(20, coroutineScope) { ... }
                                                     debounce()                util/CoroutineUtil.kt:31
                                                                              room/PeerConnectionTransport.kt:146
       └─ subscriber = pctFactory.create(rtcConfig, subscriberObserver, null)
                                                     同上                      room/RTCEngine.kt:306
```

- **类/接口**：
  - `PeerConnectionTransport`（`room/PeerConnectionTransport.kt`）— 对原生 `PeerConnection` 的封装，
    持有 `negotiate`（debounce 函数）、`createAndSendOffer()`、`setRemoteDescription()`、`addIceCandidate()`。
  - `PeerConnectionTransport.Factory`（`@AssistedFactory`，`room/PeerConnectionTransport.kt:390`）— Hilt 生成实现。
  - `PublisherTransportObserver`（`room/PublisherTransportObserver.kt:35`）— 同时实现
    `PeerConnection.Observer` 与 `PeerConnectionTransport.Listener`，作为 publisher PC 的观察者。
  - `SubscriberTransportObserver`（`room/SubscriberTransportObserver.kt:38`）— subscriber PC 的观察者。
- **初始化位置**：
  - `pctFactory` 在 `RTCEngine` 构造时注入（`room/RTCEngine.kt:117`）。
  - `publisherObserver` / `subscriberObserver` 为 `RTCEngine` 的成员，构造时初始化
    （`room/RTCEngine.kt:184`）。
  - `publisher` / `subscriber` 变量声明：`room/RTCEngine.kt:187`，在 `configure()` 中赋值
    （`room/RTCEngine.kt:300,306`）。
  - **`negotiate` debounce 函数在此刻（`PeerConnectionTransport` 构造时）注册**。

### ③ 触发协商 negotiatePublisher()

四个触发入口汇聚到同一函数：

```
入口 A（join 时主动）：
RTCEngine.joinImpl
  └─ if (!isSubscriberPrimary || joinResponse.fastPublish) { negotiatePublisher() }
                                                     RTCEngine                room/RTCEngine.kt:271-273

入口 B（重连后）：
RTCEngine.reconnect 内部循环
  └─ if (hasPublished) { negotiatePublisher() }      RTCEngine                room/RTCEngine.kt:638-640

入口 C（WebRTC 自动触发）：
PublisherTransportObserver.onRenegotiationNeeded()   PublisherTransportObserver
                                                                              room/PublisherTransportObserver.kt:56-60
  └─ engine.negotiatePublisher()                     RTCEngine

入口 D（重新发布 simulcast track）：
LocalParticipant（publish 流程）
  └─ engine.negotiatePublisher()                      RTCEngine                room/participant/LocalParticipant.kt:1253
```

`negotiatePublisher()` 本体：

```
RTCEngine.negotiatePublisher()                        RTCEngine                room/RTCEngine.kt:716
  ├─ hasPublished = true                              （标记，供重连时判断是否需要重协商）
  ├─ if (!client.isConnected) return                  SignalClient.isConnected
  └─ coroutineScope.launch {
       negotiatePublisherMutex.withLock {             Mutex（kotlinx.coroutines）
         publisher?.negotiate?.invoke(getPublisherOfferConstraints())
       }                                              PeerConnectionTransport.negotiate（debounce 函数）
     }
```

- **初始化位置**：`negotiatePublisherMutex`（`room/RTCEngine.kt:229`）；`negotiate` debounce
  （`room/PeerConnectionTransport.kt:146`，见 ②）。
- **注意**：`LocalParticipant.kt:688` 的 `suspend fun negotiate()` 是**另一个东西**——它只把
  track 加入 PC（`engine.createSenderTransceiver`，`room/RTCEngine.kt:424`），完成后靠 WebRTC
  的 `onRenegotiationNeeded` 回调间接触发本步骤。

### ④ createAndSendOffer()：生成并发送 offer

```
publisher.negotiate.invoke(constraints)               debounce 函数（20ms 防抖）  room/PeerConnectionTransport.kt:146
  └─（delay 20ms 后）
     createAndSendOffer(constraints)                  PeerConnectionTransport（私有） room/PeerConnectionTransport.kt:155
       ├─ offerLock.withLock { }                      Mutex（kotlinx.coroutines）
       ├─ launchRTCIfNotClosed {
       │    ├─ 若 signalingState == HAVE_LOCAL_OFFER：置 renegotiate = true 并返回
       │    │    （等 answer 到来后在 setRemoteDescription 中补发，见 ⑤）
       │    ├─ offerId = latestOfferId.incrementAndGet()   AtomicInteger
       │    ├─ peerConnection.createOffer(constraints)  PeerConnection        webrtc（libwebrtc）
       │    ├─ SDP munge：sdpFactory.createSessionDescription(...)
       │    │    ├─ ensureVideoDDExtensionForSVC(mediaDesc)  （SVC/AV1 dependency-descriptor 扩展）
       │    │    └─ ensureCodecBitrates(mediaDesc, trackBitrates)
       │    ├─ setMungedSdp(sdpOffer, ...) → peerConnection.setLocalDescription(mungedSdp)
       │    └─ listener.onOffer(sdp, offerId)          PeerConnectionTransport.Listener 回调
       │                                              room/PeerConnectionTransport.kt:101-103
       │ }
       └─ PublisherTransportObserver.onOffer(sd, offerId)
            └─ client.sendOffer(sd, offerId)          SignalClient              room/SignalClient.kt:422
                 ├─ offer.toProtoSessionDescription(offerId)   （SDP → protobuf）
                 └─ LivekitRtc.SignalRequest.newBuilder().setOffer(sd).build()
                      └─ sendRequest(request)          （WebSocket 发送，OkHttp）
```

- **库**：`livekit.org.webrtc.PeerConnection`（libwebrtc Android SDK）；`livekit.LivekitRtc`
  （LiveKit protobuf 定义，`livekit_rtc.proto`）。
- **初始化位置**：`offerLock`、`latestOfferId`、`renegotiate` 均为 `PeerConnectionTransport`
  成员（`room/PeerConnectionTransport.kt:94,99,154`）；`sdpFactory`、`trackBitrates` 同文件。

### ⑤ 接收服务器 answer → setRemoteDescription

```
服务器通过 WebSocket 下发 SignalResponse.setAnswer
  └─ SignalClient.onMessage(ws, bytes)                SignalClient（WebSocketListener）room/SignalClient.kt:305
       └─ 解析 SignalResponse → listener.onServerAnswer(sd, offerId)
            SignalClient.Listener 接口（room/SignalClient.kt 内定义）
  └─ RTCEngine.onServerAnswer(sessionDescription, offerId)   RTCEngine（实现 SignalClient.Listener）
                                                                              room/RTCEngine.kt:1088
       └─ publisher?.setRemoteDescription(sd, offerId)  PeerConnectionTransport   room/PeerConnectionTransport.kt:121
            ├─（offerId 过期检查：currentOfferId > offerId 则丢弃）
            ├─ peerConnection.setRemoteDescription(sd)   webrtc（libwebrtc）
            ├─ pendingCandidates.forEach { addIceCandidate(it) }   （补发 ⑥ 中缓存的候选）
            └─ if (renegotiate) { renegotiate = false; createAndSendOffer() }   （补发 ④ 中被挂起的协商）
```

- **初始化位置**：`RTCEngine` 实现 `SignalClient.Listener` 并在构造/连接时把自己注册为
  `client` 的 listener（`room/RTCEngine.kt` 中 `client` 成员 + listener 绑定）。
- subscriber 侧对称流程：`RTCEngine.onServerOffer()`（`room/RTCEngine.kt:1103`）→
  `subscriber.setRemoteDescription` → `createAnswer` → `setLocalDescription` →
  `client.sendAnswer(answer, offerId)`（`room/SignalClient.kt:431`）。

### ⑥ ICE 协商（trickle，与 ④⑤ 并行交错）

```
本地候选（上行）：
PeerConnectionTransport.peerConnection 收集到候选
  └─ PublisherTransportObserver.onIceCandidate(candidate)   PeerConnection.Observer 回调
                                                                              room/PublisherTransportObserver.kt:48
       └─ client.sendCandidate(candidate, target = PUBLISHER)  SignalClient    room/SignalClient.kt:440
            └─ LivekitRtc.TrickleRequest（candidateInit = JSON 编码的 IceCandidateJSON）
                 └─ sendRequest(...)                  （WebSocket）

远端候选（下行）：
SignalClient.onMessage → listener.onTrickle(candidate, target)   SignalClient.Listener
  └─ RTCEngine.onTrickle(candidate, target)          RTCEngine                room/RTCEngine.kt:1152
       ├─ target == PUBLISHER → publisher?.addIceCandidate(candidate)
       │                     PeerConnectionTransport.addIceCandidate   room/PeerConnectionTransport.kt:105
       │                       （若 remoteDescription 尚未设置或正在 ICE restart，
       │                         先存入 pendingCandidates 缓存，待 ⑤ 完成后补发）
       └─ target == SUBSCRIBER → subscriber?.addIceCandidate(candidate)
```

- **库**：`livekit.org.webrtc.IceCandidate`（libwebrtc）；`kotlinx.serialization` 用于
  `IceCandidateJSON` 编码。
- **初始化位置**：`pendingCandidates` 为 `PeerConnectionTransport` 成员
  （`room/PeerConnectionTransport.kt:91`）；`PublisherTransportObserver` 在 `RTCEngine`
  构造时创建（`room/RTCEngine.kt:184`）。

### ⑦ DTLS/SRTP 握手 → 媒体传输

这一步由 libwebrtc 原生栈在 ICE 连通性检查通过后自动完成，SDK 层只观察状态回调：

```
PublisherTransportObserver.onConnectionChange(newState)  PeerConnectionStateObservable
                                                     room/PublisherTransportObserver.kt（实现接口）
  └─ connectionState 更新（FlowObservable，供上层订阅）
RTCEngine.configure 中注册的 connectionStateListener: PeerConnectionStateListener
                                                     room/RTCEngine.kt:312-319
  └─ ConnectionState.CONNECTED / DISCONNECTED 更新
RTCEngine.ensurePublisherConnected(kind)              RTCEngine（dataChannel 发送前确保 publisher PC 已连通）
  └─ publisher?.isConnected() 检查 / 等待
```

- **库**：DTLS/SRTP 全部在 libwebrtc 原生层（`livekit.org.webrtc.*`），无 SDK 层显式调用。
- **初始化位置**：`PeerConnectionStateObservable` 接口 + `flowDelegate` 委托
  （`io.livekit.android.util`）；`connectionStateListener` 在 `configure()` 中注册
  （`room/RTCEngine.kt:312`）。

---

## 3. 关键类/接口一览表

| 类/接口 | 文件 | 角色 |
|---|---|---|
| `Room` | `room/Room.kt` | 面向用户的房间门面，持有 `RTCEngine` 与 `LocalParticipant` |
| `RTCEngine` | `room/RTCEngine.kt` | 核心引擎：join/reconnect、持有 publisher/subscriber transport、实现 `SignalClient.Listener` |
| `SignalClient` | `room/SignalClient.kt` | WebSocket 信令客户端（OkHttp），收发 protobuf `SignalRequest`/`SignalResponse` |
| `PeerConnectionTransport` | `room/PeerConnectionTransport.kt` | 对原生 `PeerConnection` 的封装；`negotiate` debounce、`createAndSendOffer`、`setRemoteDescription`、`addIceCandidate` |
| `PeerConnectionTransport.Factory` | `room/PeerConnectionTransport.kt:389` | `@AssistedFactory`（Hilt 生成实现） |
| `PublisherTransportObserver` | `room/PublisherTransportObserver.kt` | publisher PC 的 `PeerConnection.Observer` + `PeerConnectionTransport.Listener` |
| `SubscriberTransportObserver` | `room/SubscriberTransportObserver.kt` | subscriber PC 的观察者 |
| `SignalClient.Listener` | `room/SignalClient.kt` 内定义 | 信令事件回调接口（`onServerAnswer`、`onTrickle` 等） |
| `RTCEngine.Listener` | `room/RTCEngine.kt:1015` | 引擎事件回调接口（`onJoinResponse`、`onSignalConnected` 等） |
| `debounce<T, R>()` | `util/CoroutineUtil.kt:31` | 协程防抖工具，`negotiate` 即由它生成 |
| `PeerConnection` / `PeerConnectionFactory` | webrtc 库（`livekit.org.webrtc`） | libwebrtc 原生 WebRTC 栈 |
| `WebSocket` / `WebSocketListener` | OkHttp 库（`okhttp3`） | 信令传输通道 |
| `LivekitRtc.*` | LiveKit protobuf | 信令协议消息定义（offer/answer/trickle/join 等） |

## 4. 关键初始化位置汇总

| 对象 | 初始化位置 | 说明 |
|---|---|---|
| `SignalClient.okHttpClient` / `websocketFactory` | `room/SignalClient.kt:80`（构造注入） | 由 `LiveKit` 工厂/Hilt 配置 |
| `RTCEngine.pctFactory` | `room/RTCEngine.kt:117`（构造注入） | `PeerConnectionTransport.Factory` |
| `RTCEngine.publisherObserver` / `subscriberObserver` | `room/RTCEngine.kt:184` 附近（成员初始化） | PC 观察者 |
| `RTCEngine.publisher` / `subscriber` | `room/RTCEngine.kt:187`（声明）→ `:300,306`（`configure()` 中赋值） | transport 实例 |
| `PeerConnectionTransport.peerConnection` | `room/PeerConnectionTransport.kt:85`（构造时创建） | 原生 PC |
| **`PeerConnectionTransport.negotiate`（debounce）** | `room/PeerConnectionTransport.kt:146`（构造时注册） | **`negotiatePublisher()` 最终调用的就是它** |
| `RTCEngine.negotiatePublisherMutex` | `room/RTCEngine.kt:229` | 协商互斥锁 |
| `PeerConnectionTransport.pendingCandidates` | `room/PeerConnectionTransport.kt:91` | ICE 候选缓存 |
| `RTCEngine.connectionStateListener` | `room/RTCEngine.kt:312`（`configure()` 中注册） | PC 连接状态监听 |

## 5. 一图流（publisher 侧完整链，含分层标注）

```
[L1] MainActivity: room.connect / room.events.collect
        │
[L2] Room.connect ── state=CONNECTING ── audioHandler.start()
        │
[L3] RTCEngine.join ──①──> [L4a] SignalClient.connect ──OkHttp WS──> 服务器
                              │ JoinResponse
                              ▼
        RTCEngine.configure ──②──> [L4b] pctFactory.create ×2 (publisher/subscriber)
                              │    （PeerConnectionTransport 构造：negotiate debounce 在此注册）
                              ▼
        negotiatePublisher() ──③──> publisher.negotiate (debounce 20ms)
                              ▼
        createAndSendOffer() ──④──> [L4b] PC.createOffer → munge SDP → setLocalDescription
                              │       → onOffer → [L4a] client.sendOffer (WS)
                              ▼
        onServerAnswer ──────⑤──> [L4b] publisher.setRemoteDescription
                              │       （补发 pendingCandidates；若 renegotiate 则回到 ④）
                              ▼
        onIceCandidate ⇄────⑥──> [L4a] sendCandidate / [L4b] addIceCandidate (trickle, 双向)
                              │    （candidate 经信令通道交换；STUN 探测/打洞在 [L4b] PC 内执行）
                              ▼
        [L5] libwebrtc 原生 ──⑦──> ICE 连通检查 → DTLS/SRTP → 媒体开始传输
                              （[L4b] onConnectionChange → [L3] ConnectionState.CONNECTED
                                → [L2] Room.State.CONNECTED → [L1] 事件/Flow 通知）
```

原版
```
Room.connect
└─ RTCEngine.join ──①──> SignalClient.connect ──OkHttp WS──> 服务器
│ JoinResponse
▼
RTCEngine.configure ──②──> pctFactory.create ×2 (publisher/subscriber)
│ （PeerConnectionTransport 构造：negotiate debounce 在此注册）
▼
negotiatePublisher() ──③──> publisher.negotiate (debounce 20ms)
▼
createAndSendOffer() ──④──> PC.createOffer → munge SDP → setLocalDescription
│ → onOffer → client.sendOffer (WS)
▼
onServerAnswer ──────⑤──> publisher.setRemoteDescription
│ （补发 pendingCandidates；若 renegotiate 则回到 ④）
▼
onIceCandidate ⇄────⑥──> sendCandidate / addIceCandidate (trickle, 双向)
▼
libwebrtc 原生 ──────⑦──> ICE 连通检查 → DTLS/SRTP → 媒体开始传输
（onConnectionChange → ConnectionState.CONNECTED）
```


---

## 6. 三个下钻主题（RTCP 反馈闭环 / ICE restart / subscriber 侧协商）

### 6.1 RTCP 反馈闭环（QoS 闭环）★

**作用**：丢包恢复（NACK）、关键帧请求（PLI）、带宽估计与码率自适应（REMB/Transport-CC）。
RTCP 是 RTP 的姊妹协议，在**同一对端口上反向传输**，构成"发送方 ↔ 接收方"的质量闭环——
不需要经过信令通道。

**本 SDK 的实现位置**：RTCP 包的收发解析**全部在 libwebrtc 原生层**（L5），SDK 层不出现
`NACK/PLI/REMB` 等显式代码。SDK 层的控制点是**参数配置**，闭环生效路径：

```
SDK 层配置（协商时写入 SDP / sender parameters）：
LocalParticipant.publish 流程
  ├─ rtpParameters.degradationPreference = finalOptions.degradationPreference
  │      LocalParticipant.kt:735-737
  │      （带宽不足时：偏降帧率 还是 偏降分辨率 —— 喂给 REMB/Transport-CC 的决策）
  ├─ encodings[].maxBitrateBps（simulcast 各层码率上限）
  │      LocalParticipant.kt:719-724
  └─ SDP munge：ensureCodecBitrates()（把 codec 码率写进 offer）
         PeerConnectionTransport.kt:217

闭环执行（L5 libwebrtc 原生，无 SDK 代码）：
接收端 ──RTCP NACK──> 发送端重传
接收端 ──RTCP PLI──>  发送端发关键帧（IDR）
接收端 ──RTCP REMB/Transport-CC──> 发送端 GCC/BWE 降码率或降层（simulcast 切层）
```

**下钻入口**：`webrtc/SimulcastVideoEncoderFactoryWrapper.kt`（simulcast 编码）、
`webrtc/CustomVideoEncoderFactory.kt`、`RTCEngine.createStatsGetter()`（
`RTCStatsExt.kt` 里有 RTCP 统计扩展，可观测闭环效果）。

### 6.2 ICE restart

**作用**：网络切换（WiFi↔蜂窝）或连接劣化时，**不重建 PeerConnection**、不重新走完整
媒体协商，仅重新收集 ICE candidate 并更新 SDP 中的 ice-ufrag/pwd，实现快速恢复媒体通路。
比 full reconnect（销毁重建 PC）轻量得多。

**调用链**：

```
触发条件（三处）：
A. 重连场景（信号断开重连 / resume）
   RTCEngine.getPublisherOfferConstraints()
     └─ if (connectionState == RECONNECTING || RESUMING) { constraints += ICE_RESTART: TRUE }
          RTCEngine.kt:931-938
   → 走第 ③④ 步正常协商，只是 offer 带上了 IceRestart 约束

B. full reconnect 标志
   fullReconnectOnNext = true                              RTCEngine.kt:164,1242
     → reconnect(forceFullReconnect)                       RTCEngine.kt:536-537
       （此时直接销毁重建 PC，走完整 ①② 流程，不属于 ICE restart）

C. 网络变化
   NetworkCallbackManager（room/network/）监听系统网络事件
     → 触发 engine 重连/协商

执行（PeerConnectionTransport）：
createAndSendOffer(constraints)                           PeerConnectionTransport.kt:155
  ├─ constraints.findConstraint(ICE_RESTART) == TRUE       :166-167
  ├─ restartingIce = true                                 :170
  │    （作用：addIceCandidate() 期间远端候选先缓存在 pendingCandidates，
  │      待 setRemoteDescription 完成后补发               :105-112）
  ├─ 若 signalingState == HAVE_LOCAL_OFFER 且 iceRestart：
  │    peerConnection.setRemoteDescription(curSd)（强制覆盖未完成的 offer）  :177-180
  └─ peerConnection.createOffer(带 IceRestart 约束)
       → libwebrtc 重新收集 candidate、生成新 ice-ufrag → 走 ④⑤⑥
```

**关键状态**：`restartingIce`（`PeerConnectionTransport.kt:92`）、
`MediaConstraintKeys.ICE_RESTART = "IceRestart"`（`room/util/MediaConstraintKeys.kt:24`）。

### 6.3 Subscriber 侧协商（服务器驱动）

**作用**：接收远端媒体。与 publisher 侧（客户端发起 offer）**方向相反**——
subscriber 模式下由**服务器主动发 offer**，客户端被动应答。服务器在新参与者发布
track、订阅变化、simulcast 层变化时都会重新下发 offer 触发重协商。

**调用链**：

```
服务器 ──WS──> SignalResponse.setOffer
  └─ SignalClient.onMessage → listener.onServerOffer(sd, offerId)     SignalClient.Listener
  └─ RTCEngine.onServerOffer(sessionDescription, offerId)              RTCEngine.kt:1103
       ├─ subscriber?.setRemoteDescription(sd, offerId)               （对端 offer 落地）
       ├─ subscriber?.withPeerConnection { createAnswer(MediaConstraints()) }
       ├─ subscriber?.withPeerConnection { setLocalDescription(answer) }
       └─ client.sendAnswer(answer, offerId)                           SignalClient.kt:431
            └─ SignalRequest.setAnswer → WS 发回服务器

订阅数据处理：
SubscriberTransportObserver.onAddTrack / onAddStream                   SubscriberTransportObserver.kt
  └─ RemoteTrackPublication / RemoteParticipant 事件 → Room.events → L1

注意：
- SubscriberTransportObserver.onRenegotiationNeeded() 是空实现（:117）——
  subscriber 侧协商永远由服务器发起，客户端不主动。
- subscriberPrimary 模式下（JoinResponse.subscriberPrimary == true），
  join 时第 ③ 步被跳过（RTCEngine.kt:271 的条件不满足），publisher 协商
  推迟到真正发布 track 时（onRenegotiationNeeded 或 fastPublish）才触发。
- ICE restart 对 subscriber 同样适用：服务器重启 ICE 时会带新 offer 下发，
  客户端 answer 流程不变。
```

### 6.4 三主题对照表

| 主题 | 发起方 | 通道 | SDK 层可见代码 | libwebrtc 原生 |
|---|---|---|---|---|
| RTCP 反馈闭环 | 接收端自动 | 媒体通道（RTP 同端口反向） | 仅参数配置（degradationPreference/maxBitrate） | NACK/PLI/REMB/Transport-CC 全部 |
| ICE restart | 客户端（publisher）/服务器（subscriber） | 信令（SDP 内嵌新 ice-ufrag） | `ICE_RESTART` 约束 + `restartingIce` 状态 | candidate 重新收集/连通性检查 |
| subscriber 侧协商 | **服务器**（offer） | 信令（WS） | `onServerOffer` → `sendAnswer` | createAnswer/setLocalDescription |

---

## 7. WebRTC 原生层内部调用链（对应 7 步 + QoS 闭环）

> 版本基准：LiveKit SDK 依赖 `io.github.webrtc-sdk:android-prefixed:144.7559.09`（M144）。
> 本地参考树：`~/codes/adrtc/webrtc/webrtc_vs2022_based_windows_10/rtc/rtcsource/src`（M100+，主参考，
> 与 M144 架构一致）；`~/codes/adrtc/webrtc/webRTC`（~M85–M95，补其缺失的 `video/` 适配管线）。
> 下文路径以 vs2022 树为根（`<root>`），标注 `〔old〕` 的用老树路径。

### 7.1 版本判定依据（两棵树怎么选）

| 特征 | 老树 webRTC | 新树 vs2022 |
|---|---|---|
| JSEP 处理 | 内联 `pc/peer_connection.cc` + `pc/jsep_session_description.cc` | 独立 `pc/sdp_offer_answer.cc`（M100 拆出）✅ 贴近 M144 |
| Pacing | `modules/pacing/paced_sender.cc` | `task_queue_paced_sender.cc`（M96+）✅ |
| Adaptation | `call/adaptation/` | `api/adaptation/resource.cc`（M100+ resource 模型）✅ |
| DataChannel SCTP | `media/sctp/` | `net/dcsctp/`（M96+ 迁出）✅ |
| NACK 模块 | nack_module | `modules/video_coding/nack_requester.cc` ✅ |
| `video/` 目录 | ✅ 完整（VideoStreamEncoder） | ❌ 缺失（仅 `call/rtp_video_sender.cc`） |

**主参考 = vs2022 树；`video/`（编码器适配）读老树。**

### 7.2 JNI 边界

Android SDK 调原生栈的唯一入口（`sdk/android/src/jni/`）：
`peer_connection_factory.cc`（工厂）、`peer_connection.cc`（CreateOffer/SetLocal/SetRemote）、
`rtp_sender.cc`/`rtp_transceiver.cc`（SetParameters → degradationPreference 在此过 JNI）。

### 7.3 七步对应的原生内部链

**② 创建 PeerConnection**
```
PeerConnectionFactory::CreatePeerConnection            pc/peer_connection_factory.cc
  └─ PeerConnection::Create                           pc/peer_connection.cc
       ├─ SdpOfferAnswerHandler                        pc/sdp_offer_answer.cc（JSEP 状态机）
       ├─ RtpTransmissionManager                       pc/rtp_transmission_manager.cc（transceiver 管理）
       ├─ JsepTransportController                      pc/jsep_transport_controller.cc（传输编排核心）
       └─ stats/observer 注册
```

**④ CreateOffer + SetLocalDescription**
```
PeerConnection::CreateOffer                           pc/peer_connection.cc
  └─ SdpOfferAnswerHandler::CreateOffer                pc/sdp_offer_answer.cc
       └─ MediaSessionDescriptionFactory::CreateOffer  pc/media_session.cc（新树名）/〔old〕同文件
            ├─ MediaEngine 枚举编解码器/RTP 扩展       media/engine/webrtc_{video,voice}_engine.cc
            └─ 生成 cricket::SessionDescription        pc/session_description.cc
SetLocalDescription → ApplyLocalDescription → JsepTransportController::SetLocalDescription
       └─ 按 BUNDLE 分组建立 JsepTransport              pc/jsep_transport.cc
```

**⑤ SetRemoteDescription（answer）**
```
SdpOfferAnswerHandler::SetRemoteDescription → ApplyRemoteDescription
  ├─ JsepTransportController::SetRemoteDescription（配置远端 ufrag/证书指纹）
  └─ MediaChannel 按 m-line 配置（视频：WebRtcVideoChannel  media/engine/webrtc_video_engine.cc）
       └─ 在 Call 中创建 VideoSendStream/VideoReceiveStream   call/call.cc
```

**⑥ ICE（收集 + 连通性检查 + restart）**
```
收集：BasicPortAllocator                              p2p/client/basic_port_allocator.cc
  └─ AllocatableSession → UDPPort/StunPort/RelayPort  p2p/base/*.cc
       └─ candidate 上抛 IceTransportInternal → PeerConnection::OnIceCandidate → JNI → SDK ⑥
连通：BasicIceController                              p2p/base/basic_ice_controller.cc
  └─ 选 candidate pair → STUN binding request        p2p/base/stun_request.cc
       └─ nominate → ICE writable → 触发 DTLS ⑦
restart：offer 带 IceRestart（新 ufrag）
  → JsepTransportController 重新 MaybeStartGathering（回到"收集"分支）
```

**⑦ DTLS/SRTP**
```
DtlsTransport                                         p2p/base/dtls_transport.cc
  └─ rtc::SSLStreamAdapter（DTLS1.2 握手）             rtc_base/openssl_stream_adapter.cc
       └─ DtlsSrtpTransport 协商 SRTP 密钥            pc/dtls_srtp_transport.cc
            └─ SrtpTransport（libsrtp 加解密 RTP/RTCP） pc/srtp_transport.cc
媒体通路：RtpTransport → MediaChannel → Call → 网络收发
```

**① 不涉及原生栈**（纯 OkHttp WS），仅 PC 工厂初始化发生在 LiveKit L5 `PeerConnectionFactoryManager`。

### 7.4 QoS 闭环（专业主干）

闭环 = **反馈信号（RTCP）→ 带宽估计（GCC）→ 码率分配 → 编码适配 → 发送整形**，五段串联：

```
【接收端反馈生成】（LiveKit 作为 subscriber 收流时；或服务器对 publisher 做的相同动作）
RtpRtcp 模块                                       modules/rtp_rtcp/source/rtp_rtcp_impl.cc
  ├─ 丢包检测：NackRequester（缺号→NACK）          modules/video_coding/nack_requester.cc
  ├─ 关键帧请求：FrameBuffer 解不出 → PLI          modules/video_coding/frame_buffer2.cc
  ├─ 带宽反馈：RemoteEstimatorProxy（Transport-CC） modules/rtp_rtcp/source/remote_estimator_proxy.cc
  │               RemoteBitrateEstimator（REMB）    modules/remote_bitrate_estimator/
  └─ 以上经 RtcpSender 打包发回对端               modules/rtp_rtcp/source/rtcp_sender.cc

【发送端处理】（publisher 侧；LiveKit 作为 publisher 时就在本机）
RtcpReceiver 解析对端反馈                          modules/rtp_rtcp/source/rtcp_receiver.cc
  ├─ NACK → RtpPacketHistory 重发（RTX）           modules/rtp_rtcp/source/packet_sequencer.cc 等
  ├─ PLI/FIR → 通知 VideoStreamEncoder 立即出关键帧  video_stream_encoder〔old 树〕
  └─ TransportFeedback/ReceiverReport → 上交 GCC

【GCC 带宽估计】
RtpTransportControllerSend                          call/rtp_transport_controller_send.cc
  └─ GoogCcNetworkController                       modules/congestion_controller/goog_cc/goog_cc_network_controller.cc
       ├─ 时延梯度：TrendlineEstimator（趋势线滤波）  .../trendline_estimator.cc
       ├─ 丢包率：LossBasedBwe                       .../loss_based_bandwidth_estimation.cc
       └─ AimdRateControl（和式增/乘式减）           .../aimd_rate_control.cc
            → 目标码率

【码率分配】
BitrateAllocator（按优先级分给音/视频流）           call/bitrate_allocator.cc
  └─ RtpVideoSender::OnBitrateUpdated              call/rtp_video_sender.cc（simulcast 层码率）

【编码适配】（QoS 的最终执行者）
VideoStreamEncoder                                 video/video_stream_encoder.cc〔old 树〕
  ├─ 按 DegradationPreference 决定降什么：
  │    maintain-framerate → 降分辨率；maintain-resolution → 降帧率；balanced → 都降
  ├─ ResourceAdaptationProcessor（CPU/带宽资源过载时）  api/adaptation/resource.cc
  └─ 通知 VideoEncoder 重配（分辨率/fps/码率/QP）

【发送整形】
TaskQueuePacedSender（漏桶平滑，防突发）           modules/pacing/task_queue_paced_sender.cc
```

### 7.5 LiveKit SDK ↔ 原生 QoS 的接驳点（闭环中唯一能被 SDK 控制的地方）

| SDK 层位置 | 原生落点 | 作用 |
|---|---|---|
| `degradationPreference`（`LocalParticipant.kt:735-737`，经 `rtp_sender.cc` JNI） | `VideoStreamEncoder` 的降级偏好 | 决定带宽不足时降帧率还是降分辨率 |
| `encodings[].maxBitrateBps`（simulcast 层配置，`LocalParticipant.kt:719-724`） | `RtpSender::SetParameters` → `VideoSendStream` 层码率上限 | 各 simulcast 层上限，服务器按订阅者带宽选层 |
| `ensureCodecBitrates()` SDP munge（`PeerConnectionTransport.kt:217`） | offer 中的 codec 码率 | 影响协商出的编码能力集 |
| `createStatsGetter()`（`RTCEngine`，`RTCStatsExt.kt`） | `getStats()` → RTCP 统计 | 观测闭环效果（丢包率/RTT/码率），不做控制 |

**核心结论**：
NACK/PLI/REMB/Transport-CC/GCC/适配的**决策与执行全部在原生层自动运行**，
SDK 不参与也不应参与；SDK 的角色是**在协商时把参数（degradationPreference、层码率）写进
原生配置，然后用 getStats 观测**。
QoS 下钻路线：
`rtcp_receiver.cc` 
→ `goog_cc_network_controller.cc`
→ `bitrate_allocator.cc` 
→ `video_stream_encoder.cc`〔老树〕
→ `task_queue_paced_sender.cc`。
