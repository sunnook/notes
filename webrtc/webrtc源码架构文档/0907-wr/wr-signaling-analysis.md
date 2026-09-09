# WebRTC 信令流程分析（M144 源码版）

> 定位：与《wr-api-analysis.md》第 12 节媒体分析对称的信令侧分析。媒体文档回答"**流怎么建起来、数据怎么流动**"，本文回答"**SDP 怎么协商、ICE 怎么连上、媒体为什么在 answer 落地后才开始跑**"。
>
> **行号标注约定**（与媒体文档一致）：`(:调用行)...(:实现行)` —— 前一个数字标调用点，后一个标函数体定义位置。
>
> ⚠️ **先说清"信令"的边界**：WebRTC 源码树里**没有**应用层信令服务器（WebSocket/信令消息收发是业务层的事，LiveKit 的 SignalClient 在 LiveKit SDK 里，不在本树）。本树里的"信令"= **两件事**：①SDP offer/answer 协商（JSEP）②ICE 候选交换（trickle）。本文就讲这两件事在源码里的完整链路。

---

## 〇、导读：一张图看懂信令全程

```
【协商前准备】(应用层负责传输，WebRTC 不管)
   App 通过 WebSocket 等把 offer/answer 和 ICE candidate 来回传 —— 源码树外

【本树内发生的事】(Offer 侧视角，Answer 侧对称)
  1. CreateOffer        → 生成本地 offer（SDP 文本）
  2. SetLocalDescription → offer 落位 + 创建 transport + 开始收集候选(trickle)
       └→ 候选收齐一批 → OnIceCandidate 回调 → 应用层发出去
  3. SetRemoteDescription(answer) → answer 落位 + 通道级参数确定 + 远端候选注入
  4. AddIceCandidate(远端候选) → 塞进 ICE transport 开始连通性检查
  5. ICE pair 检查通过 → writable → DTLS 握手 → 导出 SRTP 密钥
  6. 【交接点】UpdateSessionState 里 EnableSending() → 媒体通道 Enable
       —— 从这一步起进入 wr-api-analysis.md 第 12 节的"媒体两条线"

Offerer(主叫)                信令服务器                 Answerer(被叫)
    │                           │                          │
    │ CreateOffer               │                          │
    │ SetLocal(offer) 启动收集  │                          │
    │                           │                          │
    │─── offer ────────────────►│─── offer ──────────────►│ SetRemote(offer)
    │                           │                          │
    │ onicecandidate            │                          │
    │─── candidate#1 host ─────►│─── candidate#1 ────────►│ AddIceCandidate
    │─── candidate#2 srflx ────►│─── candidate#2 ────────►│ (注入，参与检查)
    │                           │                          │
    │                           │                          │ CreateAnswer
    │                           │                          │ SetLocal(answer)
    │                           │                          │ onicecandidate
    │                           │◄── answer ──────────────│
    │ SetRemote(answer)         │◄── candidate#A ──────────│
    │ AddIceCandidate           │◄── candidate#B ──────────│
    │                           │                          │
    │◄════ STUN 打洞（直连 UDP，不经信令）════►            │
    │   nominated → DTLS 握手 → SRTP 密钥 → 媒体双线       │

```

**信令和媒体的关系一句话**：信令 = **建管道**（协商参数 + 打通网络 + 交换密钥），媒体 = **管道里流的水**。`SdpOfferAnswerHandler::UpdateSessionState()` 里的 `EnableSending()`（pc/sdp_offer_answer.cc:3136 调用 / :5076 实现）是"管道通水"的开关——answer 落地那一刻媒体通道才 Enable，这就是为什么**媒体永远在 answer 之后才跑**。

---

## 一、线一：SDP 协商链路（CreateOffer → SetLocal → SetRemote → 状态机）

### 1.1 入口层（JNI → PeerConnection → SdpOfferAnswerHandler）

```
【0】JNI 层（Java 调用进来）
  sdk/android/src/jni/pc/peer_connection.cc:609  JNI_PeerConnection_CreateOffer
  :637 SetLocalDescriptionAutomatically   :645 SetLocalDescription
  :655 SetRemoteDescription               :702 AddIceCandidate
  统一动作：JavaToNativeSessionDescription 转换 → ExtractNativePC(jni, j_pc)->XXX(...)
  ▼
【1】pc/peer_connection.cc:1500  PeerConnection::CreateOffer(observer, options)
    RTC_DCHECK_RUN_ON(signaling_thread())   ← 信令操作全部锚定在信令线程
    → sdp_handler_->CreateOffer(...)        // :1503
  同族入口：CreateAnswer :1506 / SetLocalDescription :1512-1544（4 个重载）
            SetRemoteDescription :1550/:1562 / AddIceCandidate :1666
  ▼
【2】pc/sdp_offer_answer.cc:1641  SdpOfferAnswerHandler::CreateOffer(observer, options)
    → operations_chain_->ChainOperation(lambda)   // :1648
    —— OperationsChain（rtc_base/operations_chain.h:145）把 CreateOffer/
       CreateAnswer/SetLocal/SetRemote/AddIceCandidate 全部串行化：
       排队一个一个执行，前一个完成才轮到下一个。这是信令线程版的"消息队列"。
    → lambda 内 DoCreateOffer(options, observer_wrapper)  // :1666
```

**要点**：所有 SDP 操作先过 `OperationsChain` 串行化再执行——这就是为什么应用层乱序调 SetRemoteDescription/SetLocalDescription 不会把状态机搞乱：不是靠锁，是靠**排队**。这与媒体侧"任务投递到线程队列"是同一思想（呼应 wr-api-analysis.md 第 17 节串行机制）。

### 1.2 生成本地 SDP（DoCreateOffer → 工厂 → media_session）

```
【3】pc/sdp_offer_answer.cc:2658  SdpOfferAnswerHandler::DoCreateOffer
    校验（IsClosed/session_error/options）→ HandleLegacyOfferOptions → GetOptionsForOffer
    → webrtc_session_desc_factory_->CreateOffer(observer_wrapper.get(), options, session_options)  // :2720
  ▼
【4】pc/webrtc_session_description_factory.cc:194  WebRtcSessionDescriptionFactory::CreateOffer
    检查 DTLS 证书状态（certificate_request_state_）——证书没就绪就先入队等
    → InternalCreateOffer(request)  // :222（CERTIFICATE_WAITING 时 :220 入队延迟）
  ▼
【5】pc/webrtc_session_description_factory.cc:266  InternalCreateOffer
    处理 ICE restart 标记 → session_desc_factory_.CreateOfferOrError(...)  // :279
  ▼
【6】pc/media_session.cc:721  MediaSessionDescriptionFactory::CreateOfferOrError
    —— 真正"拼 SDP"的地方：遍历 media_description_options，
       每个 m= 行：编解码列表、RTP 扩展协商(extmap)、ICE ufrag/pwd、DTLS 指纹、BUNDLE
    生成 SessionDescription（纯内存结构，还不是文本）
  ▼
【7】回到 InternalCreateOffer：
    SessionDescriptionInterface::Create(SdpType::kOffer, ...) 封装 → o= 行版本号自增（RFC 3264）
    → PostCreateSessionDescriptionSucceeded(observer, offer)   // 回调成功（信令线程 Post）
    → 触发 observer OnSuccess → JNI 回 Java → 应用层拿到 offer 文本
```

**CreateAnswer 对称**：`SdpOfferAnswerHandler::CreateAnswer(:2722)` → `DoCreateAnswer(:2752)` → `WebRtcSessionDescriptionFactory::CreateAnswer(:225)` → `InternalCreateAnswer` → `MediaSessionDescriptionFactory::CreateAnswerOrError(pc/media_session.cc:838)`。区别：answer 必须逐项**接受/拒绝** offer 的每一项（编解码取交集、方向取收窄、ICE 凭据跟 offer 配对）。

### 1.3 本地/远端落位（SetLocalDescription / SetRemoteDescription → Apply）

```
【8】SdpOfferAnswerHandler::SetLocalDescription(:1707/:1736) → DoSetLocalDescription(:2471)
    → ApplyLocalDescription(std::move(desc), bundle_groups_by_mid)  // :2591 调用
  ▼
【9】pc/sdp_offer_answer.cc:1801  ApplyLocalDescription
    ├─ 本地 offer：CreateChannels(*local_description())  // :1927 调用
    │    （—— 即媒体文档 12.1 线一初始化链路从 JNI 走进来的真正源头，
    │       sdp_offer_answer.cc:5548 的那个 CreateChannels，这里调的）
    ├─ transceiver 绑 transport 槽位：LookupDtlsTransportByMid(...)
    │    → transceiver->sender_internal()->set_transport(dtls) / receiver 同理   // :1878-1880
    ├─ UpdateSessionState(type, CS_LOCAL, ...)  // :1937 调用
    └─ 返回后在 DoSetLocalDescription 尾部：
       transport_controller_s()->MaybeStartGathering()  // :2655 调用
       —— 候选收集从这里点火（见线二 2.1）
  ▼
【10】pc/sdp_offer_answer.cc:3123  UpdateSessionState —— 状态机核心
    ├─ type == kAnswer/kPrAnswer → EnableSending()  // :3136 调用
    │    —— 【交接点】媒体通道 Enable(true)，"通水"开关
    ├─ 按 W3C 状态机改 SignalingState：
    │    kOffer → kHaveLocalOffer(本地)/kHaveRemoteOffer(远端)   // :3142
    │    kAnswer → kStable                                       // :3151
    │  → ChangeSignalingState(...)  // :3105，触发 observer OnSignalingChange
    └─ PushdownMediaDescription(type, source, bundle_groups)  // :5090
        └─ PushdownTransportDescription(source, type)  // :5270
            └─ transport_controller_s()->SetLocalDescription/SetRemoteDescription
               —— 把 ICE 凭据(ufrag/pwd)、DTLS 指纹推给传输层（见线二 2.2）
```

**SetRemoteDescription 对称且多一步**：`SetRemoteDescription(:2056/:2089)` → `DoSetRemoteDescription(:2816)` → `ApplyRemoteDescription(:2146)`。M144 用 `RemoteDescriptionOperation` 操作对象把远端落位拆成 5 步（pc/sdp_offer_answer.cc）：

```
【11】ApplyRemoteDescription(:2146) 内的五步操作（按执行顺序）：
    ① ReplaceRemoteDescriptionAndCheckError()   // :1090 存储+校验远端 SDP
    ② UpdateChannels()                            // :1116 已有通道→按新 SDP 更新 SSRC/方向
    ③ UpdateSessionState()                        // :1144 同上，answer 时 EnableSending
    ④ UseCandidatesInRemoteDescription()          // :1154 SDP 里内嵌的候选逐个 UseCandidate
    ⑤ 收尾：ICE restart 检测 / kIceConnectionChecking 推进(:2213-2217)
       → operation->SignalCompletion()            // :2246 通知 observer OnSuccess
       → SetRemoteDescriptionPostProcess(type==kAnswer)  // :2248
           └─ answer 落位后：DiscardCandidatePool(:2849 阻塞切网络线程)
              + UpdateNegotiationNeeded(:2859) → 必要时 OnRenegotiationNeeded(:2864)
```

**五步为什么这么拆**：每步都可能失败且失败路径不同（SDP 非法→回滚、通道更新失败→恢复旧描述、状态推进失败→保持原态）。M144 用操作对象把"回滚语义"封装成成员函数，比 M80 前的巨型函数清晰——和 VideoReceiveStream2 重构是同一时期"拆责任"的思想（呼应 wr-api-analysis.md 第 21 节）。

---

## 二、线二：ICE 候选与连接建立链路

### 2.1 本地候选：收集 → 上报（trickle 上行）

```
【12】点火：DoSetLocalDescription 尾部
    transport_controller_s()->MaybeStartGathering()  // sdp_offer_answer.cc:2655 调用
  ▼
【13】pc/jsep_transport_controller.cc:414  JsepTransportController::MaybeStartGathering
    network_thread_->BlockingCall → MaybeStartGathering_n()  // :418/:422
    （信令线程 → 网络线程的 BlockingCall，一去一回）
    for 每个 dtls: dtls->ice_transport()->MaybeStartGathering()  // :425
  ▼
【14】p2p/base/p2p_transport_channel.cc:842  P2PTransportChannel::MaybeStartGathering
    ├─ 检查 ice_parameters_ ufrag/pwd 非空（SDP 没落位就没有凭据，收不了集）
    ├─ ICE 凭据变了（restart）→ 旧 allocator session 全部 StopGettingPorts
    └─ allocator_->TakePooledSession(...) 复用预分配会话；否则新建
       → 网卡枚举/host候选、STUN(srflx)、TURN(relay) 由 PortAllocator 体系
         （p2p/client/basic_port_allocator.cc）在后台跑，候选到一个回调一个
  ▼
【15】候选产出（网络线程）：
    P2PTransportChannel::OnCandidatesReady(:946)
    → NotifyCandidateGathered(this, candidate)     // p2p/base/ice_transport_internal.h:323
      → candidate_gathered_callbacks_.Send(transport, candidate)
    —— JsepTransportController::CreateIceTransport 时订阅（jsep_transport_controller.cc:526
       SubscribeCandidateGathered → OnTransportCandidateGathered_n）
  ▼
【16】回到 PeerConnection（网络线程→信令线程）：
    config.signal_ice_candidates_gathered 回调（pc/peer_connection.cc:759 定义注入）
    → signaling_thread()->PostTask → OnTransportControllerCandidatesGathered(t, c)  // :2561
    → 逐个候选：sdp_handler_->AddLocalIceCandidate(candidate)（塞进本地 SDP 存档 :2579）
    → OnIceCandidate(std::move(candidate))  // :2580 调用 → :2171 实现
    → RunWithObserver(observer->OnIceCandidate(candidate.get()))  // :2178
    —— 【trickle 上行出口】应用层在这个回调里把候选通过信令服务器发给对端
```

**trickle 的本质**：候选不等收齐（`gathering_state_ != kIceGatheringGathering` → Complete 还有收尾回调 :974），**收一个发一个**。SDP 里只有 ufrag/pwd 没有候选，候选全走旁路（OnIceCandidate 回调）——这就是 trickle ICE，比"等收齐再发"快一个 RTT 量级。

### 2.2 传输层建管道（PushdownTransportDescription → JsepTransportController）

```
【17】UpdateSessionState → PushdownMediaDescription(:5090) → PushdownTransportDescription(:5270)
    source==CS_LOCAL: transport_controller_s()->SetLocalDescription(type, local, remote)
    source==CS_REMOTE: transport_controller_s()->SetRemoteDescription(type, local, remote)
  ▼
【18】pc/jsep_transport_controller.cc:124  JsepTransportController::SetLocalDescription
    network_thread_->BlockingCall → SetLocalDescription_n(:138)
    ├─ 定 ICE 角色：offer 侧 ICEROLE_CONTROLLING，answer 侧 ICEROLE_CONTROLLED  // :147-153
    └─ ApplyDescription_n(local=true, ...)  // :155 调用 → :703 实现
  ▼
【19】ApplyDescription_n(:703) —— 按描述建 transport（网络线程）
    ├─ BUNDLE 处理：同组 m= 行共享第一条 transport（HandleBundledContent）
    ├─ 每个 m= 行（非 rejected、非 bundle 成员）：
    │    CreateDtlsTransport(content_info)  // :564 调用（内部先 CreateIceTransport :503）
    │    —— ICE transport（P2PTransportChannel）+ DTLS transport（包装成加密层）
    └─ 存进 map：mid → JsepTransport（RtpTransport/DtlsTransport/SctpTransport 聚合）
```

**注意**：transport 建在**网络线程**（BlockingCall 从信令线程切过去），但 m= 行对应的**媒体通道**建在 **worker 线程**（媒体文档里 RtpTransceiver::CreateChannel 的 BlockingCall）——**传输层归网络线程、媒体层归 worker 线程**，两边的 BlockingCall 汇聚点是信令线程。这是三线程模型在信令流程里的完整呈现。

### 2.3 远端候选注入与连通性检查（trickle 下行 → ICE → DTLS）

```
【20】trickle 下行入口：
    JNI_PeerConnection_AddIceCandidate(sdk/android/src/jni/pc/peer_connection.cc:702)
    → PeerConnection::AddIceCandidate(pc/peer_connection.cc:1666)
    → SdpOfferAnswerHandler::AddIceCandidate(sdp_offer_answer.cc:2967) → ChainOperation 排队
  ▼
【21】AddIceCandidateInternal(sdp_offer_answer.cc:2921)：
    ├─ 前置校验：IsClosed / remote_description 为空则拒 / ReadyToUseRemoteCandidate
    ├─ mutable_remote_description()->AddCandidate(...)  塞进远端 SDP 存档
    └─ UseCandidate(ice_candidate)  // :5418 调用
        → 校验 VerifyCandidate → pc_->AddRemoteCandidate(mid, c)
  ▼
【22】pc/peer_connection.cc:2786  PeerConnection::AddRemoteCandidate
    network_thread()->PostTask（非阻塞投递）→
    transport_controller_->AddRemoteCandidates(mid, candidates)
    （jsep_transport_controller.cc:429 → jsep_transport->AddRemoteCandidates →
     P2PTransportChannel 把远端候选加入 pair 队列，开始 STUN 绑定请求连通性检查）
    成功后回信令线程：ReportRemoteIceCandidateAdded + 若状态是 New/Disconnected
    → SetIceConnectionState(kIceConnectionChecking)   // :1959 实现
  ▼
【23】连通性检查通过（网络线程内）：
    P2PTransportChannel::OnConnectionStateChange(:2127) → 选路
    → SetWritable(true)  // :2289 —— pair 可写了！
       NotifyReadyToSend + NotifyWritableState —— 触发 DTLS 启动
  ▼
【24】DTLS 握手与 SRTP 密钥导出（网络线程）：
    DtlsTransport::OnInternalDtlsState(pc/dtls_transport.cc:113) → UpdateInformation → observer
    → DtlsSrtpTransport::OnDtlsState(pc/dtls_srtp_transport.cc:324) → MaybeSetupDtlsSrtp(:164)
       ├─ SetupRtpDtlsSrtp(:176)
       └─ ExtractParams(:230) —— RFC 5764/5705：
          dtls_transport->ExportSrtpKeyingMaterial(dtls_buffer)  // 从 DTLS 会话导出密钥
          → SetRtpParams(crypto_suite, send_key, recv_key)  装进 SRTP 加解密器
    —— 到这里管道三件套齐了：ICE(通了) + DTLS(握了) + SRTP(有钥匙了)
```

**重要**：`writable`（ICE 通）≠ 能发媒体。媒体发出去要过 SrtpTransport 加密（媒体文档视频上行链路最后一环 `RtpTransport::SendRtpPacket → SrtpTransport 加密`），而 SRTP 密钥**只有 DTLS 握完才有**。所以完整的"能发"= ICE writable **且** DTLS connected **且** 通道 Enable（answer 落位）。三条件缺一，表现为"SDP 都交换完了但没图像"——排障时分别查 ICE state、DTLS state、EnableSending 是否执行。

### 2.4 连接状态上报链

```
【25】网络线程 → 信令线程 → 应用层：
    P2PTransportChannel 状态变化（SetWritable :2289 等）
    → JsepTransportController 聚合所有 transport 的状态
    → config.signal_ice_connection_state 回调（pc/peer_connection.cc:770 定义注入）
    → PostTask → OnTransportControllerConnectionState(pc/peer_connection.cc:2502)
       聚合翻译：kIceConnectionConnecting 但当前是 Connected → 推成 Disconnected(:2516)
                kIceConnectionFailed → Failed(:2521)；全 writable → Connected(:2540)/Completed(:2552)
    → SetIceConnectionState(:1959) → observer->OnIceConnectionChange(...)
    —— 应用层 OnIceConnectionChange 回调就是这条链的末端
```

gathering 侧同构：`gathering_state_` 变化（:857-859 Gathering / :974 Complete）→ SendGatheringStateEvent → 上行聚合成 OnIceGatheringChange 回调。

---

## 三、状态机总览（三台状态机同时转）

| 状态机 | 谁改它 | 代表什么 | 关键代码 |
|---|---|---|---|
| **SignalingState** | `ChangeSignalingState`（sdp_offer_answer.cc:3105，只在 UpdateSessionState :3123 里调） | SDP 协商进度：Stable→HaveLocalOffer→(对端 answer)→Stable | offer 置 HaveLocalOffer/HaveRemoteOffer，answer 一律回 Stable |
| **IceConnectionState** | `SetIceConnectionState`（peer_connection.cc:1959） | 网络连通性：New→Checking→Connected/Completed / Disconnected / Failed | 由 transport 状态聚合翻译（:2502），不是直通 |
| **IceGatheringState** | P2PTransportChannel 内部 + PeerConnection 聚合 | 本地候选收集进度：New→Gathering→Complete | :857/:974 + SendGatheringStateEvent |
| （第四台）PeerConnectionState | 标准化聚合（ICE+DTLS 合并的 standardized state） | W3C 规范版连接状态 | SetStandardizedIceConnectionState(:1984 起) 等 |

**为什么 answer 一定是 Stable**：UpdateSessionState 对 kAnswer 无条件 `ChangeSignalingState(kStable)`（:3151）——W3C 状态机如此：一轮协商完成回到稳定态，下一轮 renegotiation 从 Stable 重新出发。`SetRemoteDescriptionPostProcess` 里紧接着检查 `is_negotiation_needed`（:2859），需要就再触发一轮——renegotiation 不是新机制，就是状态机再转一圈。

---

## 四、线程视角（信令流程跨线程图）

```
信令线程（所有 SDP 操作的锚）
 ├─ OperationsChain 串行化（ChainOperation 排队）
 ├─ DoCreateOffer / DoSetLocal / DoSetRemote —— 全程信令线程
 │    ├─ BlockingCall→网络线程：MaybeStartGathering / SetLocalDescription(transport)
 │    │   （jsep_transport_controller.cc:124-133 等，推 ICE 凭据/建 transport）
 │    ├─ BlockingCall→worker 线程：CreateChannels → RtpTransceiver::CreateChannel
 │    │   （媒体文档 12.1 线一，通道建在 worker）
 │    └─ ←PostTask 回信令线程：候选产出(signal_ice_candidates_gathered :759)
 │        ICE 状态(signal_ice_connection_state :770) → observer 回调全在信令线程
网络线程（transport 全家）
 ├─ ApplyDescription_n 建 ICE/DTLS transport
 ├─ PortAllocator 收候选 → OnCandidatesReady → 回调上行
 ├─ pair 连通性检查 → SetWritable → DTLS 握手 → SRTP 密钥导出（全程网络线程）
worker 线程（媒体通道）
 └─ EnableSending(:5076) → channel->Enable(true) —— answer 落位那一刻的动作
```

三个观察：
1. **信令流程是"信令线程主导 + 两处 BlockingCall 下沉"**：transport 操作下沉网络线程、通道创建下沉 worker 线程，都阻塞等结果（协商期可以阻塞，媒体期不行——这是信令与媒体在线程策略上的本质区别）。
2. **所有对应用层的回调（OnIceCandidate/OnIceConnectionChange/OnSuccess）都在信令线程**——JNI 回 Java 不会碰媒体线程。
3. **ICE/DTLS/SRTP 全程网络线程自治**：一旦启动，pair 检查、重连、DTLS 重握手不需要信令线程参与；信令线程只在 trickle 候选进来时投递一下。

---

## 五、与媒体文档的衔接点（两份文档怎么拼成闭环）

| 位置 | 衔接内容 |
|---|---|
| `ApplyLocalDescription` 内 `CreateChannels`（sdp_offer_answer.cc:1927 调用 → :5548 实现） | **媒体文档 12.1"线一初始化链路"的真正起点**。媒体文档从 JNI SetRemoteDescription 讲起，本文补全了它之前（CreateOffer/DoCreateOffer/拼 SDP）和内部（OperationsChain/状态机）的部分。 |
| `UpdateSessionState` → `EnableSending`（:3136 → :5076） | **媒体的"通水"开关**。媒体文档所有流处理链路的前提是通道已 Enable——这个 Enable 发生在 answer 落位。 |
| `PushdownTransportDescription` → `JsepTransportController::SetLocalDescription`（:5270 → jsep_transport_controller.cc:124） | **媒体文档视频上行链路末端 `RtpTransport::SendRtpPacket` 的 RtpTransport 从哪来**：ApplyDescription_n(:703) 按 m= 行建出来的，BUNDLE 组共享一条。 |
| `DtlsSrtpTransport::ExtractParams`（:230，ExportSrtpKeyingMaterial） | **媒体文档"RtpTransport → SrtpTransport 加密"的密钥来源**。没有这一步，媒体包在 SrtpTransport 就发不出去。 |

**读完顺序建议**：本文线一（SDP 怎么来怎么落位）→ 本文 2.2（transport 怎么建）→ 媒体文档 12.1 线一（通道和流怎么建）→ 媒体文档线二（数据怎么流）→ 本文线二 2.3（网络怎么通、密钥怎么换）——五段拼起来 = 从 `pc.createOffer()` 到第一个视频帧渲染的完整工程链。

---

## 六、常见误读澄清（对照源码）

1. **"信令服务器在 WebRTC 里"** —— 错。源码树边界在"SDP 文本/候选对象进出 PeerConnection 接口"处，WebSocket 传输是业务层（LiveKit SignalClient 等）。本文档全部内容都在边界之内。
2. **"SetRemoteDescription 触发建通道"** —— 不精确。**本地 offer 落位（SetLocalDescription(offer)）时就 CreateChannels**（ApplyLocalDescription :1927，type==kOffer 分支）；远端 answer 只更新方向/SSRC（UpdateChannels），不再建新通道。媒体文档初始化链路以 SetRemoteDescription 为 JNI 入口示例，实际触发建通道的是本地侧的 offer 落位。
3. **"ICE 候选收集要等收齐"** —— 错，trickle 收一个发一个（OnCandidatesReady → OnIceCandidate 逐个回调），SDP 里根本没有候选。
4. **"ICE 通了就能发媒体"** —— 错。要 ICE writable **且** DTLS 握完 **且** SRTP 密钥装好 **且** answer 落位 EnableSending，四件事。
5. **"信令操作靠锁保护"** —— 错。靠 OperationsChain 排队（串行化），锁只出现在 BlockingCall 边界内部。"排队代替加锁"是 WebRTC 的通用哲学（呼应媒体文档任务队列机制）。
6. **"signaling state 由 ICE 决定"** —— 错。SignalingState 只由 SDP 协商事件驱动（UpdateSessionState），ICE 再怎么变化不影响它——两台状态机独立。

---

## 七、行号速查表（信令流程全部锚点）

| 环节 | 文件:行 |
|---|---|
| JNI CreateOffer / SetLocal / SetRemote / AddIceCandidate | sdk/android/src/jni/pc/peer_connection.cc:609 / :637-645 / :655 / :702 |
| PeerConnection::CreateOffer / SetRemoteDescription / AddIceCandidate | pc/peer_connection.cc:1500 / :1550 / :1666 |
| SdpOfferAnswerHandler::CreateOffer / DoCreateOffer | pc/sdp_offer_answer.cc:1641 / :2658 |
| OperationsChain::ChainOperation | rtc_base/operations_chain.h:145 |
| WebRtcSessionDescriptionFactory::CreateOffer / InternalCreateOffer | pc/webrtc_session_description_factory.cc:194 / :266 |
| MediaSessionDescriptionFactory::CreateOfferOrError（真正拼 SDP） | pc/media_session.cc:721（Answer :838） |
| SdpOfferAnswerHandler::SetLocalDescription / DoSetLocalDescription | pc/sdp_offer_answer.cc:1707/:1736 / :2471 |
| ApplyLocalDescription / CreateChannels 调用点 / MaybeStartGathering 调用点 | pc/sdp_offer_answer.cc:1801 / :1927 / :2655 |
| SetRemoteDescription / DoSetRemoteDescription / ApplyRemoteDescription | pc/sdp_offer_answer.cc:2056/:2089 / :2816 / :2146 |
| RemoteDescriptionOperation 五步 | pc/sdp_offer_answer.cc:1090/:1116/:1144/:1154 |
| UpdateSessionState（状态机）/ ChangeSignalingState / EnableSending | pc/sdp_offer_answer.cc:3123 / :3105 / :5076（调用 :3136） |
| PushdownMediaDescription / PushdownTransportDescription | pc/sdp_offer_answer.cc:5090 / :5270 |
| JsepTransportController::SetLocalDescription / ApplyDescription_n | pc/jsep_transport_controller.cc:124 / :703 |
| CreateIceTransport / CreateDtlsTransport | pc/jsep_transport_controller.cc:503 / :564 |
| MaybeStartGathering / MaybeStartGathering_n | pc/jsep_transport_controller.cc:414 / :422 |
| P2PTransportChannel::MaybeStartGathering / OnCandidatesReady / SetWritable | p2p/base/p2p_transport_channel.cc:842 / :946 / :2289 |
| NotifyCandidateGathered（候选回调分发） | p2p/base/ice_transport_internal.h:323 |
| signal_ice_candidates_gathered / signal_ice_connection_state 注入 | pc/peer_connection.cc:759 / :770 |
| OnTransportControllerCandidatesGathered / OnIceCandidate | pc/peer_connection.cc:2561 / :2171 |
| PeerConnection::AddRemoteCandidate / SetIceConnectionState / OnTransportControllerConnectionState | pc/peer_connection.cc:2786 / :1959 / :2502 |
| SdpOfferAnswerHandler::AddIceCandidate / AddIceCandidateInternal / UseCandidate | pc/sdp_offer_answer.cc:2967 / :2921 / :5418 |
| JsepTransportController::AddRemoteCandidates | pc/jsep_transport_controller.cc:429 |
| DtlsTransport::OnInternalDtlsState | pc/dtls_transport.cc:113 |
| DtlsSrtpTransport::OnDtlsState / MaybeSetupDtlsSrtp / SetupRtpDtlsSrtp / ExtractParams | pc/dtls_srtp_transport.cc:324 / :164 / :176 / :230 |

> 以上行号全部在 M144 源码逐个核对过（2026-09-08）。核对方法与媒体文档相同：先 `grep -n` 定位函数定义行，再读函数体确认调用点行——区分"调用行"与"定义行"，声明行不当调用点。

---

## 八、【LiveKit → libwebrtc 分阶段调用流程图】

> 定位：把前七节讲的 libwebrtc 信令机制，放回真实工程的调用现场——LiveKit Android SDK 怎么驱动它。
> LiveKit 代码路径：`client-sdk-android-main/livekit-android-sdk/src/main/java/io/livekit/android/`（示意，以你 clone 的版本为准）；libwebrtc 路径为仓库相对路径，行号全部在 M144 源码核对过（2026-09-09）。
>
> **总览**：LiveKit 客户端持有**两条** PeerConnection——`publisher`（上行，客户端发 offer）与 `subscriber`（下行，SFU 发 offer、客户端答）。SDP 与 ICE 候选不直接传输，而是经 `SignalClient`（WebSocket + protobuf）与 LiveKit SFU 中转。所以第〇节那张总览图里的"应用层负责传输"在 LiveKit 里的实体就是 SignalClient。
>
> **线程约定**：SDP 操作全程锚定信令线程（OperationsChain 串行）；transport 操作下沉网络线程；通道创建与 Enable 下沉 worker 线程；所有对 Java 的回调都回信令线程。

### 8.1 两个前置问题（先厘清再读图）

**Q1：`PeerConnection::SetLocalDescription` 4 个重载（pc/peer_connection.cc:1512-1544），JNI 路径走哪个？**

| 重载 | 行 | 签名要点 | JNI 是否走 |
|---|---|---|---|
| :1512 | `(SetSessionDescriptionObserver*, SessionDescriptionInterface*)` | 老式 observer + **显式 desc** | ✅ `JNI_PeerConnection_SetLocalDescription`(:645) → `SetLocalDescription(JavaToNativeSessionDescription(...), observer)` |
| :1525 | `(unique_ptr<desc>, SetLocalDescriptionObserverInterface)` | 新式 observer 接口 + 显式 desc | ❌（新 C++ API 用） |
| :1538 | `(SetSessionDescriptionObserver*)` | **不传 desc**（自动取 implicit） | ✅ `JNI_PeerConnection_SetLocalDescriptionAutomatically`(:637) → `SetLocalDescription(observer)` |
| :1544 | `(SetLocalDescriptionObserverInterface)` | 新式 observer，不传 desc | ❌ |

Java 层两个入口对应（sdk/android/api/org/webrtc/PeerConnection.java）：
- `setLocalDescription(observer)`(:909) → nativeSetLocalDescriptionAutomatically → JNI :637 → **:1538**
- `setLocalDescription(observer, sdp)`(:913) → nativeSetLocalDescription → JNI :645 → **:1512**

LiveKit 的 `CoroutineSdpObserver.kt:157` 走 **:1512**（显式带 sdp）。":1538/:1544 自动版"是给"引擎自己拿最近一次 CreateOffer/CreateAnswer 结果"的用法，LiveKit 没用。

**Q2：CreateOffer 之后的 CreateAnswer/SetLocal/SetRemote/AddIceCandidate 是被 CreateOffer"串联调用"的吗？**

**不是串联调用，是排队串行**。`ChainOperation(:1648)` 只把当前操作的 lambda 塞进 `OperationsChain` 队列；每个操作（CreateOffer/CreateAnswer/SetLocal/SetRemote/AddIceCandidate）**各自**入队。队列保证：同一时刻只执行一个操作，前一个 lambda **执行完毕（SignalCompletion）后才 pop 下一个**。所以准确说法是"这些操作被排成一条队，一个完成才轮到下一个"——不是 CreateOffer 内部去调用它们。它们的先后顺序由应用层（LiveKit 业务代码）自己编排。

**Q3：libwebrtc 与 LiveKit 各自的边界**：WebSocket 传输、offerId 管理、SDP munging、候选缓冲兜底全在 LiveKit；JSEP 状态机、SDP 生成/校验、transport/通道创建、ICE/DTLS/SRTP 全在 libwebrtc。分界线就是 `org.webrtc.PeerConnection` 的公开方法。

### 8.2 分阶段调用流程图

```
════════════════════════════════════════════════════════════
阶段① 建连（Room.connect → PeerConnection 创建完成）
════════════════════════════════════════════════════════════
Room::connect(url, token, options)
├─ Room::connect 【src/main/java/io/livekit/android/room/Room.kt:461】
│   └─ RTCEngine::join(url, token, options, roomOptions) 【Room.kt:544 调用 → RTCEngine.kt:235 定义】
│       └─ RTCEngine::joinImpl 【src/main/java/io/livekit/android/room/RTCEngine.kt:250】
│           ├─ SignalClient::join 【SignalClient.kt:138 定义】
│           │   └─ SignalClient::connect 【SignalClient.kt:138 内调用 → :167 定义】
│           │       └─ WebSocket 连 LiveKit 服务器，收 JoinResponse（信令建连，无 libwebrtc 参与）
│           ├─ makeRTCConfig(joinResponse, connectOptions) 【RTCEngine.kt:941】
│           ├─ publisher = pctFactory.create(rtcConfig, publisherObserver, ...) 【RTCEngine.kt:300】
│           └─ subscriber = pctFactory.create(rtcConfig, subscriberObserver, null) 【RTCEngine.kt:305】
│               └─ PeerConnectionTransport 创建，内部建 org.webrtc.PeerConnection
│                  【src/main/java/io/livekit/android/room/PeerConnectionTransport.kt:70】
│
│  #（publisher/subscriber 各创建一次，以下只画一条线）
│
├─ 【建 PeerConnection 时 libwebrtc 内部（一次性，不再展开）】
│   └─ PeerConnectionFactory → PeerConnection 构造
│      ├─ sdp_handler_ = SdpOfferAnswerHandler 创建
│      ├─ operations_chain_ = OperationsChain 创建 【rtc_base/operations_chain.h:145】
│      └─ transport_controller_ = JsepTransportController 创建
│
【验证】grep -n "fun connect" src/main/java/io/livekit/android/room/Room.kt
        grep -n "pctFactory.create" src/main/java/io/livekit/android/room/RTCEngine.kt
        grep -n "class PeerConnectionTransport" src/main/java/io/livekit/android/room/PeerConnectionTransport.kt

════════════════════════════════════════════════════════════
阶段② SDP 协商（SetRemote → 校验 → 应用；Answerer 侧含 CreateAnswer + SetLocal）
════════════════════════════════════════════════════════════
── Offerer 侧 = LiveKit 客户端 publisher（向 SFU 发流）──

PublisherTransportObserver::onRenegotiationNeeded
├─ RTCEngine::negotiatePublisher() 【PublisherTransportObserver.kt:58 调用 → RTCEngine.kt:714 定义】
│   └─ PeerConnectionTransport::negotiate (debounce 20ms) 【PeerConnectionTransport.kt:146】
│       └─ PeerConnectionTransport::createAndSendOffer 【PeerConnectionTransport.kt:155】
│           ├─ peerConnection.createOffer(constraints) 【PeerConnectionTransport.kt:194 调用】
│           │   └─ CoroutineSdpObserver 挂起封装 【src/main/java/io/livekit/android/room/util/CoroutineSdpObserver.kt:139】
│           │       └─ org.webrtc.PeerConnection::createOffer(observer, constraints) 【sdk/android/api/org/webrtc/PeerConnection.java:901】
│           │
│           │   ← 进入 libwebrtc，全程信令线程
│           │
│           │   ├─ JNI_PeerConnection_CreateOffer 【sdk/android/src/jni/pc/peer_connection.cc:609】
│           │   ├─ PeerConnection::CreateOffer 【pc/peer_connection.cc:1500】
│           │   │   └─ SdpOfferAnswerHandler::CreateOffer 【pc/sdp_offer_answer.cc:1641】
│           │   │       ├─ operations_chain_->ChainOperation(λ) 【pc/sdp_offer_answer.cc:1648】
│           │   │       │   ← OperationsChain 排队串行：CreateOffer/CreateAnswer/SetLocal/
│           │   │       │     SetRemote/AddIceCandidate 全部过此队列，前一个完成才轮到下一个
│           │   │       └─ λ → DoCreateOffer 【pc/sdp_offer_answer.cc:2658】
│           │   │           ├─ WebRtcSessionDescriptionFactory::CreateOffer 【pc/webrtc_session_description_factory.cc:194】
│           │   │           │   └─ InternalCreateOffer 【pc/webrtc_session_description_factory.cc:266】
│           │   │           │       └─ MediaSessionDescriptionFactory::CreateOfferOrError 【pc/media_session.cc:721】
│           │   │           │           ← 真正拼 SDP（m= 行/编解码/extmap/ICE 凭据/DTLS 指纹）
│           │   │           └─ PostCreateSessionDescriptionSucceeded → observer OnSuccess → JNI 回 Java（信令线程）
│           │   │               └─ CoroutineSdpObserver 恢复挂起协程，拿到 offer
│           │   ├─ setMungedSdp（SVC/码率 SDP munging，LiveKit 自己的步骤）
│           │   │   └─ peerConnection.setLocalDescription(sdp) 【PeerConnectionTransport.kt:279 调用】
│           │   │       └─ org.webrtc.PeerConnection::setLocalDescription(observer, sdp) 【PeerConnection.java:913】
│           │   │           ├─ JNI_PeerConnection_SetLocalDescription 【sdk/android/src/jni/pc/peer_connection.cc:645】
│           │   │           └─ PeerConnection::SetLocalDescription(observer, desc) 【pc/peer_connection.cc:1512】
│           │   │               ← 4 重载中走这个（见 8.1 Q1）
│           │   │               └─ sdp_handler_->SetLocalDescription 【pc/peer_connection.cc:1516】
│           │   │                   └─ DoSetLocalDescription 【pc/sdp_offer_answer.cc:2471】
│           │   │                       ├─ ApplyLocalDescription 【pc/sdp_offer_answer.cc:1801】
│           │   │                       │   ├─ CreateChannels（type==kOffer 才建） 【pc/sdp_offer_answer.cc:1927】
│           │   │                       │   │   ← BlockingCall 下沉 worker 线程，媒体通道在此创建
│           │   │                       │   │   └─ RtpTransceiver::CreateChannel 【pc/rtp_transceiver.cc:204】
│           │   │                       │   │       ← 信令线程 → worker 线程
│           │   │                       │   ├─ UpdateSessionState 【pc/sdp_offer_answer.cc:3123】
│           │   │                       │   │   ├─ kOffer → ChangeSignalingState(kHaveLocalOffer) 【pc/sdp_offer_answer.cc:3142】
│           │   │                       │   └─ PushdownTransportDescription 【pc/sdp_offer_answer.cc:5270】
│           │   │                       │       └─ JsepTransportController::SetLocalDescription 【pc/jsep_transport_controller.cc:124】
│           │   │                       │           ← 信令线程 → 网络线程（BlockingCall）
│           │   │                       │           └─ ApplyDescription_n（按 m= 行建 ICE/DTLS transport） 【pc/jsep_transport_controller.cc:703】← 网络线程
│           │   │                       │   └─ MaybeStartGathering 【pc/sdp_offer_answer.cc:2655】→（阶段③ ICE 点火）
│           │   │                       └─ Observer OnSuccess → 回 Java（信令线程）
│           │   └─ listener.onOffer(sdp, offerId) 【PeerConnectionTransport.kt:233 调用】
│           │       └─ PublisherTransportObserver::onOffer 【PublisherTransportObserver.kt:66】
│           │           └─ SignalClient::sendOffer(offer, offerId) 【PublisherTransportObserver.kt:68 调用 → SignalClient.kt:422 定义】
│           │               └─ SignalRequest(offer) 经 WebSocket 发给 SFU 【SignalClient.kt:644 sendRequest】
│
│  # SFU 收 offer → 生成 answer → WebSocket 推回客户端
│
├─ SignalClient 分发 onServerAnswer 【src/main/java/io/livekit/android/room/SignalClient.kt:742】
│   └─ RTCEngine::onServerAnswer 【src/main/java/io/livekit/android/room/RTCEngine.kt:1086】
│       └─ publisher?.setRemoteDescription(sessionDescription, offerId) 【RTCEngine.kt:1095 调用】
│           └─ PeerConnectionTransport::setRemoteDescription（含旧 offerId 丢弃判断） 【PeerConnectionTransport.kt:121】
│               ├─ peerConnection.setRemoteDescription(sd) 【PeerConnectionTransport.kt:126】+ 冲刷 pendingCandidates（阶段③ 攒下的远端候选）
│               │   └─ CoroutineSdpObserver 挂起封装 【CoroutineSdpObserver.kt:151】
│               │       └─ org.webrtc.PeerConnection::setRemoteDescription(observer, sdp) 【PeerConnection.java:917】
│               │
│               │   ← 进入 libwebrtc，信令线程
│               │
│               │   ├─ JNI_PeerConnection_SetRemoteDescription 【sdk/android/src/jni/pc/peer_connection.cc:655】
│               │   └─ PeerConnection::SetRemoteDescription 【pc/peer_connection.cc:1550】
│               │       └─ sdp_handler_->SetRemoteDescription 【pc/peer_connection.cc:1558】
│               │           └─ DoSetRemoteDescription 【pc/sdp_offer_answer.cc:2816】
│               │               └─ ApplyRemoteDescription 【pc/sdp_offer_answer.cc:2146】
│               │                   ├─ ① ReplaceRemoteDescriptionAndCheckError（存储+校验） 【pc/sdp_offer_answer.cc:1090】
│               │                   ├─ ② UpdateChannels（已有通道按新 SDP 更新，不重建） 【pc/sdp_offer_answer.cc:1116】
│               │                   ├─ ③ UpdateSessionState 【pc/sdp_offer_answer.cc:1144】
│               │                   │   └─ type==kAnswer → EnableSending() 【pc/sdp_offer_answer.cc:3136 调用 → :5076 实现】
│               │                   │       ← 媒体"通水"开关（worker 线程通道 Enable）
│               │                   │       └─ ChangeSignalingState(kStable) 【pc/sdp_offer_answer.cc:3151】← SignalingState 回稳定态
│               │                   ├─ ④ UseCandidatesInRemoteDescription（SDP 内嵌候选逐个 UseCandidate） 【pc/sdp_offer_answer.cc:1154】
│               │                   └─ ⑤ SignalCompletion → OnSuccess；SetRemoteDescriptionPostProcess
│               │                       └─ DiscardCandidatePool 【pc/sdp_offer_answer.cc:2849】← BlockingCall 网络线程
│               │
│               └─ renegotiate 标记处理：若 negotiate 期间又有变化 → createAndSendOffer 再来一轮 【PeerConnectionTransport.kt:138-140】
│
── Answerer 侧 = LiveKit 客户端 subscriber（收 SFU 下行流）──

├─ SignalClient 分发 onServerOffer 【src/main/java/io/livekit/android/room/SignalClient.kt:748】
│   └─ RTCEngine::onServerOffer 【src/main/java/io/livekit/android/room/RTCEngine.kt:1101】
│       ├─ subscriber?.setRemoteDescription(sessionDescription, offerId) 【RTCEngine.kt:1105 调用】
│       │   └─ （同 Offerer 侧 SetRemote 链：Java:917 → JNI:655 → pc:1550 → ApplyRemoteDescription:2146）
│       │       └─ 区别：type==kOffer → ChangeSignalingState(kHaveRemoteOffer)，不 EnableSending
│       ├─ subscriber?.withPeerConnection { createAnswer(MediaConstraints()) } 【RTCEngine.kt:1120 调用】
│       │   └─ CoroutineSdpObserver 挂起封装 【CoroutineSdpObserver.kt:145】
│       │       └─ org.webrtc.PeerConnection::createAnswer(observer, constraints) 【PeerConnection.java:905】
│       │           ├─ JNI_PeerConnection_CreateAnswer 【sdk/android/src/jni/pc/peer_connection.cc:623】
│       │           └─ PeerConnection::CreateAnswer 【pc/peer_connection.cc:1506】
│       │               └─ sdp_handler_->CreateAnswer 【pc/peer_connection.cc:1508】
│       │                   └─ SdpOfferAnswerHandler::CreateAnswer 【pc/sdp_offer_answer.cc:2722】
│       │                       └─ ChainOperation 排队 → DoCreateAnswer 【pc/sdp_offer_answer.cc:2752】
│       │                           └─ MediaSessionDescriptionFactory::CreateAnswerOrError 【pc/media_session.cc:838】
│       │                               ← 逐项接受/拒绝 offer（交集/收窄/凭据配对）
│       ├─ subscriber?.withPeerConnection { setLocalDescription(answer) } 【RTCEngine.kt:1134 调用】
│       │   └─ org.webrtc.PeerConnection::setLocalDescription(observer, sdp) 【PeerConnection.java:913】
│       │       ├─ JNI_PeerConnection_SetLocalDescription 【sdk/android/src/jni/pc/peer_connection.cc:645】
│       │       └─ PeerConnection::SetLocalDescription(observer, desc) 【pc/peer_connection.cc:1512】
│       │           └─ DoSetLocalDescription → ApplyLocalDescription 【pc/sdp_offer_answer.cc:2471 → :1801】
│       │               └─ UpdateSessionState：type==kAnswer → EnableSending() 【pc/sdp_offer_answer.cc:3136】
│       │                   ← subscriber 侧 answer 落位 = 下行媒体通道"通水"（worker 线程）
│       └─ SignalClient::sendAnswer(answer, offerId) 【RTCEngine.kt:1146 调用 → SignalClient.kt:431 定义】
│           └─ WebSocket 发回 SFU
│
【验证】grep -n "CreateOffer" pc/sdp_offer_answer.cc
        grep -n "ApplyRemoteDescription\|ApplyLocalDescription" pc/sdp_offer_answer.cc
        grep -n "fun onServerOffer\|fun onServerAnswer" src/main/java/io/livekit/android/room/RTCEngine.kt
        grep -n "fun createAndSendOffer\|fun setRemoteDescription" src/main/java/io/livekit/android/room/PeerConnectionTransport.kt

════════════════════════════════════════════════════════════
阶段③ ICE（候选收集 onicecandidate → 信令交换 → AddIceCandidate 注入 → 连通性检查）
════════════════════════════════════════════════════════════
── 本地候选收集（trickle 上行，publisher/subscriber 对称）──

├─ 【点火】DoSetLocalDescription 尾部（阶段②内）
│   └─ transport_controller_s()->MaybeStartGathering() 【pc/sdp_offer_answer.cc:2655】
│       └─ JsepTransportController::MaybeStartGathering 【pc/jsep_transport_controller.cc:414】
│           └─ network_thread_->BlockingCall → MaybeStartGathering_n 【pc/jsep_transport_controller.cc:418/:422】
│           │   ← 信令线程 → 网络线程
│           └─ ice_transport->MaybeStartGathering 【pc/jsep_transport_controller.cc:425】
│               └─ P2PTransportChannel::MaybeStartGathering 【p2p/base/p2p_transport_channel.cc:842】
│                   ← 网络线程，PortAllocator 后台收集（host/srflx/relay）
│
├─ 【产出】候选到一个发一个（不等收齐 = trickle）
│   ├─ P2PTransportChannel::OnCandidatesReady 【p2p/base/p2p_transport_channel.cc:946】
│   ├─ → signal_ice_candidates_gathered 回调注入 【pc/peer_connection.cc:759】
│   │   ← 网络线程 → 信令线程（PostTask）
│   └─ → PeerConnection::OnIceCandidate 【pc/peer_connection.cc:2171】
│       └─ observer->OnIceCandidate(candidate) 【pc/peer_connection.cc:2178】→ JNI 回 Java（信令线程）
│
├─ LiveKit 侧接住候选（两个 observer 对称）
│   ├─ PublisherTransportObserver::onIceCandidate 【src/main/java/io/livekit/android/room/PublisherTransportObserver.kt:48】
│   │   └─ SignalClient::sendCandidate(candidate, PUBLISHER) 【PublisherTransportObserver.kt:52 调用 → SignalClient.kt:440 定义】
│   └─ SubscriberTransportObserver::onIceCandidate 【src/main/java/io/livekit/android/room/SubscriberTransportObserver.kt:52】
│       └─ SignalClient::sendCandidate(candidate, SUBSCRIBER) 【SubscriberTransportObserver.kt:55 调用 → SignalClient.kt:440 定义】
│
── 远端候选注入（trickle 下行）──

├─ SignalClient 分发 onTrickle 【src/main/java/io/livekit/android/room/SignalClient.kt:759】
│   └─ RTCEngine::onTrickle(candidate, target) 【src/main/java/io/livekit/android/room/RTCEngine.kt:1150】
│       ├─ target==PUBLISHER → publisher?.addIceCandidate(candidate) 【RTCEngine.kt:1154】
│       └─ target==SUBSCRIBER → subscriber?.addIceCandidate(candidate) 【RTCEngine.kt:1159】
│           └─ PeerConnectionTransport::addIceCandidate 【PeerConnectionTransport.kt:105】
│               ├─ remoteDescription 已设 → 直接注入 【PeerConnectionTransport.kt:108】
│               │   └─ org.webrtc.PeerConnection::addIceCandidate 【sdk/android/api/org/webrtc/PeerConnection.java:954】
│               └─ 否则 → pendingCandidates 攒着（setRemoteDescription 成功后冲刷）【PeerConnectionTransport.kt:110】
│
│   ← 进入 libwebrtc，AddIceCandidate 也过 OperationsChain 排队
│
│   ├─ JNI_PeerConnection_AddIceCandidate 【sdk/android/src/jni/pc/peer_connection.cc:702】
│   ├─ PeerConnection::AddIceCandidate 【pc/peer_connection.cc:1666】
│   ├─ SdpOfferAnswerHandler::AddIceCandidate 【pc/sdp_offer_answer.cc:2967】
│   │   └─ AddIceCandidateInternal 【pc/sdp_offer_answer.cc:2921】
│   │       ├─ AddCandidate（塞进远端 SDP 存档）
│   │       └─ UseCandidate 【pc/sdp_offer_answer.cc:5418】
│   │           └─ PeerConnection::AddRemoteCandidate 【pc/peer_connection.cc:2786】
│   │               └─ network_thread()->PostTask → transport_controller_->AddRemoteCandidates 【pc/jsep_transport_controller.cc:429】
│   │               │   ← 信令线程 → 网络线程（非阻塞 Post）
│   │               └─ P2PTransportChannel 加入 pair 队列，开始 STUN 绑定请求连通性检查 ← 网络线程
│   └─ 成功回信令线程：SetIceConnectionState(kIceConnectionChecking) 【pc/peer_connection.cc:1959】
│
── 连通性检查 → DTLS → SRTP 密钥（全程网络线程，无信令参与）──

├─ P2PTransportChannel::OnConnectionStateChange（选路） 【p2p/base/p2p_transport_channel.cc:2127】
│   └─ SetWritable(true) 【p2p/base/p2p_transport_channel.cc:2289】← pair 可写
├─ DtlsTransport::OnInternalDtlsState 【pc/dtls_transport.cc:113】
│   └─ DtlsSrtpTransport::OnDtlsState 【pc/dtls_srtp_transport.cc:324】
│       └─ MaybeSetupDtlsSrtp 【pc/dtls_srtp_transport.cc:164】
│           └─ ExtractParams（ExportSrtpKeyingMaterial 导出密钥 → SetRtpParams） 【pc/dtls_srtp_transport.cc:230】
└─ 状态上行（网络线程 → 信令线程 → Java）
    └─ config.signal_ice_connection_state 【pc/peer_connection.cc:770 注入】
        └─ OnTransportControllerConnectionState（聚合翻译 Connected/Failed/...） 【pc/peer_connection.cc:2502】
            └─ SetIceConnectionState → observer->OnIceConnectionChange 【pc/peer_connection.cc:1959】
                → LiveKit PublisherTransportObserver/SubscriberTransportObserver 收到

【验证】grep -n "MaybeStartGathering" pc/jsep_transport_controller.cc
        grep -n "AddIceCandidate" pc/sdp_offer_answer.cc
        grep -n "fun onTrickle" src/main/java/io/livekit/android/room/RTCEngine.kt
        grep -n "fun addIceCandidate" src/main/java/io/livekit/android/room/PeerConnectionTransport.kt

════════════════════════════════════════════════════════════
阶段④ 媒体（DTLS → SRTP → 媒体双线，只画入口）
════════════════════════════════════════════════════════════
前提齐备：ICE writable + DTLS connected + SRTP 密钥装好 + EnableSending（answer 落位）

── 发送线入口（publisher 侧）──
├─ EnableSending() → channel->Enable(true) 【pc/sdp_offer_answer.cc:3136 调用 → :5076 实现】
│   ← 信令线程指令下沉 worker 线程
│   └─ （进入 wr-api-analysis.md 第 12.1 节上行链：VideoStreamEncoder 编码 → RTPSender 打包
│      → TaskQueuePacedSender → RtpTransport::SendRtpPacket → SrtpTransport 用阶段③导出的密钥加密 → 网络）
│       └─ 发送出口：RtpTransport::SendRtpPacket 【pc/rtp_transport.cc:155】
│
── 接收线入口（subscriber 侧）──
└─ 网络包到达 → RtpTransport::OnReadPacket 【pc/rtp_transport.cc:86】← 网络线程
    └─ DemuxPacket 【pc/rtp_transport.cc:215】 → RtpDemuxer::OnRtpPacket → 各通道 sink
        └─ （进入 wr-api-analysis.md 第 12.1 节下行链：PacketBuffer 组帧 → FrameBuffer 抖动缓冲
           → 解码 → 渲染；音频走 NetEq）

【验证】grep -n "EnableSending" pc/sdp_offer_answer.cc
        grep -n "SendRtpPacket\|OnReadPacket" pc/rtp_transport.cc
```

### 8.3 读图要点（三个最容易看错的地方）

1. **publisher 是 Offerer、subscriber 是 Answerer**——LiveKit 客户端不是"一条 PC 两头"，而是两条 PC：上行 PC 客户端先发 offer（SFU 答），下行 PC SFU 先发 offer（客户端答，即图中 onServerOffer → CreateAnswer → SetLocal → sendAnswer 链）。所以**同一段 libwebrtc 代码（ApplyRemoteDescription/ApplyLocalDescription/EnableSending）在两条 PC 上各跑一遍**——读图时要注意每条线挂在哪条 PC 上。
2. **AddIceCandidate 的时序坑在 LiveKit 侧，不在 libwebrtc**：远端候选可能比 answer/offer 先到（trickle 不保证顺序），`PeerConnectionTransport.addIceCandidate(:105)` 用 `pendingCandidates` 攒着，`setRemoteDescription(:121)` 成功后冲刷——这是 LiveKit 对 trickle 时序的兜底，纯应用层逻辑。libwebrtc 自己也有一个类似的池（candidate pool），但那是给 SetRemoteDescription 之前注入用的，两个机制不同层。
3. **线程迁移只有三种模式**：SDP 全程信令线程（OperationsChain 串行）→ transport 操作下沉网络线程（BlockingCall :124 / PostTask :429）→ 通道创建与 Enable 下沉 worker 线程（CreateChannels :1927 / EnableSending :5076）；所有 OnIceCandidate/OnSuccess/OnIceConnectionChange 回调都回信令线程再进 Java。找不到第四种迁移——记住这三种，整张图的线程归属就能自己推出来。

---

## 九、信令线程模型深度剖析（2026-09-09 专业版）

> 定位：第四节给了"跨线程图"（谁在哪条线程上做什么），本节回答**为什么**——信令线程模型靠哪些机制保证"乱序调用不崩、跨线程不踩数据、析构不悬垂"。全部行号在 M144 源码核对过。
>
> **一句话**：信令线程模型 = **一个串行队列（OperationsChain）+ 一个代理（PeerConnectionProxy）+ 两种下沉（BlockingCall/PostTask）+ 两道保险（安全句柄/禁阻塞作用域）**。

### 9.1 三线程从哪来、各管什么

```
sdk/android/src/jni/pc/peer_connection_factory.cc:259  CreatePeerConnectionFactoryForJava
  :285  network_thread = std::make_unique<Thread>(socket_server.get())  ← 唯一带 socket_server 的
  :286    SetName("network_thread")  :287  Start()
  :289  worker_thread = Thread::Create()
  :290    SetName("worker_thread")   :291  Start()
  :293  signaling_thread = Thread::Create()
  :294    SetName("signaling_thread"):295  Start()
  :303-305  dependencies.network/worker/signaling_thread = ...（塞进工厂依赖）
```

**Android 固定 vs 原生可注入**：JNI 路径里三线程是**无条件创建**的（Java 层没有注入入口）；而 C++ 原生 `PeerConnectionFactoryDependencies`（factory.cc:153-155 的构造参数）允许外部注入线程。也就是说：**Android 应用永远拿到的都是这三个内部线程；想自定义线程模型必须走原生 C++ 或改源码**——LiveKit 也逃不出这个约束。

**线程初始化 → 运行的完整链（从 pthread 到消息循环）**：

```
【创建】factory.cc:285/:289/:293  Thread 对象构造（此时只是 C++ 对象，还没有 OS 线程）
  ▼
【启动】Thread::Start()  rtc_base/thread.cc:616
  └─ :639  pthread_create(&thread_, &attr, PreRun, this)  ← OS 线程诞生
      ▼
【入口】Thread::PreRun  rtc_base/thread.cc:716（静态函数，pthread 的入口）
  └─ :719  thread->Run()  ← 转到虚函数
      ▼
【循环】Thread::Run  rtc_base/thread.cc:734
  └─ :735  ProcessMessages(kForever)  ← kForever = 永不退出
      ▼
【取任务】ProcessMessages → Thread::Get(cmsNext)  rtc_base/thread.cc:413
  └─ 扫描普通队列 + delayed_messages_ 优先队列（到点的延迟任务先搬进普通队列）
      ▼
【执行】Thread::Dispatch(std::move(task))  rtc_base/thread.cc:543
  └─ 执行 lambda（就是 proxy Marshal 投进来的 MethodCall::Invoke、
     BlockingCall 投进来的任务、PostTask 投进来的回调）
  └─ 循环回到 Get()，直到 Quit()
```

三个线程都是这条同样的链——**差别只在"谁往它的队列里投什么"**：信令线程队列里是 proxy 转发的 SDP 操作 + 下沉回来的回调；网络线程队列里是 transport BlockingCall/PostTask + ICE/DTLS 自治任务；worker 线程队列里是通道创建 + Enable + 解码调度（媒体文档的解码调度器就绑在这条队列上）。

| 线程 | 创建处 | 职责（信令语境） | 关键对象 |
|---|---|---|---|
| **signaling_thread** | :293 | SDP 协商、状态机、observer 回调、Java 回调 | `SdpOfferAnswerHandler`、`OperationsChain`、`PeerConnectionProxy(primary)` |
| **network_thread** | :285 | transport 全家：建 ICE/DTLS、候选收集、pair 检查、DTLS 握手、SRTP 密钥 | `JsepTransportController`、`P2PTransportChannel`、`DtlsTransport`、`DtlsSrtpTransport` |
| **worker_thread** | :289 | 媒体通道创建与 Enable | `RtpTransceiver::CreateChannel`、`channel->Enable()` |

**关键**：三个线程都是**独立 `Thread` 对象**，各自跑一个 `Thread::Run()` 消息循环（rtc_base/thread.cc:734 → ProcessMessages:735）。注意 network_thread 构造时带 `socket_server`（物理 socket，它要真的收发网络包），worker/signaling 是 `Thread::Create()` 纯消息队列线程（不碰 socket）。"信令线程"不是主线程，是 PeerConnectionFactory 建出来的第三条专用线程。**所有信令方法开头都有 `RTC_DCHECK_RUN_ON(signaling_thread())`**——跑错线程直接断言崩溃，这是第一道防线。

### 9.2 PeerConnectionProxy：外部调用的线程迁移器

**问题**：应用层（Java/任意线程）调 `pc.createOffer()` 时，可能不在信令线程上。谁负责把它挪到信令线程？

**答案**：`PeerConnectionProxy`。所有外部拿到的 `PeerConnection` 引用其实是 proxy，不是裸对象（pc/peer_connection_factory.cc:335）：

```
PeerConnectionProxy::Create(signaling_thread(), network_thread(), std::move(pc))
  → primary_thread_ = signaling_thread
  → secondary_thread_ = network_thread
```

**PROXY_METHOD 宏**（pc/proxy.h:324）把每个公开方法包成：
```cpp
r method() override {
  MethodCall<C, r> call(c(), &C::method);
  return call.Marshal(primary_thread_);   // ← 关键
}
```

`MethodCall::Marshal(Thread* t)`（pc/proxy.h:105-118）：
```cpp
if (t->IsCurrent()) {
  Invoke(...);                       // 已在目标线程 → 直接执行
} else {
  t->PostTask([this]{ Invoke(...); event_.Set(); });  // 投到目标线程
  event_.Wait(Event::kForever);      // ← 阻塞等结果（同步代理）
}
```

**两种方法类别**：
- **默认走 primary（signaling）**：`CreateOffer/SetLocalDescription/SetRemoteDescription/AddIceCandidate` 等——`PROXY_METHOD*`，Marshal 到 `primary_thread_`（信令线程）
- **少数走 secondary（network）**：`GetDtlsTransport` 等——`PROXY_SECONDARY_METHOD*`（pc/proxy.h:401），Marshal 到 `secondary_thread_`（网络线程）
- **少数 bypass**：`local_description()/signaling_thread()` 等——`BYPASS_PROXY_*`（pc/proxy.h:110-119），线程无关的纯 getter，不走代理

**为什么用 BlockingCall 而非 PostTask**：proxy 的 Marshal 用 `event_.Wait(kForever)` 阻塞等结果（同步语义），保证调用者拿到返回值。这与信令链路内部用的 `BlockingCall` 是同一思想——**协商期可以阻塞**，因为 SDP 操作是低频、需要同步结果的操作。

### 9.3 OperationsChain：信令线程内的串行队列

**问题**：proxy 只保证"调用到了信令线程"，不保证"多个操作不乱序"。应用层可能 `createOffer()` 还没回调就 `setRemoteDescription()`。

**答案**：`OperationsChain`（rtc_base/operations_chain.h:145）。所有 SDP 操作（CreateOffer/CreateAnswer/SetLocal/SetRemote/AddIceCandidate）都 `ChainOperation` 入队（sdp_offer_answer.cc:1648 等）：

```
ChainOperation(λ)   // 每个操作各自入队
  └─ 队列：同一时刻只执行一个
      └─ 前一个 λ 执行完毕（SignalCompletion）→ 才 pop 下一个
```

**关键**：这是**排队串行，不是锁**。信令线程本身是单线程（一个消息循环），但 OperationsChain 额外保证"操作级串行"——即使两个操作被投到信令线程，也按入队顺序一个完成才下一个。**为什么不用锁**：锁会阻塞调用者线程（可能死锁），队列只是让调用者"等前面做完"，不持有任何锁。

**与媒体侧对比**：媒体侧"任务投递到线程队列"（解码队列/encoder_queue），信令侧"OperationsChain 排队"——**同一哲学：队列代替加锁**。区别是媒体侧是"数据流任务"，信令侧是"协商操作"。

### 9.4 两种下沉：BlockingCall vs PostTask

信令线程要向其他线程派活，有两种方式，**区别在"要不要等结果"**：

| 方式 | 语义 | 信令链路里的例子 |
|---|---|---|
| **BlockingCall** | 投任务 + 阻塞等结果 | `JsepTransportController::SetLocalDescription`（jsep_transport_controller.cc:124，BlockingCall 在 :125→:138）<br>`MaybeStartGathering`（:414 定义，BlockingCall 在 **:418**→:422，信令→网络）<br>`RtpTransceiver::CreateChannel` 的通道创建（媒体文档，信令→worker）<br>`DiscardCandidatePool`（sdp_offer_answer.cc:2849，信令→网络） |
| **PostTask** | 投任务 + 立即返回（异步） | `PeerConnection::AddRemoteCandidate`（peer_connection.cc:2786 内 `network_thread()->PostTask`，信令→网络）<br>候选产出/ICE 状态回信令线程（`signal_ice_candidates_gathered` :759 的 `signaling_thread()->PostTask`） |

**选型规律**：
- **要同步结果**（如 SetLocalDescription 要确认 transport 建成功）→ BlockingCall
- **不需要结果**（如把远端候选投给网络线程去检查、把候选回调投回信令线程通知 Java）→ PostTask

**为什么协商期能 BlockingCall 而媒体期不能**：协商是低频、需要确认的操作，阻塞信令线程几毫秒无所谓；媒体是高频数据流，阻塞会卡住整个通话。所以信令链路大量用 BlockingCall，媒体链路几乎全用 PostTask。

### 9.5 两道保险：安全句柄 + 禁阻塞作用域

**保险一：安全句柄（防析构后回调悬垂）**

```
pc/peer_connection.h:689  ScopedTaskSafety signaling_thread_safety_;
pc/peer_connection.h:690  scoped_refptr<PendingTaskSafetyFlag> network_thread_safety_;
```

跨线程投递任务时，用 `SafeTask(flag, λ)` 包一层（如 peer_connection.cc:764 的 `SafeTask(signaling_thread_safety_.flag(), ...)`）。**原理**：network 侧用 `network_thread_safety_->SetNotAlive()`（peer_connection.cc:870，在 CloseOnNetworkThread 投给网络线程的 lambda 内显式调用）→ 之后队列里还没执行的任务被 SafeTask 判别为"对象已死"→ 丢弃，不执行回调。signaling 侧的 `signaling_thread_safety_` 是 `ScopedTaskSafety` 类型，**没有显式 SetNotAlive 调用**——它在 PeerConnection 析构时随对象自动失效（RAII，析构函数自动 flag 灭活）。**防止**：网络线程还在跑 ICE，信令线程已把 PeerConnection 析构，回调回来访问已释放对象 → 悬垂指针。

**保险二：ScopedDisallowBlockingCalls（禁阻塞作用域）**

```
pc/sdp_offer_answer.cc:5421  UseCandidate 内 Thread::ScopedDisallowBlockingCalls no_blocking_calls;
pc/peer_connection.cc:2459/:2634/:2885  统计/上报路径内
```

**问题**：信令线程上如果嵌套 BlockingCall 到网络线程，而网络线程又 BlockingCall 回信令线程 → 死锁。`ScopedDisallowBlockingCalls` 在作用域内**禁止再发起 BlockingCall**，一旦违反直接断言崩溃。它标记"这段代码必须非阻塞"——比如 `UseCandidate`（:5421）在信令线程上处理候选，内部绝不能再 BlockingCall 等网络线程，否则候选处理路径可能死锁。

### 9.6 observer 回 Java：信令线程 → JNI 附着 → 回调

**问题**：C++ 的 observer（`CreateSdpObserverJni` 等）在信令线程上被调用，怎么回 Java？

**答案**：`AttachCurrentThreadIfNeeded()`（sdk/android/src/jni/jvm.cc:120）。信令线程第一次回 Java 时 attach 到 JVM，之后复用：

```cpp
void CreateSdpObserverJni::OnSuccess(SessionDescriptionInterface* desc) {  // 信令线程
  JNIEnv* env = AttachCurrentThreadIfNeeded();   // 附着/复用 JNIEnv
  Java_SdpObserver_onCreateSuccess(env, j_observer_global_, ...);  // 直接调 Java
}
```

**关键**：observer 回调**不经 PostTask 排队，直接在当前线程（信令线程）同步调 Java**。因为信令线程已经 attach 了 JVM，JNI 调用是同步的。所以"回 Java"没有额外的线程迁移——**信令线程本身就是能调 Java 的线程**。

**Java 侧接收**：`@CalledByNative("Observer")` 注解的方法（sdk/android/api/org/webrtc/PeerConnection.java:102 `onSignalingChange` 等）就是被这个 native 回调触发的。

### 9.7 线程归属全景（信令语境）

```
应用层 Java（任意线程）
  │  pc.createOffer() / setLocalDescription() / addIceCandidate()
  ▼
PeerConnectionProxy（pc/peer_connection_factory.cc:335）
  │  PROXY_METHOD → MethodCall::Marshal(primary_thread_)
  │  不在信令线程 → PostTask + event_.Wait（同步代理）
  ▼
信令线程（消息循环 Thread::Run :734）
  ├─ OperationsChain 排队串行（rtc_base/operations_chain.h:145）
  ├─ SdpOfferAnswerHandler 全程在此
  ├─ 下沉（BlockingCall，需结果）：
  │    → 网络线程：JsepTransportController::SetLocalDescription :124 / MaybeStartGathering :414 / DiscardCandidatePool :2849
  │    → worker 线程：RtpTransceiver::CreateChannel / channel->Enable
  ├─ 下沉（PostTask，不需结果）：
  │    → 网络线程：PeerConnection::AddRemoteCandidate :2786 内 PostTask
  └─ 回 Java（直接同步，AttachCurrentThreadIfNeeded）：
       OnSuccess / OnIceCandidate / OnSignalingChange / OnIceConnectionChange
网络线程（消息循环）
  ├─ 建 ICE/DTLS transport（ApplyDescription_n :703）
  ├─ 候选收集/上报（OnCandidatesReady :946 → PostTask 回信令线程）
  ├─ pair 检查/SetWritable :2289 / DTLS 握手 / SRTP 密钥（全程自治）
  └─ 状态上行（signal_ice_connection_state :770 → PostTask 回信令线程）
worker 线程（消息循环）
  └─ 通道创建（CreateChannels）与 Enable（EnableSending :5076）
```

### 9.8 析构线程顺序（防悬垂的最后一环）

**Close 完整顺序**（peer_connection.cc:1876 `PeerConnection::Close`，全程信令线程发起）：

```
PeerConnection::Close(:1876，信令线程)
  ├─ 状态收尾：SetIceConnectionState(kIceConnectionClosed) → observer OnIceConnectionChange/OnConnectionChange
  ├─ sdp_handler_->Close()                    —— SDP 侧先关门
  ├─ transceiver 逐个 StopInternal()
  ├─ stats_collector_->WaitForPendingRequest() —— 等统计请求完成才能拆通道
  ├─ sdp_handler_->DestroyMediaChannels()      —— 拆媒体通道（stats 已收尾）
  ├─ sdp_handler_->ResetSessionDescFactory()    —— 防 CreateOffer 异步回调访问已死 transport
  ├─ CloseOnNetworkThread()(:708 调用 → :854 实现)
  │    ├─ network_thread()->BlockingCall:
  │    │    ├─ TeardownDataChannelTransport_n
  │    │    ├─ port_allocator_->DiscardCandidatePool()
  │    │    ├─ transport_controller_.reset() / port_allocator_.reset()（:866-868）
  │    │    └─ network_thread_safety_->SetNotAlive()(:870) —— 之后网络线程任务全丢弃
  │    └─ （BlockingCall 阻塞等网络线程拆完才继续——析构顺序是同步保证的）
  ├─ worker_thread()->BlockingCall:
  │    ├─ worker_thread_safety_->SetNotAlive()
  │    └─ call_.reset()                          —— 源码注释原话："call_ must be destroyed on the worker thread"
  ├─ sdp_handler_->PrepareForShutdown() + data_channel_controller_ 同
  └─ observer_ = nullptr                        —— 注释原话：close() 返回后 observer 可丢弃
```

**顺序为什么重要**：
1. **先 stats 后拆通道**——最后一次统计请求还要从通道读数据；
2. **先 ResetSessionDescFactory 再拆 transport**——CreateOffer 是异步的，工厂不重置，它的回调会访问即将析构的 transport_controller；
3. **网络线程先拆**（它是"最下游"，媒体/ICE 都靠它），且用 BlockingCall 同步等待拆完——保证走到下一步时网络侧一定已死；
4. **call_ 必须在 worker 线程析构**——它在 worker 上创建就在 worker 上销毁（线程亲和的析构）；
5. **observer 最后置空**——Close() 返回后应用层可安全丢弃 observer。

**SetNotAlive 的语义**："先标记死亡，再等线程自然退出"——不 join 线程，只保证队列里残留任务不执行。真正的线程退出在 PeerConnectionFactory 层（三条线程随工厂析构而 Stop/Join，超出本文范围）。

### 9.9 面试可用的一句话总结

> "信令线程模型 = 一个串行队列（OperationsChain 排队代替加锁）+ 一个代理（PeerConnectionProxy 把任意线程的调用 Marshal 到信令线程）+ 两种下沉（BlockingCall 要结果、PostTask 不要）+ 两道保险（SafeTask 防析构悬垂、ScopedDisallowBlockingCalls 防嵌套死锁）。所有对 Java 的回调都在信令线程同步执行，不额外迁移线程。"

**对比媒体线程模型**（呼应媒体文档）：媒体 = 高频数据流，全 PostTask、不能阻塞；信令 = 低频协商操作，可 BlockingCall、需同步结果。**同一个三线程，两种使用哲学**——这是理解 WebRTC 线程模型的钥匙。

### 9.10 本节内容一览 + 关键事实小结

**一句话主线**：信令线程模型 = **一个串行队列 + 一个代理 + 两种下沉 + 两道保险**。

| 小节 | 回答的问题 | 核心机制（行号已核对） |
|---|---|---|
| 9.1 三线程从哪来 | 谁创建、各管什么 | peer_connection_factory.cc:285-295，三线程各跑 Thread::Run 消息循环 |
| 9.2 PeerConnectionProxy | 外部任意线程调用怎么挪到信令线程 | :335 创建，PROXY_METHOD→MethodCall::Marshal(primary_thread_) proxy.h:324/:105，同步代理 event_.Wait |
| 9.3 OperationsChain | 多个操作怎么不乱序 | operations_chain.h:145，排队串行代替加锁 |
| 9.4 两种下沉 | BlockingCall vs PostTask 怎么选 | 要结果→BlockingCall（SetLocalDescription :124），不要→PostTask（AddRemoteCandidate :2786） |
| 9.5 两道保险 | 防析构悬垂 / 防嵌套死锁 | SafeTask 安全句柄 peer_connection.h:689-690，ScopedDisallowBlockingCalls sdp_offer_answer.cc:5421 |
| 9.6 observer 回 Java | C++ 回调怎么进 Java | AttachCurrentThreadIfNeeded jvm.cc:120，信令线程同步直调不经 PostTask |
| 9.7 线程归属全景 | 一张图 | 应用层→proxy→信令→下沉网络/worker→回 Java |
| 9.8 析构线程顺序 | 防悬垂最后一环 | CloseOnNetworkThread :854 先关网络线程 SetNotAlive :870 |
| 9.9 面试总结 | 一句话 | 串行队列+代理+两种下沉+两道保险 |

**五个最容易记错/忽略的关键事实**：

1. **PeerConnectionProxy 是双线程代理**（primary=signaling, secondary=network），不是单线程——少数方法（GetDtlsTransport 等）直接 Marshal 到网络线程（PROXY_SECONDARY_METHOD1，proxy.h:401）。
2. **observer 回 Java 不经 PostTask**——信令线程已 attach JVM（AttachCurrentThreadIfNeeded jvm.cc:120），直接同步调 Java。很多人误以为"要切线程回 Java"，实际信令线程本身就是能调 Java 的线程。
3. **ScopedDisallowBlockingCalls 是防死锁的**——信令线程上嵌套 BlockingCall 到网络线程、网络线程又 BlockingCall 回来就死锁，这个作用域标记"这段必须非阻塞"（如 UseCandidate sdp_offer_answer.cc:5421）。
4. **析构先关网络线程（最下游），再关上层**——`SetNotAlive()` 标记死亡后队列残留任务全丢弃（CloseOnNetworkThread :854 → network SetNotAlive :870）。注意 signaling 侧是 `ScopedTaskSafety` RAII 自动失效，只有 network 侧显式调 SetNotAlive。
5. **与媒体线程模型的对比**：媒体 = 高频数据流全 PostTask 不能阻塞；信令 = 低频协商可 BlockingCall 需同步结果。**同一个三线程，两种使用哲学**——这是理解 WebRTC 线程模型的钥匙。

> 行号说明：LiveKit 侧（Room.kt / RTCEngine.kt / PeerConnectionTransport.kt / Publisher·SubscriberTransportObserver.kt / SignalClient.kt / CoroutineSdpObserver.kt）基于我 clone 的版本核对（示意，以你 clone 的版本为准）；libwebrtc 侧全部行号在 M144 源码逐个核对过（2026-09-09），与第七节速查表一致。
