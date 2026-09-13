# LiveKit 工程补充文档（lkt-wrt-append）

> 针对 `lkt-chain.md` / `lkt-qos-framework.md` 的 7 条覆盖缺口，逐条补充。调用链到类级（含 JNI 桥接 `**[JNI]**`），文件路径准确。
> 执行计划见 `lkt-wrt-append-plan.md`。

---

## 1. LiveKit 应用层 API（事件 / Participant / TrackPublication 状态机）

> 此章节面向**应用开发者**：如何使用 LiveKit 的事件、参与者与轨道发布状态。底层调用链见 `lkt-chain.md`。

### 1.1 事件总线机制（BroadcastEventBus）

LiveKit 的事件系统基于 **Kotlin Flow**（`MutableSharedFlow`），非回调监听器。

- `events/BroadcastEventBus.kt` — 通用事件总线，内部用 `MutableSharedFlow<T>(extraBufferCapacity = Int.MAX_VALUE)`，提供 `postEvent`（挂起）/`tryPostEvent`（非挂起）/`postEvent(event, scope)`（异步）。
- `events/EventListenable.kt` — 接口 `EventListenable<out T> { val events: SharedFlow<T> }`，`readOnly()` 返回只读 `SharedFlow`。扩展函数 `collect { }` 用于订阅。
- `events/Event.kt` — 事件基类。

**核心对象的事件流：**

| 对象 | 事件类型 | 事件流属性 |
|------|---------|-----------|
| `Room` | `RoomEvent` | `room.events`（`SharedFlow<RoomEvent>`） |
| `Participant` | `ParticipantEvent` | `participant.events` |
| `Track` | `TrackEvent` | `track.events` |
| `TrackPublication` | `TrackPublicationEvent` | `publication.events` |

**订阅方式（Flow）：**
```kotlin
room.events.collect { event ->
    when (event) {
        is RoomEvent.TrackSubscribed -> { /* 处理 */ }
        is RoomEvent.ParticipantConnected -> { /* 处理 */ }
        else -> {}
    }
}
```
（旧式 `ParticipantListener` / `RoomListener` 接口已 `@Deprecated`，事件统一走 Flow。）

### 1.2 Room 事件（RoomEvent）

`events/RoomEvent.kt` — `sealed class RoomEvent(val room: Room)`，按功能分组：

**连接状态：**
- `Connected` / `Reconnecting` / `Reconnected` / `Disconnected(error, reason)` / `FailedToConnect(error)`
- `DisconnectReason` 枚举：`CLIENT_INITIATED`、`DUPLICATE_IDENTITY`、`SERVER_SHUTDOWN`、`PARTICIPANT_REMOVED`、`ROOM_DELETED`、`STATE_MISMATCH`、`JOIN_FAILURE`、`MIGRATION`、`SIGNAL_CLOSE`、`CONNECTION_TIMEOUT`、`MEDIA_FAILURE` 等。

**参与者：**
- `ParticipantConnected(participant)` / `ParticipantDisconnected(participant)`
- `ActiveSpeakersChanged(speakers)`（按音频电平排序，含本地）
- `ParticipantMetadataChanged` / `ParticipantAttributesChanged` / `ParticipantNameChanged`
- `ParticipantPermissionsChanged` / `ParticipantStateChanged(newState, oldState)`
- `ConnectionQualityChanged(participant, quality)`

**轨道：**
- `TrackPublished` / `TrackUnpublished` / `TrackPublicationFailed`
- `TrackSubscribed(track, publication, participant)` / `TrackUnsubscribed` / `TrackSubscriptionFailed`
- `TrackMuted` / `TrackUnmuted`
- `LocalTrackSubscribed`（首个远端订阅了本地轨道）
- `TrackStreamStateChanged` / `TrackSubscriptionPermissionChanged`
- `TrackE2EEStateEvent`

**其他：**
- `DataReceived(data, participant, topic, encryptionType)`
- `RecordingStatusChanged` / `RoomMetadataChanged` / `TranscriptionReceived`（@Beta）

### 1.3 Participant 状态机

`room/participant/Participant.kt` — `open class Participant`，关键可观察状态用 `flowDelegate`：

| 属性 | 类型 | 说明 |
|------|------|------|
| `state` | `Participant.State` | 连接状态（见下） |
| `audioLevel` | `Float` | 音频电平 |
| `isSpeaking` | `Boolean` | 是否正在说话 |
| `connectionQuality` | `ConnectionQuality` | 连接质量 |
| `metadata` / `attributes` | `String?` / `Map` | 参与者元数据/属性 |

**`Participant.State` 枚举（`fromProto` 映射）：**

```
JOINING      // WebSocket 已连接，但尚未 offer
JOINED       // 服务器已收到客户端 offer
ACTIVE       // ICE 连接已建立（可收发媒体）
DISCONNECTED // WebSocket 断开
UNKNOWN
```

**`ConnectionQuality` 枚举：** `EXCELLENT` / `GOOD` / `POOR` / `LOST` / `UNKNOWN`。

**子类：**
- `LocalParticipant` — 本地参与者，负责发布/取消发布轨道、`publishData`、DTMF。
- `RemoteParticipant` — 远端参与者，负责订阅状态、`setVideoQuality`。

### 1.4 TrackPublication 状态机

`room/track/TrackPublication.kt` — `open class TrackPublication`，关键状态：

| 属性 | 类型 | 说明 |
|------|------|------|
| `track` | `Track?` | 关联的实际轨道（`flowDelegate`） |
| `muted` | `Boolean` | 是否静音（`flowDelegate`） |
| `subscribed` | `Boolean` | 是否已订阅（远端） |
| `dimensions` | `Track.Dimensions?` | 视频尺寸 |
| `source` | `Track.Source` | 轨道来源（camera/microphone/screen 等） |
| `kind` | `Track.Kind` | 轨道类型（audio/video） |
| `simulcasted` | `Boolean?` | 是否 simulcast |

**子类：**
- `LocalTrackPublication` — 本地发布，`setEnabled`（静音/开关）。
- `RemoteTrackPublication` — 远端发布，`setEnabled` / `setVideoQuality` / `setVideoDimensions` / `setSubscribed`。

**`Track.Kind`：** `AUDIO` / `VIDEO`。
**`Track.Source`：** `CAMERA` / `MICROPHONE` / `SCREEN_SHARE` / `SCREEN_SHARE_AUDIO` / `UNKNOWN`。
**`Track.StreamState`：** `LIVE` / `PAUSED`。

### 1.5 应用层 API 概览

| API | 作用 | 涉及文件 |
|-----|------|---------|
| `LiveKit.create(context)` | 初始化 SDK，创建 Room | `LiveKit.kt` |
| `Room.connect(url, token)` | 连接房间 | `room/Room.kt` |
| `Room.disconnect()` / `Room.release()` | 断开/释放 | `room/Room.kt` |
| `Room.events` | 房间事件流 | `events/RoomEvent.kt` |
| `room.localParticipant.publishVideoTrack/publishAudioTrack` | 发布轨道 | `room/participant/LocalParticipant.kt` |
| `room.remoteParticipants` | 远端参与者集合 | `room/Room.kt` |
| `participant.events` | 参与者事件流 | `events/ParticipantEvent.kt` |
| `publication.setVideoQuality` | 订阅端调清晰度 | `room/track/RemoteTrackPublication.kt` |
| `track.addRenderer(renderer)` | 添加渲染器 | `room/track/Track.kt` |
| `room.localParticipant.publishData` | 发布数据 | `room/participant/LocalParticipant.kt` |

---

## 2. 音频处理细节（AudioProcessing / audioswitch / AudioFocus）

> 音频链路分三层：**LiveKit 音频管理**（路由/焦点）→ **WebRTC AudioProcessing**（AEC/降噪/AGC）→ **JavaAudioDeviceModule**（采集/播放）。

### 2.1 LiveKit 音频管理（audio/ 目录）

**`AudioHandler` 接口**（`audio/AudioHandler.kt`）：`start()` / `stop()`，Room 生命周期驱动。实现类：

| 类 | 作用 | 关键依赖 |
|----|------|---------|
| `AudioSwitchHandler` | 音频路由（蓝牙/扬声器/有线耳机） | Twilio `AudioSwitch`（`com.twilio.audioswitch`） |
| `AudioFocusHandler` | 音频焦点（request/abandon） | Android `AudioManager` + `AudioFocusRequest` |
| `AudioProcessingController` | 自定义音频处理钩子 | `AudioProcessorInterface` |
| `NoAudioHandler` | 空实现（无音频） | — |
| `ScreenAudioCapturer` | 屏幕共享音频采集 | — |
| `CommunicationWorkaround` | 通话模式 workaround | — |

**`AudioSwitchHandler`**（`audio/AudioSwitchHandler.kt`）：
- 基于 Twilio `AbstractAudioSwitch`（`CommDeviceAudioSwitch` / `LegacyAudioSwitch`），在独立 `HandlerThread`（"AudioSwitchHandlerThread"）运行（AudioSwitch 非线程安全）。
- 处理音频设备切换：蓝牙、有线耳机、扬声器、听筒。
- 可选请求音频焦点（`requestAudioFocus` on start，`abandon` on stop）。

**`AudioFocusHandler`**（`audio/AudioFocusHandler.kt`）：
- `start()` → `audioManager.requestAudioFocus(audioFocusListener, streamType, focusMode)`（或 `AudioFocusRequest`）。
- `stop()` → `abandonAudioFocus` / `abandonAudioFocusRequest`。
- 提供 `onAudioFocusChangeListener` 回调。

**`AudioProcessingController`**（`audio/AudioProcessingController.kt`）：
- 接口：`setCapturePostProcessing(processing)`（采集后处理）、`setRenderPreProcessing(processing)`（渲染前处理）、`setBypassForCapturePostProcessing` / `setBypassForRenderPreProcessing`、`authenticate(url, token)`。
- 用于注入自定义 AEC/降噪/AGC 处理器。

### 2.2 自定义音频处理工厂（CustomAudioProcessingFactory）

`webrtc/CustomAudioProcessingFactory.kt` — 基于 WebRTC `ExternalAudioProcessingFactory`：
- `capturePostProcessor` → `externalAudioProcessor.setCapturePostProcessing(...)`（采集后处理，如降噪）
- `renderPreProcessor` → `externalAudioProcessor.setRenderPreProcessing(...)`（渲染前处理）
- `bypassCapturePostProcessing` / `bypassRenderPreProcessing` → 绕过标志
- 通过 `LiveKitOverrides.audioProcessingFactory` 注入。

### 2.3 WebRTC AudioProcessing（AEC / 降噪 / AGC）

WebRTC 原生 `modules/audio_processing/audio_processing_impl.cc`，`AudioProcessingImpl`：

| 模块 | 目录 | 作用 |
|------|------|------|
| **AEC**（回声消除） | `modules/audio_processing/echo_canceller3/` | EchoCanceller3，消除扬声器回声 |
| **NS**（降噪） | `modules/audio_processing/ns/` | 噪声抑制 |
| **AGC**（自动增益） | `modules/audio_processing/agc/` + `agc2/` | GainController1/2，自动增益控制 |

**采集处理入口**：`AudioProcessingImpl::ProcessStream`（`audio_processing_impl.cc:936`）→ 依次执行 AEC/NS/AGC。

### 2.4 音频上下行完整链路

**上行（采集→处理→编码→RTP）：**
```
[JavaAudioDeviceModule 采集]  →  sdk/android/src/jni/audio_device/java_audio_device_module.cc
  → AudioProcessingImpl::ProcessStream（AEC/NS/AGC）
  → ChannelSend::ProcessAndEncodeAudio（audio/channel_send.cc:847）
  → 音频编码（Opus）
  → ChannelSend::SendData（audio/channel_send.cc:375）
  → RTP 发送（rtp_rtcp）
```

**下行（RTP→解码→处理→播放）：**
```
RTP 接收 → ChannelReceive::OnRtpPacket（audio/channel_receive.cc）
  → NetEq（抖动缓冲 + 解码，neteq_）
  → ChannelReceive::GetAudioFrameWithInfo（audio/channel_receive.cc:410，neteq_->GetAudio）
  → AudioProcessingImpl::ProcessStream（渲染前处理）
  → JavaAudioDeviceModule 播放
```

**`JavaAudioDeviceModule`**（`sdk/android/src/jni/audio_device/java_audio_device_module.cc`）：Android 音频采集/播放，经 JNI 调用 `AudioRecord`/`AudioTrack`。

---

## 3. E2EE 内部（密钥协商 / FrameCryptor / DataPacketCryptor）

> E2EE 分媒体帧加密（FrameCryptor）与数据包加密（DataPacketCryptor）两条线，密钥由 `KeyProvider` 统一管理。

### 3.1 密钥管理（KeyProvider）

`e2ee/KeyProvider.kt` — 基于 WebRTC `FrameCryptorKeyProvider`（`FrameCryptorFactory.createFrameCryptorKeyProvider`），支持 **keyIndex 轮换** 和 **ratchet（密钥滚动）**：

| 方法 | 作用 |
|------|------|
| `setSharedKey(key, keyIndex)` | 设置共享密钥（所有参与者用同一 key） |
| `ratchetSharedKey(keyIndex)` | 滚动共享密钥（返回新 key） |
| `exportSharedKey(keyIndex)` | 导出共享密钥 |
| `setKey(key, participantId, keyIndex)` | 设置指定参与者的密钥 |
| `ratchetKey(participantId, keyIndex)` | 滚动指定参与者密钥 |
| `exportKey(participantId, keyIndex)` | 导出指定参与者密钥 |
| `setSifTrailer(trailer)` | 设置 SIF（敏感信息帧）trailer |
| `getLatestKeyIndex(participantId)` | 获取最新 keyIndex |

- 构造参数：`ratchetSalt`、`ratchetWindowSize`（控制 ratchet 窗口）。
- `rtcKeyProvider` 属性暴露 WebRTC 原生 `FrameCryptorKeyProvider`。

### 3.2 媒体帧加密（E2EEManager + FrameCryptor）

`e2ee/E2EEManager.kt` — 为每个轨道创建 `FrameCryptor`：

| 方法 | 作用 |
|------|------|
| `setup(room, emitEvent)` | 初始化，注册事件 |
| `addSubscribedTrack(track, publication, participant)` | 为订阅轨道创建接收端 FrameCryptor |
| `addPublishedTrack(track, publication, participant)` | 为发布轨道创建发送端 FrameCryptor |
| `enableE2EE(enabled)` | 启用/禁用 E2EE |
| `ratchetKey()` | 滚动密钥 |
| `isDataChannelEncryptionEnabled()` | 是否启用数据通道加密 |

**关键调用链（LiveKit → WebRTC）：**
```
E2EEManager::addRtpSender / addRtpReceiver
  → FrameCryptorFactory.createFrameCryptorForRtpSender / ForRtpReceiver
  → FrameCryptor（sdk/android/api/org/webrtc/FrameCryptor.java）
  → [JNI] frame_cryptor.cc（sdk/android/src/jni/pc/frame_cryptor.cc）
  → FrameEncryptorInterface / FrameDecryptorInterface（api/crypto/）
  → 挂到 RTP 发送器/接收器（媒体帧加密后进 RTP）
```

**WebRTC `FrameCryptor.java` 方法：** `setEnabled` / `isEnabled` / `getKeyIndex` / `setKeyIndex` / `setObserver` / `dispose`。`FrameCryptionState` 枚举：`NOT_ENCRYPTED`/`OK`/`KEY_RATCHETED`/`MISSING_KEY`/`ENCRYPTION_FAILED`/`DECRYPTION_FAILED`/`INTERNAL_ERROR`。

**`E2EEState` 枚举**（`e2ee/E2EEState.kt`）：`NEW`/`OK`/`KEY_RATCHETED`/`MISSING_KEY`/`ENCRYPTION_FAILED`/`DECRYPTION_FAILED`/`INTERNAL_ERROR`。

### 3.3 数据包加密（DataPacketCryptor）

`e2ee/DataPacketCryptorManager.kt` — 基于 WebRTC `DataPacketCryptor`：

| 方法 | 作用 |
|------|------|
| `encrypt(participantId, keyIndex, payload)` | 加密数据包（DataChannel 数据） |
| `decrypt(participantId, packet)` | 解密数据包 |
| `dispose()` | 释放 |

**关键调用链：**
```
DataPacketCryptorManagerImpl
  → DataPacketCryptorFactory.createDataPacketCryptor(AES_GCM, keyProvider.rtcKeyProvider)
  → DataPacketCryptor.encrypt / decrypt
  → 加密后经 DataChannel 发送 / 解密后分发
```

### 3.4 E2EE 配置（E2EEOptions）

`e2ee/E2EEOptions.kt` — 通过 `RoomOptions.e2eeOptions` 配置：`keyProvider`、`dataChannelEncryptionEnabled`、`frameCryption` 等。

---

## 4. 重连 / 网络状态机

> 连接状态机 + 重连策略 + 重连流程。核心在 `room/RTCEngine.kt`、`room/ConnectionState.kt`、`room/network/`。

### 4.1 ConnectionState 完整状态流转

`room/ConnectionState.kt` — 枚举：`CONNECTING` / `CONNECTED` / `DISCONNECTED` / `RECONNECTING` / `RESUMING`。

`RTCEngine.connectionState`（`flowDelegate`，`RTCEngine.kt:130`）反映 **SignalClient + 主 PeerConnection 的组合状态**，状态变更触发回调：

| 新状态 | 旧状态 | 触发回调 |
|--------|--------|---------|
| `CONNECTED` | `DISCONNECTED` / `CONNECTING` | `onEngineConnected`（首次连接） |
| `CONNECTED` | `RECONNECTING` | `onEngineReconnected`（全量重连成功） |
| `CONNECTED` | `RESUMING` | `onEngineResumed`（软重连成功） |
| `DISCONNECTED` | `CONNECTED` | **`reconnect()`**（触发重连） |

**关键触发点**：`connectionState` 从 `CONNECTED` → `DISCONNECTED` 时自动调用 `reconnect()`（`RTCEngine.kt:147-152`）。`DISCONNECTED` 由 PeerConnection ICE 状态（`PeerConnectionStateListener`，`RTCEngine.kt:312-317`）或 Signal 断开驱动。

### 4.2 重连策略（ReconnectPolicy）

`room/network/ReconnectPolicy.kt`：
- 接口 `ReconnectPolicy.getNextRetryDelay(context: ReconnectContext): Duration?` — 返回下次重试前延迟，返回 `null` 取消重连。
- `ReconnectContext(retryCount, elapsedTime)` — `retryCount` 为已失败次数（0 表示首次），`elapsedTime` 为断开后经过时长。
- **硬上限 30 次重试**（无论策略如何）。

`room/network/DefaultReconnectPolicy.kt` — 默认实现：
- `retryDelays: List<Duration>`（默认 `DEFAULT_RETRY_DELAYS`）：指数退避，`[100ms, 300ms, 300ms, 500ms, 500ms, 500ms, 2·2·300ms, 3·3·300ms, 4·4·300ms, 5s, 5s, ...]`，封顶 5s。
- `maxReconnectionTimeout`（默认 60s）。
- 逻辑：`retryCount >= retryDelays.size` 或 `elapsedTime > maxReconnectionTimeout` → 返回 `null`（取消）。

### 4.3 重连流程（RTCEngine::reconnect）

`RTCEngine.reconnect()`（`RTCEngine.kt:521`）— `@Synchronized`，防重入（`reconnectingJob` 活跃则返回）。流程：

```
connectionState: CONNECTED → DISCONNECTED（触发 reconnect()）
  → 循环 retries（0..MAX_RECONNECT_RETRIES）：
      1. 取策略延迟：reconnectPolicy.getNextRetryDelay(context)；null → 取消
      2. 判断重连类型（reconnectType）：
         - ReconnectType.DEFAULT：首试软重连，之后全量重连
         - FORCE_SOFT_RECONNECT：始终软重连
         - FORCE_FULL_RECONNECT：始终全量重连
      3. 【全量重连】connectionState=RECONNECTING
         → closeResources("Full Reconnecting") → joinImpl(url, token, ...)（重新走 join）
      4. 【软重连】connectionState=RESUMING
         → subscriber.prepareForIceRestart()
         → client.reconnect(url, token, participantSid)（Signal WS 重连）
         → updateRTCConfig(rtcConfig)（含 reconnectResponse.lastMessageSeq）
         → client.onReadyForResponses() → listener.onSignalConnected(true)
         → 若 hasPublished：negotiatePublisher()（重启 publisher ICE）
      5. 等待 publisher/subscriber ICE connected（withTimeoutOrNull MAX_ICE_CONNECT_TIMEOUT_MS）
      6. 若 CONNECTED/RESUMING 且 subscriber+publisher 均连上：
         → RESUMING→CONNECTED
         → resendReliableMessagesForResume(lastMessageSeq)（补发可靠 DataChannel 消息）
         → client.onPCConnected() → listener.onPostReconnect(isFullReconnect) → 成功返回
      7. 超时（MAX_RECONNECT_TIMEOUT）→ break
  → 失败：close("Failed reconnecting") → onEngineDisconnected(UNKNOWN_REASON)
```

**关键点**：
- **软重连（RESUMING）**：仅重连 Signal WS + ICE restart，保留已有 PeerConnection；成功后补发 `lastMessageSeq` 之后的可靠消息。
- **全量重连（RECONNECTING）**：关闭全部资源重新 `joinImpl`。
- `MAX_RECONNECT_RETRIES` / `MAX_RECONNECT_TIMEOUT` 兜底，策略返回 null 或超时则放弃。

### 4.4 网络监听（NetworkCallbackManager）

`room/network/NetworkCallbackManager.kt`：
- `NetworkCallbackRegistry`（`registerNetworkCallback`/`unregisterNetworkCallback`）→ 实现 `NetworkCallbackRegistryImpl`（包装 `ConnectivityManager`）。
- `NetworkCallbackManager`（`registerCallback`/`unregisterCallback`/`close`）→ `NetworkCallbackManagerImpl`：用 `AtomicBoolean isRegistered` 保证 **NetworkCallback 只注册一次**（Android 8.0 前重复注册会泄漏网络请求，且 ConnectivityService 有 100 请求硬上限）。
- 监听 `NET_CAPABILITY_INTERNET` 网络能力变化，用于触发/感知网络切换（配合重连）。

---

## 5. DataStream / RPC 协议

> DataStream 是 LiveKit 的可靠数据流传输协议（文本/字节流分片），RPC 构建在 DataStream 之上。核心在 `room/datastream/`、`room/rpc/`。

### 5.1 DataStream 传输协议

**协议结构**（`livekit.LivekitModels.DataStream`，经 `DataPacket` 承载，`DataPacket.Kind.RELIABLE` 可靠通道）：

一个数据流 = **Header + N×Chunk + Trailer**，全部走可靠 DataChannel：

| 包类型 | proto | 作用 |
|--------|-------|------|
| `Header` | `DataStream.Header` | 流元数据：`streamId`、`topic`、`timestamp`、`attributes`、`totalLength`（可选）；区分 `ByteHeader`（`mimeType`/`name`）/ `TextHeader`（`operationType`/`version`/`replyToStreamId`/`attachedStreamIds`/`generated`） |
| `Chunk` | `DataStream.Chunk` | 数据分片：`streamId`、`content`、`chunkIndex`（从 0 递增） |
| `Trailer` | `DataStream.Trailer` | 流结束：`streamId`、`reason`（可选，异常关闭原因） |

**发送端**（`datastream/outgoing/OutgoingDataStreamManager.kt`）：
- `streamText(options)` / `streamBytes(options)` → 返回 `TextStreamSender` / `ByteStreamSender`（`BaseStreamSender` 子类）。
- `openStream`：构建并发送 `Header` 包（`engine.sendData`）。
- `sendChunk`：`nextChunkIndex` 自增，发送 `Chunk` 包；发送前 `engine.waitForBufferStatusLow(RELIABLE)`（背压）。
- `closeStream`：发送 `Trailer` 包。
- `BaseStreamSender.write(data)` → `writeImpl` → `StreamDestination.write(data, chunker)`，`DataChunker<T>` 把数据切成 `List<ByteArray>` 分片。
- `StreamTextOptions` / `StreamBytesOptions`：`topic`、`attributes`、`streamId`（默认 UUID）、`destinationIdentities`（目标参与者）、`totalSize`；字节流含 `mimeType`/`name`。

**接收端**（`datastream/incoming/IncomingDataStreamManager.kt`）：
- 按 `topic` 注册 handler：`registerTextStreamHandler` / `registerByteStreamHandler`（每 topic 仅一个）。
- `handleStreamHeader`（建流，开 `Channel<ByteArray>`）→ `handleDataChunk`（写入 channel，`readLength` 累计）→ `handleStreamTrailer`（关闭 channel）。
- `BaseStreamReceiver<T>`（`TextStreamReceiver`/`ByteStreamReceiver`）：`flow: Flow<T>`（增量）、`readNext()`、`readAll()`；channel 关闭带 cause 时以 `StreamException` 失败。

**路由**：`RTCEngine` 收到 `DataPacket` 后按 `ValueCase` 分发（`RTCEngine.kt:1339`）→ `onDataStreamPacket` → `IncomingDataStreamManager`。

### 5.2 RPC 协议（基于 DataStream）

`room/rpc/` — 请求/响应式 RPC，构建在 DataStream 之上，支持 V1（RpcRequest 包）与 V2（DataStream）两种传输。

**常量**（`RpcConstants.kt`）：
- `MAX_V1_PAYLOAD_BYTES = 15KB`（V1 包载荷上限）、`RPC_VERSION_V1=1`、`RPC_VERSION_V2=2`。
- topic：`lk.rpc_request` / `lk.rpc_response`。
- 请求属性：`lk.rpc_request_id`、`lk.rpc_request_method`、`lk.rpc_request_response_timeout_ms`、`lk.rpc_request_version`。

**客户端发起**（`RpcClientManager.kt`）：
- `performRpc(destinationIdentity, method, payload, responseTimeout, maxRoundTripLatency)` → 返回响应字符串，失败抛 `RpcError`。
- 生成 `requestId`（UUID）；`effectiveTimeout = (responseTimeout - maxRoundTripLatency).coerceAtLeast(min)`；维护 `pendingAcks` / `pendingResponses` + `responseTimeoutJob`（超时清理）。
- 协议选择：远端 `ClientProtocolVersion >= DATA_STREAM_RPC` → **V2**（`publishRpcRequestV2`：`streamText(topic=lk.rpc_request, attributes=请求属性)`，payload 作为流内容）；否则 → **V1**（`publishRpcRequestV1`：`RpcRequest` 包，含 `id`/`method`/`payload`/`responseTimeoutMs`/`version`）。

**服务端处理**（`RpcServerManager.kt`）：
- V1：`handleIncomingRpcRequest`（`RpcRequest` 包）→ 校验 version → 分发 handler。
- V2：`handleIncomingRpcRequestV2`（`lk.rpc_request` 流，从 stream attributes 解析 requestId/method/timeout/version）→ 分发 handler。
- handler 返回 `response` 字符串；抛 `RpcError` 则带 message 返回，其他异常映射为 `1500`（Application Error）。
- 响应：**成功**且调用方 `>= DATA_STREAM_RPC` → **V2**（`publishRpcResponseV2`：`lk.rpc_response` 流）；否则 **V1**（`publishRpcResponseV1`：`RpcResponse` 包）。**错误响应一律走 V1 包**（无论协议版本）。

**客户端接收**（`RpcClientManager.kt`）：
- `handleIncomingRpcAck(requestId)`（ACK，`pendingAcks` 移除）→ `handleIncomingRpcResponse`（`RpcResponse` 包，`pendingResponses` 移除，取消超时 job）。

---

## 6. WebRTC 算法级细节（DTLS-SRTP / ICE 状态机 / 拥塞控制）

> 三个算法级链路的内部状态机。均位于 WebRTC 原生 C++（`pc/`、`p2p/`、`modules/congestion_controller/`）。

### 6.1 DTLS-SRTP 状态机

**DTLS 传输状态**（`api/dtls_transport_interface.h:29`）：

```
kNew        // 尚未开始协商
kConnecting // 正在协商安全连接
kConnected  // 协商完成并验证指纹
kClosed     // 主动关闭
kFailed     // 出错或指纹验证失败
```

**内部实现**（`p2p/dtls/dtls_transport.cc`，`DtlsTransportInternalImpl`）：
- 状态由 `SSLStreamAdapter` 事件驱动：`OnDtlsEvent`（`dtls_transport.cc:933`）处理 `SE_OPEN`/`SE_READ`/`SE_CLOSE`。
- `SE_OPEN`（握手完成，`SS_OPEN`）→ `set_dtls_state(kConnected)` + `set_writable(true)`（`:949-950`）。
- `SE_READ` 读失败：`SR_EOS` → `kClosed`；`SR_ERROR` → `kFailed`（`:970-984`）。
- `SE_CLOSE`：无错 → `kClosed`，有错 → `kFailed`（`:988-997`）。
- 握手启动：`MaybeStartDtls` → `StartSSL`（ICE writable 或 `dtls_in_stun_` 时）。

**SRTP 建立**（`pc/dtls_srtp_transport.cc`）：
- `DtlsSrtpTransport` 继承 `SrtpTransport`，管理 RTP/RTCP 两路 DTLS。
- `OnDtlsState`（`:324`）：当 DTLS 进入 `kConnected` → `MaybeSetupDtlsSrtp()`。
- `MaybeSetupDtlsSrtp` → `SetupRtpDtlsSrtp` / `SetupRtcpDtlsSrtp`：`ExtractParams` 从 DTLS 导出 SRTP 密钥（`SrtpSession`）→ 启用 SRTP 加解密。
- `IsDtlsConnected`：RTP 与 RTCP 两路 DTLS 均 `kConnected` 才为真（`:144-150`）。

### 6.2 ICE 状态机

**内部状态**（`p2p/base/ice_transport_internal.h:44`）：

```
STATE_INIT       // 初始
STATE_CONNECTING // 已创建连接，正在检查
STATE_COMPLETED  // 完成
STATE_FAILED     // 失败
```

**状态推导**（`p2p/base/p2p_transport_channel.cc` `ComputeState`，`:420`）：
- 无连接（`!had_connection_`）→ `STATE_INIT`。
- 无活跃连接 → `STATE_FAILED`。
- 有活跃连接但某网络有多个活跃连接 → `STATE_CONNECTING`。
- 每个网络至多一个活跃连接且至少一个 → `STATE_COMPLETED`。

**对外 RTCIceTransportState**（`api/peer_connection_interface.h` `IceConnectionState`）：
`kIceConnectionNew` / `kIceConnectionChecking` / `kIceConnectionConnected` / `kIceConnectionCompleted` / `kIceConnectionFailed` / `kIceConnectionDisconnected` / `kIceConnectionClosed`。

**PeerConnection 组合状态**（`pc/jsep_transport_controller.cc:1490`，合并所有 ICE + DTLS 传输）：
- 任一 `kFailed` → `PeerConnectionState.kFailed`
- 任一 ICE `kDisconnected` → `kDisconnected`
- 全部 `kNew`/`kClosed` → `kNew`
- 任一 `kNew`/DTLS `kConnecting`/ICE `kChecking` → `kConnecting`
- 全部 `kConnected`/`kCompleted`/`kClosed` → `kConnected`

`PeerConnectionState` 枚举（`api/peer_connection_interface.h:204`）：`kNew` / `kConnecting` / `kConnected` / `kDisconnected` / `kFailed` / `kClosed`。

### 6.3 拥塞控制（GCC）状态机

`modules/congestion_controller/goog_cc/` — Google Congestion Control，发送端基于反馈驱动。

**核心类**：
| 类 | 文件 | 作用 |
|----|------|------|
| `GoogCcNetworkControl` | `goog_cc_network_control.cc` | GCC 总控，处理 RTT/反馈/发送 |
| `SendSideBandwidthEstimation` | `send_side_bandwidth_estimation.cc` | 丢包/延迟估计合并，产出目标码率 |
| `DelayBasedBwe` | `delay_based_bwe.cc` | 延迟梯度估计（trendline） |
| `LossBasedBweV2` | `loss_based_bwe_v2.cc` | 丢包估计（v2，牛顿法） |
| `ProbeController` | `probe_controller.cc` | 带宽探测（probe） |
| `AcknowledgedBitrateEstimator` | `acknowledged_bitrate_estimator.cc` | 确认吞吐估计 |

**BandwidthUsage 状态**（`api/transport/bandwidth_usage.h`）：
```
kBwNormal     // 正常
kBwUnderusing // 带宽未用满（可升码率）
kBwOverusing  // 过载（需降码率）
```
由 `DelayBasedBwe` 的 `TrendlineEstimator`（`trendline_estimator.cc`，延迟梯度）判定。

**输入事件**（`GoogCcNetworkControl`）：
- `OnRtt`（RTT 更新）→ `SendSideBandwidthEstimation.UpdateRtt`。
- `OnTransportPacketsFeedback`（TransportFeedback 包）→ 丢包统计 → `UpdatePacketsLost`（丢包估计）→ `LossBasedBweV2.UpdateBandwidthEstimate`。
- `OnSentPacket` / `OnReceivedPacket`（接收端 REMB/TMMBR）→ `UpdateDelayBasedEstimate`（延迟估计）。
- `OnProcessInterval`（周期处理）→ `UpdateEstimate` 合并丢包+延迟估计 → 产出 `TargetTransferRate`（目标码率）。

**码率决策**：丢包与延迟两条估计线合并，`SendSideBandwidthEstimation::UpdateEstimate` 取保守值作为目标码率，经 `PacedSender`（pacing）平滑发送。

---

## 7. 子模块（CameraX / track-processors）

> 两个独立 Gradle 模块：`livekit-android-camerax`（CameraX 采集）、`livekit-android-track-processors`（视频处理，如虚背景）。

### 7.1 livekit-android-camerax（CameraX 采集集成）

包 `livekit.org.webrtc`，替代 WebRTC 原生 Camera2 采集器，基于 **AndroidX CameraX**（生命周期感知）。

| 类 | 作用 |
|----|------|
| `CameraXProvider` | 实现 `CameraCapturerUtils.CameraProvider`（`cameraVersion = 3`），提供 `provideEnumerator` / `provideCapturer` |
| `CameraXEnumerator` | 继承 `Camera2Enumerator`，枚举摄像头（含物理摄像头） |
| `CameraXCapturer` | 继承 `CameraCapturer`（`livekit.org.webrtc.CameraCapturer`），创建 `CameraXSession` |
| `CameraXSession` | 基于 `ProcessCameraProvider` + `Preview`/`UseCase` 的 CameraX 会话，绑定 `LifecycleOwner` |
| `CameraXHelper` | 辅助工具 |
| `ScaleZoomHelper` | 缩放/变焦（`io.livekit.android.camerax.ui`） |

**采集流程**：
```
CameraXProvider.provideCapturer → CameraXCapturer
  → createCameraSession → CameraXSession（ProcessCameraProvider 绑定 Preview UseCase）
  → 帧 → SurfaceTextureHelper → VideoCapturer 回调 → VideoSource → RTP
```

**集成**：通过 `CameraCapturerUtils.CameraProvider` 接口注入，LiveKit 用 CameraX 而非原生 Camera2 采集，支持生命周期感知、多 UseCase（如同时预览+分析）。

### 7.2 livekit-android-track-processors（视频处理）

包 `io.livekit.android.track.processing.video`，实现 **视频轨道处理**（如虚背景）。

**核心**：
- `VirtualBackgroundVideoProcessor`：虚背景处理器，继承 `NoDropVideoProcessor`（`livekit-android-sdk` 的 `room/track/video/`）。
- `VirtualBackgroundTransformer`：虚背景变换（EglRenderer 渲染管线）。
- `shader/`：OpenGL 着色器（`BlurShader`/`BoxBlurShader`/`CompositeShader`/`ResamplerShader`/`DefaultVertexShader`/`ShaderUtil`）。

**虚背景流程**：
```
VirtualBackgroundVideoProcessor（NoDropVideoProcessor）
  → ML Kit SelfieSegmenter（人像分割，STREAM_MODE）
  → VirtualBackgroundTransformer（EglRenderer + shader 合成背景）
  → 输出处理后的 VideoFrame
```

**与 SDK 集成**：`NoDropVideoProcessor` 是 SDK 的 `VideoProcessor` 子类，`onFrameCaptured` 强制处理每帧（`allowDropping=false` 时不做丢帧），处理后的帧进入 VideoSource 编码发送。

---

## 8. 小结

7 条缺口已全部补充完毕：
1. **应用层 API** — 事件总线（BroadcastEventBus/Flow）、Room/Participant/TrackPublication 状态机。
2. **音频处理** — AudioHandler/audioswitch/AudioFocus + WebRTC AEC/NS/AGC + JavaAudioDeviceModule 上下行。
3. **E2EE** — KeyProvider 密钥 + FrameCryptor 媒体帧 + DataPacketCryptor 数据包。
4. **重连/网络状态机** — ConnectionState 流转 + ReconnectPolicy + RTCEngine.reconnect。
5. **DataStream/RPC** — Header/Chunk/Trailer 分片 + RPC V1/V2。
6. **WebRTC 算法级** — DTLS-SRTP/ICE/GCC 状态机。
7. **子模块** — CameraX 采集 + track-processors 视频处理。

对应 memory 文件已建立并登记索引（`livekit-app-layer`、`livekit-audio`、`livekit-e2ee`、`livekit-reconnect`、`livekit-datastream-rpc`、`webrtc-algorithm-details`）。