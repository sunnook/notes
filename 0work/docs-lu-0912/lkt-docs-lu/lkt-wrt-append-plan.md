# LiveKit 工程补充文档执行计划（lkt-wrt-append）

> 目标：针对 `lkt-chain.md` / `lkt-qos-framework.md` 的 7 条覆盖缺口，逐条调研并写入补充文档 `lkt-wrt-append.md`。
> 原则：调用链到类级（含 JNI 桥接标注 `**[JNI]**`），文件路径准确，与既有文档风格一致。

## 7 条缺口 → 执行计划

### 1. LiveKit 应用层 API（Room 事件 / Participant / TrackPublication 状态机）
- **调研内容**：
  - `events/` 目录：`BroadcastEventBus`、`RoomEvent`、`ParticipantEvent`、`TrackEvent`、`TrackPublicationEvent`
  - `Room.kt` 事件分发入口（`emit`/`on`）、`Room` 对外 API
  - `participant/`：`Participant`、`LocalParticipant`、`RemoteParticipant` 生命周期与状态
  - `track/`：`TrackPublication`（Local/Remote）、`Track` 状态机（enabled/subscribed/muted）
- **涉及文件**：`events/`、`room/Room.kt`、`room/participant/`、`room/track/`
- **产出**：应用层 API 概览 + 事件总线链路 + 状态机表格

### 2. 音频处理细节（AudioProcessing / audioswitch / AudioFocus）
- **调研内容**：
  - `audio/` 目录：`AudioHandler`、`AudioSwitchHandler`、`AudioFocusHandler`、`AudioProcessingController`、`AudioRecordPrewarmer`
  - `CustomAudioProcessingFactory`（AEC/降噪/AGC）
  - audioswitch 音频路由（`io.github.ryanharter.audiomixer` 或类似）
  - WebRTC 侧 `AudioProcessing`（`modules/audio_processing/`）
- **涉及文件**：`audio/`、`webrtc/CustomAudioProcessingFactory.kt`、WebRTC `modules/audio_processing/`
- **产出**：音频采集→处理→路由→播放完整链路

### 3. E2EE 内部（密钥协商 / FrameCryptor / DataPacketCryptor）
- **调研内容**：
  - `e2ee/`：`E2EEManager`、`KeyProvider`、`DataPacketCryptorManager`、`E2EEOptions`
  - 密钥协商流程（KeyProvider 生成/分发）
  - `FrameCryptor` / `FrameEncryptor` / `FrameDecryptor` 内部
  - `DataPacketCryptor` 数据包加密协议
- **涉及文件**：`e2ee/`、WebRTC `sdk/android/api/org/webrtc/FrameCryptor*.java`
- **产出**：E2EE 完整链路（密钥→媒体帧加密→数据包加密）

### 4. 重连 / 网络状态机
- **调研内容**：
  - `network/`：`ReconnectPolicy`、`DefaultReconnectPolicy`、`NetworkCallbackManager`
  - `ConnectionState.kt` 完整状态流转（DISCONNECTED/CONNECTING/CONNECTED/RECONNECTING/RESUMING）
  - 重连触发条件与流程（`RTCEngine::reconnect`）
- **涉及文件**：`room/network/`、`room/ConnectionState.kt`、`room/RTCEngine.kt`
- **产出**：连接状态机 + 重连策略 + 重连流程

### 5. DataStream / RPC 协议
- **调研内容**：
  - `datastream/`：`incoming/`、`outgoing/` 数据流编解码
  - `rpc/`：`RpcClientManager`、`RpcServerManager`、`RpcManager`
  - DataStream 分片/重组协议
- **涉及文件**：`room/datastream/`、`room/rpc/`
- **产出**：DataStream 传输协议 + RPC 请求/响应链路

### 6. WebRTC 算法级细节（DTLS-SRTP / ICE 状态机 / 拥塞控制）
- **调研内容**：
  - DTLS-SRTP：`pc/dtls_srtp_transport.cc`、`pc/srtp_transport.cc`、`pc/dtls_transport.cc`
  - ICE 状态机：`p2p/base/ice_transport.cc`、`p2p/base/port.cc`
  - 拥塞控制算法内部：`modules/congestion_controller/goog_cc/`（GCC 状态机、丢包/延迟估计）
- **涉及文件**：WebRTC `pc/`、`p2p/`、`modules/congestion_controller/`
- **产出**：三个算法级链路的内部状态机说明

### 7. 子模块（CameraX / track-processors）
- **调研内容**：
  - `livekit-android-camerax/`：CameraX 采集集成
  - `livekit-android-track-processors/`：虚拟背景、降噪等轨道处理
- **涉及文件**：`livekit-android-camerax/`、`livekit-android-track-processors/`
- **产出**：子模块架构与集成方式概览

## 执行方式

1. 逐条调研（Bash/Read 源码）
2. 每条调研完成后，将结论写入 `lkt-wrt-append.md` 对应章节
3. **必要的有效知识同步写入 memory**（新增/更新 memory 文件，如 `livekit-app-layer.md`、`livekit-audio.md`、`livekit-e2ee.md` 等，并在 `MEMORY.md` 登记索引）
4. 全部完成后汇总核对

## Memory 写入原则

- 只写**必要且有效**的知识（架构、协议、状态机、关键调用链），不写可从代码直接读出的琐碎细节
- 每条缺口对应一个 memory 文件（若已有则更新，不重复建）
- 更新 `MEMORY.md` 索引
