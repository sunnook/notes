


┌─────────────────────────────────────────────┐
│               RoomImpl (Room.kt)            │  对外API门面，房间业务总控
│  ┌───────────────────────────────────────┐  │
│  │  val signalClient: SignalClient       │──┼───► SignalClient.kt（信令WebSocket TCP）
│  ├───────────────────────────────────────┤  │
│  │  val participantManager: ParticipantManager │──► ParticipantManager.kt 用户/参与者状态管理
│  ├───────────────────────────────────────┤  │
│  │  val trackManager: TrackManager       │──┼───► TrackManager.kt 轨道管理（本地/远端音视频）
│  ├───────────────────────────────────────┤  │
│  │  val reconnectManager: ReconnectManager │──► ReconnectManager.kt 断线重连
│  ├───────────────────────────────────────┤  │
│  │  val e2eeManager: E2EEManager         │──┼───► E2EEManager.kt 端到端加密
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘




        ▲
        │  Factory.create() 返回给上层App
        │
App ViewModel / Activity

//--------------------------------------------------------------------------------
// TrackManager 内部继续持有 WebRTC底层封装
TrackManager (TrackManager.kt)
 ├─ val peerConnectionFactory: PeerConnectionFactory  // WebRTC全局单例，C++大工厂
 ├─ 管理多个 PeerConnection 实例  ←────── WebRTC原生(WebRTC‑C++层)
 ├─ 管理 LocalAudioTrack / LocalVideoTrack
 └─ 管理 RemoteAudioTrack / RemoteVideoTrack

//--------------------------------------------------------------------------------
// SignalClient(SignalClient.kt)：只负责信令通道(TCP‑WebSocket)
SignalClient
 ├─ WebSocket 连接
 ├─ 收发Join / Publish / Unpublish / SDP / ICE 控制信令
 └─ 收到信令事件 → 回调分发回 RoomImpl → 再派给各个Manager

//--------------------------------------------------------------------------------
// WebRTC底层（C++，Kotlin只持有句柄）
PeerConnectionFactory(C++)
 ├─ 创建 PeerConnection(C++)
 ├─ 创建 AudioSource / VideoSource
 ├─ AudioDeviceModule：音频硬件管理
 └─ VideoCapturer：摄像头采集

PeerConnection(C++)
 ├─ SDP协商、ICE
 └─ RTP/RTCP媒体数据包（UDP，真正音视频流）