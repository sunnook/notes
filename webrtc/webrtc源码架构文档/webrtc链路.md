








我会按你指定的格式重做这张“阶段对照表”：删掉所有“通常、可能、间接”等不确定词；每条 WebRTC 链路拆成独立行，并把“目录/概念”改成实际类名或标明它不是类。对抖动缓冲和解码部分，我先核对当前 WebRTC 代码中的真实函数名。

Ran terminal command: $root='D:\codes\webrtc\webrtc'; Get-ChildItem $root -Recurse -File -Include *.cc,*.h | Select-String -Pattern 'InsertFrame\(|GetFrameForDecoding\(|Decode\(|DecodeFrame\(|OnCompleteFrame\(|HandleEncodedFrame\(' | Where-Object { $_.Path -match 'video_coding|video_receive_stream|audio_receive_stream' } | Select-Object -First 160 | ForEach-Object { "$($_.Path):$($_.LineNumber):$($_.Line.Trim())" }

Read , lines 1 to 160

你的方法是对的。建议固定为 **“阶段 + LiveKit 调用 + 文件 + WebRTC 接口 + C++ 精确链路 + 结果”**。下面把链路改成确定表达，不使用“通常、可能、间接”等模糊词。

## LiveKit Android -> WebRTC 流程对照表

> `SignalClient` 和 `PeerConnectionTransport` 是并列关系：
>
> ```text
> RTCEngine
>     ├── SignalClient
>     └── PeerConnectionTransport
> ```

| 阶段                  | LiveKit 内部流程                                                                                        | LiveKit 文件                                                        | WebRTC 接口                                                                  | WebRTC C++ 链路                                                                                                                                                                                           | 结果                                         |
| ------------------- | --------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| 0. SDK 初始化          | 创建 `Room`、`RTCEngine`、`SignalClient`、`PeerConnectionFactory` 和 Track 工厂                             | `Room.kt`、`RTCEngine.kt`、依赖注入相关文件                                 | `PeerConnectionFactory`、`EglBase`、`AudioDeviceModule`                      | `PeerConnectionFactory` Java API -> JNI -> C++ `PeerConnectionFactory`                                                                                                                                  | 初始化线程、音频设备、EGL、编解码器和 PeerConnection 工厂     |
| 1. 加入房间             | `Room.connect()` -> `RTCEngine.join()` -> `SignalClient.join()` -> WebSocket 发送 `JoinRequest`       | `Room.kt`、`RTCEngine.kt`、`SignalClient.kt`                        | 无 `PeerConnection` 调用                                                      | `SignalClient` -> WebSocket -> LiveKit Server                                                                                                                                                           | 完成 LiveKit 房间认证，获得房间、参与者和服务器状态             |
| 2. 创建 WebRTC 连接     | `RTCEngine` 创建 Publisher 和 Subscriber 的 `PeerConnectionTransport`                                   | `RTCEngine.kt`、`PeerConnectionTransport.kt`                       | `PeerConnectionFactory.createPeerConnection()`                             | `PeerConnectionFactory.createPeerConnection()` -> JNI -> C++ `PeerConnection::Create()` -> 创建 `Call`、`JsepTransportController` 等                                                                        | 创建 WebRTC PeerConnection 对象                |
| 3. 创建 SDP Offer     | 发布端调用 `PeerConnectionTransport.createOffer()`                                                       | `PeerConnectionTransport.kt`、`CoroutineSdpObserver.kt`            | `PeerConnection.createOffer()`                                             | Java `PeerConnection.createOffer()` -> JNI -> `webrtc::PeerConnection::CreateOffer()` -> `SdpOfferAnswerHandler`                                                                                        | 生成本地 SDP Offer                             |
| 4. 应用本地 SDP         | LiveKit 调用 `PeerConnectionTransport.setLocalDescription()`                                          | `PeerConnectionTransport.kt`、`CoroutineSdpObserver.kt`            | `PeerConnection.setLocalDescription()`                                     | Java `setLocalDescription()` -> JNI -> `PeerConnection::SetLocalDescription()` -> `SdpOfferAnswerHandler` -> `JsepTransportController::SetLocalDescription()`                                           | WebRTC 保存本地 SDP，并按 SDP 创建/更新传输对象           |
| 5. 发送 SDP           | `SignalClient` 将 SDP 封装到 LiveKit 信令消息发送给 SFU                                                        | `RTCEngine.kt`、`SignalClient.kt`                                  | 无新的 WebRTC 接口                                                              | `SignalClient` -> WebSocket -> LiveKit Server                                                                                                                                                           | SFU 获取客户端 SDP                              |
| 6. 接收 SDP Offer     | Subscriber 收到 SFU SDP Offer 后调用 `setRemoteDescription()`                                            | `RTCEngine.kt`、`PeerConnectionTransport.kt`                       | `PeerConnection.setRemoteDescription()`                                    | Java `setRemoteDescription()` -> JNI -> `PeerConnection::SetRemoteDescription()` -> `SdpOfferAnswerHandler` -> `JsepTransportController::SetRemoteDescription()`                                        | WebRTC 应用远端 SDP                            |
| 7. 创建 SDP Answer    | Subscriber 调用 `createAnswer()`                                                                      | `PeerConnectionTransport.kt`、`CoroutineSdpObserver.kt`            | `PeerConnection.createAnswer()`                                            | Java `createAnswer()` -> JNI -> `PeerConnection::CreateAnswer()` -> `SdpOfferAnswerHandler`                                                                                                             | 生成本地 SDP Answer                            |
| 8. ICE Candidate 收集 | WebRTC 回调产生 Candidate，LiveKit 将 Candidate 封装后发送给 SFU                                                | `PeerConnectionTransport.kt`、`RTCEngine.kt`、`SignalClient.kt`     | `PeerConnection.Observer.onIceCandidate()`                                 | C++ `PeerConnection` -> `JsepTransportController` -> `IceTransportInternal` -> `PortAllocator` / `p2p`                                                                                                  | 产生本地 ICE Candidate 并通过 LiveKit 信令发送        |
| 9. 应用远端 Candidate   | LiveKit 收到 SFU Candidate 后调用 `addIceCandidate()`                                                    | `RTCEngine.kt`、`PeerConnectionTransport.kt`                       | `PeerConnection.addIceCandidate()`                                         | Java `addIceCandidate()` -> JNI -> `PeerConnection::AddIceCandidate()` -> `JsepTransportController` -> `IceTransportInternal`                                                                           | WebRTC 获得远端 Candidate                      |
| 10. ICE 连通性检查       | LiveKit 只传递 Candidate 和 ICE 状态事件                                                                    | `SignalClient.kt`、`RTCEngine.kt`                                  | `onIceConnectionChange()`                                                  | `JsepTransportController` -> `IceTransportInternal` -> `p2p` -> STUN/TURN 连通性检查                                                                                                                         | 选择可用的 ICE Candidate Pair                   |
| 11. DTLS/SRTP 建立    | LiveKit 接收 WebRTC Transport 状态回调                                                                    | `PeerConnectionTransport.kt`、`RTCEngine.kt`                       | `PeerConnection.Observer`、`onIceConnectionChange()`、`onConnectionChange()` | `JsepTransportController` -> `DtlsTransport` -> `DtlsSrtpTransport` -> `RtpTransport`                                                                                                                   | 建立加密的 RTP/RTCP 通道                          |
| 12. 发布本地 Track      | `LocalParticipant.publishTrack()` -> `RTCEngine.addTrack()` -> `PeerConnectionTransport.addTrack()` | `LocalParticipant.kt`、`RTCEngine.kt`、`PeerConnectionTransport.kt` | `PeerConnection.addTransceiver()`、`RtpSender`                              | Java `addTransceiver()` -> JNI -> `PeerConnection` -> `RtpTransmissionManager` -> `RtpTransceiver` -> `RtpSender`                                                                                       | 本地 Track 加入 Publisher PeerConnection       |
| 13. 发布媒体数据          | 摄像头/麦克风 Track 产生媒体帧                                                                                 | `LocalAudioTrack.kt`、`LocalVideoTrack.kt`、`RtpSender.kt`          | `MediaStreamTrack`、`RtpSender`                                             | `MediaStreamTrack` -> `RtpSender` -> `VideoSendStream` / `AudioSendStream` -> `RTPSender` -> `RtpSenderEgress` -> RTP                                                                                   | RTP 包发送到 LiveKit SFU                       |
| 14. 服务器通知远端 Track   | `RTCEngine` 接收 Track Published / Subscribed 信令事件                                                    | `RTCEngine.kt`、`Room.kt`、`RemoteParticipant.kt`                   | 无新的媒体创建接口                                                                  | `SignalClient` -> `RTCEngine` -> `RemoteParticipant`                                                                                                                                                    | LiveKit 创建远端 Track Publication             |
| 15. 接收远端 SDP        | Subscriber 调用 `setRemoteDescription()` 应用 SFU SDP Offer                                             | `RTCEngine.kt`、`PeerConnectionTransport.kt`                       | `PeerConnection.setRemoteDescription()`                                    | `PeerConnection::SetRemoteDescription()` -> `SdpOfferAnswerHandler` -> `JsepTransportController`                                                                                                        | 创建远端媒体接收关系                                 |
| 16. 接收远端 Track      | WebRTC 触发 `onAddTrack()`                                                                            | `RTCEngine.kt`、`Room.kt`、`RemoteParticipant.kt`                   | `PeerConnection.Observer.onAddTrack()`                                     | `RtpTransport` -> `RtpReceiver` -> `VideoReceiveStream` / `AudioReceiveStream` -> `RtpVideoStreamReceiver`                                                                                              | 生成 `RemoteVideoTrack` / `RemoteAudioTrack` |
| 17. 接收媒体解码          | RTP 包进入接收器和视频解码流程                                                                                   | `RemoteVideoTrack.kt`、`RemoteAudioTrack.kt`                       | `VideoTrack`、`AudioTrack`                                                  | `RtpReceiver` -> `VideoReceiveStream` -> `VideoStreamDecoder` -> `VCMFrameBuffer::PrepareForDecode()` -> `VideoDecoder::Decode()`                                                                       | 生成解码后的视频帧或音频帧                              |
| 18. 实时 QoS          | LiveKit 设置媒体发布参数，WebRTC 执行网络控制                                                                      | `LocalParticipant.kt`、`RTCEngine.kt`、Track 相关文件                   | `RtpSender`、编码参数接口                                                         | `RTCPReceiver` -> `NetworkLinkRtcpObserver` -> `RtpTransportControllerSend` -> `TransportFeedbackAdapter` -> `GoogCcNetworkController` -> `PacingController`                                            | 调整目标码率、Pacer 速率、Probe、RTX 和 FEC            |
| 19. 信令断线重连          | `Room` -> `RTCEngine.reconnect()` -> `SignalClient.reconnect()`                                     | `Room.kt`、`RTCEngine.kt`、`SignalClient.kt`、`ReconnectPolicy.kt`   | WebRTC 状态查询、SDP 和 ICE 接口                                                   | `SignalClient` 重新连接 -> `RTCEngine` 处理 `ReconnectResponse` -> `PeerConnectionTransport` 重新应用 SDP/ICE                                                                                                     | 恢复 LiveKit 信令连接                            |
| 20. ICE Restart     | `RTCEngine` 设置重连流程后重新进行 WebRTC 协商                                                                   | `RTCEngine.kt`、`PeerConnectionTransport.kt`                       | `createOffer()`、`setLocalDescription()`、`setRemoteDescription()`           | `PeerConnection::RestartIce()` -> `SdpOfferAnswerHandler` -> `JsepTransportController::SetNeedsIceRestartFlag()` -> `JsepTransportController::MaybeStartGathering()` -> `IceTransportInternal` -> `p2p` | 使用新的 ICE ufrag/password 和 Candidate 建立连接   |
| 21. 完整重连            | 保存本地 Track -> 重新加入房间 -> 重新发布 Track -> 恢复订阅                                                          | `LocalParticipant.kt`、`Room.kt`、`RTCEngine.kt`                    | `addTransceiver()`、SDP、ICE 接口                                              | 重新创建或重新配置 `PeerConnection` -> `RtpSender` / `RtpReceiver` -> `JsepTransportController`                                                                                                                  | 恢复完整媒体会话                                   |
| 22. 退出房间            | `Room.disconnect()` -> 停止 Track -> 关闭信令和 WebRTC Transport                                           | `Room.kt`、`RTCEngine.kt`、`SignalClient.kt`                        | `PeerConnection.close()`                                                   | `PeerConnection::Close()` -> `RtpTransport` -> `DtlsTransport` -> `IceTransport` -> `SctpTransport`                                                                                                     | 离开 LiveKit 房间                              |
| 23. SDK 销毁          | 释放 `Room`、`RTCEngine`、Track、音频设备、EGL 和协程资源                                                          | `Room.kt`、`RTCEngine.kt`、Track 文件                                 | `PeerConnection.dispose()`、`PeerConnectionFactory.dispose()`               | JNI -> C++ `PeerConnection` / `PeerConnectionFactory` 析构                                                                                                                                                | 释放 SDK 全局资源                                |

## 关键关系

### 1. LiveKit 信令和 WebRTC 的关系

```text
LiveKit SignalClient
    -> WebSocket
        -> LiveKit Server / SFU
```

它负责传递：

```text
JoinRequest
JoinResponse
SDP Offer
SDP Answer
ICE Candidate
ReconnectRequest
TrackPublished
TrackSubscribed
```

但是信令消息中的 SDP 和 Candidate，最终由 WebRTC 接口执行：

```text
LiveKit SDP
    -> PeerConnection.setLocalDescription()
    -> PeerConnection.setRemoteDescription()

LiveKit ICE Candidate
    -> PeerConnection.addIceCandidate()
```

### 2. Publisher 和 Subscriber

```text
Publisher PeerConnection
    -> 本地客户端
    -> LiveKit SFU
    -> 发布本地音视频
```

```text
Subscriber PeerConnection
    -> LiveKit SFU
    -> 本地客户端
    -> 接收远端音视频
```

因此发布和接收可以拥有不同的 PeerConnection。

### 3. WebRTC C++ 核心链路

```text
org.webrtc.PeerConnection
    -> JNI
        -> webrtc::PeerConnection
            -> SdpOfferAnswerHandler
            -> JsepTransportController
            -> Call
            -> ModuleRtpRtcpImpl2
            -> RtpTransportControllerSend
            -> PacingController
```

### 4. 接收端抖动缓冲和解码链路

应该写成具体类和函数，而不是：

```text
抖动缓冲 -> 解码器
```

可以写成：

```text
VideoReceiveStream
    -> RtpVideoStreamReceiver
        -> FrameBuffer::InsertFrame()
        -> FrameBuffer::NextFrame()
            -> VideoStreamDecoder::Decode()
                -> VideoDecoder::Decode()
```

对于当前代码中明确存在的旧版路径，可以写成：

```text
VCMReceiver::Decode()
    -> VCMJitterBuffer::ExtractAndSetDecode()
        -> VCMFrameBuffer::PrepareForDecode()
            -> VideoDecoder::Decode()
```

最终定位：

```text
LiveKit
    负责房间、参与者、发布订阅和私有信令

WebRTC Java
    负责 PeerConnection API

JNI
    负责 Java 到 C++ 的桥接

WebRTC C++
    负责 SDP、ICE、DTLS、SRTP、RTP/RTCP、QoS 和编解码链路

```





我会直接给你完整新版表格，不再只展示示例。表格会固定为 7 列，并把存在两条分支的地方明确写成“发布端/订阅端”或“信令重连/ICE 重启”，而不是用“通常、可能”；接收端抖动缓冲和解码链路只写当前源码中能确认的类和函数。


可以，下面是增加 `WebRTC 文件` 列后的完整版本。表格固定为 7 列：

| LiveKit 文件                                                                                                                                                                  | LiveKit 内部流程                                                                                                                                                                                                        | 阶段                        | WebRTC Java 接口                                                                                                                                                                                                                                                                                                                                                                          | WebRTC C++ 调用链                                                                                                                                                                                                                                                                              | WebRTC 文件                                                                                                                                                                                                                           | 结果                                         |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| `room/Room.kt`<br>`room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`                                                                                                  | 创建 `Room`、`RTCEngine`、`SignalClient`、`PeerConnectionFactory`、音视频 Track 工厂                                                                                                                                           | 0. SDK 初始化                | `PeerConnectionFactory`<br>`EglBase`<br>`AudioDeviceModule`                                                                                                                                                                                                                                                                                                                             | `PeerConnectionFactory` → JNI <br>→ `webrtc::PeerConnectionFactory`  <br>→ `CallFactory` / `AudioDeviceModule` <br>/ `VideoEncoderFactory` / `VideoDecoderFactory`                                                                                                                          | `peer_connection_interface.h`<br>`peer_connection_factory.cc`<br>`peer_connection_factory.h`                                                                                                                                        | 初始化 WebRTC 工厂、线程、音频设备和 EGL                 |
| `room/Room.kt`<br>`room/RTCEngine.kt`<br>`room/SignalClient.kt`                                                                                                             | `Room.connect()` <br>-> `RTCEngine.join()` <br>-> `SignalClient.join()` <br>-> WebSocket 发送 `JoinRequest`<br>-> LiveKit Server                                                                                      | 1. 加入房间                   | 无 `PeerConnection` 调用，此阶段主要是 LiveKit 信令，不进入 WebRTC `PeerConnection` C++ 链路                                                                                                                                                                                                                                                                                                              |                                                                                                                                                                                                                                                                                             | LiveKit SDK `SignalClient.kt`<br>WebRTC 无对应 C++ 调用                                                                                                                                                                                  | 完成 LiveKit 房间认证，得到 `JoinResponse`          |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`                                                                                                                    | `RTCEngine` 创建 Publisher 和 Subscriber 的 `PeerConnectionTransport`                                                                                                                                                   | 2. 创建 WebRTC 连接           | `PeerConnectionFactory.createPeerConnection()`  <br>→ JNI  <br>→ `webrtc::PeerConnectionFactory::CreatePeerConnection()`                                                                                                                                                                                                                                                                | -> JNI <br>-> `PeerConnection::Create()` <br>-> `创建Call, JseTransportController等`                                                                                                                                                                                                           | `peer_connection_factory.cc`<br>`peer_connection.cc`                                                                                                                                                                                | 创建 WebRTC PeerConnection                   |
| `room/PeerConnectionTransport.kt`<br>`room/util/CoroutineSdpObserver.kt`                                                                                                    | Publisher 调用 `PeerConnectionTransport.createOffer()`                                                                                                                                                                | 3. 创建 SDP Offer           | `PeerConnection.createOffer()`  <br>→ JNI  <br>→ `webrtc::PeerConnection::CreateOffer()`                                                                                                                                                                                                                                                                                                | ->`PeerConnection::CreateOffer()` <br>->`SdpOfferAnswerHandler`                                                                                                                                                                                                                             | `peer_connection.cc`<br>`sdp_offer_answer.cc`<br>`sdp_offer_answer.h`                                                                                                                                                               | 生成 SDP Offer                               |
| `room/PeerConnectionTransport.kt`<br>`room/util/CoroutineSdpObserver.kt`                                                                                                    | `PeerConnectionTransport<br><br>.setLocalDescription()`                                                                                                                                                             | 4. 设置本地 SDP               | `PeerConnection.setLocalDescription()`  <br>→ JNI  <br>→ `webrtc::PeerConnection::SetLocalDescription()`                                                                                                                                                                                                                                                                                | ->`PeerConnection::SetLocalDescription()` <br>-> `SdpOfferAnswerHandler` <br>-> `JsepTransportController::SetLocalDescription()`                                                                                                                                                            | `peer_connection.cc`<br>`sdp_offer_answer.cc`<br>`jsep_transport_controller.cc`<br>`jsep_transport_controller.h`                                                                                                                    | 保存本地 SDP，更新 RTP/DTLS/ICE 传输配置              |
| `room/RTCEngine.kt`<br>`room/SignalClient.kt`                                                                                                                               | `SignalClient` -> WebSocket -> LiveKit Server<br>`RTCEngine` 将 SDP 封装为 LiveKit 信令消息，由 `SignalClient` 发送给 SFU                                                                                                        | 5. 发送 SDP                 | 无新的 WebRTC 接口                                                                                                                                                                                                                                                                                                                                                                           |                                                                                                                                                                                                                                                                                             | LiveKit SDK `SignalClient.kt`<br>WebRTC 无对应 C++ 调用                                                                                                                                                                                  | SFU 获得客户端 SDP                              |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`                                                                                                                    | Subscriber 收到 SFU SDP Offer，调用 `setRemoteDescription()`                                                                                                                                                             | 6. 接收并设置远端 SDP            | `PeerConnection.setRemoteDescription()`                                                                                                                                                                                                                                                                                                                                                 | -> JNI<br>->`PeerConnection::SetRemoteDescription()` <br>-> `SdpOfferAnswerHandler` <br>->`JsepTransportController::SetRemoteDescription()`                                                                                                                                                 | `peer_connection.cc`<br>`sdp_offer_answer.cc`<br>`jsep_transport_controller.cc`                                                                                                                                                     | 应用 SFU 的 SDP Offer                         |
| `room/PeerConnectionTransport.kt`<br>`room/util/CoroutineSdpObserver.kt`                                                                                                    | Subscriber 调用 `createAnswer()`                                                                                                                                                                                      | 7. 创建 SDP Answer          | `PeerConnection.createAnswer()`                                                                                                                                                                                                                                                                                                                                                         | -> JNI<br>->`PeerConnection::CreateAnswer()` <br>-> `SdpOfferAnswerHandler`                                                                                                                                                                                                                 | `peer_connection.cc`<br>`sdp_offer_answer.cc`                                                                                                                                                                                       | 生成 SDP Answer                              |
| `room/PeerConnectionTransport.kt`<br>`room/RTCEngine.kt`<br>`room/SignalClient.kt`                                                                                          | WebRTC 触发 ICE Candidate 回调，LiveKit 将 Candidate 封装后发送给 SFU                                                                                                                                                           | 8. ICE Candidate 收集       | `PeerConnection.Observer.onIceCandidate()` `webrtc::PeerConnection`  <br>→ JNI  <br>→ `PeerConnection.Observer.onIceCandidate()`                                                                                                                                                                                                                                                        | C++ `PeerConnection` <br>-> `JsepTransportController`  <br>→ `IceTransportInternal`  <br>→ `PortAllocator`  <br>→ `P2PTransportChannel`  <br>→ STUN / TURN Candidate 收集                                                                                                                     | `peer_connection.cc`<br>`jsep_transport_controller.cc`<br>`ice_transport_internal.h`<br>`port_allocator.h`                                                                                                                          | 产生本地 Candidate                             |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`                                                                                                                    | `RTCEngine` 收到 SFU Candidate，调用 `PeerConnectionTransport.addIceCandidate()`                                                                                                                                         | 9. 应用远端 Candidate         | `PeerConnection.addIceCandidate()`  <br>→ JNI  <br>→ `webrtc::PeerConnection::AddIceCandidate()`                                                                                                                                                                                                                                                                                        | -> JNI<br>->`PeerConnection::AddIceCandidate()` <br>-> `JsepTransportController` <br>-> `IceTransportInternal`                                                                                                                                                                              | `peer_connection.cc`<br>`jsep_transport_controller.cc`<br>`ice_transport_internal.h`                                                                                                                                                | WebRTC 获得远端 Candidate                      |
| `room/SignalClient.kt`<br>`room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`                                                                                          | LiveKit 传递 Candidate 和 ICE 状态；<br>WebRTC 执行连通性检查                                                                                                                                                                    | 10. ICE 连通性检查             | `PeerConnection.Observer`<br>.`onIceConnectionChange()`                                                                                                                                                                                                                                                                                                                                 | `JsepTransportController` <br>-> `IceTransportInternal` <br>-> `Port (p2p)`<br>-> `STUN/TURN 连通性检查`                                                                                                                                                                                         | `jsep_transport_controller.cc`<br>`ice_transport_internal.h`<br>`port.cc`                                                                                                                                                           | 选出可用 Candidate Pair                        |
| `room/PeerConnectionTransport.kt`<br>`room/RTCEngine.kt`                                                                                                                    | `PeerConnectionTransport` 接收 WebRTC Transport 状态                                                                                                                                                                    | 11. DTLS/SRTP 建立          | `PeerConnection.Observer`<br>.`onIceConnectionChange()`<br>`onConnectionChange()`                                                                                                                                                                                                                                                                                                       | `JsepTransportController` <br>-> `DtlsTransport` <br>-> `DtlsSrtpTransport` <br>-> `RtpTransport`                                                                                                                                                                                           | `jsep_transport_controller.cc`<br>`dtls_transport.cc`<br>`dtls_srtp_transport.cc`<br>`rtp_transport.cc`                                                                                                                             | 建立加密 RTP/RTCP 通道                           |
| `room/participant/LocalParticipant.kt`<br>`room/RTCEngine.kt`<br>`room/SignalClient.kt`                                                                                     | `LocalParticipant.publishTrack()` <br>-> `RTCEngine.addTrack()` <br>-> 发送 `AddTrackRequest` <br>-> LiveKit Server 返回 `TrackInfo`  <br><br>-> `RTCEngine.addTrack()` <br><br>-> `PeerConnectionTransport.addTrack()` | 12. 发布 Track 的 LiveKit 注册 | 无新的 WebRTC 接口                                                                                                                                                                                                                                                                                                                                                                           | `SignalClient` -> WebSocket -> LiveKit Server<br>?<br>`LocalParticipant.publishTrack()`<br><br>-> `org.webrtc.PeerConnection.addTransceiver()`<br>-> `JNI`<br>  -> `webrtc::PeerConnection::AddTransceiver()`<br>  -> `RtpTransmissionManager`<br>  -> `RtpTransceiver`<br>  -> `RtpSender` | LiveKit SDK `LocalParticipant.kt`<br>`RTCEngine.kt`<br>`SignalClient.kt`                                                                                                                                                            | LiveKit Server 分配业务层 Track SID             |
| `room/participant/LocalParticipant.kt`<br>`room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`                                                                          | `LocalParticipant.publishTrack()`<br>`-> RTCEngine.addTrack()`<br>`-> PeerConnectionTransport.addTrack()`                                                                                                           | 13. 发布本地 Track            | `PeerConnection.addTransceiver()`<br>`RtpTransceiver`<br>`RtpSender`                                                                                                                                                                                                                                                                                                                    | `PeerConnection::AddTransceiver()`-> JNI<br><br>`-> RtpTransmissionManager`<br>`-> RtpTransceiver`<br>`-> RtpSender`                                                                                                                                                                        | `peer_connection.cc`<br>`rtp_transmission_manager.cc`<br>`rtp_transceiver.cc`<br>pc/`rtp_sender.cc`                                                                                                                                 | 本地 Track 加入 Publisher PeerConnection       |
| `room/track/LocalVideoTrack.kt`<br>`room/track/LocalAudioTrack.kt`                                                                                                          | `LocalVideoTrack` / `LocalAudioTrack`<br>`-> WebRTC MediaStreamTrack`<br>`-> RtpSender`<br>`-> 编码帧发送`                                                                                                               | 14. 上行媒体发送                | `MediaStreamTrack`<br>`RtpSender`                                                                                                                                                                                                                                                                                                                                                       | `RtpSender`<br>`-> VideoSendStream::SendEncodedImage / AudioSendStream`<br>`-> RTPSenderVideo / RTPSenderAudio`<br>`-> RTPSender::SendPacket()`<br>`-> RtpSenderEgress::SendPacket()`<br>`-> PacingController::EnqueuePacket()`<br>`-> RTP / SRTP`                                          | `video_send_stream.cc`<br>`audio_send_stream.cc`<br>`rtp_sender_video.cc`<br>`rtp_sender_audio.cc`<br>`rtp_sender_egress.cc`<br>`pacing_controller.cc`                                                                              | RTP 包发送到 LiveKit SFU                       |
| `room/RTCEngine.kt`<br>`room/Room.kt`<br>`room/participant/RemoteParticipant.kt`                                                                                            | `RTCEngine` 收到 `TrackPublished` / `TrackSubscribed` 信令事件                                                                                                                                                            | 15. LiveKit 通知远端 Track    | 无新的媒体创建接口                                                                                                                                                                                                                                                                                                                                                                               | `SignalClient` -> `RTCEngine` -> `RemoteParticipant`                                                                                                                                                                                                                                        | LiveKit SDK `SignalClient.kt`<br>`RTCEngine.kt`<br>`RemoteParticipant.kt`                                                                                                                                                           | 创建远端 Track Publication                     |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`                                                                                                                    | Subscriber 收到 SFU SDP Offer，设置远端 SDP 并创建 Answer                                                                                                                                                                     | 16. 订阅远端媒体                | `setRemoteDescription()`<br>`createAnswer()`<br>`setLocalDescription()`                                                                                                                                                                                                                                                                                                                 | `PeerConnection::SetRemoteDescription()` <br>-> `SdpOfferAnswerHandler` <br>-> `JsepTransportController` <br>-> `RtpReceiver`                                                                                                                                                               | `peer_connection.cc`<br>`sdp_offer_answer.cc`<br>`jsep_transport_controller.cc`<br>`rtp_transmission_manager.cc`                                                                                                                    | 创建远端媒体接收关系                                 |
| `room/RTCEngine.kt`<br>`room/Room.kt`<br>`room/participant/RemoteParticipant.kt`                                                                                            | WebRTC 调用 `RTCEngine.onAddTrack()`，再分发到 `Room` 和 `RemoteParticipant`                                                                                                                                                | 17. WebRTC 回调远端 Track     | `PeerConnection.Observer<br>.onAddTrack()`                                                                                                                                                                                                                                                                                                                                              | `RtpTransport` <br>-> `RtpReceiver` <br>-> `VideoReceiveStream` / `AudioReceiveStream`                                                                                                                                                                                                      | `peer_connection.cc`<br>`rtp_transport.cc`<br>`video_receive_stream.cc`<br>`audio_receive_stream.cc`                                                                                                                                | 创建 `RemoteVideoTrack` / `RemoteAudioTrack` |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`<br>`room/participant/RemoteParticipant.kt`<br>`room/track/RemoteVideoTrack.kt`<br>`room/track/RemoteAudioTrack.kt` | `RTCEngine.onAddTrack()`<br>`-> Room.onAddTrack()`<br>`-> RemoteParticipant`<br>`-> RemoteTrackPublication`<br>`-> RemoteVideoTrack` / `RemoteAudioTrack`                                                           | 18. 下行媒体接收                | `PeerConnection.Observer.onAddTrack()`<br>`RtpReceiver`<br>`VideoTrack`<br>`AudioTrack`                                                                                                                                                                                                                                                                                                 | `RtpTransport`<br>`-> RtpReceiver`<br>`-> VideoReceiveStream / AudioReceiveStream`<br> `-> 接收编码帧`<br>`-> VCMReceiver::Decode()`<br>`-> VCMJitterBuffer::ExtractAndSetDecode()`<br>`-> VCMFrameBuffer::PrepareForDecode()`<br>`-> VideoDecoder::Decode()`                                    | `rtp_transport.cc`<br>`video_receive_stream.cc`<br>`audio_receive_stream.cc`<br>`receiver.cc`<br>`jitter_buffer.cc`<br>`frame_buffer.cc`<br>`modules/video_coding/video_decoder.cc`<br>`modules/video_coding/codecs/*/*_decoder.cc` | 接收 SFU 的 RTP，完成抖动缓存和视频解码，得到远端视频帧           |
|                                                                                                                                                                             |                                                                                                                                                                                                                     | 21. 实时 QoS（参考下表）          |                                                                                                                                                                                                                                                                                                                                                                                         |                                                                                                                                                                                                                                                                                             |                                                                                                                                                                                                                                     |                                            |
| `room/Room.kt`<br>`room/RTCEngine.kt`<br>`room/SignalClient.kt`<br>`room/network/ReconnectPolicy.kt`                                                                        | `Room` <br>-> `RTCEngine.reconnect()` <br>-> `SignalClient.reconnect()` <br>-> 重新发送重连请求                                                                                                                             | 22. 信令断线重连                | PeerConnection 状态查询接口                                                                                                                                                                                                                                                                                                                                                                   | `SignalClient` <br>-> `WebSocket 重连`<br>-> `RTCEngine 处理ReconnectResponse`<br>-> `PeerConnectionTransport`                                                                                                                                                                                  | LiveKit SDK 文件<br>WebRTC `peer_connection.cc`                                                                                                                                                                                       | 恢复 LiveKit 信令连接                            |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`                                                                                                                    | `RTCEngine` 设置 ICE 重启流程，重新创建 SDP Offer 并重新发送 Candidate                                                                                                                                                              | 23. ICE Restart           | `createOffer()`<br>`setLocalDescription()`<br>`setRemoteDescription()`  <br>b<br>`PeerConnection.restartIce()`  <br>→ JNI  <br>→ `webrtc::PeerConnection::RestartIce()`  <br>→ `PeerConnection.createOffer()`  <br>→ JNI  <br>→ `webrtc::PeerConnection::CreateOffer()`  <br>→ `PeerConnection.setLocalDescription()`  <br>→ JNI  <br>→ `webrtc::PeerConnection::SetLocalDescription()` | `PeerConnection::RestartIce()` <br>-> `SdpOfferAnswerHandler`<br>->`JsepTransportController::SetNeedsIceRestartFlag()` <br>-> `JsepTransportController::MaybeStartGathering()` <br>-> `IceTransportInternal` <br>-> `p2p`                                                                   | `peer_connection.cc`<br>`sdp_offer_answer.cc`<br>`jsep_transport_controller.cc`<br>`ice_transport_internal.h`                                                                                                                       | 使用新的 ICE 参数和 Candidate 建立连接                |
| `room/Room.kt`<br>`room/RTCEngine.kt`<br>`room/participant/LocalParticipant.kt`<br>`room/participant/RemoteParticipant.kt`                                                  | 保存 Track 状态 <br>-> 重新加入房间 <br>-> 重新发布 Track <br>-> 恢复远端订阅                                                                                                                                                           | 24. 完整重连                  | `createPeerConnection()`<br>`addTransceiver()`<br>SDP/ICE 接口                                                                                                                                                                                                                                                                                                                            | -> `JNI`<br>->`PeerConnectionFactory::CreatePeerConnection()` <br>-> `PeerConnection`  `重新创建或重新配置`<br>-> `RtpSender` / `RtpReceiver` <br>-> `JsepTransportController`                                                                                                                       | `peer_connection_factory.cc`<br>`peer_connection.cc`<br>`jsep_transport_controller.cc`<br>`rtp_transmission_manager.cc`                                                                                                             | 恢复完整媒体会话                                   |
| `room/Room.kt`<br>`room/RTCEngine.kt`<br>`room/SignalClient.kt`                                                                                                             | `Room.disconnect()` <br>-> 停止 Track <br>-> 关闭 WebRTC Transport <br>-> 关闭信令                                                                                                                                          | 25. 退出房间                  | `PeerConnection.close()`                                                                                                                                                                                                                                                                                                                                                                | -> `JNI`<br>->`PeerConnection::Close()` <br>-> `RtpTransport` <br>-> `DtlsTransport` <br>-> `IceTransport` <br>-> `SctpTransport`                                                                                                                                                           | `peer_connection.cc`<br>`rtp_transport.cc`<br>`dtls_transport.cc`<br>`jsep_transport_controller.cc`<br>`sctp_transport.cc`                                                                                                          | 离开房间并关闭媒体连接                                |
| `room/Room.kt`<br>`room/RTCEngine.kt`<br>`room/track/*`                                                                                                                     | 释放 `Room`、`RTCEngine`、Track、音频设备、EGL、协程和工厂                                                                                                                                                                          | 26. SDK 全局销毁              | `PeerConnection.dispose()`<br>`PeerConnectionFactory.dispose()`                                                                                                                                                                                                                                                                                                                         | JNI <br>-> C++ `PeerConnection` 析构 <br>-> `PeerConnectionFactory` 析构                                                                                                                                                                                                                        | `peer_connection.cc`<br>`peer_connection_factory.cc`<br>`peer_connection_interface.h`                                                                                                                                               | 释放 SDK 全局资源                                |


是的，**“上行媒体发送/下行媒体接收”和“QoS 上行/下行”有重合**。建议：

- 上行媒体：只保留一条媒体发送链路。
- 下行媒体：只保留一条媒体接收、抖动缓存、解码链路。
- QoS：只描述反馈、统计和控制，不再重复媒体数据链路。

## 修正版相关表格




明白了。你是要**在原表格基础上，把这几行补全和修正**，不是重新设计一张新表。

下面保留你指定的 7 列，只修正相关内容：

| LiveKit 文件                                                                                                                                    | LiveKit 内部流程                                                                                                                                                               | 阶段                         | WebRTC Java 接口                                    | WebRTC C++ 调用链                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | WebRTC 文件                                                                                                                                                                     | 结果                                               |
| --------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- | ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`<br>`room/participant/LocalParticipant.kt`                                            | `RtpSender` 发送 RTP<br>`-> RtpSenderEgress` 记录发送包信息<br>`-> TransportFeedbackAdapter` 保存发送历史                                                                                 | 16. QoS：上行发送记录             | `RtpSender`<br>`RtpParameters`                    | `RtpSenderEgress::SendPacket()`<br>`-> TransportFeedbackAdapter::AddPacket()`<br>`-> 记录 Transport Sequence Number、发送时间、包大小、包类型`                                                                                                                                                                                                                                                                                                                                                                 | `rtp_sender_egress.cc`<br>`transport_feedback_adapter.cc`                                                                                                                     | 为远端 Transport-CC 反馈建立本地发送历史                      |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`                                                                                      | LiveKit 信令消息：<br>SignalClient.kt<br>-> PeerConnectionTransport.kt<br>-> PeerConnection.setRemoteDescription()<br>-> PeerConnection.addIceCandidate()                       | 17. QoS：上行反馈控制             | `PeerConnection` 的 RTCP 内部处理                      | `RTCPReceiver::IncomingPacket()`<br>`-> RTCPReceiver::ParseCompoundPacket()`<br>`-> RTCPReceiver::TriggerCallbacksFromRtcpPacket()`<br>`-> NetworkLinkRtcpObserver::OnTransportFeedback()`<br>`-> RtpTransportControllerSend::OnTransportFeedback()`<br>`-> TransportFeedbackAdapter::ProcessTransportFeedback()`<br>`-> RtpTransportControllerSend::HandleTransportPacketsFeedback()`<br>`-> GoogCcNetworkController::OnTransportPacketsFeedback()`<br>`-> PacingController::SetPacerConfig()` | `rtcp_receiver.cc`<br>`rtp_rtcp_defines.h`<br>`rtp_transport_controller_send.cc`<br>`transport_feedback_adapter.cc`<br>`goog_cc_network_control.cc`<br>`pacing_controller.cc` | 根据 SFU 返回的 RTCP 反馈调整本地目标码率、Pacer、Probe、RTX 和 FEC |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`<br>`room/participant/RemoteParticipant.kt`                                           | Subscriber PeerConnection 接收远端 RTP<br>`-> WebRTC 统计 RTP 接收质量`<br>`-> 生成 RR`<br>`-> 通过 WebRTC 媒体传输发送给 SFU`                                                                  | 18. QoS：下行接收统计和 RR 反馈      | `RtpReceiver`<br>`PeerConnection.Observer` 不生成 RR | `RtpReceiver`<br>`-> ReceiveStatistics`<br>`-> RTCPSender::SendCompoundPacket()`<br>`-> ReceiverReport`<br>`-> RtpTransport`<br>`-> SRTCP`<br>`-> ICE / UDP`<br>`-> LiveKit SFU`                                                                                                                                                                                                                                                                                                                | `receive_statistics_impl.cc`<br>`rtcp_sender.cc`<br>`receiver_report.cc`<br>`rtp_transport.cc`                                                                                | 向 SFU 报告下行丢包率、抖动、扩展最高序列号等接收质量                    |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`<br>`room/participant/RemoteParticipant.kt`                                           | Subscriber PeerConnection 接收带有 Transport Sequence Number 的 RTP<br>-> `接收端 Transport-CC 反馈生成器记录到达信息`<br>-> `RTCPSender 组装 Transport Feedback`<br>-> `通过 WebRTC 媒体传输发送给 SFU` | 19. QoS：下行 Transport-CC 反馈 | `RtpReceiver`<br>`PeerConnection` 内部生成 RTCP       | `RtpTransport`<br>`-> Transport-CC 接收反馈生成逻辑`<br>`-> RTCPSender`<br>`-> TransportFeedback`<br>`-> RtpTransport`<br>`-> SRTCP`<br>`-> ICE / UDP`<br>`-> LiveKit SFU`                                                                                                                                                                                                                                                                                                                              | `rtp_transport.cc`<br>`rtcp_sender.cc`<br>`transport_feedback.cc`                                                                                                             | 向 SFU 报告每个 RTP 包的到达时间和丢失情况                       |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`<br>`room/participant/LocalParticipant.kt`<br>`room/participant/RemoteParticipant.kt` | LiveKit 调用 WebRTC `getStats()`<br>-> `获取发送、接收和传输统计`<br>-> `返回 LiveKit 业务层`<br><br>`-> PeerConnectionTransport.kt`<br>`-> RTCEngine.kt`                                     | 20. QoS：统计导出               | `PeerConnection.getStats()`                       | -> `JNI`<br>->`PeerConnection::GetStats()`<br>`-> RTCStatsCollector::GetStats()`<br>`-> RtpSender / RtpReceiver / RtpTransport 统计对象`<br>`-> RTCStatsReport`<br>`-> JNI`<br>`-> WebRTC Java RTCStatsReport`<br>`-> PeerConnectionTransport.kt`<br>`-> RTCEngine.kt`                                                                                                                                                                                                                              | `peer_connection.cc`<br>`rtc_stats_collector.cc`<br>`transport_stats.cc`<br>`rtp_sender_egress.cc`<br>`receive_statistics_impl.cc`                                            | 统计结果返回 LiveKit Android 业务层                       |

需要特别修正的地方：

```text
RtpSenderEgress
    不直接调用 RTCPReceiver
```

正确关系是两条输入汇合到 QoS：

```text
RtpSenderEgress::SendPacket()
    -> TransportFeedbackAdapter::AddPacket()

RTCPReceiver::IncomingPacket()
    -> RtpTransportControllerSend::OnTransportFeedback()
    -> TransportFeedbackAdapter::ProcessTransportFeedback()
```

另外：

```text
下行媒体
    -> RtpReceiver
    -> ReceiveStatistics
    -> 抖动缓存
    -> 解码器
```

和：

```text
下行反馈
    -> ReceiveStatistics
    -> RTCPSender
    -> RR / Transport-CC
    -> SRTCP
    -> ICE / UDP
    -> LiveKit SFU
```

是两条不同方向的链路。`ReceiveStatistics` 同时为下行媒体质量统计和下行 RTCP 反馈提供数据。



## 最终应该保留的三条主线

### 1. 上行媒体

```text
LocalVideoTrack / LocalAudioTrack
    -> MediaStreamTrack
    -> RtpSender
    -> VideoSendStream / AudioSendStream
    -> RTPSenderVideo / RTPSenderAudio
    -> RtpSenderEgress::SendPacket()
    -> PacingController::EnqueuePacket()
    -> RTP / SRTP
    -> LiveKit SFU
```

### 2. 下行媒体

```text
LiveKit SFU
    -> RTP / SRTP
    -> RtpTransport
    -> RtpReceiver
    -> VideoReceiveStream
    -> VCMReceiver::Decode()
    -> VCMJitterBuffer::ExtractAndSetDecode()
    -> VCMFrameBuffer::PrepareForDecode()
    -> VideoDecoder::Decode()
    -> RemoteVideoTrack
```

### 3. QoS 闭环

```text
上行发送记录：
RtpSenderEgress::SendPacket()
    -> TransportFeedbackAdapter::AddPacket()

下行 RTCP 反馈：
RTCPReceiver::IncomingPacket()
    -> RtpTransportControllerSend::OnTransportFeedback()
    -> TransportFeedbackAdapter::ProcessTransportFeedback()
    -> GoogCcNetworkController::OnTransportPacketsFeedback()
    -> PacingController::SetPacerConfig()
    -> RtpSenderEgress::SendPacket()
```

下行接收质量反馈则是另一条方向：

```text
RtpReceiver
    -> ReceiveStatistics
    -> RTCPSender
    -> ReceiverReport / TransportFeedback
    -> SRTCP
    -> ICE / UDP
    -> LiveKit SFU
```

所以建议不要再使用：

```text
21. 实时 QoS-上行媒体
21.2 实时 QoS-下行媒体
```

改成：

```text
14. 上行媒体发送
15. 下行媒体接收
16. QoS：上行发送记录
17. QoS：上行反馈控制
18. QoS：下行接收统计
19. QoS：下行 Transport-CC 反馈
20. QoS：统计导出
```

这样媒体数据流和 QoS 控制流就不会混在一起。



你的表格需要修正两点：

1. **上行 QoS 不能写成** `RtpSender -> RtpSenderEgress -> RTCPReceiver`，因为 `RTCPReceiver` 是接收远端 RTCP，和本地 RTP 发送记录是两条输入，最后在 QoS 控制器处汇合。
2. **下行 RTCP 反馈不能写成** `PacketFeedback -> RTCPSender`。`RR` 主要来自接收统计；Transport-CC 来自接收端逐包到达反馈，两者生成路径不同。

建议使用下面这张表：

| LiveKit 文件                                                                                                                                    | LiveKit 内部流程                                                                                              | 阶段                             | WebRTC Java 接口                                                                          | WebRTC C++ 调用链                                                                                                                                                                                                                                                                                                                                                                                                             | WebRTC 文件                                                                                                                                                                                                                           | 结果                                   |
| --------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------ | --------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| `room/RTCEngine.kt`<br>`room/participant/LocalParticipant.kt`<br>`room/PeerConnectionTransport.kt`                                            | `LocalParticipant.publishTrack()`<br>`-> RTCEngine.addTrack()`<br>`-> PeerConnectionTransport.addTrack()` | 21.1 实时 QoS：上行媒体发送             | `PeerConnection.addTransceiver()`<br>`RtpSender`<br>`RtpParameters`                     | `RtpSender`<br>`-> RTPSenderVideo / RTPSenderAudio`<br>`-> RtpSenderEgress::SendPacket()`<br>`-> PacingController::EnqueuePacket()`<br>`-> RtpSenderEgress::SendPacket()`                                                                                                                                                                                                                                                  | `rtp_video_sender.cc`<br>`audio_send_stream.cc`<br>`rtp_sender_video.cc`<br>`rtp_sender_audio.cc`<br>`rtp_sender_egress.cc`<br>`pacing_controller.cc`                                                                               | 本地媒体编码后通过 RTP/SRTP 发送到 LiveKit SFU   |
| `room/RTCEngine.kt`<br>`room/participant/LocalParticipant.kt`<br>`room/PeerConnectionTransport.kt`                                            | `LocalParticipant.publishTrack()`<br>`-> RTCEngine.addTrack()`<br>`-> PeerConnectionTransport.addTrack()` | 21.1 实时 QoS：上行发送记录             | `RtpSender`<br>`RtpParameters`                                                          | `RtpSenderEgress`<br>`-> TransportFeedbackAdapter::AddPacket()`<br>`-> 记录 Transport Sequence Number、发送时间、包大小和包类型`                                                                                                                                                                                                                                                                                                          | `modules/rtp_rtcp/source/rtp_sender_egress.cc`<br>`modules/congestion_controller/rtp/transport_feedback_adapter.cc`                                                                                                                 | 为后续 Transport-CC 反馈匹配发送历史            |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`                                                                                      | `PeerConnectionTransport` 接收远端 RTCP 反馈                                                                    | 21.1 实时 QoS：上行 RTCP 输入         | `PeerConnection.Observer` 不负责 QoS 数据；RTCP 在 WebRTC C++ 内部处理                             | `RTCPReceiver::IncomingPacket()`<br>`-> RTCPReceiver::ParseCompoundPacket()`<br>`-> RTCPReceiver::TriggerCallbacksFromRtcpPacket()`<br>`-> NetworkLinkRtcpObserver::OnTransportFeedback()`<br>`-> RtpTransportControllerSend::OnTransportFeedback()`<br>`-> TransportFeedbackAdapter::ProcessTransportFeedback()`<br>`-> GoogCcNetworkController::OnTransportPacketsFeedback()`<br>`-> PacingController::SetPacerConfig()` | `rtcp_receiver.cc`<br>`rtp_rtcp_defines.h`<br>`rtp_transport_controller_send.cc`<br>`transport_feedback_adapter.cc`<br>`goog_cc_network_control.cc`<br>`pacing_controller.cc`                                                       | 根据远端反馈调整本地目标码率、Pacer、Probe、RTX 和 FEC |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`<br>`room/participant/RemoteParticipant.kt`                                           | `RemoteParticipant` 收到远端轨道信息；Subscriber `PeerConnectionTransport` 接收媒体                                    | 21.2 实时 QoS：下行媒体接收             | `PeerConnection.Observer.onAddTrack()`<br>`RtpReceiver`<br>`VideoTrack`<br>`AudioTrack` | `RtpTransport`<br>`-> RtpReceiver`<br>`-> VideoReceiveStream / AudioReceiveStream`<br>`-> VCMReceiver::Decode()`<br>`-> VCMJitterBuffer::ExtractAndSetDecode()`<br>`-> VCMFrameBuffer::PrepareForDecode()`<br>`-> VideoDecoder::Decode()`                                                                                                                                                                                  | `rtp_transport.cc`<br>`video_receive_stream.cc`<br>`audio_receive_stream.cc`<br>`receiver.cc`<br>`jitter_buffer.cc`<br>`frame_buffer.cc`<br>`modules/video_coding/video_decoder.cc`<br>`modules/video_coding/codecs/*/*_decoder.cc` | 接收 RTP，经过抖动缓存后解码并渲染                  |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`<br>`room/participant/RemoteParticipant.kt`                                           | Subscriber `PeerConnectionTransport` 接收远端媒体；LiveKit 业务层接收 `onAddTrack()` 结果                               | 21.2 实时 QoS：下行 RR 反馈           | `PeerConnection.Observer.onAddTrack()`<br>`RtpReceiver`                                 | `RtpReceiver` 接收 RTP<br>`-> ReceiveStatistics`<br>`-> RTCPSender`<br>`-> ReceiverReport`<br>`-> RtpTransport`<br>`-> SRTCP`<br>`-> ICE/UDP`<br>`-> LiveKit SFU`                                                                                                                                                                                                                                                            | `receive_statistics_impl.cc`<br>`rtcp_sender.cc`<br>`receiver_report.cc`<br>`rtp_transport.cc`                                                                                                                                      | 向 SFU 报告丢包率、抖动、最高序列号等接收质量            |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`<br>`room/participant/RemoteParticipant.kt`                                           | Subscriber `PeerConnectionTransport` 接收远端 RTP，并生成逐包到达反馈                                                   | 21.2 实时 QoS：下行 Transport-CC 反馈 | `PeerConnection.Observer` 不直接处理 Transport-CC                                            | `RtpTransport`<br>`-> RTP 接收处理`<br>`-> Transport Feedback 生成器`<br>`-> RTCPSender`<br>`-> TransportFeedback`<br>`-> RtpTransport`<br>`-> SRTCP`<br>`-> ICE/UDP`<br>`-> LiveKit SFU`                                                                                                                                                                                                                                         | `rtp_transport.cc`<br>`rtcp_sender.cc`<br>`transport_feedback.cc`                                                                                                                                                                   | 向 SFU 报告每个 RTP 包的到达时间和丢失情况           |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`<br>`room/participant/LocalParticipant.kt`<br>`room/participant/RemoteParticipant.kt` | LiveKit 调用 WebRTC `getStats()`，读取发送、接收和连接统计                                                               | 21.3 实时 QoS：统计导出               | `PeerConnection.getStats()`                                                             | `PeerConnection::GetStats()`<br>`-> RTCStatsCollector::GetStats()`<br>`-> RtpSender/RtpReceiver/Transport 统计对象`<br>`-> RTCStatsReport`<br>`-> JNI`<br>`-> WebRTC Java RTCStatsReport`                                                                                                                                                                                                                                      | `peer_connection.cc`<br>`rtc_stats_collector.cc`<br>`rtc_stats_collector.h`<br>`transport_stats.cc`                                                                                                                                 | 将统计报告返回给 LiveKit Android 业务层         |
| `room/RTCEngine.kt`<br>`room/PeerConnectionTransport.kt`<br>`room/participant/LocalParticipant.kt`<br>`room/participant/RemoteParticipant.kt` | 发送统计和接收统计分别进入 WebRTC 统计收集器                                                                                | 21.3 统计：上行和下行数据来源              | `PeerConnection.getStats()`                                                             | 上行：`RtpSenderEgress`<br>`-> RTCStatsCollector`<br><br>下行：`RtpReceiver`<br>`-> ReceiveStatistics`<br>`-> RTCStatsCollector`<br><br>连接级：`RtpTransport`<br>`-> TransportStats`<br>`-> RTCStatsCollector`                                                                                                                                                                                                                      | `rtp_sender_egress.cc`<br>`receive_statistics_impl.cc`<br>`transport_stats.cc`<br>`rtc_stats_collector.cc`                                                                                                                          | 统计同时包含上行、下行和连接级数据，不属于单独的下行链路         |

## 三条主线应这样记

### 上行媒体和 QoS

```text
本地 Track
    -> RtpSender
    -> RtpSenderEgress
    -> PacingController
    -> RTP/SRTP
    -> LiveKit SFU
```

远端反馈从另一条路径进入：

```text
LiveKit SFU
    -> RTCP
    -> RTCPReceiver
    -> RtpTransportControllerSend
    -> TransportFeedbackAdapter
    -> GoogCcNetworkController
    -> PacingController
    -> 本地 RTP 发送
```

所以不能连接成：

```text
RtpSenderEgress
    -> RTCPReceiver
```

而应该理解为两条输入：

```text
RtpSenderEgress
    -> TransportFeedbackAdapter

RTCPReceiver
    -> RtpTransportControllerSend
    -> TransportFeedbackAdapter
```

### 下行媒体

```text
LiveKit SFU
    -> RTP/SRTP
    -> RtpTransport
    -> RtpReceiver
    -> VideoReceiveStream
    -> VCMReceiver::Decode()
    -> VCMJitterBuffer::ExtractAndSetDecode()
    -> VCMFrameBuffer::PrepareForDecode()
    -> VideoDecoder::Decode()
```

### 下行反馈

```text
接收 RTP
    -> ReceiveStatistics
    -> RTCPSender
    -> Receiver Report
    -> SRTCP
    -> ICE/UDP
    -> LiveKit SFU
```

Transport-CC 是另一类 RTCP 反馈：

```text
接收 RTP
    -> 逐包到达反馈生成
    -> RTCPSender
    -> TransportFeedback
    -> SRTCP
    -> ICE/UDP
    -> LiveKit SFU
```

## JNI 的位置

媒体 RTP、RTCP 和 QoS 内部处理不经过 JNI：

```text
C++ RTP/RTCP/QoS
    -> SRTCP/SRTP
    -> ICE/UDP
    -> LiveKit SFU
```

只有控制和统计结果需要返回 Android/LiveKit 时才经过 JNI：

```text
LiveKit Kotlin
    -> org.webrtc.PeerConnection.getStats()
    -> JNI
    -> C++ RTCStatsCollector
    -> JNI
    -> WebRTC Java RTCStatsReport
    -> PeerConnectionTransport.kt
    -> RTCEngine.kt
    -> LiveKit 业务层
```

另外，`PeerConnection.Observer` 主要接收状态和轨道回调，例如 `onAddTrack()`、`onIceConnectionChange()`，**它不是 QoS 数据传输接口**。



## 关键链路

### LiveKit 信令链路

```text
Room
    -> RTCEngine
        -> SignalClient
            -> WebSocket
                -> LiveKit Server / SFU
```

LiveKit 信令传递：

```text
JoinRequest
JoinResponse
SDP Offer
SDP Answer
ICE Candidate
TrackPublished
TrackSubscribed
ReconnectRequest
```

### SDP 执行链路

```text
PeerConnectionTransport
    -> org.webrtc.PeerConnection
        -> JNI
            -> webrtc::PeerConnection
                -> SdpOfferAnswerHandler
                    -> SessionDescription
                    -> JsepTransportController
```

### ICE Restart 链路

```text
PeerConnection::RestartIce()
    -> SdpOfferAnswerHandler
```

```text
ICE Restart
    -> JsepTransportController::SetNeedsIceRestartFlag()
    -> JsepTransportController::MaybeStartGathering()
    -> IceTransportInternal
    -> p2p
```

### 视频接收链路

```text
RtpTransport::OnReadPacket()
    -> RtpReceiver
    -> VideoReceiveStream::OnCompleteFrame()
    -> VCMReceiver::Decode()
    -> VCMJitterBuffer::ExtractAndSetDecode()
    -> VCMFrameBuffer::PrepareForDecode()
    -> VideoDecoder::Decode()
```

其中：

- `VCMJitterBuffer` 是抖动缓存类。
- `VCMJitterBuffer::ExtractAndSetDecode()` 是取出待解码帧的函数。
- `VideoDecoder::Decode()` 是视频解码接口。
- `deprecated` 是当前工程中这条旧版 VCM 路径的实际目录。

### 音频接收链路

```text
AudioReceiveStream::DeliverRtp()
    -> AudioCodingModule::IncomingPacket()
    -> NetEq::InsertPacket()
    -> NetEq::GetAudio()
    -> AudioDecoder::Decode()
```

### QoS 链路

```text
RTCPReceiver
    -> NetworkLinkRtcpObserver
    -> RtpTransportControllerSend
    -> TransportFeedbackAdapter
    -> GoogCcNetworkController
    -> PacingController
    -> RtpSenderEgress
```

最终定位：

```text
LiveKit
    -> 房间、参与者、发布订阅、私有信令

PeerConnectionTransport
    -> LiveKit 对 org.webrtc.PeerConnection 的封装

org.webrtc.PeerConnection
    -> WebRTC Java API

JNI
    -> Java 和 C++ 的桥接

webrtc::PeerConnection
    -> WebRTC C++ 总入口

SdpOfferAnswerHandler
    -> SDP 协商执行

JsepTransportController
    -> RTP、DTLS、ICE、SCTP 传输协调

Call
    -> 音视频运行时

RTP / RTCP / GoogCC / Pacer
    -> 媒体传输、反馈、带宽估计和发送调度
```