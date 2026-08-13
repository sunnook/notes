# WebRTC 完整业务流程分析：初始化 → 协商 → 通话 → 链路变化 → 断开

> 读者画像：具备 C/C++ 经验，熟悉高级 C++ 用法但需要补充；已有模块认知，需要端到端流程串联。
> 前置文档：`wr-modules-analysis.md`（模块架构分析）。

---

## 目录

| 章节 | 标题 | 摘要 |
|---|---|---|
| 第 1 章 | 全景概览 | 五大阶段全景图、控制流/数据流/状态机三层分离、线程模型总览 |
| 第 2 章 | 阶段一：初始化 | PeerConnectionFactory → PeerConnection → MediaEngine 创建全流程 |
| 第 3 章 | 阶段二：SDP 协商 | Offer/Answer、ICE 候选收集、DTLS 握手、ICE 连接检查 |
| 第 3.5 章 | 重新协商 vs 初次协商 | 触发场景、ICE Restart、DTLS 复用、状态机差异、增量修改、控制流对比 |
| 第 4 章 | 阶段三：通话进行中 | 音视频发送/接收完整链路、DataChannel、拥塞控制闭环、视频自适应 |
| 第 5 章 | 阶段四：链路变化 | 网络切换、ICE 重连、DTLS 重握手、拥塞响应、自适应触发 |
| 第 6 章 | 阶段五：正常断开 | 应用关闭、SDP BYE、DTLS CloseNotify、资源清理顺序 |
| 第 7 章 | 阶段六：异常断开 | 断网、ICE 超时、DTLS 断开、编码器崩溃、远端无响应、部分恢复 |
| 第 8 章 | 跨阶段协作总览 | 模块角色矩阵、协议栈交互图、QoS 协作图、端到端数据流、线程消息流、生命周期 |

---

## 第 1 章：全景概览

### 1.1 完整业务流程全景图

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                        WebRTC 完整业务流程                                        │
│                                                                                  │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌────────┐│
│  │ 阶段一   │────▶│ 阶段二   │────▶│ 阶段三   │────▶│ 阶段四   │────▶│ 阶段五 ││
│  │ 初始化   │     │ 协商     │     │ 通话     │     │ 链路变化 │     │ 正常断开││
│  └──────────┘     └──────────┘     └──────────┘     └──────────┘     └────────┘│
│       │                                                        ▲                │
│       │                                                        │                │
│       │                    ┌──────────┐                         │                │
│       └────────────────────│ 阶段六   │◀────────────────────────┘                │
│                            │ 异常断开  │                                          │
│                            └──────────┘                                          │
│                                                                                  │
│  ─────────────────────────────────────────────────────────────────────────────  │
│                                                                                  │
│  控制流（信令/状态机）：                                                          │
│    PeerConnection → SDP → ICE → DTLS → RTP/RTCP → Close                         │
│                                                                                  │
│  数据流（媒体/协议包）：                                                          │
│    麦克风/摄像头 → 编码 → RTP → 网络 ← RTP ← 解码 ← 扬声器/屏幕                  │
│                                                                                  │
│  状态机（内部状态转换）：                                                         │
│    New → Connecting → Connected → Completed → Failed / Disconnected → Closed    │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

以下为参考

<think>
1.  **分析用户的需求**：
    *   用户指出之前回答中的“WebRTC 完整业务流程全景图”有点乱，要求重新画一下。
    *   原图存在几个问题：
        *   阶段一到五的横向流程，加上阶段六的回环，视觉上显得杂乱。
        *   控制流、数据流、状态机堆叠在下方，没有很好地与上方阶段结合，导致整体看起来像个大杂烩，不够清晰。
    *   目标：重新设计一张清晰、专业、结构化的WebRTC业务流全景图，使用ASCII/Unicode字符画，体现出WebRTC的核心阶段、控制流、数据流和状态机，且布局整洁。

2.  **重新设计全景图的结构**：
    *   为了避免乱，可以采用**分层+分阶段**的矩阵式布局，或者**泳道图**风格的ASCII画法。
    *   **横向**：WebRTC的生命周期阶段（初始化 -> 信令协商 -> 媒体协商/建链 -> 媒体传输 -> 动态调整 -> 断开）。
    *   **纵向**：不同的维度（控制流/信令、数据流/媒体、网络传输层/底层协议）。
    *   这样能清晰展示每个阶段在各个维度上发生了什么。

3.  **梳理WebRTC的核心流程**：
    *   **阶段1：初始化** -> 获取设备，创建PeerConnection。
    *   **阶段2：信令协商** -> SDP Offer/Answer交换。
    *   **阶段3：连接建立** -> ICE收集候选者，连通性检查，DTLS握手，SRTP建立。
    *   **阶段4：媒体传输** -> RTP/RTCP传输，NACK/FEC抗丢包，GCC拥塞控制，Jitter Buffer。
    *   **阶段5：动态调整** -> 网络变化（ICE Restart），带宽估计变化（码率/分辨率调整）。
    *   **阶段6：断开** -> 正常关闭或异常断开。

4.  **绘制ASCII图（草稿与迭代）**：

    *   *尝试1：泳道图风格*
        ```text
        阶段:   [1.初始化]  ->  [2.信令协商]  ->  [3.建链]  ->  [4.媒体传输]  ->  [5.动态调整]  ->  [6.断开]
        ----------------------------------------------------------------------------------------
        信令流: 创建PC    交换SDP Offer/Answer  ICE候选交换  RTCP反馈     ICE Restart     Close
        ----------------------------------------------------------------------------------------
        媒体流: 获取音视频  (无)                 (无)        编码->RTP->网络   降码率/降分辨率    (无)
                设备                                                       解码<-RTP<-网络
        ----------------------------------------------------------------------------------------
        底层链路: (无)     (无)                 STUN/TURN    DTLS握手      网络探测          连接断开
                                                    ICE检查  SRTP建立
        ```
        这种方式比较清晰，但可能不够“全景”，缺少一点宏观感。

    *   *尝试2：更结构化的模块化全景图*
        把WebRTC分成三大平面：**信令控制面**、**媒体数据面**、**网络传输面**，然后贯穿整个生命周期。

        ```text
        ╔══════════════════════════════════════════════════════════════════════════════════╗
        ║                              WebRTC 业务流全景图                                  ║
        ╚══════════════════════════════════════════════════════════════════════════════════╝

        【时间轴/生命周期】
        [1. 初始化] ──▶ [2. 信令协商] ──▶ [3. 媒体协商与建链] ──▶ [4. 媒体传输与控制] ──▶ [5. 动态调整/断开]

        ┌─────────────────────────────────────────────────────────────────────────────────┐
        │ 1. 信令控制面 - 负责业务逻辑与会话建立                                            │
        │   getUserMedia  ──▶  Signaling Server (WebSocket/HTTP)                          │
        │   PeerConnection     ↕ 交换 SDP (Offer/Answer: 编解码器, 带宽, RTP扩展)          │
        │                      ↕ 交换 ICE Candidates (IP/Port)                            │
        └─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼ (协商完成后，进入P2P或TURN中继)
        ┌─────────────────────────────────────────────────────────────────────────────────┐
        │ 2. 网络传输面 - 负责打通底层链路与加密                                            │
        │   ICE (Interactive Connectivity Establishment)                                  │
        │   ├─ Host Candidate (局域网直连)                                                │
        │   ├─ Server Reflexive Candidate (NAT穿透, STUN)                                │
        │   └─ Relay Candidate (中继转发, TURN)                                           │
        │         │                                                                       │
        │         ▼                                                                       │
        │   DTLS (Datagram TLS) 握手 ──▶ 协商SRTP密钥 ──▶ SRTP/SRTCP 加密通道建立          │
        └─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼ (链路打通，开始传输)
        ┌─────────────────────────────────────────────────────────────────────────────────┐
        │ 3. 媒体数据面 - 负责音视频处理与QoS控制                                          │
        │                                                                                 │
        │  [发送端 Sender Pipeline]                                                       │
        │  采集 ─▶ 前处理(降噪/美颜) ─▶ 编码器 ─▶ RTP打包 ─▶ [抗丢包FEC/NACK生成] ─▶ Pacer│
        │   │             (H264/VP8/Opus)        │          (FlexFEC/ULPFEC)          │ │
        │   │                                     │                                     │ ▼
        │   │                                     └──────────────────────────────────▶ 网络
        │   │                                                                           │
        │  [接收端 Receiver Pipeline]                                                  │
        │   网络 ─▶ RTP接收/乱序重排 ─▶ [抗丢包恢复/NACK请求] ─▶ Jitter Buffer ─▶ 解码器│
        │                                    (FEC解码/重传)         (平滑抖动)          │ │
        │                                                                              ▼
        │                                                                          渲染/播放
        │                                                                                 │
        │  [QoS反馈闭环 - RTCP]                                                          │
        │   接收端 ──▶ RR (丢包率/RTT/抖动) / NACK ──▶ 发送端                            │
        │   发送端 ──▶ GCC带宽估计 ──▶ 调整编码器码率/帧率/FEC冗余率                      │
        └─────────────────────────────────────────────────────────────────────────────────┘
        ```

5.  **优化和调整**：
    *   用户之前提到原图“乱”，原图的问题在于阶段划分和流程线交叉。现在的分层设计（信令面、网络面、媒体面）配合生命周期，逻辑非常清晰，不会交叉。
    *   补充状态机的信息，可以放在右侧或者底部，不干扰主流程。
    *   调整字符画对齐，确保在不同设备上看起来整齐。

6.  **最终成图设计**：
    *   顶部：生命周期阶段。
    *   中间：三大平面（信令控制面、网络传输面、媒体数据面），用箭头连接，体现从信令到建链，再到传输的递进关系。
    *   底部：状态机流转。
    *   用清晰的边框和分隔线。

7.  **撰写回复**：
    *   承认之前的图确实有点乱。
    *   给出重新设计的、基于“三大平面”和“生命周期”维度的全景图。
    *   对图中的各个部分进行简要的补充说明，确保专业性。
</think>之前那张图确实因为流程线交叉和模块堆叠显得有些杂乱。为了让 WebRTC 的业务流更加清晰，我摒弃了之前的平铺式画法，改用**“生命周期 + 三大平面（信令、网络、媒体）”**的维度来重新绘制这张全景图。

这样画的好处是：你能一眼看出 WebRTC 在不同阶段，信令、网络和媒体分别在干什么，以及它们是如何协同的。

### WebRTC 完整业务流全景图（重构版）

```text
╔════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                WebRTC 完整业务流全景架构图                                       ║
╚════════════════════════════════════════════════════════════════════════════════════════════════╝

【时间轴 / 生命周期】
[1. 初始化] ──▶ [2. 信令协商] ──▶ [3. 媒体协商与建链] ──▶ [4. 媒体传输与 QoS 控制] ──▶ [5. 动态调整/断开]

┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                             1. 信令控制面                          │
│   职责：交换元数据、协商能力、传递网络信息（非 WebRTC 标准，常借 WebSocket/SIP 实现）            │
│                                                                                             │
│   Peer A                          Signaling Server                          Peer B            │
│      │ ◀────────── WebSocket 连接 ──────────▶ │ ◀────────── WebSocket 连接 ──────────▶ │      │
│      │                                        │                                        │      │
│      │──── 1. CreateOffer (SDP) ────────────▶│────────────────────────────────────▶  │      │
│      │ ◀─── 2. CreateAnswer (SDP) ───────────│◀─────────────────────────────────────  │      │
│      │──── 3. SetLocalDescription ───────────│                                       │      │
│      │──── 4. SetRemoteDescription ──────────│                                       │      │
│      │                                        │                                        │      │
│      │──── 5. ICE Candidates (Trickle ICE) ─▶│────────────────────────────────────▶  │      │
└──────┼────────────────────────────────────────┼────────────────────────────────────────┼──────┘
       │                                        │                                        │
       ▼                                        ▼                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                             2. 网络传输面                              │
│   职责：打通 P2P 链路、建立加密通道                                                            │
│                                                                                             │
│   [ICE 候选收集]                               [ICE 候选收集]                                  │
│   ├─ Host (本机 IP)                            ├─ Host (本机 IP)                               │
│   ├─ SRFLX (STUN 穿透 NAT)                     ├─ SRFLX (STUN 穿透 NAT)                        │
│   └─ RELAY (TURN 中继)                         └─ RELAY (TURN 中继)                           │
│         │                                            │                                       │
│         └──────────── [ICE 连通性检查] ──────────────┘                                       │
│                            (STUN Binding 请求/响应测试)                                       │
│                                    │                                                         │
│                                    ▼                                                         │
│                         [DTLS 握手] (验证证书，协商加密算法)                                    │
│                                    │                                                         │
│                                    ▼                                                         │
│                    [SRTP/SRTCP 传输通道建立完成] (媒体加密通道就绪)                              │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
       │                                                                                       │
       ▼                                                                                       ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                          3. 媒体数据面 & QoS 控制                   │
│   职责：音视频采集、编解码、传输、抗丢包、拥塞控制                                               │
│                                                                                             │
│   ▶ 发送端流水线:                                                                            │
│   [摄像头/麦克风] ─▶ [采集/前处理] ─▶ [编码器 (H264/VP8/Opus)] ─▶ [RTP 打包]                  │
│                                                                                             │
│                                        ┌──────── QoS 决策中心 ────────┐                       │
│                                        │                                 │                       │
│                                        ▼                                 ▼                       │
│                                 [Pacer 平滑发送] ◀───────── [GCC 拥塞控制] (动态调整码率)      │
│                                        │                                 ▲                       │
│                                        ▼                                 │                       │
│                                 [抗丢包生成器] ◀────────── [基于 RTT/丢包率决策]             │
│                                 ├─ NACK (不主动发，等对方请求)                                 │
│                                 ├─ ULPFEC / FlexFEC (生成冗余包)                              │
│                                 └─ RED / In-band FEC (音频冗余)                               │
│                                        │                                 │                       │
│                                        ▼                                 │                       │
│   ================================== [SRTP 网络] ==================================  │
│                                        │                                 │                       │
│                                        ▼                                 │                       │
│   ▶ 接收端流水线:                      │                                 │                       │
│   [RTP 收包/乱序重排] ◀────────────────┘                                 │                       │
│         │                                                                                   │
│         ├─▶ [NACK 请求模块] ── (丢包时发 RTCP NACK 给发送端) ──────────────┘                       │
│         ├─▶ [FEC 解码恢复] (用冗余包恢复丢失的 RTP 包)                                          │
│         ├─▶ [Jitter Buffer] (平滑网络抖动，等待 FEC/重传数据)                                   │
│         │                                                                                   │
│         ▼                                                                                   │
│   [解码器] ─▶ [后处理] ─▶ [渲染/扬声器]                                                       │
│         │                                                                                   │
│         └─▶ [统计模块] ── (发送 RTCP RR：丢包率/RTT/带宽估计) ──────────────┐                       │
│                                                                             │                       │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│  状态机流转:                                                                                 │
│  New ──▶ Connecting (ICE检查中) ──▶ Connected (首个ICE成功) ──▶ Completed (选定最佳链路)      │
│                                  │                                                           │
│                                  └─▶ Failed (全候选失败) / Disconnected (链路丢失) ──▶ Closed │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 图解说明（配合全景图阅读）

#### 1. 三个平面的解耦
WebRTC 架构最核心的设计是**信令与媒体分离**：
*   **信令控制面**：负责“互相认识”。通过业务自己的信令服务器（如 WebSocket），交换 SDP（我有能力编什么码）和 ICE Candidate（我有哪些网络入口）。WebRTC 标准并不规定信令怎么传。
*   **网络传输面**：负责“互相连通”。通过 ICE 框架，尝试各种 NAT 穿透方案（直连、STUN、TURN），打通后进行 DTLS 握手，生成 SRTP 加密密钥。
*   **媒体数据面**：负责“互相交流”。链路通了之后，音视频数据才走这条路，并在路上实时进行 QoS（抗丢包、拥塞控制）调节。

#### 2. QoS 决策中心（重点）
在媒体数据面中，发送端和接收端形成了一个闭环：
*   **接收端**：收到包后，如果发现丢包，会判断是否可以通过 FEC 直接恢复；如果不行，通过 RTCP 发送 NACK 请求重传。同时，接收端持续通过 RTCP RR 报告网络状况（丢包率、RTT）。
*   **发送端**：收到反馈后，`GCC`（拥塞控制）预估出当前可用带宽。发送端的分配器会将带宽分配给编码器（调整画质）、FEC生成器（调整冗余率）和重传队列。最后由 `Pacer`（平滑发送器）按一定速率发往网络，避免瞬间发洪了网络。

这样重构后，纵向是时间流程，横向是功能平面，逻辑递进会清晰很多。



### 1.2 五大阶段定义与触发条件

| 阶段 | 触发条件 | 核心事件 | 关键协议/算法 |
|---|---|---|---|
| **一：初始化** | 应用调用 `CreatePeerConnectionFactory()` | 创建工厂、引擎、线程 | 无（纯本地） |
| **二：协商** | 应用调用 `CreateOffer()` | SDP 生成/解析、ICE 候选收集、DTLS 握手、ICE 连接检查 | SDP、ICE/STUN、DTLS |
| **三：通话** | ICE Connected + DTLS Established | 音视频流建立、RTP/RTCP 收发、拥塞控制、视频自适应 | RTP、RTCP、GCC/BWE |
| **四：链路变化** | 网络切换/带宽变化/编码质量变化 | ICE 重连、DTLS 重握手、BWE 调整、自适应降级 | ICE、DTLS、GCC、视频适配 |
| **五：正常断开** | 应用调用 `Close()` 或对端 BYE | SDP BYE、DTLS CloseNotify、资源释放 | SDP、DTLS |
| **六：异常断开** | 网络中断/超时/崩溃 | 超时检测、回退策略、部分恢复 | ICE Timeout、Heartbeat |

### 1.3 控制流 vs 数据流 vs 状态机

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        三层分离架构                                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  控制流（Control Plane）                                                     │
│  ─────────────────────                                                         │
│  职责：管理连接生命周期、协商参数、状态转换                                     │
│  路径：PeerConnection → SDP → ICE → DTLS → MediaSession                      │
│  特点：低频、高可靠、必须有序                                                   │
│                                                                              │
│  数据流（Data Plane）                                                        │
│  ─────────────────────                                                         │
│  职责：传输音视频媒体数据和 DataChannel 数据                                   │
│  路径：采集 → 编码 → RTP → 网络 ← RTP ← 解码 → 渲染                          │
│  特点：高频、低延迟、容忍丢包                                                   │
│                                                                              │
│  状态机（State Machine）                                                     │
│  ─────────────────────                                                         │
│  职责：管理内部状态转换，驱动控制流和数据流                                     │
│  状态：New → Connecting → Connected → Completed → Failed/Disconnected/Closed │
│  特点：确定性、可预测、可恢复                                                   │
│                                                                              │
│  三者关系：                                                                    │
│    状态机 ← 监听 → 控制流事件（SDP 完成、ICE 连接）                            │
│       │                                                                        │
│       ├─ 驱动 → 控制流（创建 Stream、启动编码）                                 │
│       └─ 驱动 → 数据流（允许 RTP 收发）                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 1.4 线程模型总览

WebRTC 采用 **线程亲和性（Thread Affinity）** 模型，不同层运行在不同线程上：

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        WebRTC 线程模型                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  应用线程 (App Thread)                                                       │
│  ──────────────────                                                           │
│  - 创建 PeerConnectionFactory / PeerConnection                               │
│  - 调用 API: CreateOffer, AddTrack, CreateDataChannel                        │
│  - 所有 API 调用通过 Proxy::Call() 切换到 pc_thread_                          │
│                                                                              │
│  pc_thread_ (信令线程)                                                       │
│  ──────────────────                                                           │
│  - PeerConnection 对象所在线程                                               │
│  - SDP 生成/解析                                                             │
│  - ICE 状态管理                                                              │
│  - 媒体轨道管理（AddTrack/RemoveTrack）                                       │
│  - 所有控制面操作在此线程顺序执行                                              │
│                                                                              │
│  worker_thread_ (工作线程，每个 Engine 一个)                                  │
│  ──────────────────                                                           │
│  - MediaEngine (VoiceEngine + VideoEngine) 所在线程                          │
│  - Call 对象所在线程                                                         │
│  - 音视频流创建/销毁                                                         │
│  - 编解码器调度                                                              │
│  - RTP/RTCP 包收发                                                           │
│                                                                              │
│  ProcessThread (模块线程，每个 Call 一个)                                     │
│  ──────────────────                                                           │
│  - 周期性调用各 Module::Process()                                             │
│  - audio_coding / video_coding / congestion_controller / pacing             │
│  - 音频处理管道 (ADM → APE → audio_coding)                                   │
│  - 视频处理管道 (VCM → VC → RTP)                                             │
│                                                                              │
│  网络线程 (Network Threads)                                                  │
│  ──────────────────                                                           │
│  - UDPPort / TCP Port 的 Socket I/O                                          │
│  - STUN/TURN 请求/响应                                                       │
│  - 底层 Socket 接收/发送                                                      │
│                                                                              │
│  编码器线程 (Encoder Task Queue)                                              │
│  ──────────────────                                                           │
│  - 视频编码任务队列                                                           │
│  - 音频编码任务队列                                                           │
│  - 异步执行，避免阻塞主处理线程                                                │
│                                                                              │
│  线程间通信方式：                                                              │
│    Proxy::Call() → 投递 lambda 到目标线程                                     │
│    AsyncInvoker → 异步派发到 worker_thread_                                   │
│    sigslot → 信号槽（同线程内事件通知）                                        │
│    Socket → 网络线程回调到 worker_thread_                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 第 2 章：阶段一 — 初始化

> **触发条件**：应用进程启动，首次调用 `CreatePeerConnectionFactory()`。
> **核心特征**：纯本地操作，不涉及任何网络协议；负责创建整个 WebRTC 运行所需的工厂、引擎、线程和任务队列。
> **耗时**：通常 50~200ms（取决于编码器枚举和音频设备初始化）。

### 2.1 创建 PeerConnectionFactory（入口工厂）

`PeerConnectionFactory` 是整个 WebRTC 体系的 **入口点**，承担三大职责：

1. **线程池创建** — 创建 signaling_thread、worker_thread、network_thread
2. **MediaEngine 组装** — 聚合音频设备(ADM)、音频处理(APM)、编解码器工厂
3. **PeerConnection 工厂** — 通过 `CreatePeerConnection()` 方法创建独立连接实例

```
+----------------------------------------------------------------------+
|                    PeerConnectionFactory 创建流程                      |
+----------------------------------------------------------------------+
|                                                                      |
|  应用线程                                                             |
|  ----------                                                           |
|                                                                      |
|  1. 创建 TaskQueueFactory                                            |
|     task_queue_factory = CreateDefaultTaskQueueFactory()              |
|                                                                      |
|  2. 创建 Thread 对象                                                 |
|     signaling_thread = new rtc::Thread("signaling")                   |
|     worker_thread = new rtc::Thread("worker")                         |
|     network_thread = new rtc::Thread("network")                       |
|     -> 每个 Thread 内部创建 EventDispatcher (select/poll/IOCP)        |
|                                                                      |
|  3. 启动线程                                                         |
|     signaling_thread->Start()  -> 进入 Run() 循环，处理 Task           |
|     worker_thread->Start()      -> 进入 Run() 循环                    |
|     network_thread->Start()     -> 进入 Run() 循环                    |
|                                                                      |
|  4. 创建 PeerConnectionFactoryDependencies                            |
|     deps.network_thread = network_thread                              |
|     deps.worker_thread = worker_thread                                |
|     deps.signaling_thread = signaling_thread                          |
|     deps.task_queue_factory = task_queue_factory                      |
|     deps.audio_encoder_factory = ...                                  |
|     deps.video_encoder_factory = ...                                  |
|     deps.audio_decoder_factory = ...                                  |
|     deps.video_decoder_factory = ...                                  |
|     deps.network_manager = new rtc::BasicNetworkManager()             |
|     deps.socket_factory = new rtc::BasicPacketSocketFactory()         |
|                                                                      |
|  5. 构造 PeerConnectionFactory                                       |
|     factory = new PeerConnectionFactory(deps)                         |
|                                                                      |
|  6. 内部初始化 (PeerConnectionFactory 构造函数内)                     |
|     -> CreateRtcEventLog_w()  创建事件日志                             |
|     -> CreateCallFactory()    创建 Call 工厂                           |
|     -> CreateChannelManager() 创建 ChannelManager                      |
|     -> channel_manager_->Initialize(...) 初始化各 MediaEngine          |
|                                                                      |
|  -----> scoped_refptr<PeerConnectionFactory>                        |
|  应用线程: factory 持有强引用，生命周期贯穿整个应用                     |
|                                                                      |
+----------------------------------------------------------------------+
```

**关键设计**：

- `PeerConnectionFactory` 本身是 `scoped_refptr` 引用计数对象，可在多线程间安全传递
- 但它 **不** 遵循线程亲和性 — 它的 `signaling_thread()`/`worker_thread()`/`network_thread()` 可被任何线程调用
- 真正的线程亲和性体现在 `PeerConnection` 对象上：所有对 `PeerConnection` 的 API 调用必须通过 `Proxy::Call()` 切换到 `signaling_thread_` 执行

### 2.2 创建 PeerConnection（连接实例）

应用调用 `factory->CreatePeerConnection(configuration, dependencies)` 创建第一个（通常也是唯一一个）`PeerConnection` 实例：

```
+----------------------------------------------------------------------+
|                  PeerConnection 创建流程                               |
+----------------------------------------------------------------------+
|                                                                      |
|  应用线程 (调用 CreatePeerConnection)                                 |
|  ----------------------------------------------------------------    |
|                                                                      |
|  1. 通过 Proxy 将创建任务投递到 signaling_thread                     |
|     Proxy::Call(signaling_thread_, [deps, config] {                   |
|       return new PeerConnection(deps, config);                        |
|     })                                                                |
|                                                                      |
|  2. signaling_thread_ 上执行 PeerConnection 构造函数:                 |
|                                                                      |
|     PeerConnection::PeerConnection(...) {                             |
|       // 2.1 创建 Call 对象 (worker_thread)                           |
|       call_ = call_factory_->Create(config.call_config);             |
|       // Call 内部创建:                                               |
|       //   - ProcessThread (音视频处理循环)                            |
|       //   - Pacer (pacing 线程)                                      |
|       //   - RtpTransportControllerSend (发送传输控制)                 |
|       //   - GccCongestionController (拥塞控制器)                      |
|       //   - RemoteBitrateEstimator (远端带宽估计)                     |
|       //                                                              |
|       // 2.2 创建 JsepTransportController (信令传输层)                 |
|       transport_controller_ =                                         |
|         std::make_unique<JsepTransportController>(...);               |
|       // 内部创建:                                                    |
|       //   - IceTransport (ICE 传输层)                                |
|       //   - DtlsTransport (DTLS 传输层)                              |
|       //   - SCTPTransport (SCTP 数据通道)                            |
|       //   - 各 Transport 之间通过 sigslot 信号链连接                  |
|       //                                                              |
|       // 2.3 创建 ChannelManager (通道管理器)                          |
|       channel_manager_ = factory->channel_manager();                  |
|       channel_manager_->Init(pc.get());                               |
|       // 内部包含:                                                    |
|       //   - WebRtcVoiceEngine (音频引擎)                             |
|       //   - WebRTCVideoEngine (视频引擎)                             |
|       //                                                              |
|       // 2.4 初始化 RtcEventLog                                       |
|       event_log_ = factory->CreateRtcEventLog_w();                    |
|       // 记录所有信令、ICE、DTLS、RTP 事件，用于调试                   |
|       //                                                              |
|       // 2.5 创建 MediaTransportFactory (可选: WebRTC Media Transport) |
|       // 融合 DTLS + SRTP 的新一代传输方案                             |
|       //                                                              |
|       // 2.6 状态机初始状态:                                          |
|       state_ = PeerConnectionState::kNew;                             |
|       //                                                              |
|     }                                                                |
|                                                                      |
|  3. 返回 scoped_refptr<PeerConnection>                               |
|                                                                      |
+----------------------------------------------------------------------+
```

**关键对象关系**（构造完成后）：

```
PeerConnectionFactory (应用线程持有)
+-- signaling_thread_  --> PeerConnection (在此线程创建)
|   +-- call_  --> Call (在 worker_thread 上运行)
|   |   +-- AudioSendStream[]
|   |   +-- AudioReceiveStream[]
|   |   +-- VideoSendStream[]
|   |   +-- VideoReceiveStream[]
|   |   +-- GccCongestionController
|   |   +-- Pacer
|   |   +-- RtpTransportControllerSend
|   |   +-- RemoteBitrateEstimator
|   |   +-- AudioState
|   |   +-- ProcessThread (周期性 Process)
|   +-- JsepTransportController
|   |   +-- IceTransport
|   |   +-- DtlsTransport
|   |   +-- SCTPTransport
|   +-- ChannelManager
|   |   +-- WebRtcVoiceEngine
|   |   |   +-- WebRtcVoiceMediaChannel[] (音频)
|   |   |   +-- ADM (AudioDeviceModule)
|   |   |   +-- APM (AudioProcessing)
|   |   |   +-- AudioMixer
|   |   +-- WebRTCVideoEngine
|   |       +-- WebRtcVideoChannel[] (视频)
|   +-- RtcEventLog
+-- worker_thread_  --> Call 和 MediaEngine 运行在此
+-- network_thread_ --> 网络 I/O 相关操作
```

### 2.3 MediaEngine 初始化详解

`MediaEngine` 是音视频处理的 **核心引擎**，在 `ChannelManager::Initialize()` 中被创建和配置：

```
+----------------------------------------------------------------------+
|                  MediaEngine 初始化流程                                |
+----------------------------------------------------------------------+
|                                                                      |
|  创建入口: cricket::CreateMediaEngine(MediaEngineDependencies deps)   |
|                                                                      |
|  +-------------------------+  +-------------------------+            |
|  |  音频部分 (VoiceEngine)  |  |  视频部分 (VideoEngine)  |            |
|  +-------------------------+  +-------------------------+            |
|                                                                      |
|  adm_ (AudioDeviceModule)            video_encoder_factory_          |
|   - 枚举音频设备                        - 应用传入 (可能包装          |
|   - 初始化音频管道                       SimulcastEncoderAdapter)     |
|   - 选择默认输入/输出设备               video_decoder_factory_        |
|   - 启动音频线程                          - 应用传入                 |
|                                                                      |
|  apm_ (AudioProcessing)               枚举所有支持的编解码器:          |
|   - AEC (回声消除)                      音频: ISAC, Opus, G711, CN   |
|   - NS (噪声抑制)                       视频: VP8, VP9, H264, AV1    |
|   - AGC (自动增益)                     接收端:                        |
|   - VAD (语音检测)                      音频: Opus, ISAC, G711, CN   |
|   - GainController                      视频: VP8, VP9, H264, AV1    |
|                                                                      |
|  audio_mixer_ (混音器)             audio_state_ (AudioState)         |
|   - 混合多个音频源                    - 音频质量监控                   |
|   - 产生 10ms 音频帧                 - APM 模块质量指示               |
|     (160 samples @ 16kHz)          +-------------------------+       |
|                                                                      |
|  audio_coding_ (AudioCoding)                                       |
|   - 音频编码器管理                                                   |
|   - 音频解码器管理                                                   |
|  +-------------------------+                                         |
|                                                                      |
|  初始化后状态:                                                        |
|    send_codecs_ = [Opus 48kHz, ISAC 16kHz, ISAC 32kHz, G711, CN]    |
|    recv_codecs_ = [Opus 48kHz, ISAC 16kHz, ISAC 32kHz, G711, CN]    |
|    video_send_codecs_ = [VP8, VP9, H264, AV1] (取决于 encoder_)      |
|    video_recv_codecs_ = [VP8, VP9, H264, AV1] (取决于 decoder_)      |
|                                                                      |
+----------------------------------------------------------------------+
```

**音频管道初始化细节**：

```
ADM (AudioDeviceModule) 初始化:
+----------------------------------------------------------------------+
|  ADM 内部结构                                                         |
|                                                                      |
|  +------------+   +------------+   +------------+                   |
|  | 输入路径    |   | 输出路径    |   | 定时路径    |                   |
|  | (录制)     |   | (播放)     |   | (Process)  |                   |
|  +------------+   +------------+   +------------+                   |
|  | 硬件驱动层   |   | 硬件驱动层   |   | 10ms 定时器  |                   |
|  | (CoreAudio/ |   | (CoreAudio/ |   |            |                   |
|  |  ALSA/WDMA) |   |  ALSA/WDMA) |   | ADM::Process()                 |
|  |            |   |            |   |   触发录制回调                     |
|  | 硬件检测   |   | 音量控制    |   | APM::Process()                   |
|  | (枚举设备) |   | (SetOutputVolume) |   AEC/NS/AGC/VAD               |
|  |            |   |            |   | audio_coding::Incoming()          |
|  | 录制回调   |   | 播放队列    |   |   处理接收音频                     |
|  | (OnData)  |   | (PlayoutBuffer)|   |            |                   |
|  | -> 原始 PCM|   |            |   |            |                   |
|  +------------+   +------------+   +------------+                   |
|                                                                      |
|  线程模型:                                                            |
|    - 硬件线程: 音频驱动回调 (高优先级，低延迟)                          |
|    - ProcessThread: 10ms 周期调用 ADM::Process()                       |
|    - 应用线程: 通过 Proxy 调用 ADM API                                 |
|                                                                      |
+----------------------------------------------------------------------+
```

### 2.4 线程分配与 Proxy 创建

WebRTC 的线程模型在 `PeerConnectionFactory` 创建时就已经全部搭建完毕：

```
+----------------------------------------------------------------------+
|                  线程生命周期                                          |
+----------------------------------------------------------------------+
|                                                                      |
|  PeerConnectionFactory::PeerConnectionFactory(deps)                  |
|  ----------------------------------------------------------------    |
|                                                                      |
|  1. signaling_thread_ = deps.signaling_thread                        |
|     -> 所有 PeerConnection 控制面操作在此线程执行                      |
|     -> 所有 SDP 生成/解析在此线程执行                                  |
|     -> Proxy<PeerConnectionInterface> 将跨线程调用转发到此线程         |
|                                                                      |
|  2. worker_thread_ = deps.worker_thread                              |
|     -> Call 对象创建在此线程                                          |
|     -> MediaEngine (VoiceEngine/VideoEngine) 在此线程 Init()         |
|     -> RTP/RTCP 包处理在此线程                                        |
|     -> 编码器调度在此线程                                              |
|     -> ProcessThread 的 Process() 循环在此线程运行                     |
|                                                                      |
|  3. network_thread_ = deps.network_thread                            |
|     -> ICE 候选发现和网络管理                                          |
|     -> STUN 请求发送/接收                                              |
|     -> 网络路由变化通知                                                |
|                                                                      |
|  Proxy 创建 (当 CreatePeerConnection 被调用时):                        |
|  ----------------------------------------------------------------    |
|                                                                      |
|  应用线程: PeerConnection* pc = factory->CreatePeerConnection(...)    |
|                                                                      |
|  内部实现:                                                            |
|    auto pc = new PeerConnection(deps, config);                        |
|    return PeerConnectionInterface::Proxy2::Create(                    |
|      deps.signaling_thread,                                          |
|      std::unique_ptr<PeerConnectionInterface>(pc),                    |
|      &deps.dependencies);                                            |
|                                                                      |
|  结果: 应用线程持有的是 Proxy<PeerConnectionInterface>                 |
|  所有虚函数调用 (CreateOffer, AddTrack, etc.) 都被 Proxy 拦截，        |
|  通过 signaling_thread_->Post() 投递 lambda 到 signaling_thread 执行   |
|                                                                      |
+----------------------------------------------------------------------+
```

**Proxy 模式核心实现**：

```cpp
// Proxy 模板: WrapType 是接口类型，UnwrapType 是实际实现
template <typename WrapType, typename UnwrapType, typename Tag>
class Proxy : public WrapType {
 public:
  static scoped_refptr<WrapType> Create(
      TaskQueueBase* target_thread,
      std::unique_ptr<UnwrapType> object,
      Dependencies* deps);

  // 所有虚函数调用都被拦截:
  RTCError CreateOffer(const CreateSessionDescriptionObserver&) override {
    // 跨线程投递到 target_thread_
    signaling_thread_->Post(
        rtc::Bind(&Proxy::CreateOfferImpl, this, wrapped_observer));
  }

 private:
  // 实际实现在目标线程上执行
  void CreateOfferImpl(scoped_refptr<CreateSessionDescriptionObserver> observer);

  TaskQueueBase* const signaling_thread_;  // 目标线程
  std::unique_ptr<UnwrapType> object_;      // 实际 PeerConnection 对象
};
```

### 2.5 控制流时序图

```
App Thread         PeerConnectionFactory      PeerConnection        MediaEngine
------             -------------------         ---------------        -----------

CreateTaskQueueFactory()
-------------------->

new Thread("signaling")
new Thread("worker")
new Thread("network")
-------------------->  Start()
                      ---------------------->
                                               Start()
                      ----------------------->  ProcessThread 启动

PeerConnectionFactoryDependencies
(thread + factories)
                      new PeerConnectionFactory(deps)
                      CreateChannelManager()
                      ---------------------->

                      channel_manager_->Init()
                      ---------------------->
                                               CreateMediaEngine()
                      ----------------------->  ADM 初始化
                                               APM 初始化
                                               编解码器枚举
                                               send_codecs_ 填充

scoped_refptr<PeerConnectionFactory> 返回
<--------------------

CreatePeerConnection(config, deps)
-------------------->  Proxy::Call(signaling)
                      new PeerConnection()
                      +-- CreateCall()
                      +-- TransportController
                      +-- EventLog

scoped_refptr<PeerConnectionInterface> (Proxy) 返回
<--------------------+
```

### 2.6 C++ 知识点：unique_ptr 所有权转移与依赖注入

**2.6.1 unique_ptr 所有权链**

WebRTC 在初始化阶段大量使用 `std::unique_ptr` 实现 **明确的所有权转移**：

```cpp
// PeerConnectionFactory 构造函数中：
PeerConnectionFactory::PeerConnectionFactory(PeerConnectionFactoryDependencies& deps)
    : apm_(deps.audio_processing.get() ? deps.audio_processing : CreateDefaultApm()) {
  // deps.audio_processing 是 raw pointer，所有权不转移（工厂只借用）
  // deps.video_encoder_factory 是 unique_ptr，所有权转移:
  video_encoder_factory_ = std::move(deps.video_encoder_factory);
  // deps.video_encoder_factory 现在为空，调用者不再拥有该对象
}
```

三种参数所有权的区别：
- **raw pointer 参数** (`AudioDeviceModule* adm`)：所有权不归工厂所有，工厂只借用，生命周期由调用者管理
- **unique_ptr 参数** (`unique_ptr<VideoEncoderFactory>`)：所有权转移给工厂，调用者 `move` 后不再拥有
- **scoped_refptr 参数** (`scoped_refptr<AudioEncoderFactory>`)：引用计数共享，谁用谁 `AddRef`，最后释放

**2.6.2 依赖注入模式 (Dependency Injection)**

`PeerConnectionFactoryDependencies` 和 `MediaEngineDependencies` 是典型的 **DI 容器**：

```cpp
// PeerConnectionFactoryDependencies -- 应用层注入所有外部依赖
struct PeerConnectionFactoryDependencies {
  rtc::Thread* network_thread;          // 基础设施
  rtc::Thread* worker_thread;           // 基础设施
  rtc::Thread* signaling_thread;        // 基础设施
  std::unique_ptr<TaskQueueFactory> task_queue_factory;
  std::unique_ptr<rtc::NetworkManager> network_manager;
  std::unique_ptr<rtc::PacketSocketFactory> socket_factory;
  rtc::scoped_refptr<AudioEncoderFactory> audio_encoder_factory;
  std::unique_ptr<VideoEncoderFactory> video_encoder_factory;
  rtc::scoped_refptr<AudioDecoderFactory> audio_decoder_factory;
  std::unique_ptr<VideoDecoderFactory> video_decoder_factory;
  // ... 更多可选依赖
};

// MediaEngineDependencies -- 引擎层注入处理链组件
struct MediaEngineDependencies {
  TaskQueueFactory* task_queue_factory;
  rtc::scoped_refptr<AudioDeviceModule> adm;
  rtc::scoped_refptr<AudioEncoderFactory> audio_encoder_factory;
  rtc::scoped_refptr<AudioDecoderFactory> decoder_factory;
  rtc::scoped_refptr<AudioMixer> audio_mixer;
  rtc::scoped_refptr<AudioProcessing> audio_processing;
  std::unique_ptr<VideoEncoderFactory> video_encoder_factory;
  std::unique_ptr<VideoDecoderFactory> video_decoder_factory;
};
```

**设计优势**：
1. **可测试性**：单元测试可注入 mock 编码器、mock ADM
2. **平台隔离**：Android/iOS/Desktop 只需提供不同的依赖，工厂逻辑统一
3. **编译裁剪**：通过 GN 参数控制哪些依赖被注入，自动裁剪二进制

**2.6.3 scoped_refptr 的线程亲和性销毁**

`scoped_refptr` 类似 `std::shared_ptr`，但有一个关键区别：**引用计数归零时的销毁操作发生在对象所属线程上**：

```cpp
// scoped_refptr 内部逻辑 (简化)
~scoped_refptr() {
  if (ptr_) {
    // 如果当前线程 == 对象创建线程 (通过 ThreadAnnotation 验证)
    //   -> 直接调用 ptr_->Release()
    // 否则
    //   -> Post 到对象所属线程执行 Release
    //   -> 确保销毁也在该线程执行 (thread-affine destruction)
  }
}
```

这保证了：
- 所有 `AddRef()`/`Release()` 在同一个线程顺序执行 -> 无需锁
- 对象销毁也在所属线程 -> 避免跨线程访问已销毁内存
- 配合 `rtc_thread_annotations_` 在 debug 模式下做线程安全性检查

---

## 第 3 章：阶段二 — SDP 协商

> **触发条件**：应用调用 `CreateOffer()` 或 `CreateAnswer()`。
> **核心特征**：这是 WebRTC 连接建立中最复杂的阶段，涉及 SDP 生成/解析、ICE 候选收集、DTLS 握手、ICE 连接检查四个子协议的串行/并行协作。
> **耗时**：通常 200ms~2s（取决于网络质量和 STUN/TURN 服务器可达性）。

### 3.1 本地 SDP 生成（Offer）

当应用调用 `pc->CreateOffer(observer, options)` 时，触发 Offer 生成流程：

```
+----------------------------------------------------------------------+
|                  本地 SDP Offer 生成流程                                |
+----------------------------------------------------------------------+
|                                                                      |
|  PeerConnection::CreateOffer(observer, options)                        |
|  (signaling_thread)                                                   |
|  |                                                                   |
|  | 1. 检查 signaling_state:                                          |
|  |    kStable → 允许创建 Offer                                        |
|  |    kHaveLocalOffer/kHaveLocalPrAnswer → 不允许（已有未确认的 Offer） |
|  |                                                                   |
|  | 2. 设置 signaling_state = kHaveLocalOffer                          |
|  |    → 触发 SignalSignalingState 信号                                |
|  |    → PeerConnectionState → kConnecting                             |
|  |                                                                   |
|  | 3. 构建 CreateSessionDescriptionOptions                             |
|  |    - offer_to_receive_audio: 是否允许接收音频                       |
|  |    - offer_to_receive_video: 是否允许接收视频                       |
|  |    - ice_restart: true → 生成新的 ice-ufrag/ice-pwd               |
|  |    - bundle_policy: kBundlePolicyBalanced → 使用 BUNDLE            |
|  |                                                                   |
|  | 4. 通过 webrtc_session_desc_factory_->CreateOffer()                 |
|  |    → JsepSessionDescription::CreateOffer()                         |
|  |    → SessionDescriptionCreator::CreateOffer()                      |
|  |                                                                   |
|  | 5. SessionDescriptionCreator 内部:                                 |
|  |    a) ChannelManager::CreateSessionDescription()                   |
|  |       → 遍历所有 Channel (VoiceChannel + VideoChannel)             |
|  |       → 每个 Channel 调用 CreateSessionDescription()               |
|  |       → 生成 m=audio / m=video m-line                              |
|  |    b) 编解码器协商:                                                 |
|  |       - 从 MediaEngine 获取 send_codecs_ 和 recv_codecs_           |
|  |       - 取本地支持的 codecs 与远端兼容的 codecs                      |
|  |       - 按优先级排序写入 a=rtpmap                                 |
|  |    c) SSRC 分配:                                                   |
|  |       - 为每个 SendStream 分配唯一 SSRC                              |
|  |       - 写入 a=ssrc 和 a=msid                                     |
|  |    d) RTP 扩展注册:                                                |
|  |       - a=extmap 1 URI:urn:ietf:params:rtp-hdrext:ssrc-audio-level |
|  |       - a=extmap 2 URI:...,abs-sendtime                           |
|  |       - a=extmap 3 URI:...,transport-cc                           |
|  |    e) BUNDLE 组:                                                   |
|  |       - a=bundle only:0 1 (audio mid=0, video mid=1)              |
|  |    f) ICE ufrag/pwd:                                              |
|  |       - a=ice-ufrag:xxx                                           |
|  |       - a=ice-pwd:yyy                                             |
|  |    g) DTLS fingerprint:                                           |
|  |       - a=fingerprint:sha-256 XX:XX:...                           |
|  |    h) 候选收集:                                                    |
|  |       - PortAllocator 开始收集 Host/Server-Reflexive/Relay 候选     |
|  |       - a=candidate:... 逐步追加到 SDP                             |
|  |                                                                   |
|  | 6. 回调 observer->OnSuccess(JsepSessionDescription*)               |
|  |                                                                   |
|  └─────────────────────────────────────────────────────────────┘    |
|                                                                      |
+----------------------------------------------------------------------+
```

**生成的 SDP Offer 示例结构**：

```
v=0
o=- 4597384729408889148 2 IN IP4 0.0.0.0
s=-
t=0 0
a=group:BUNDLE audio video
a=ice-options:trickle
a=extmap-allow-mixed

--- m=audio (mid=audio) ---
m=audio 9 UDP/TLS/RTP/SAVPF 111 103 104 0 8 106 105 13
c=IN IP4 0.0.0.0
a=mid:audio
a=ice-ufrag:abc123
a=ice-pwd:def456789012345678901234
a=fingerprint:sha-256 AA:BB:CC:...
a=setup:actpass
a=rtcp-mux
a=rtcp-rsize
a=rtpmap:111 Opus/48000/2
a=rtpmap:103 ISAC/16000
a=rtx=50000
a=ssrc:12345678 cname:xxx
a=ssrc:12345678 msid:stream-id track-id
a=msid-semantic: WMS
a=sendrecv

--- m=video (mid=video) ---
m=video 9 UDP/TLS/RTP/SAVPF 96 97 98 99
c=IN IP4 0.0.0.0
a=mid:video
a=ice-ufrag:abc123
a=ice-pwd:def456789012345678901234
a=fingerprint:sha-256 AA:BB:CC:...
a=setup:actpass
a=rtcp-mux
a=rtpmap:96 VP8/90000
a=rtpmap:97 VP9/90000
a=rtpmap:98 H264/90000
a=ssrc:87654321 cname:xxx
a=ssrc:87654321 msid:stream-id track-id
a=sendrecv
```

**关键设计决策**：

- **`a=setup:actpass`**：Offer 端不主动发起 DTLS 连接，等待 Answer 端指定 role（active/passive）
- **`a=ice-ufrag` 和 `a=ice-pwd`**：每次新 Offer 时重新生成（除非 `ice_restart=false` 且复用旧值）
- **BUNDLE**：所有媒体流共享同一个 UDP 端口，通过 MID header 区分
- **Trickle ICE**：SDP 中可以只包含 Host 候选，Server-Reflexive/Relay 候选通过信令通道后续追加

### 3.2 ICE 候选收集

ICE 候选收集由 `PortAllocator` 在 `network_thread` 上异步执行：

```
+----------------------------------------------------------------------+
|                  ICE 候选收集流程                                      |
+----------------------------------------------------------------------+
|                                                                      |
|  PortAllocator (network_thread)                                       |
|  |                                                                   |
|  | 1. 创建 PortAllocatorSession                                       |
|  |    → 为每个 m=section 创建一个 session                             |
|  |    → 每个 session 绑定到一个 ice-ufrag/ice-pwd 组合                |
|  |                                                                   |
|  | 2. 并行收集三类候选:                                               |
|  |                                                                      |
|  |  Host 候选 (本地网卡)                                               |
|  |  ──────────────                                                     |
|  |  PortAllocatorSession::OnNetworkChanged()                           |
|  |    → 枚举本地网络接口                                                |
|  |    → 为每个接口创建 HostPort                                         |
|  |    → 类型: host, 协议: udp                                          |
|  |    → 优先级: (126 - delay) * 65536 + type_preference                |
|  |    → 例如: 192.168.1.100:54321 host udp                            |
|  |                                                                      |
|  |  Server-Reflexive 候选 (STUN)                                       |
|  |  ──────────────────────                                             |
|  |  PortAllocatorSession 发送 STUN Binding Request                       |
|  |    → 到配置的 STUN server (google:stun.l.google.com:19302)           |
|  |    → 解析 STUN Binding Response 获取公网 IP:Port                    |
|  |    → 创建 ServerReflexivePort                                        |
|  |    → 类型: srflx, 协议: udp                                         |
|  |    → 优先级: 100 * 65536 + type_preference                           |
|  |    → 例如: 123.45.67.89:12345 srflx udp rel addr:192.168.1.100      |
|  |                                                                      |
|  |  Relay 候选 (TURN)                                                  |
|  |  ────────────────                                                   |
|  |  仅当 STUN 失败或配置了 TURN server 时                               |
|  |  PortAllocatorSession 创建 TURN 绑定请求                              |
|  |    → 到配置的 TURN server                                            |
|  |    → 分配 TURN 分配地址                                              |
|  |    → 创建 RelayPort                                                  |
|  |    → 类型: relay                                                     |
|  |    → 优先级: 0 (最低优先级)                                          |
|  |    → 例如: 1.2.3.4:54321 relay udp rel addr:192.168.1.100           |
|  |                                                                      |
|  | 3. 每收集到一个候选:                                                 |
|  |    → SignalCandidateGathered 信号                                    |
|  |    → JsepTransportController::OnTransportCandidateGathered_n()       |
|  |    → SignalIceCandidatesGathered(mid, candidates)                    |
|  |    → PeerConnection 回调应用层                                       |
|  |                                                                      |
|  | 4. ICE 收集完成:                                                     |
|  |    → SignalIceGatheringState → complete                              |
|  |    → PeerConnectionState 仍为 kConnecting（等待 ICE 连接）            |
|  |                                                                      |
+----------------------------------------------------------------------+
```

**候选优先级计算**：

```
优先级 = (1 << 24) * type_preference + (1 << 8) * local_preference + component_id

类型优先级:
  host     = 126
  srflx    = 100
  prflx    = 110  (peer-reflexive, ICE 检查过程中发现)
  relay    = 0

典型优先级示例:
  Host UDP (IPv4):   126 * 65536 + 0 + 1 = 8,258,049
  SRFLX UDP:         100 * 65536 + 0 + 1 = 6,553,601
  Relay UDP:          0 * 65536 + 0 + 1 = 1
```

### 3.3 远程 SDP 应用（Answer）

远端 Answer SDP 通过信令通道到达后，应用调用 `pc->SetRemoteDescription(observer, answer)`：

```
+----------------------------------------------------------------------+
|                  SetRemoteDescription 流程                             |
+----------------------------------------------------------------------+
|                                                                      |
|  PeerConnection::SetRemoteDescription(observer, answer)               |
|  (signaling_thread)                                                   |
|  |                                                                   |
|  | 1. 检查 signaling_state:                                          |
|  |    kStable + Offer → 期望 Answer                                   |
|  |    kHaveLocalOffer → 合法状态                                      |
|  |                                                                   |
|  | 2. 解析 SDP:                                                      |
|  |    → JsepSessionDescription::Parse(answer_sdp)                    |
|  |    → 验证 m-line 顺序与 Offer 一致                                 |
|  |    → 提取 BUNDLE 组信息                                            |
|  |    → 提取每个 m-line 的 ICE/DTLS/Codec 信息                       |
|  |                                                                   |
|  | 3. JsepTransportController::ApplyDescription(local=false, type=SdpType::kAnswer) |
|  |                                                                      |
|  |    3a) 验证 BUNDLE 组:                                              |
|  |        → ValidateAndMaybeUpdateBundleGroup()                       |
|  |        → 确认 Answer 的 BUNDLE 顺序与 Offer 一致                    |
|  |                                                                      |
|  |    3b) 为每个 Content (m-line) 创建/更新 JsepTransport:             |
|  |        → MaybeCreateJsepTransport(local=false, content, description) |
|  |        → 创建 IceTransport (绑定到已有的 PortAllocatorSession)       |
|  |        → 创建 DtlsTransport:                                        |
|  |           - 解析 a=fingerprint 和 a=crypto                          |
|  |           - 设置远端证书指纹                                         |
|  |           - 确定 DTLS Role:                                         |
|  |             Offer 端 setup=actpass → Answer 端 setup=active          |
|  |             → Answerer 角色 = active (主动发起 DTLS)                |
|  |             → Offerer 角色 = passive (被动接受 DTLS)                |
|  |                                                                      |
|  |    3c) 创建 MediaChannel (Stream):                                  |
|  |        → ChannelManager::UpdateTransport()                          |
|  |        → 为每个 m=audio 创建 AudioReceiveStream                      |
|  |        → 为每个 m=video 创建 VideoReceiveStream                      |
|  |        → 从 SDP 中解析 SSRC、codec payload type、rtpmap             |
|  |        → 设置 RTCP 接收端                                           |
|  |                                                                      |
|  |    3d) 确定 ICE Role:                                               |
|  |        → 如果本端是 Offerer: ice_role = ICEROLE_CONTROLLING         |
|  |        → 如果本端是 Answerer: ice_role = ICEROLE_CONTROLLED         |
|  |        → 控制端发送 STUN CHECKING，受控端响应 STUN RESPONSE          |
|  |                                                                      |
|  | 4. signaling_state = kStable                                       |
|  |    → 触发 SignalSignalingState 信号                                 |
|  |                                                                      |
|  | 5. 回调 observer->OnSuccess()                                       |
|  |                                                                      |
+----------------------------------------------------------------------+
```

### 3.4 DTLS 握手

DTLS 握手在 ICE 连接建立的同时或之后进行，是 SRTP 密钥交换的机制：

```
+----------------------------------------------------------------------+
|                  DTLS-SRTP 握手流程                                    |
+----------------------------------------------------------------------+
|                                                                      |
|  角色确定:                                                           |
|  ───────────                                                         |
|  Offerer: setup=actpass + Answerer: setup=active                      |
|  → Answerer = active (主动发起 DTLS ClientHello)                      |
|  → Offerer = passive (等待 ClientHello，回复 ServerHello)              |
|                                                                      |
|  DTLS 握手 (在 DTLSTransport 内部，network_thread):                    |
|  ──────────────────────────────────────────────────────                |
|                                                                      |
|  Active (Answerer)                           Passive (Offerer)       |
|  |                                              |                     |
|  │ ClientHello                                  │                     |
|  │  - random timestamp + nonce                  │                     |
|  │  - cipher_suites: TLS_ECDHE_ECDSA_WITH_...   │                     |
|  │  - cert_chain: RTCCertificate (X.509)        │                     |
|  │  ─────────────────────────────────────────▶ │                     |
|  │                                              │ ServerHello         |
|  │                                              │  - selected cipher  │
|  │                                              │  - server random    │
|  │                                              │ ───────────────────▶│
|  │                                              │                     |
|  │  ServerKeyExchange (ECDSA key)               │                     |
|  │  ─────────────────────────────────────────▶ │                     |
|  │                                              │                     |
|  │  ClientKeyExchange                           │                     |
|  │  ─────────────────────────────────────────▶ │                     |
|  │                                              │                     |
|  │  CertificateVerify                           │                     |
|  │  ─────────────────────────────────────────▶ │                     |
|  │                                              │                     |
|  │                                              │ ChangeCipherSpec    |
|  │                                              │ ───────────────────▶│
|  │                                              │                     |
|  │  ChangeCipherSpec                            │ Finished            |
|  │  ─────────────────────────────────────────▶ │ ───────────────────▶│
|  │                                              │                     |
|  │  Finished                                      |                     |
|  │ ─────────────────────────────────────────────▶│                     |
|  │                                              │                     |
|  │  [DTLS 握手完成]                              │                     |
|  │                                              │                     |
|  └──────────────────────────────────────────────────────────────────┘    |
|                                                                      |
|  SRTP 密钥派生 (DTLS Finished 完成后):                                |
|  ──────────────────────────────────────                               |
|  │  使用 DTLS 交换的 ECDHE 密钥，通过 HKDF 派生:                       |
|  │    master_secret = HKDF(ECDHE_shared_secret)                       |
|  │    local_key = HKDF(master_secret, "client key", label)            |
|  │    remote_key = HKDF(master_secret, "server key", label)           |
|  │    local_salt = HKDF(master_secret, "client salt", label)          |
|  │    remote_salt = HKDF(master_secret, "server salt", label)         |
|  │                                                                      |
|  │  结果: 每个方向获得 SRTP 密钥 + salt                                 |
|  │    → 用于 RTP 加密 (AES_CM_128_HMAC_SHA1_80)                        |
|  │    → 用于 RTCP 加密                                                  |
|  │    → 密钥索引 (salt) 用于 RTCP-FB 区分                              |
|  │                                                                      |
+----------------------------------------------------------------------+
```

### 3.5 ICE 连接检查

ICE 连接检查是 ICE 协议的核心——两端通过 STUN 报文互相探测，找到最佳路径：

```
+----------------------------------------------------------------------+
|                  ICE 连接检查流程                                      |
+----------------------------------------------------------------------+
|                                                                      |
|  角色:                                                               |
|  ─────                                                               |
|  CONTROLLING (Offerer): 主动发起检查                                  |
|  CONTROLLED (Answerer): 被动响应检查                                  |
|                                                                      |
|  检查机制:                                                           |
|  ────────                                                            |
|  ICE 使用 STUN (Session Traversal Utilities for NAT) 协议执行检查:    |
|                                                                      |
|  CONTROLLING (Offerer)                               CONTROLLED      |
|  | (发送 STUN Binding Request)                          (Answerer)     |
|  |                                                                      |
|  │ STUN Binding Request (CHECKING)                                      |
|  │  - type: STUN_BINDING_REQUEST                                        |
|  │  - username: "<controlled-ufrag> <controlling-ufrag>"                |
|  │  - MAC: STUN_MESSAGE_INTEGRITY (用 ice-pwd 计算 HMAC-SHA1)          |
|  │  - CANDIDATE-PAIR: 当前检查的候选对                                   |
|  │  ──────────────────────────────────────────────────────────────────▶│
|  │                                                                      |
|  │                                                                      │ STUN Binding Response (SUCCESS_RESPONSE)
|  │                                                                      │  - XOR-MAPPED-ADDRESS: 远端看到的本地 IP:Port
|  │                                                                      │ ──────────────────────────────────────────▶│
|  │                                                                      │
|  │  本地收到 SUCCESS_RESPONSE:                                          │
|  │  → 比较 XOR-MAPPED-ADDRESS 与远端候选                                │
|  │  → 如果匹配 → 候选对状态 = SUCCESS                                   │
|  │  → 触发 SignalCandidatePairChanged (checking → completed)             │
|  │  → 将该候选对设为活跃候选对 (active candidate pair)                   │
|  │  → ICE 连接状态 → connected                                          │
|  │                                                                      |
|  └──────────────────────────────────────────────────────────────────────┘|
|                                                                      |
|  候选对排序与检查顺序:                                                 |
|  ─────────────────────                                                 |
|  1. 根据 ICE 优先级对所有候选对排序                                     |
|  2. 按优先级从高到低依次发送 CHECKING 报文                              |
|  3. 第一个成功的候选对成为活跃候选对                                    |
|  4. 后续如果收到更优候选对的 SUCCESS → 切换 (preemptive)               |
|                                                                      |
|  ICE 状态机转换:                                                       |
|  ─────────────────                                                     |
|  new → checking → connected → completed                              |
|          ↘ failed (所有候选对超时)                                     |
|                                                                      |
|  超时机制:                                                             |
|  ────────                                                              |
|  每个候选对有 150ms 超时计时器                                         |
|  最多重试 7 次 (间隔递增: 2.5s, 5s, 10s, ...)                         |
|  全部失败 → ICE state = failed                                        |
|                                                                      |
+----------------------------------------------------------------------+
```

### 3.6 控制流时序图（完整 Offer→Answer→ICE→DTLS）

```
App          PeerConnection        JsepTransportCtrl     PortAllocator     DtlsTransport
 |                |                      |                    |                  |
 | CreateOffer()  |                      |                    |                  |
 |----->          |                      |                    |                  |
 |                | DoCreateOffer()      |                    |                  |
 |                |----->                |                    |                  |
 |                |                      PortAllocator::StartGathering()         |
 |                |                      |----->                |                  |
 |                |                      |                    收集 Host 候选      |
 |                |                      |<-----                |                  |
 |                | SignalCandidateGathered()                  |                  |
 |<-----          |----->                |                    |                  |
 | (local SDP)    |                      |                    |                  |
 |                | SetLocalDescription()                    |                  |
 |                |----->                |                    |                  |
 |                |                      ApplyDescription(local=true)            |
 |                |                      |----->                |                  |
 |                |                      |                    创建 IceTransport   |
 |                |                      |                    创建 DtlsTransport  |
 |                |                      |                    setup=passive       |
 |                |                      |<-------------------|                  |
 |                |                      |                    开始监听 DTLS       |
 |                |                      |                    |                  |
 |  [信令通道]     |                      |                    |                  |
 |  发送 SDP Offer |                    |                    |                  |
 | ◀──────────────|--------------------|--------------------|------------------|
 |  接收 SDP Answer|                    |                    |                  |
 |──────────────▶ |                    |                    |                  |
 |                | SetRemoteDescription()                 |                  |
 |                |----->                |                    |                  |
 |                |                      ApplyDescription(local=false)           |
 |                |                      |----->                |                  |
 |                |                      |                    解析 Answer SDP    |
 |                |                      |                    setup=active        |
 |                |                      |                    确定 ICE role       |
 |                |                      |                    确定 DTLS role      |
 |                |                      |                    |                  |
 |                |                      |<-------------------|                  |
 |                |                      |                    触发 DTLS 握手      |
 |                |                      |                    |<-----------------|
 |                |                      |                    |  ClientHello     |
 |                |                      |                    |----> 网络         |
 |                |                      |                    |<---- 网络         |
 |                |                      |                    |  ServerHello     |
 |                |                      |                    |                  |
 |                | SignalDtlsConnected()|                    |                  |
 |<---------------|-------------------->|--------------------|------------------|
 |                | ICE connected        |                    |                  |
 |<---------------|-------------------->|--------------------|------------------|
 |                |                      |                    |                  |
 |  PeerConnectionState: kConnected      |                    |                  |
 |                |                      |                    |                  |
 |  [通话开始，媒体流建立]                  |                    |                  |
 |                |                      |                    |                  |
```

### 3.7 C++ 知识点：absl::optional 与 async 回调链

**3.7.1 absl::optional 在 SDP 解析中的应用**

WebRTC 中大量使用 `absl::optional` 表示 **可能缺失的 SDP 属性**：

```cpp
// SessionDescription 中，很多字段是可选的
class SessionDescription : public SessionDescriptionInterface {
 public:
  // BUNDLE 组是可选的——如果不支持 BUNDLE，返回 nullopt
  const absl::optional<ContentGroup>& bundle_group() const { return bundle_group_; }

  // ICE ufrag/pwd 在 trickle ICE 场景下可能暂时缺失
  const absl::optional<std::string>& ice_ufrag() const { return ice_ufrag_; }

  // DTLS fingerprint 是必需的（RFC 4145），但用 optional 做安全检查
  const absl::optional<std::string>& dtls_fingerprint() const { return dtls_fingerprint_; }
};

// 使用方式：
auto bundle = desc->bundle_group();
if (bundle) {
  // BUNDLE 启用，使用 bundle->FirstContentName()
} else {
  // 非 BUNDLE 模式，每个 m-line 独立端口
}
```

**3.7.2 async 回调链：CreateOffer → SetLocalDescription**

WebRTC 的 SDP 协商使用 **链式异步回调** 而非同步返回：

```cpp
// 第一层: CreateOffer (异步，需要枚举所有 codec)
pc->CreateOffer(
    rtc::AdaptedCallback<CreateSessionDescriptionObserver>::Create(
        [pc_weak = pc->weak_ptr_factory_.GetWeakPtr()](
            std::unique_ptr<SessionDescriptionInterface> offer) mutable {
          // 第二层: SetLocalDescription (异步，触发 ICE 收集)
          pc_weak->SetLocalDescription(
              rtc::AdaptedCallback<SetSessionDescriptionObserver>::Create(
                  [pc_weak = pc_weak](RTCError error) {
                    if (error.ok()) {
                      // 第三层: ICE 收集完成
                      // 通过 SignalIceCandidatesGathered 信号获取
                    }
                  }),
              std::move(offer));
        }),
    options);
```

**设计考量**：
- 回调链避免了阻塞任何线程
- 每个阶段可以独立失败（codec 枚举失败、SDP 解析失败、ICE 收集失败）
- `weak_ptr` 防止循环引用导致的内存泄漏
- `AdaptedCallback` 自动处理 `std::unique_ptr` 到 `scoped_refptr` 的转换

---

## 第 3.5 章：重新协商 vs 初次协商（对比分析）

> **核心问题**：重新建连（re-negotiation）的流程与初次协商是否相同？
> **答案**：**不完全相同**。核心协议栈（ICE/DTLS/SDP）复用，但状态机路径、Stream 管理、ICE/DTLS 行为有显著差异。

### 3.5.1 重新协商触发场景

```
+----------------------------------------------------------------------+
|                  重新协商触发场景                                       |
+----------------------------------------------------------------------+
|                                                                      |
|  场景 1: 应用层动态添加/移除媒体流                                      |
|  ──────────────────────────────────────────────────────────────       |
|  pc->AddTrack(track)                                                 |
|  pc->RemoveTrack(sender)                                             |
|  → 内部触发 CreateOffer (ice_restart=false)                           |
|  → 远端收到 Offer → CreateAnswer → SetRemoteDescription              |
|                                                                      |
|  场景 2: ICE Restart (重新 ICE 收集)                                   |
|  ──────────────────────────────────────────────────────────────       |
|  应用调用: pc->AddIceCandidate() 失败或网络切换                         |
|  内部触发: CreateOffer (ice_restart=true)                             |
|  → 生成新的 ice-ufrag/ice-pwd                                         |
|  → 保留已有 DTLS 连接                                                  |
|  → 复用已建立的 BUNDLE 端口                                             |
|                                                                      |
|  场景 3: 修改编码参数 (bitrate/resolution)                              |
|  ──────────────────────────────────────────────────────────────       |
|  sender.SetParameters(parameters)                                     |
|  → 如果参数兼容 (同 codec): 不需要 SDP 协商，直接修改 SendStream       |
|  → 如果参数不兼容 (切换 codec): 需要 CreateOffer                        |
|                                                                      |
|  场景 4: 远端发起重新协商                                               |
|  ──────────────────────────────────────────────────────────────       |
|  远端发送新的 SDP Offer                                                |
|  → 本端 CreateAnswer → SetLocalDescription                            |
|  → 行为与场景 1 对称                                                   |
|                                                                      |
|  场景 5: 完整断开后重新建连 (Close → New PeerConnection)                |
|  ──────────────────────────────────────────────────────────────       |
|  应用调用 pc->Close() 后再创建新的 PeerConnection                       |
|  → 完全重新初始化 (同初次协商)                                          |
|  → 或者复用 PeerConnectionFactory + RTCCertificate                     |
|                                                                      |
+----------------------------------------------------------------------+
```

### 3.5.2 初次协商 vs 重新协商 差异对比表

```
+------------------------+------------------------+------------------------+
|                        |   初次协商              |   重新协商              |
+------------------------+------------------------+------------------------+
|                        |                        |                        |
| 状态机起点              |   kNew                 |   kStable              |
|                        |   PeerConnectionState  |   signaling_state      |
|                        |                        |                        |
+------------------------+------------------------+------------------------+
|                        |                        |                        |
| signaling_state 转换   |   kNew → kHaveLocal    |   kStable → kHaveLocal |
|                        |   → kHaveRemoteOffer   |   → kHaveRemoteOffer   |
|                        |   → kStable            |   → kStable            |
|                        |                        |                        |
+------------------------+------------------------+------------------------+
|                        |                        |                        |
| SDP 生成               |   从零构建完整 SDP       |   基于当前状态增量修改    |
|                        |   所有 m-line 从头生成   |   复用已有 m-line       |
|                        |                        |   只修改变化的部分       |
|                        |                        |                        |
+------------------------+------------------------+------------------------+
|                        |                        |                        |
| ICE 行为               |   全新 ufrag/pwd        |   取决于 ice_restart 标志|
|                        |   全新候选收集           |   true: 新 ufrag/pwd    |
|                        |                        |   false: 复用旧 ufrag/pwd|
|                        |                        |                        |
+------------------------+------------------------+------------------------+
|                        |                        |                        |
| DTLS 行为              |   全新握手 (ClientHello) |   通常跳过握手           |
|                        |                        |   ICE Restart 时 DTLS   |
|                        |                        |   保持连接               |
|                        |                        |                        |
+------------------------+------------------------+------------------------+
|                        |                        |                        |
| MediaStream            |   全新创建所有 Stream    |   增量修改               |
|                        |   AudioSendStream[]     |   AddTrack → 新建       |
|                        |   VideoSendStream[]     |   RemoveTrack → 销毁    |
|                        |                        |   未修改的 Stream 保留   |
|                        |                        |                        |
+------------------------+------------------------+------------------------+
|                        |                        |                        |
| SSRC                   |   全新分配所有 SSRC     |   新增 SSRC             |
|                        |                        |   已有 SSRC 保留        |
|                        |                        |                        |
+------------------------+------------------------+------------------------+
|                        |                        |                        |
| BUNDLE                 |   从头建立 BUNDLE       |   复用 BUNDLE 端口       |
|                        |                        |                        |
+------------------------+------------------------+------------------------+
|                        |                        |                        |
| 耗时                    |   200ms ~ 2s           |   50ms ~ 500ms          |
|                        |                        |                        |
+------------------------+------------------------+------------------------+
```

### 3.5.3 ICE Restart：完整 ICE 重建 vs 复用

```
+----------------------------------------------------------------------+
|                  ICE Restart 流程                                     |
+----------------------------------------------------------------------+
|                                                                      |
|  触发: PeerConnection::CreateOffer(options) with ice_restart=true     |
|                                                                      |
|  1. SetNeedsIceRestartFlag()                                         |
|     → 设置 pending_ice_restarts_ 标志                                 |
|     → 下次 SetLocalDescription 时生成新的 ice-ufrag/ice-pwd           |
|                                                                      |
|  2. 生成新 Offer:                                                     |
|     → 新 ice-ufrag/ice-pwd (随机生成)                                 |
|     → 保留已有的 DTLS fingerprint (DTLS 连接不中断)                    |
|     → 保留已有的 BUNDLE 组信息                                         |
|     → 保留已有的 codec 列表                                           |
|                                                                      |
|  3. 远端收到 ICE Restart Offer:                                       |
|     → 检测到 ice-ufrag 变化 → 识别为 ICE Restart                      |
|     → 不销毁 DTLS 连接                                                |
|     → 启动新的 ICE 候选收集 (新 ufrag/pwd)                            |
|     → 回复 Answer (新 ufrag/pwd)                                      |
|                                                                      |
|  4. ICE 检查在新候选对上进行:                                          |
|     → 旧的活跃候选对被标记为废弃                                       |
|     → 新的候选对建立后切换                                             |
|                                                                      |
|  关键区别:                                                           |
|  ───────────                                                         |
|  ICE Restart:                                                       |
|    - 仅重建 ICE 层 (ufrag/pwd 变化 → 触发新收集)                      |
|    - DTLS 连接保持 (无需重新握手)                                     |
|    - RTP/RTCP 连接保持 (SRTP 密钥不变)                                |
|    - 媒体流不中断 (零感知切换)                                         |
|                                                                      |
|  全新 ICE:                                                          |
|    - 从零开始所有层                                                   |
|    - DTLS 握手 + ICE 检查 + 媒体流建立全部需要                        |
|    - 建立期间无法收发媒体                                             |
|                                                                      |
+----------------------------------------------------------------------+
```

### 3.5.4 DTLS 状态：已建立时跳过握手

```
+----------------------------------------------------------------------+
|                  DTLS 在重新协商中的行为                               |
+----------------------------------------------------------------------+
|                                                                      |
|  初次协商:                                                           |
|  ───────────                                                         |
|  DTLS 状态: New → Handshake → Connected                              |
|  → 完整 ClientHello → ServerHello → ... → Finished                   |
|  → 派生 SRTP 密钥                                                     |
|                                                                      |
|  重新协商 (ice_restart=false):                                       |
|  ─────────────────────────────                                       |
|  DTLS 状态: Connected → Connected (不变)                              |
|  → 完全跳过 DTLS 握手                                                 |
|  → SRTP 密钥不变                                                     |
|  → 媒体流零中断                                                       |
|                                                                      |
|  重新协商 (ice_restart=true):                                        |
|  ─────────────────────────────                                       |
|  DTLS 状态: Connected → Connected (不变)                              |
|  → 同样跳过 DTLS 握手                                                 |
|  → DTLS 连接与 ICE 解耦：ICE 重启不影响 DTLS                          |
|                                                                      |
|  何时需要 DTLS 重握手?                                               |
|  ─────────────────────                                               |
|  1. DTLS 连接断开后恢复                                               |
|  2. 证书轮换 (Certificate Rotation，WebRTC 4.9.1 引入)                |
|  3. 应用主动调用 SetCertificates() 更换证书                           |
|                                                                      |
+----------------------------------------------------------------------+
```

### 3.5.5 状态机差异

```
+----------------------------------------------------------------------+
|                  状态机路径对比                                        |
+----------------------------------------------------------------------+
|                                                                      |
|  初次协商:                                                           |
|  ───────────                                                         |
|                                                                      |
|  PeerConnectionState:                                                |
|  kNew → kConnecting → kConnected → kCompleted                        |
|                                                                      |
|  signaling_state:                                                    |
|  kStable → kHaveLocalOffer → kHaveRemoteOffer → kStable              |
|                                                                      |
+----------------------------------------------------------------------+
|                                                                      |
|  重新协商 (ice_restart=false):                                       |
|  ─────────────────────────────                                       |
|                                                                      |
|  PeerConnectionState:                                                |
|  kCompleted → kConnecting → kConnected → kCompleted                  |
|  (kCompleted 不变时可能不触发状态变化)                                 |
|                                                                      |
|  signaling_state:                                                    |
|  kStable → kHaveLocalOffer → kHaveRemoteOffer → kStable              |
|  (与初次相同的转换，但起点是 kStable 而非 kNew)                        |
|                                                                      |
+----------------------------------------------------------------------+
|                                                                      |
|  ICE Restart:                                                        |
|  ─────────────                                                       |
|                                                                      |
|  ICE 状态:                                                           |
|  kConnected → kConnecting → kConnected                             │
|  (不经过 kNew 和 kFailed)                                            |
|                                                                      |
|  PeerConnectionState:                                                |
|  kConnected → kConnecting → kConnected                             │
|  (可能不经过 kCompleted，取决于其他 transport 状态)                   |
|                                                                      |
+----------------------------------------------------------------------+
```

### 3.5.6 MediaStream 处理：全新创建 vs 增量修改

```
+----------------------------------------------------------------------+
|                  MediaStream 管理对比                                  |
+----------------------------------------------------------------------+
|                                                                      |
|  初次协商:                                                           |
|  ───────────                                                         |
|  ChannelManager::CreateSessionDescription()                          |
|  → 遍历所有 Track → 为每个 Track 创建 StreamParams                    |
|  → 为每个 SendStream 分配全新 SSRC                                    |
|  → 创建全新的 AudioSendStream / VideoSendStream                       |
|                                                                      |
|  重新协商 (AddTrack):                                                |
|  ────────────────────                                                |
|  1. 应用调用 pc->AddTrack(track)                                     |
|  2. 内部: ChannelManager::AddTrack(track)                             |
|     → 创建新的 MediaStream                                           |
|     → 创建新的 AudioSendStream / VideoSendStream                      |
|     → 分配新 SSRC                                                     |
|  3. CreateOffer (ice_restart=false)                                  |
|     → SDP 中新增一个 m-line (如果 codec 不同)                         |
|     → 或在现有 m-line 中追加新的 SSRC                                 |
|  4. 远端 CreateAnswer → 创建对应的 ReceiveStream                       |
|                                                                      |
|  重新协商 (RemoveTrack):                                             |
|  ──────────────────────                                              |
|  1. 应用调用 pc->RemoveTrack(sender)                                 |
|  2. 内部: ChannelManager::RemoveTrack(sender)                         |
|     → 标记 SendStream 为待销毁                                        |
|     → SDP 中移除对应的 SSRC 或 m-line                                 |
|  3. CreateOffer → 远端收到 → 销毁对应的 ReceiveStream                  |
|                                                                      |
+----------------------------------------------------------------------+
```

### 3.5.7 控制流对比时序图

```
+--------------------------------------------------------------+
|                  初次协商 vs 重新协商 对比                     |
+--------------------------------------------------------------+
|                                                              |
|  初次协商:                                                   |
|  ───────────                                                 |
|                                                              |
|  App    PC    TransportCtrl  MediaEngine   ICE/DTLS          |
|  |      |      |            |             |                 |
|  | CreateOffer()                                          |
|  |----->|      |            |             |                 |
|  |      | 创建全新 SDP      |             |                 |
|  |      |------>           |             |                 |
|  |      |            创建全新 Call Streams                    |
|  |      |            |----->                 |               |
|  |      |            |             创建全新 ICE Transport    |
|  |      |            |             |----->       |           |
|  |      |            |             |           创建全新 DTLS |
|  |      |            |             |             |----->     |
|  |      |            |             |             |  Handshake|
|  |      |            |             |             |<----->    |
|  |      |            |             |             |  Connected|
|  |      |            |             |<----|<------|           |
|  |      |            |<----|                 |               |
|  |      |<=========== 媒体流建立 ===========|               |
|                                                              |
|  重新协商 (AddTrack, ice_restart=false):                      |
|  ────────────────────────────────────────────────────────    |
|                                                              |
|  App    PC    TransportCtrl  MediaEngine   ICE/DTLS          |
|  |      |      |            |             |                 |
|  | AddTrack()                                             |
|  |----->|      |            |             |                 |
|  |      | 创建增量 SDP      |             |                 |
|  |      |------>           |             |                 |
|  |      |            仅创建新 Stream                    |     |
|  |      |            |----->                 |               |
|  |      |            |             复用已有 ICE Transport    |
|  |      |            |             |               |         |
|  |      |            |             |               |         |
|  |      |            |             |               |         |
|  |      |            |             |  DTLS 保持 Connected  |
|  |      |            |             |               |         |
|  |      |            |<----|                 |               |
|  |      |<=========== 新流建立 ===========|               |
|  |      |         已有流不受影响                             |
|                                                              |
+--------------------------------------------------------------+
```

### 3.5.8 何时不需要 SDP 重新协商？

```
+----------------------------------------------------------------------+
|                  免 SDP 协商的操作                                    |
+----------------------------------------------------------------------+
|                                                                      |
|  以下操作不需要触发 SDP 重新协商（零信令开销）:                         |
|                                                                      |
|  1. 视频码率调整 (同 codec 内)                                        |
|     sender.SetParameters({max_bitrate_bps: 1000000})                  |
|     → 直接修改 VideoSendStream 的码率参数                              |
|     → GCC 拥塞控制器自动响应                                          |
|                                                                      |
|  2. 视频分辨率/帧率调整 (同 codec 内)                                  |
|     sender.SetParameters({max_resolution: {width: 640, height: 480}}) |
|     → 修改 VideoSendStream 的分辨率参数                               |
|     → 编码器自适应                                                    |
|                                                                      |
|  3. 静音/取消静音                                                     |
|     track.SetMuted(true)                                              |
|     → 发送静音帧 (CN/PLI) 而非完全停止                                 |
|                                                                      |
|  4. DataChannel 数据收发                                              |
|     → 不受 SDP 协商影响                                               |
|                                                                      |
|  5. RTCP 反馈 (NACK/PLI/FIR/RR)                                      |
|     → RTCP 独立于 SDP，随时可发送                                     |
|                                                                      |
|  6. 接收端自适应 (Remote Bitrate Estimation)                          |
|     → 接收端根据 RTCP XR 报告自动调整解码器选择                         |
|                                                                      |
+----------------------------------------------------------------------+
```

---

## 第 4 章：阶段三 — 通话进行中

> **触发条件**：ICE Connected + DTLS Established。
> **核心特征**：音视频媒体流和 RTCP 控制流在已建立的传输通道上持续运行；拥塞控制闭环实时调节码率；视频自适应算法动态调整编码参数。
> **周期**：从通话开始到断开，持续运行。ProcessThread 以 10ms 周期循环调用各模块的 Process()。

### 4.1 音频发送链路（麦克风 → ADM → APE → 编码 → RTP → 网络）

```
+----------------------------------------------------------------------+
|                  音频发送完整链路                                       |
+----------------------------------------------------------------------+
|                                                                      |
|  线程分布:                                                            |
|  ──────────                                                          |
|  硬件线程 (音频驱动) → worker_thread (Call/ProcessThread) → network_thread (网络 I/O) |
|                                                                      |
|  步骤 1: 音频采集 (Hardware → ADM)                                    |
|  ──────────────────────────────────                                   |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | 音频硬件驱动    |   | ADM            |   | APM (Audio     |         |
|  | (CoreAudio/    |──▶| (AudioDevice   |──▶|  Processing)   |         |
|  |  ALSA/WDMA)    |   |  Module)       |   |                |         |
|  +----------------+   +----------------+   +----------------+         |
|                                     |         |                      |
|                                     |         ├── AEC (回声消除)      |
|                                     |         │   WebRtcAecm/AecmCore |
|                                     |         │   原理: 自适应滤波     |
|                                     |         │   参考: 发送端音频    |
|                                     |         │   输出: 消除回声的音频 |
|                                     |         ├── NS (噪声抑制)       |
|                                     |         │   WebRtcNs            |
|                                     |         │   原理: FFT+频谱分析   |
|                                     |         │   输出: 降噪音频       |
|                                     |         ├── AGC (自动增益)      |
|                                     |         │   WebRtcAgc           |
|                                     |         │   原理: 音量归一化     |
|                                     |         │   模式: Fixed/Analog/Legacy |
|                                     |         ├── VAD (语音检测)      |
|                                     |         │   WebRtcVad           |
|                                     |         │   输出: 语音/非语音标记 |
|                                     |         └── GainController      |
|                                     |             增益控制             |
|                                     |                                  |
|  数据格式: 16kHz/48kHz, 16-bit PCM, 10ms 帧 (160/480 samples)          |
|                                                                      |
|  步骤 2: 音频编码 (audio_coding)                                      |
|  ──────────────────────────────────                                   |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | AudioCoding    |   | Encoder 调度    |   | 编码选择        |         |
|  | Module         |   | (per-stream)   |   |                |         |
|  +----------------+   +----------------+   +----------------+         |
|       |                    |                    |                    |
|       | Encode(PCM)       |  Opus/ISAC/G711    |  选择逻辑:          |
|       | ─────────────────▶|                    |  - SDP 协商确定     |
|       |                    |                    |  - 优先级排序       |
|       |                    |                    |  - 带宽自适应降级   |
|       |                    |                    |                    |
|       |                    |  输出: 编码后字节   |                    |
|       |                    |  (通常 20~500 字节) |                    |
|       |                    |                    |                    |
|  关键细节:                                                                   |
|  - Opus 是最优选择: 支持 6kbps~510kbps，最低延迟 2.5ms                         |
|  - Opus 自动模式切换: 语音模式 (VOIP) / 音频模式 (music)                       |
|  - CNG (Comfort Noise Generation): 静音时发送 16 字节 CN 包                     |
|  - DTX (Discontinuous Transmission): 静音时不发送或发送 CN                     |
|                                                                      |
|  步骤 3: RTP 封装 (RTP/RTCP Module)                                    |
|  ──────────────────────────────────                                   |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | Packetizer     |   | RTP Header     |   | Frame Encryptor|         |
|  |                |   | 注入            |   | (可选 E2EE)   |         |
|  +----------------+   +----------------+   +----------------+         |
|       |                    |                    |                    |
|       | 添加 RTP Header:   |  - SSRC           |                    |
|       |  - Version (2)    |  - PT (payload type)|                   |
|       |  - Sequence Number |  - Timestamp      |                    |
|       |  - SSRC           |  - Extension:     |                    |
|       |                    |    MID/RID/Transport-CC |                |
|       |                    |                    |                    |
|       | 分帧策略:                                        |
|       | - 10ms 音频帧 → 1 个 RTP 包                      |
|       | - 如果编码器输出 > MTU: 分包 (Opus 多帧打包)       |
|       | - RTX: 复制 RTP 包，不同 seq number，用于重传       |
|                                                                      |
|  步骤 4: 加密 (Frame Encryptor / SRTP)                                |
|  ──────────────────────────────────                                   |
|                                                                      |
|  如果启用了 Insertable Streams (E2EE):                                |
|    → FrameEncryptorInterface::Encrypt(frame)                          |
|    → 在 RTP 封装后、SRTP 加密前拦截帧                                  |
|                                                                      |
|  标准 SRTP 加密 (DTLS 派生密钥):                                      |
|    → AES_CM_128_HMAC_SHA1_80                                         |
|    → 基于 SRTP 密钥索引区分控制平面 (RTCP) 和媒体平面 (RTP)            |
|                                                                      |
|  步骤 5: 发送 (RTP Transport → 网络)                                  |
|  ──────────────────────────────────                                   |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | RtpTransport   |   | Pacer          |   | Socket Send     |         |
|  | (SendRtp)      |──▶| (Pacing)       |──▶| (network_thread)|         |
|  +----------------+   +----------------+   +----------------+         |
|       |                    |                    |                    |
|       | 通过 Transport 接口发送                       |                  |
|       | AudioSendStream → VoiceMediaChannel         |                  |
|       | → SendRtp(packet, options)                  |                  |
|       | → JsepTransport → DtlsTransport             |                  |
|       | → IceTransport → Port → Socket              |                  |
|       |                    |                          |                  |
|       |                    | Pacing (整形):           |                  |
|       |                    | - 按 BWE 估算的带宽      |                  |
|       |                    |   控制发送速率            |                  |
|       |                    | - 避免应用层排队         |                  |
|       |                    | - 减少 BBR 误判          |                  |
|       |                    | - 典型: 100kbps → 8ms 间隔 |                  |
|       |                    |                    |                    |
|       |                    | 输出: UDP 包 → Socket 发送 |                  |
|                                                                      |
+----------------------------------------------------------------------+
```

### 4.2 音频接收链路（网络 → RTP → 解码 → APE → ADM → 扬声器）

```
+----------------------------------------------------------------------+
|                  音频接收完整链路                                       |
+----------------------------------------------------------------------+
|                                                                      |
|  线程分布:                                                            |
|  ──────────                                                          |
|  network_thread (接收 UDP) → worker_thread (ProcessThread) → 应用线程 (播放回调) |
|                                                                      |
|  步骤 1: RTP 接收与解包                                               |
|  ──────────────────────────────────                                   |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | Socket Receive |   | RTP Depacketizer|  | Frame Decryptor|         |
|  | (network_thread)|──▶|                |──▶| (可选 E2EE)    |         |
|  +----------------+   +----------------+   +----------------+         |
|       |                    |                    |                    |
|       | UDP 包到达                                         |          |
|       | → 通过 IceTransport → DtlsTransport              |          |
|       | → 解包 RTP Header                                |          |
|       | → 提取 SSRC, PT, SeqNum, Timestamp               |          |
|       | → 查找对应的 AudioReceiveStream (by SSRC)         |          |
|       |                    |                          |          |
|       |                    | SRTP 解密 (基于 DTLS 密钥)              |
|       |                    | → AES_CM_128_HMAC_SHA1_80           |
|       |                    | → 验证 MAC                           |
|       |                    |                    |                  |
|       |                    | 如果启用了 E2EE:                       |
|       |                    | → FrameDecryptorInterface::Decrypt()  |
|       |                    |                    |                  |
|                                                                      |
|  步骤 2: JitterBuffer (NetEq)                                        |
|  ────────────────────────                                            |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | NetEq          |   | 乱序重组       |   | 丢包隐藏 (PLC)  |         |
|  | (JitterBuffer) |   | (by SeqNum)   |   |                |         |
|  +----------------+   +----------------+   +----------------+         |
|       |                    |                    |                    |
|       | 输入: 乱序/延迟变化/丢包的 RTP 包         |                    |
|       |                    |                    |                    |
|       | 重组逻辑:                                        |                    |
|       | - 按 SeqNum 排序                                  |                    |
|       | - 维护缓冲区 (默认 200 个包)                       |                    |
|       | - 自适应延迟调整 (fast_accelerate)                |                    |
|       | - RTX 重传包合并                                  |                    |
|       |                    |                    |                    |
|       | 丢包检测:                                        |                    |
|       | - SeqNum 不连续 → 标记丢包                        |                    |
|       | - 触发 PLC (Packet Loss Concealment)             |                    |
|       | - PLC: 用上一帧参数生成模拟语音，平滑过渡           |                    |
|       |                    |                    |                    |
|       | 输出: 连续的 10ms PCM 帧 (16kHz/48kHz, 16-bit)     |                    |
|                                                                      |
|  步骤 3: RTCP 反馈处理                                               |
|  ──────────────────────────────────                                   |
|                                                                      |
|  接收端发送的 RTCP 报文:                                              |
|  ──────────────────────────────────                                   |
|  - RR (Receiver Report): 每 5s，报告接收统计                          |
|    → RR: SSRC of sender, RR count, Last SR timestamp, DLSR          |
|    → RR: Report Block per source                                    |
|      → Fraction Lost, Cumulative Packets Lost                       |
|      → Jitter, Last SR Timestamp                                    |
|                                                                      |
|  - NACK (Transport-Layer): 请求重传                                  |
|    → NACK: PID (lost packet seq num), Bitmask (burst)                |
|    → 仅在音频启用 transport-wide NACK 时发送                          |
|                                                                      |
|  - RTCP-FB PLI/FIR (视频用，音频一般不用)                               |
|                                                                      |
|  步骤 4: 音频混合 (AudioMixer)                                        |
|  ──────────────────────────────                                       |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | AudioMixer     |   | 多路混合       |   | 输出到 ADM      |         |
|  +----------------+   +----------------+   +----------------+         |
|       |                    |                    |                    |
|       | 混合所有 ReceiveStream 的解码输出         |                    |
|       | + 本地铃声/提示音                              |                    |
|       | → 产生 10ms 混合 PCM 帧                       |                    |
|       |                    |                    |                    |
|       | 注意: 每个 ReceiveStream 可单独设置 sink    |                    |
|       | SetSink() → 单独获取未混合的音频流          |                    |
|                                                                      |
|  步骤 5: 音频播放 (ADM Playout)                                        |
|  ──────────────────────────────                                       |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | ADM            |   | 硬件驱动层     |   | 扬声器/耳机     |         |
|  | (Playout)      |──▶|                |──▶|                 |         |
|  +----------------+   +----------------+   +----------------+         |
|       |                    |                    |                    |
|       | ADM::WritePlayoutData(PCM)               |                    |
|       | → 硬件驱动层缓冲                              |                    |
|       | → 定时输出到声卡                               |                    |
|       | → 时钟同步: 基于 RTP Timestamp 对齐          |                    |
|                                                                      |
+----------------------------------------------------------------------+
```

### 4.3 视频发送链路（采集 → VPM → 编码 → NACK/FEC → RTP → 网络）

```
+----------------------------------------------------------------------+
|                  视频发送完整链路                                       |
+----------------------------------------------------------------------+
|                                                                      |
|  线程分布:                                                            |
|  ──────────                                                          |
|  采集线程 (Camera/MediaSource) → worker_thread (编码/RTP) → network_thread (网络 I/O) |
|                                                                      |
|  步骤 1: 视频采集                                                     |
|  ──────────────────────────────────                                   |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | Camera/Media   |   | VideoSource    |   | VideoFrame      |         |
|  | Source         |   | (MediaSource)  |   | (scoped_refptr) |         |
|  +----------------+   +----------------+   +----------------+         |
|       |                    |                    |                    |
|       | 采集原始帧:                                        |                    |
|       | - I420 (YUV420P) 格式                            |                    |
|       | - 典型分辨率: 640x480, 1280x720, 1920x1080        |                    |
|       | - 典型帧率: 15/24/30/60 FPS                        |                    |
|       | - 帧间隔: 33ms (30fps) / 16.67ms (60fps)           |                    |
|       |                    |                    |                    |
|       | VideoSource → VideoSink 接口                     |                    |
|       | OnFrame(video_frame)                             |                    |
|       | → scoped_refptr<VideoFrame> (零拷贝引用计数)       |                    |
|                                                                      |
|  步骤 2: 视频预处理 (VideoProcessing - 可选)                           |
|  ──────────────────────────────────────────                           |
|                                                                      |
|  在编码前可插入处理:                                                  |
|  - 旋转/翻转 (Rotation/Flip)                                          |
|  - 分辨率缩放 (Scaling)                                               |
|  - 帧率适配 (FrameRate Adaptation)                                    |
|  - 背景虚化/替换 (Background Blur/Replace)                            |
|                                                                      |
|  步骤 3: 视频编码                                                     |
|  ──────────────────────────────────                                   |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | VideoSend      |   | VideoEncoder   |   | Simulcast       |         |
|  | Stream         |──▶| (per-layer)    |──▶| Encoder Adapter |         |
|  +----------------+   +----------------+   +----------------+         |
|       |                    |                    |                    |
|       | 输入: VideoFrame                                  |                    |
|       | → 关键帧请求 (PLI/FIR)                           |                    |
|       | → 帧率/分辨率/码率配置                            |                    |
|       |                    |                    |                    |
|       | 编码流程:                                         |                    |
|       | 1. 帧进入编码队列                                  |                    |
|       | 2. 编码器选择:                                     |                    |
|       |    - VP8 / VP9 / H264 / AV1                      |                    |
|       | 3. 编码:                                           |                    |
|       |    - I 帧 (关键帧): 完整帧                         |                    |
|       |    - P 帧 (预测帧): 差帧                           |                    |
|       |    - B 帧: WebRTC 不支持 (低延迟要求)               |                    |
|       | 4. 输出: EncodedImage (YUV + 比特流)               |                    |
|       |                    |                    |                    |
|       | Simulcast (多流编码):                              |
|       | - 同时编码 2~3 个不同分辨率的流                     |
|       | - 例如: QVGA (低) / VGA (中) / HD (高)             |
|       | - 每个流独立 SSRC                                   |
|       | - 根据带宽动态切换活跃流                             |
|       | - RID header extension 标识层                      |
|                                                                      |
|  步骤 4: NACK / FEC 增强                                            |
|  ──────────────────────────────────                                   |
|                                                                      |
|  NACK (重传):                                                        |
|  - 接收端通过 RTCP NACK 请求重传丢失包                              |
|  - 发送端维护已发送包缓存 (默认 1500ms)                              |
|  - 重传包使用 RTX SSRC (非媒体 SSRC)                                |
|                                                                      |
|  FEC (前向纠错) - FlexFEC:                                           |
|  - 为前 N 个媒体包生成 FEC 校验包                                   |
|  - FEC 包使用独立 SSRC 和 m-line                                    |
|  - 可恢复连续丢包 (burst loss)                                       |
|  - 开销: 通常 5%~20% 额外带宽                                        |
|                                                                      |
|  步骤 5: RTP 封装与发送                                               |
|  ──────────────────────────────────                                   |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | Packetizer     |   | RTP Header     |   | Pacer + Socket  |         |
|  |                |   | 注入            |   | Send            |         |
|  +----------------+   +----------------+   +----------------+         |
|       |                    |                    |                    |
|       | 视频 RTP 封装特点:                                    |                    |
|       | - 一帧可能分多个 RTP 包 (MTU 分割)                       |                    |
|       | - 使用 STUN payload 格式 (RFC 5769)                       |                    |
|       | - Fragmentation Header (FH) 指示分片                      |                    |
|       | - RTCP Sender Report (SR) / Receiver Report (RR)          |                    |
|       | - REMB (Receiver Estimated Maximum Bitrate)               |                    |
|       | - GCC Transport Wide Congestion Control (TWCC)            |                    |
|       |                    |                    |                    |
|       | Pacing: 视频包间隔比音频大 (码率高)                          |                    |
|       | 例如: 1Mbps @ 720p30 → 每包 ~4000 字节 → ~1ms 间隔         |                    |
|                                                                      |
+----------------------------------------------------------------------+
```

### 4.4 视频接收链路（网络 → RTP → JitterBuffer → 解码 → 渲染）

```
+----------------------------------------------------------------------+
|                  视频接收完整链路                                       |
+----------------------------------------------------------------------+
|                                                                      |
|  步骤 1: RTP 接收与重组                                               |
|  ──────────────────────────────────                                   |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | RTP Depacketizer|  | 分片重组       |   | Frame Decryptor |         |
|  +----------------+   +----------------+   +----------------+         |
|       |                    |                    |                    |
|       | 按 SSRC 分发到对应 VideoReceiveStream  |                    |
|       | 按 SeqNum 排序                                    |                    |
|       | 重组分片帧 (FH header)                           |                    |
|       | SRTP 解密 / E2EE 解密                             |                    |
|                                                                      |
|  步骤 2: JitterBuffer                                                  |
|  ────────────────────────                                            |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | Video Jitter   |   | 丢包检测       |   | 帧缓冲          |         |
|  | Buffer         |   | (SeqNum gap)   |   | (Frame Buffer)  |         |
|  +----------------+   +----------------+   +----------------+         |
|       |                    |                    |                    |
|       | 视频 JitterBuffer 比音频更复杂:                          |                    |
|       | - 需要按帧 (而非包) 管理延迟                               |                    |
|       | - 等待帧的所有分片到达后才输出                              |                    |
|       | - 超时丢弃不完整帧 (通常 200ms)                            |                    |
|       |                    |                    |                    |
|       | 丢包处理:                                        |                    |
|       | - 标记丢失的包                                    |                    |
|       | - 通知编码器发送 PLI/FIR (关键帧请求)                 |                    |
|       | - 使用上一帧的最后一帧做插值 (Frame Interpolation)      |                    |
|                                                                      |
|  步骤 3: 视频解码                                                     |
|  ──────────────────────────────────                                   |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | VideoDecoder   |   | 解码输出       |   | Post-Processing |         |
|  |                |──▶| (I420 Frame)   |──▶| (可选)          |         |
|  +----------------+   +----------------+   +----------------+         |
|       |                    |                    |                    |
|       | 解码器选择:                                        |                    |
|       | - VP8Decoder / VP9Decoder / H264 / AV1           |                    |
|       | - 基于 SDP 协商的 payload type 选择                 |                    |
|       |                    |                    |                    |
|       | 解码输出:                                        |                    |
|       | - I420 (YUV420P) 格式                             |                    |
|       | - scoped_refptr<VideoFrame> (零拷贝)               |                    |
|       | - NTP 时间戳 + RTP 时间戳                           |                    |
|       |                    |                    |                    |
|       | Post-Processing:                                   |                    |
|       | - 去块滤波 (Deblocking)                            |                    |
|       | - 去模糊 (Deblocking)                              |                    |
|       | - 色彩空间转换 (如果需要)                            |                    |
|                                                                      |
|  步骤 4: 视频渲染                                                     |
|  ──────────────────────────────────                                   |
|                                                                      |
|  +----------------+   +----------------+   +----------------+         |
|  | VideoSink      |   | VideoRenderer  |   | GPU/Display     |         |
|  | (OnFrame)      |──▶| (Renderer)     |──▶|                 |         |
|  +----------------+   +----------------+   +----------------+         |
|       |                    |                    |                    |
|       | 帧调度:                                        |                    |
|       | - 按 RTP Timestamp 排序 (非到达时间)            |                    |
|       | - 与音频时钟同步 (A/V Sync)                      |                    |
|       | - 帧率适配: 丢弃过时帧，保持渲染帧率                |                    |
|       |                    |                    |                    |
|       | 渲染管道:                                        |                    |
|       | - I420 → YUV to RGB 转换                          |                    |
|       | - GPU 纹理上传 (OpenGL/DirectX)                     |                    |
|       | - 屏幕扫描同步 (VSync)                             |                    |
|                                                                      |
+----------------------------------------------------------------------+
```

### 4.5 DataChannel 数据流（SCTP over DTLS）

```
+----------------------------------------------------------------------+
|                  DataChannel 数据流                                    |
+----------------------------------------------------------------------+
|                                                                      |
|  协议栈层次:                                                           |
|  ─────────────                                                         |
|  PeerConnection                                                     |
|    └── SCTPTransport (media/sctp/)                                   |
|         └── SCTP (Stream Control Transmission Protocol)              |
|              └── DTLS (加密传输)                                       |
|                 └── ICE/UDP (网络传输)                                  |
|                                                                      |
|  发送端:                                                               |
|  ────────                                                            |
|                                                                      |
|  Application                                                        |
|    │ createDataChannel("chat", params)                               |
|    │  - ordered: true/false (是否有序)                                |
|    │  - maxRetransmits: 重传次数                                      |
|    │  - maxPacketLifeTime: 生命周期                                    |
|    │  - protocol: SCTP 端口号                                         |
|    ▼                                                                |
|  DataChannel (pc/sctp_transport.cc)                                  |
|    │ onbufferedamountlow = callback                                  |
|    │ bufferedAmountLowThreshold = 阈值                                |
|    ▼                                                                |
|  SCTP Transport                                                      |
|    │ 配置 SCTP 参数:                                                   |
|    │ - 流 ID (Stream ID)                                              |
|    │ - 有序/无序模式                                                   |
|    │ - 重传策略                                                        |
|    ▼                                                                |
|  SCTP Protocol                                                       |
|    │ 封装 SCTP DATA chunk:                                            |
|    │ - TSNI (Transmission Sequence Number)                            |
|    │ - PPID (Payload Protocol ID):                                   |
|    │   - 51 = SCTP DATA CHANNEL                                     |
|    │   - 50 = RELIABLE DATA CHANNEL                                  |
|    │   - 53 = UNRELIABLE DATA CHANNEL                                |
|    ▼                                                                |
|  DTLS Transport (加密)                                                 |
|    ▼                                                                |
|  ICE/UDP (网络发送)                                                    |
|                                                                      |
|  接收端:                                                               |
|  ────────                                                            |
|                                                                      |
|  ICE/UDP (网络接收) ← DTLS (解密) ← SCTP (解包) ← DataChannel        |
|                                                                      |
|  事件回调 (signaling_thread):                                         |
|  ────────────────────────────                                         |
|  - OnMessage(): 收到数据                                               |
|  - OnBufferedAmountLow(): 缓冲区低于阈值                                |
|  - OnOpen(): 通道建立完成                                               |
|  - OnClose(): 通道关闭                                                  |
|                                                                      |
|  两种模式:                                                             |
|  ──────────                                                          |
|  可靠模式 (Reliable):                                                 |
|  - SCTP 保证有序交付                                                    |
|  - 丢包自动重传                                                        |
|  - 流量控制 (Flow Control)                                             |
|                                                                      |
|  不可靠模式 (Unreliable):                                              |
|  - 有序不可靠: 丢包不重传，先到的先交付                                  |
|  - 无序可靠: 重传但乱序交付                                             |
|  - 无序不可靠: 不重传不排序 (游戏状态同步最佳)                            |
|                                                                      |
+----------------------------------------------------------------------+
```

### 4.6 拥塞控制闭环（BWE → GCC → Pacing → 码率调整）

```
+----------------------------------------------------------------------+
|                  拥塞控制完整闭环                                       |
+----------------------------------------------------------------------+
|                                                                      |
|  这是 WebRTC 中最复杂的算法闭环，涉及发送端和接收端的协同:              |
|                                                                      |
|  ┌──────────────────────────────────────────────────────────────┐    |
|  │                    GCC 拥塞控制闭环                           │    |
|  │                                                              │    |
|  │   发送端                                    接收端            │    |
|  │   ────────                                    ────────         │    |
|  │                                                              │    |
|  │   +----------+    RTCP RR/REMB     +----------------+        │    |
|  │   | Bandwidth| ◀══════════════════ │ Bandwidth      │        │    |
|  │   | Estimator|                      | Estimator      │        │    |
|  │   | (BWE)    |                      | (Remote)       │        │    |
|  │   +----------+                      +----------------+        │    |
|  │        │                                    │                  │    |
|  │        │ 带宽估计值                           │ RTCP RR:         │    |
|  │        │                                    │ - Loss ratio     │    |
|  │        │                                    │ - Delta RTT      │    |
|  │        │                                    │ - Inter-arrival  │    |
|  │        ▼                                    │                  │    |
|  │   +----------+    码率调整    +-------------+                 │    |
|  │   | Rate     | ───────────▶  | VideoSend    |                 │    |
|  │   | Controller|             | Stream       |                 │    |
|  │   | (GCC)    |             | ::SetBitrate |                 │    |
|  │   +----------+             +-------------+                 │    |
|  │        │                                    │                │    |
|  │        │ Pacing Rate                       │                │    |
|  │        ▼                                  │                │    |
|  │   +----------+                            │                │    |
|  │   | Pacer    |                            │                │    |
|  │   | ( pacing  │                            │                │    |
|  │   | 器)       │                            │                │    |
|  │   +----------+                            │                │    |
|  │        │                                  │                │    |
|  │        │ UDP 包 → 网络                      │                │    |
|  │        ──────────────────────────────────────────────────── │    |
|  │                                  网络 (可能丢包/排队)          │    |
|  │                                                              │    |
|  └──────────────────────────────────────────────────────────────┘    │
|                                                                      |
|  BWE (Bandwidth Estimation) 两种算法:                                 |
|  ──────────────────────────────────                                   |
|                                                                      |
|  1. Delay-based BWE (DelayBasedBwe)                                  |
|  ──────────────────────────────────                                   |
|  原理: 通过包组 (Packet Group) 的排队延迟变化估计带宽                    |
|                                                                      |
|  核心算法:                                                             |
|  - 将发送包分组为 Packet Group (基于发送速率)                            |
|  - 比较同组包的 Delivery Time (到达时间)                                |
|  - 如果 Delivery Time 递增 → 队列在增长 → 带宽不足                      |
|  - 如果 Delivery Time 递减 → 队列在消散 → 带宽有余                      |
|                                                                      |
|  关键组件:                                                             |
|  - LinkCapacityEstimator: 估计链路容量                                  |
|  - DelayIncreaseDetector: 检测排队延迟突增                              |
|  - TrendlineEstimator: 用趋势线拟合延迟变化                              |
|                                                                      |
|  优势: 对 RTT 不敏感，适合高 RTT 网络 (如卫星)                           |
|  劣势: 对包组边界敏感，低流量时估计不准                                   |
|                                                                      |
|  2. Loss-based BWE (Gcc / RemoteBitrateEstimator)                     |
|  ──────────────────────────────────────────────────                   |
|  原理: 通过丢包率和 RTT 变化估计带宽                                     |
|                                                                      |
|  核心算法 (基于 AIMD - Add Increase Multiplicative Decrease):          |
|  - 发送端: 基于 REMB/XR 报告计算丢包率                                  |
|  - 接收端: RemoteBitrateEstimator 分析 RTT + Loss                      |
|  - BWE = RTT * MinLinkCapacity - 2 * BandwidthDelayProduct            |
|                                                                      |
|  优势: 在丢包网络中稳定                                                  |
|  劣势: 对 RTT 变化敏感，WiFi 抖动下误判多                                 |
|                                                                      |
|  混合 BWE (Google BWE):                                               |
|  - 同时运行 Delay-based + Loss-based                                  |
|  - 取两者的较小值 (保守策略)                                             |
|  - 权重自适应: 根据网络类型动态调整                                      |
|                                                                      |
|  码率调整策略 (Generic Rate Controller):                               |
|  ──────────────────────────────────────────                           |
|  - 目标码率 = min(BWE, 当前码率 * 1.05)  (增长不超过 5%/s)              |
|  - 目标码率 = max(BWE * 0.85, 最低码率)  (下降不超过 15%)               |
|  - 分配给各视频流: 基于 Simulcast 层级和优先级                           |
|                                                                      |
+----------------------------------------------------------------------+
```

### 4.7 视频自适应（分辨率/码率/帧率动态调整）

```
+----------------------------------------------------------------------+
|                  视频自适应机制                                        |
+----------------------------------------------------------------------+
|                                                                      |
|  触发条件:                                                           |
|  ──────────                                                          |
|  1. 带宽下降 → 降低码率 → 切换低分辨率 Simulcast 层                    |
|  2. 带宽恢复 → 提升码率 → 切换高分辨率 Simulcast 层                    |
|  3. CPU 过载 → 降低分辨率/帧率 → 减轻编码负担                          |
|  4. 屏幕尺寸 → 根据渲染窗口大小调整分辨率                               |
|  5. 远端接收能力 → 根据 REMB/RTCP 反馈调整                              |
|                                                                      |
|  Simulcast 自适应:                                                   |
|  ────────────────────                                                |
|                                                                      |
|  发送端同时编码 3 层:                                                 |
|  +-----------+   +-----------+   +-----------+                      |
|  | Layer A   |   | Layer B   |   | Layer C   |                      |
|  | QVGA      |   | VGA       |   | HD        |                      |
|  | 150kbps   |   | 500kbps   |   | 2Mbps     |                      |
|  | 30fps     |   | 30fps     |   | 30fps     |                      |
|  +-----------+   +-----------+   +-----------+                      |
|       | SSRC-A        | SSRC-B        | SSRC-C                       |
|       | RID: low      | RID: mid      | RID: high                    |
|                                                                      |
|  自适应决策 (VideoSendStream):                                        |
|  ──────────────────────────────                                       |
|                                                                      |
|  带宽下降时:                                                          |
|  BWE < 400kbps → 停止发送 Layer C (HD)                                |
|  BWE < 200kbps → 停止发送 Layer B (VGA)                               |
|  仅发送 Layer A (QVGA)                                                |
|                                                                      |
|  带宽恢复时:                                                          |
|  BWE > 600kbps → 恢复发送 Layer B (VGA)                               |
|  BWE > 2.5Mbps → 恢复发送 Layer C (HD)                                |
|                                                                      |
|  关键算法: VideoBitrateAllocator                                       |
|  ──────────────────────────────────                                   |
|                                                                      |
|  - BuiltinVideoBitrateAllocatorFactory: 默认分配器                      |
|  - 基于目标码率在各层间分配:                                            |
|    · 最高层优先 (maximize quality)                                     |
|    · 每层有最低码率保障                                                |
|    · RTX/FEC 开销预留                                                 |
|                                                                      |
|  CPU 自适应:                                                          |
|  ────────────                                                        |
|  - 监控编码耗时 (encode_time_ms / frames_encoded)                       |
|  - CPU 使用率 > 80% → 降低分辨率或帧率                                  |
|  - CPU 使用率 < 50% → 提升分辨率或帧率                                  |
|  - 通过 field_trial 控制:                                             |
|    "WebRTC-CpuAdaptation/Enabled/"                                    |
|                                                                      |
|  远端自适应 (Receiver-driven):                                        |
|  ──────────────────────────────                                       |
|  - 远端通过 RTCP PLI/FIR 请求关键帧                                    |
|  - 远端通过 REMB 报告接收带宽                                            |
|  - 远端通过 Transport-CC 反馈网络拥塞                                    |
|  - 本端根据反馈调整发送策略                                              |
|                                                                      |
+----------------------------------------------------------------------+
```

### 4.8 控制流时序图（实时交互）

```
+------------------------------------------------------------------+
|                  通话中实时交互时序图                               |
+------------------------------------------------------------------+
|                                                                  |
|  ProcessThread (10ms 周期)     AudioSendStream   Call             |
|  ---------------               ---------------   ----             |
|                                                                  |
|  | ADM::Process()              |                    |             |
|  | (采集 10ms PCM)             |                    |             |
|  | ──────────────────▶         |                    |             |
|  |                             | Encode(PCM)        |             |
|  |                             | ──────────────▶    |             |
|  |                             |                    |             |
|  |                             | Packetizer         |             |
|  |                             | ──────────────▶    |             |
|  |                             | SendRtp()          |             |
|  |                             | ─────────────────────────▶ Pacer |
|  |                             |                                         |
|  | APM::Process()              |                    |             |
|  | (AEC/NS/AGC/VAD)          |                    |             |
|  | ──────────────────▶         |                    |             |
|  |                             |                    |             |
|  | AudioMixer::Process()       |                    |             |
|  | (混合所有接收流)             |                    |             |
|  | ──────────────────▶         |                    |             |
|  |                             | ADM::WriteData()   |             |
|  |                             | ◀────────────      |             |
|  |                             |                    |             |
|  | RTCP 处理 (每 5s):          |                    |             |
|  | SenderReport()              |                    |             |
|  | ──────────────────▶         | Send RR            |             |
|  |                             | ◀────────────      |             |
|  |                             |                    |             |
|  | BWE 更新 (每 500ms):        |                    |             |
|  | GetStats()                  |                    |             |
|  | ──────────────────▶         | UpdateBitrate()    |             |
|  |                             | ◀────────────      |             |
|  |                             |                    |             |
|  | Video Process:              |                    |             |
|  | OnFrame(video_frame)        |                    |             |
|  | ◀─────────────────          | (采集线程推送)       |             |
|  |                             | Encode(VideoFrame) |             |
|  |                             | ──────────────▶    |             |
|  |                             | SendRtp()          |             |
|  |                             | ─────────────────────────▶ Pacer |
|  |                             |                                         |
|  | RTCP Receiver Report:       |                    |             |
|  | ──────────────────▶         |                    |             |
|  |                             | Process RTCP       |             |
|  |                             | (NACK/REMB/RR)     |             |
|  |                             | ──────────────▶    |             |
|  |                             | NACK → 重传         |             |
|  |                             | REMB → 调整码率     |             |
|                                                                  |
+------------------------------------------------------------------+
```

### 4.9 C++ 知识点：Observer 模式、回调链、WeakPtr

**4.9.1 Observer 模式在 WebRTC 中的广泛应用**

WebRTC 大量使用 Observer 模式实现事件驱动架构：

```cpp
// 1. SDP 协商 Observer
class CreateSessionDescriptionObserver {
 public:
  virtual void OnSuccess(JsepSessionDescription* desc) = 0;
  virtual void OnFailure(RTCError error) = 0;
};

// 2. ICE 状态 Observer
sigslot::signal1<cricket::IceConnectionState> SignalIceConnectionState;
sigslot::signal1<cricket::IceGatheringState> SignalIceGatheringState;
sigslot::signal2<const std::string&, const std::vector<cricket::Candidate>&>
    SignalIceCandidatesGathered;

// 3. 媒体轨道状态 Observer
class AudioSourceInterface : public rtc::RefCountedObject<AudioSourceInterface> {
 public:
  virtual void AddObserver(AudioSourceObserver* observer) = 0;
  virtual void RemoveObserver(AudioSourceObserver* observer) = 0;
};

// 4. DataChannel Observer
class DataChannelObserver {
 public:
  virtual void OnMessage(DataChannelInterface* channel) = 0;
  virtual void OnBufferedAmountLow() = 0;
  virtual void OnOpen() = 0;
  virtual void OnClose() = 0;
};

// sigslot 信号槽使用示例 (同线程内事件通知)
class JsepTransportController : public sigslot::has_slots<> {
 public:
  sigslot::signal1<PeerConnectionState> SignalConnectionState;

 private:
  void UpdateAggregateStates_n() {
    // 状态变化时触发信号
    SignalConnectionState(new_state);
    // 所有订阅了 SignalConnectionState 的对象会收到通知
  }
};
```

**4.9.2 WeakPtr 防悬空**

WebRTC 中异步回调链极长，WeakPtr 防止回调时对象已销毁：

```cpp
class PeerConnection : public PeerConnectionInterface {
 public:
  PeerConnection() {
    // 创建 WeakPtrFactory
  }

  void CreateOffer(CreateSessionDescriptionObserver* observer) {
    // 捕获 WeakPtr，确保回调时 PeerConnection 仍存在
    auto weak = weak_ptr_factory_.GetWeakPtr();
    worker_thread_->Post([weak, observer] {
      if (!weak) return;  // PeerConnection 已销毁，安全退出
      weak->DoCreateOffer(options, observer);
    });
  }

 private:
  ~PeerConnection() {
    // weak_ptr_factory_ 自动失效所有 WeakPtr
    // 所有 pending 的回调检查 weak 后安全退出
  }

  rtc::WeakPtrFactory<PeerConnection> weak_ptr_factory_;
};
```

**4.9.3 回调链中的内存管理**

```cpp
// 典型异步回调链:
pc->CreateOffer(new CreateSessionDescriptionObserverWrapper(
    rtc::scoped_refptr<CreateSessionDescriptionObserver>(observer),
    [pc_weak = pc->weak_ptr_factory_.GetWeakPtr(), observer_refptr](
        std::unique_ptr<SessionDescriptionInterface> desc) mutable {
      // 检查 pc 是否仍存在
      if (!pc_weak) return;
      // 继续下一环
      pc_weak->SetLocalDescription(
          new SetSessionDescriptionObserverWrapper(
              observer,
              [pc_weak](RTCError error) {
                if (!pc_weak) return;
                // ICE 收集完成后通知应用层
                pc_weak->NotifyIceGatheringComplete();
              }),
          std::move(desc));
    }));
```

关键设计原则：
- 每个异步回调都检查 WeakPtr
- `scoped_refptr` 确保 Observer 对象在回调链中不被提前释放
- `unique_ptr` 传递 SDP 描述，所有权清晰
- 所有回调最终在 worker_thread 或 signaling_thread 上执行，保证线程安全

---

## 第 5 章：阶段四 — 链路变化

> **触发条件**：网络切换（WiFi→4G）、带宽波动、编码质量变化、ICE 候选变化。
> **核心特征**：WebRTC 连接在通话中动态适应，目标是保持连接不断、质量最优。
> **关键原则**：分层处理——网络层（ICE）和传输层（DTLS）解耦，应用层（码率/分辨率）与传输层解耦。

### 5.1 网络切换（WiFi → 4G / IP 变更）

```
+----------------------------------------------------------------------+
|                  网络切换处理流程                                      |
+----------------------------------------------------------------------+
|                                                                      |
|  场景: 设备从 WiFi 切换到 4G，IP 地址从 192.168.1.100 变为 10.0.0.5   |
|                                                                      |
|  触发链:                                                             |
|  ──────────                                                          |
|                                                                      |
|  操作系统网络变化事件                                                 |
|    │                                                                  |
|    ▼                                                                |
|  rtc::NetworkManager::OnNetworkChanged()                              |
|    │ 枚举新网络接口                                                   |
|    │ 发现新 IP: 10.0.0.5                                              |
|    │                                                                  |
|    ▼                                                                |
|  PortAllocator::OnNetworkChanged()                                    |
|    │ 为每个 PortAllocatorSession 通知新网络                             |
|    │                                                                  |
|    ▼                                                                |
|  PortAllocatorSession::OnNetworkChanged()                             |
|    │ 触发新候选发现                                                   |
|    │  - HostPort: 新 IP 上创建新的 Host 候选                            |
|    │  - STUN: 重新查询 STUN 获取新的 Server-Reflexive 候选              |
|    │                                                                  |
|    ▼                                                                |
|  SignalCandidateGathered(new_candidate)                               |
|    │                                                                  |
|    ▼                                                                |
|  PeerConnection → 通过信令通道发送新候选给远端                           |
|  pc->AddIceCandidate(new_candidate)                                   |
|                                                                      |
|  关键行为:                                                           |
|  ──────────                                                          |
|  1. 旧候选不立即删除:                                                  |
|     → 如果旧网络仍可用（WiFi 未完全断开），旧路径可能仍通                  |
|     → ICE 会同时尝试新旧候选对                                         |
|     → 第一个成功的候选对成为活跃对                                       |
|                                                                      |
|  2. 活跃候选对切换:                                                    |
|     → 如果新候选对成功 → 自动切换到新路径                               |
|     → ICE 状态: connected → connected (不经过 failed)                  |
|     → DTLS 连接不受影响（底层 UDP 端口变化但 DTLS 基于 IP 无关的密钥）    |
|     → SRTP 密钥不变                                                   |
|                                                                      |
|  3. 旧候选超时:                                                        |
|     → 30s 无响应 → 标记为废弃                                          |
|     → 从候选列表中移除                                                 |
|                                                                      |
+----------------------------------------------------------------------+
```

### 5.2 ICE 重连：新候选发现、Candidate Pair 更新

```
+----------------------------------------------------------------------+
|                  ICE 重连流程                                          |
+----------------------------------------------------------------------+
|                                                                      |
|  ICE 重连与 ICE Restart 的区别:                                       |
|  ──────────────────────────────────                                   |
|                                                                      |
|  ICE 重连 (Reconnection):                                            |
|  - 触发: 当前活跃候选对超时/不可达                                     |
|  - 不生成新 SDP                                                       |
|  - 不改变 ice-ufrag/ice-pwd                                          |
|  - 利用已收集的候选对重新检查                                          |
|  - 如果候选耗尽 → 触发新候选收集                                       |
|                                                                      |
|  ICE Restart:                                                        |
|  - 触发: 应用调用 CreateOffer(ice_restart=true)                        |
|  - 生成新 SDP (新 ufrag/pwd)                                         |
|  - 全新候选收集                                                       |
|  - 需要通过信令通道交换新 SDP                                          |
|                                                                      |
|  ICE 重连的触发条件:                                                   |
|  ────────────────────                                                 |
|                                                                      |
|  条件 1: ICE 连接超时                                                  |
|  → 所有活跃候选对超过 15s 无响应                                      |
|  → ice_connection_state: connected → disconnected                    |
|  → 启动重新收集候选                                                    |
|                                                                      |
|  条件 2: 当前活跃候选对失败                                             |
|  → 活跃候选对的 Connection 状态从 connected → failed                   |
|  → 检查是否有 pending 的 checking 候选对                               |
|  → 如果有 → 切换到该候选对                                              |
|  → 如果没有 → 触发新候选收集                                            |
|                                                                      |
|  条件 3: 网络路由变化                                                   |
|  → NetworkManager 检测到网络变化                                       |
|  → PortAllocator 发现新候选                                            |
|  → 新候选加入候选集 → 自动开始检查                                      |
|                                                                      |
|  重连过程中的媒体处理:                                                 |
|  ──────────────────────                                               |
|  - ICE disconnected 时:                                               |
|    → 不立即断开 DTLS 连接                                              |
|    → 不立即丢弃媒体包                                                   |
|    → 继续用旧路径发送 (如果旧路径仍通)                                   |
|    → 同时尝试新路径                                                     |
|                                                                      |
|  - ICE 状态转换:                                                      |
|    connected → disconnected → connecting → connected                  |
|    (整个过程通常 1~5 秒)                                                |
|                                                                      |
|  媒体中断窗口:                                                         |
|  ────────────────────                                                 |
|  如果旧路径完全失效且新路径尚未建立:                                     |
|  → 发送端: 继续编码和发送 (包进入队列)                                   |
|  → 接收端: JitterBuffer 消耗已有缓冲                                   |
|  → 缓冲耗尽 → 播放静音 (PLC)                                           |
|  → 新路径建立 → 恢复播放                                                |
|  → 中断时间: 通常 < 2s (同网络内切换)                                   |
|  → 中断时间: 可能 2~10s (跨网络切换且无 TURN)                           |
|                                                                      |
+----------------------------------------------------------------------+
```

### 5.3 DTLS 重握手

```
+----------------------------------------------------------------------+
|                  DTLS 重握手场景                                       |
+----------------------------------------------------------------------+
|                                                                      |
|  正常通话中 DTLS 通常不重握手，以下情况会触发:                           |
|                                                                      |
|  场景 1: DTLS 连接断开后恢复                                           |
|  ──────────────────────────────────                                   |
|  触发: ICE 完全断开且无法恢复，DTLS 超时                                |
|  行为:                                                               |
|  - DTLS 状态: Connected → Closed                                     |
|  - PeerConnection 状态: kConnected → kFailed                          |
|  - 需要 ICE Restart + DTLS 全新握手                                   |
|  - 这不是"重握手"，而是完整重建                                         |
|                                                                      |
|  场景 2: 证书轮换 (Certificate Rotation, WebRTC 108+)                  |
|  ──────────────────────────────────────────────────────────────       |
|  触发: 应用调用 pc->SetCertificates(new_cert, new_priv_key)            |
|  行为:                                                               |
|  - 发送新的 DTLS Certificate 消息                                     |
|  - 触发 DTLS KeyUpdate 消息                                          |
|  - 远端回复 KeyUpdate                                                 |
|  - 密钥材料更新，但不中断数据传输                                       |
|  - 零中断 (zero-downtime)                                             |
|                                                                      |
|  场景 3: DTLS 重握手 (标准 TLS 重握手机制)                              |
|  ──────────────────────────────────────────                           |
|  WebRTC 默认不使用标准 DTLS 重握手，因为:                               |
|  - SRTP 密钥可以通过 Keying Material Export 重新派生                     |
|  - 无需完整的 DTLS 握手                                               |
|  - 通过 DTLS-SRTP 的 export_keying_material 可定期更新 SRTP 密钥       |
|                                                                      |
|  密钥更新机制 (SRTP Key Rotation):                                     |
|  ──────────────────────────────────                                   |
|  - 定期通过 DTLS export_keying_material 派生新 SRTP 密钥                |
|  - 新旧密钥并行使用 (过渡期)                                            |
|  - 旧密钥逐步废弃                                                       |
|  - 对媒体流无感知                                                     |
|                                                                      |
+----------------------------------------------------------------------+
```

### 5.4 拥塞控制响应：带宽骤降/恢复

```
+----------------------------------------------------------------------+
|                  带宽骤降响应                                          |
+----------------------------------------------------------------------+
|                                                                      |
|  场景: 网络拥塞导致可用带宽从 2Mbps 骤降至 200kbps                     |
|                                                                      |
|  检测:                                                               |
|  ─────                                                               |
|  DelayBasedBwe 检测到:                                                |
|  - 连续多个 Packet Group 的 Delivery Time 递增                         |
|  - 排队延迟持续上升 (> 300ms)                                          |
|  - LinkCapacityEstimator 估计链路容量下降                               |
|                                                                      |
|  LossBased BWE 检测到:                                                |
|  - RTCP RR 中 fraction_lost 上升 (> 5%)                               |
|  - RTT 抖动增大                                                        |
|  - RemoteBitrateEstimator 计算 BWE 下降                                |
|                                                                      |
|  响应 (发送端):                                                        |
|  ──────────────                                                       |
|  1. GCC RateController 立即降低目标码率:                                |
|     → 当前码率 * 0.85 (每次最多降 15%)                                 |
|     → 如果连续 2~3 个 RTT 仍拥塞 → 继续降                               |
|     → 最低到 codec 的最低码率                                           |
|                                                                      |
|  2. 视频自适应:                                                        |
|     → Simulcast 层切换: HD → VGA → QVGA                              |
|     → 如果已最低层: 降低帧率 (30fps → 15fps → 8fps)                    |
|     → 如果已最低帧率: 降低分辨率 (通过编码器参数)                        |
|                                                                      |
|  3. 音频自适应:                                                        |
|     → 切换低码率 codec (Opus 256kbps → Opus 64kbps → Opus 32kbps)     |
|     → 启用更激进的 VAD/DTX                                            |
|                                                                      |
|  4. 停止非媒体发送:                                                     |
|     → 停止 padding 包                                                  |
|     → 停止 RTX 重传 (如果队列积压)                                     |
|     → 停止 FlexFEC 包                                                  |
|                                                                      |
|  场景: 带宽恢复 (从 200kbps 恢复到 2Mbps)                              |
|  ──────────────────────────────────────────────────────────────       |
|                                                                      |
|  检测:                                                               |
|  - Delivery Time 开始递减                                              |
|  - fraction_lost 下降到 < 1%                                          |
|  - 排队延迟消散                                                        |
|                                                                      |
|  响应 (发送端):                                                        |
|  - 码率增长: 每次最多增 5% (缓慢增长，避免再次拥塞)                       |
|  - Simulcast 层恢复: QVGA → VGA → HD                                 |
|  - 帧率恢复: 8fps → 15fps → 30fps                                    |
|  - 恢复 FEC/RTX                                                        |
|                                                                      |
|  关键参数:                                                           |
|  ──────────                                                          |
|  - 拥塞下降速率: 15%/RTT (快速响应)                                    |
|  - 拥塞恢复速率: 5%/RTT (缓慢爬升，避免 overshoot)                      |
|  - 目标: 维持排队延迟在 100~200ms 之间                                  |
|                                                                      |
+----------------------------------------------------------------------+
```

### 5.5 视频自适应触发：质量降级/恢复

```
+----------------------------------------------------------------------+
|                  视频自适应触发链路                                    |
+----------------------------------------------------------------------+
|                                                                      |
|  质量降级触发链:                                                       |
|  ──────────────────                                                   |
|                                                                      |
|  带宽不足 (GCC BWE 下降)                                              |
|    │                                                                  |
|    ▼                                                                |
|  VideoSendStream::SetBitrate()                                        |
|    │                                                                  |
|    ├──▶ Simulcast 层切换                                              |
|    │     → 停止高层 SSRC 的发送                                        |
|    │     → Pacing 仅对剩余层 pacing                                    |
|    │                                                                  |
|    ├──▶ 帧率降低                                                       |
|    │     → VideoSendStream::SetMaxFramerate()                          |
|    │     → 编码器跳过帧                                                |
|    │                                                                  |
|    └──▶ 分辨率降低                                                    |
|          → VideoSendStream::SetMaxFramerateAndResolution()             |
|          → 编码器降分辨率                                              |
|                                                                      |
|  CPU 过载 (编码耗时监控)                                               |
|  ──────────────────────────────                                       |
|                                                                      |
|  encode_time_ms / frames_encoded > CPU 阈值                           |
|    │                                                                  |
|    ▼                                                                |
|  CpuOveruseDetector                                                   |
|    │                                                                  |
|    ├──▶ 降低目标分辨率                                                 |
|    │                                                                  |
|    └──▶ 降低目标帧率                                                   |
|                                                                      |
|  远端反馈 (RTCP Receiver Report)                                       |
|  ──────────────────────────────────                                   |
|                                                                      |
|  接收端 fraction_lost > 5% 或 jitter > 100ms                          |
|    │                                                                  |
|    ▼                                                                |
|  发送端 BWE 下降                                                      |
|    │                                                                  |
|    └──▶ 同上: 码率 → Simulcast → 帧率 → 分辨率                        |
|                                                                      |
|  质量恢复触发链:                                                       |
|  ──────────────────                                                   |
|                                                                      |
|  BWE 上升 + CPU 空闲 + 远端反馈改善                                     |
|    │                                                                  |
|    ▼                                                                |
|  VideoSendStream 逐步提升:                                             |
|  1. 首先恢复帧率 (成本最低)                                             |
|  2. 然后提升 Simulcast 层 (切换 SSRC)                                  |
|  3. 最后提升分辨率 (编码成本最高)                                        |
|                                                                      |
|  自适应的滞后防抖 (Hysteresis):                                        |
|  ──────────────────────────────                                       |
|  - 降级阈值 < 恢复阈值 (避免频繁切换)                                    |
|  - 例如: Simulcast 层切换:                                             |
|    HD → VGA: BWE < 400kbps                                           |
|    VGA → HD: BWE > 700kbps (需要比降级阈值高 75%)                       |
|  - 帧率切换:                                                           |
|    30fps → 15fps: encode_cpu > 70%                                   |
|    15fps → 30fps: encode_cpu < 40%                                   |
|                                                                      |
+----------------------------------------------------------------------+
```

### 5.6 控制流时序图

```
+------------------------------------------------------------------+
|                  链路变化控制流时序图                               |
+------------------------------------------------------------------+
|                                                                  |
|  NetMgr       PortAllocator      ICE Transport    PeerConnection  |
|  ---------    -------------      ------------    ------------    |
|                                                                  |
|  Network Change (WiFi->4G)                                       |
|  │                                                                  |
|  │ OnNetworkChanged()                                               |
|  │──────────────────▶                                               |
|  │                                  New Candidate Discovered        |
|  │                                  │                                 |
|  │                                  ▼                                 |
|  │                                  SignalCandidateGathered           |
|  │                                  │                                 |
|  │                                  ▼                                 |
|  │  AddIceCandidate()                                               |
|  │◀──────────────────┬────────────── Add to remote via signaling     |
|  │                    │                                              |
|  │                    │ ICE Check on new candidate pair               |
|  │                    │───────────────────────────────                |
|  │                    │                                               |
|  │                    │ Candidate Pair: checking → completed           |
|  │                    │───────────────────────────────                |
|  │                    │                                               |
|  │                    │ SignalCandidatePairChanged                     |
|  │                    │◀───────────────────────────────                |
|  │                    │                                               |
|  │                    │ Active pair switched to new route              |
|  │                    │◀───────────────────────────────                |
|  │                    │                                               |
|  │  IceConnectionState: connected (unchanged)                         |
|  │◀──────────────────┴───────────────────────────────                |
|                                                                  |
|  拥塞场景:                                                         |
|  ────────                                                          |
|                                                                  |
|  Call (ProcessThread)      VideoSendStream     Pacer               |
|  ──────────────            ────────────────     ─────               |
|                                                                  |
|  BWE drops (delay increase)                                      |
|  │                                                                  |
|  │ GetStats() -> BWE = 200kbps                                     |
|  │──────────────────▶                                               |
|  │                                  SetBitrate(200kbps)             |
|  │                                  │                                |
|  │                                  ▼                                 |
|  │                                  Simulcast: HD -> VGA            |
|  │                                  │                                |
|  │                                  ▼                                 |
|  │                                  Pacing rate adjusted             |
|  │                                  │                                |
|  │  CPU overload detected                                           |
|  │  │                                                                 |
|  │  │ Encode time > threshold                                        |
|  │  │──────────────────▶ SetMaxFramerate(15)                          |
|  │  │                              │                                 |
|  │  │                              ▼                                 |
|  │  │                              Frame drop                        |
|                                                                  |
+------------------------------------------------------------------+
```

### 5.7 C++ 知识点：状态机模式、事件驱动

**5.7.1 ICE 连接状态机**

```cpp
// WebRTC 中 ICE 状态机定义在 cricket::IceTransport
enum class IceConnectionState {
  kIceConnectionNew,         // 初始状态
  kIceConnectionChecking,    // 正在检查候选对
  kIceConnectionConnected,   // 至少一对候选对连通（可能还在检查其他）
  kIceConnectionCompleted,   // 检查完成，活跃对已确定
  kIceConnectionFailed,      // 所有候选对均失败
  kIceConnectionDisconnected, // 活跃对断开（可恢复）
  kIceConnectionClosed,      // 显式关闭
};

// 状态转换规则 (确定性有限状态机):
//
//   New ──────▶ Checking ──────▶ Connected ──────▶ Completed
//     │            │                  │                  │
//     │            ▼                  ▼                  ▼
//     │         Failed             Failed            Failed
//     │            │                  │                  │
//     │            ▼                  ▼                  ▼
//     │         Closed             Disconnected      Closed
//     │                                          │
//     │                                          ▼
//     │                                        Checking (reconnect)
//     │                                          │
//     └──────────────────────────────────────────┘
//
// 关键: Disconnected → Checking 是唯一的恢复路径
// 其他失败状态都是终态（需要 ICE Restart 或全新连接）
```

**5.7.2 PeerConnection 状态机**

```cpp
// PeerConnection 的完整状态机
enum class PeerConnectionState {
  kNew,              // 初始化完成，未开始协商
  kConnecting,       // 协商进行中 (SDP + ICE + DTLS)
  kConnected,        // 媒体连接建立
  kDisconnected,     // 连接中断（可恢复）
  kFailed,           // 连接失败（不可恢复）
  kClosed,           // 显式关闭
};

// 状态转换:
// kNew ──▶ kConnecting ──▶ kConnected ──▶ kDisconnected ──▶ kClosed
//   │           │               │                │
//   │           ▼               ▼                ▼
//   │        kFailed        kFailed          kFailed
//   │           │               │                │
//   │           ▼               ▼                ▼
//   │        kClosed          kClosed          kClosed
//   │                                              │
//   │                                      (需要 ICE Restart)
//   │                                              │
//   └──────────────────────── kConnecting ◀────────┘
//
// kConnected → kConnecting 仅通过 ICE Restart 实现（不经过 kDisconnected）
```

**5.7.3 事件驱动架构**

WebRTC 的链路变化处理完全基于事件驱动：

```cpp
// 事件源 → 信号 → 处理器 (sigslot 模式)
class P2PTransportChannel : public sigslot::has_slots<> {
 public:
  // 事件源
  sigslot::signal1<Port*> SignalPortComplete;
  sigslot::signal2<Port*, Connection*> SignalConnectionCreated;

  // 处理器 (通过 sigslot::has_slots<> 自动连接)
  void OnConnectionCreated(Port* port, Connection* conn) {
    // 新连接创建时处理
    connections_.push_back(conn);
    conn->SignalConnectionStateChanged.connect(
        this, &P2PTransportChannel::OnConnectionStateChanged);
  }

  void OnConnectionStateChanged(Connection* connection,
                                 IceConnectionState state) {
    // 连接状态变化时处理
    switch (state) {
      case ICEROLE_CONNECTED:
        OnConnectionConnected(connection);
        break;
      case ICEROLE_FAILED:
        OnConnectionFailed(connection);
        break;
    }
    UpdateAggregateState();  // 重新计算聚合状态
  }
};

// 事件传播链:
// Port (网络层)
//   └─ SignalConnectionStateChanged
//       └─ P2PTransportChannel (传输层)
//           └─ SignalCandidatePairChanged
//               └─ JsepTransportController (信令层)
//                   └─ SignalIceConnectionState
//                       └─ PeerConnection (控制层)
//                           └─ 应用层 Observer
```

**5.7.4 事件驱动 vs 轮询的优势**

- **零延迟响应**: 网络变化立即触发回调，无需等待轮询周期
- **低 CPU 开销**: 无轮询循环，事件驱动只在有事件时处理
- **状态一致性**: 状态转换在信号处理中集中管理，避免竞态条件
- **可测试性**: 每个信号可独立测试，状态转换可模拟

---

## 第 6 章：阶段五 — 正常断开

> **触发条件**：应用主动调用 `pc->Close()` 或对端发送 SDP BYE。
> **核心特征**：有序、可预测的资源清理流程；所有层按依赖顺序逐层关闭；保证对端感知断开。
> **关键原则**：先关应用层 → 再关传输层 → 最后关基础设施；反向于初始化顺序。

### 6.1 应用主动关闭（Close）

```
+----------------------------------------------------------------------+
|                  PeerConnection::Close() 流程                         |
+----------------------------------------------------------------------+
|                                                                      |
|  PeerConnection::Close()                                              |
|  (signaling_thread)                                                   |
|  |                                                                   |
|  | 1. 更新统计                                                        |
|  |    stats_->UpdateStats(kStatsOutputLevelStandard)                  |
|  |    → 捕获最后的统计数据 (bytes sent/received, packets, etc.)        |
|  |                                                                   |
|  | 2. 改变 signaling_state 为 kClosed                                 |
|  |    ChangeSignalingState(kClosed)                                   |
|  |    → connection_state_ = kClosed                                   |
|  |    → 通知 observer_->OnIceConnectionChange(kClosed)                 |
|  |    → 通知 observer_->OnConnectionStateChange(kClosed)               |
|  |                                                                   |
|  | 3. 停止所有 Transceiver                                            |
|  |    for (auto& tr : transceivers_) tr->Stop()                       |
|  |    → 停止音频/视频轨道的采集                                        |
|  |    → 停止编码器                                                     |
|  |    → 停止解码器                                                     |
|  |                                                                   |
|  | 4. 等待 pending stats 请求完成                                      |
|  |    stats_collector_->WaitForPendingRequest()                        |
|  |    → 确保所有异步 stats 回调在销毁前完成                             |
|  |                                                                   |
|  | 5. 销毁所有 Channel (按依赖顺序)                                     |
|  |    DestroyAllChannels()                                            |
|  |    → 先销毁 Video Channel (可能依赖 Voice Channel)                  |
|  |    → 再销毁 Audio Channel                                           |
|  |    → 最后销毁 DataChannel Transport                                 |
|  |                                                                   |
|  | 6. 重置 SessionDescriptionFactory                                  |
|  |    webrtc_session_desc_factory_.reset()                             |
|  |    → 允许 pending 的 SDP 操作安全退出                               |
|  |                                                                   |
|  | 7. 重置 TransportController                                        |
|  |    transport_controller_.reset()                                   |
|  |    → 销毁所有 JsepTransport                                         |
|  |    → 销毁所有 DtlsTransport (发送 DTLS CloseNotify)                 |
|  |    → 销毁所有 IceTransport (停止候选收集)                            |
|  |    → 销毁 SCTPTransport                                             |
|  |                                                                   |
|  | 8. 清理网络层                                                      |
|  |    PortAllocator::DiscardCandidatePool()                            |
|  |    → 丢弃所有缓存的 ICE 候选                                        |
|  |    → 关闭所有 Socket                                                |
|  |                                                                   |
|  | 9. 重置 Call 和 EventLog (worker_thread)                            |
|  |    worker_thread_->Invoke([call_.reset(), event_log_.reset()])      |
|  |    → 销毁所有 AudioSendStream/ReceiveStream                         |
|  |    → 销毁所有 VideoSendStream/ReceiveStream                         |
|  |    → 销毁 ProcessThread                                             |
|  |    → 销毁 Pacer                                                     |
|  |    → 销毁拥塞控制器                                                  |
|  |    → 销毁编码器/解码器实例                                           |
|  |    → 销毁 EventLog                                                  |
|  |                                                                   |
|  | 10. 清除 observer 引用                                               |
|  |     observer_ = nullptr                                             |
|  |     → 防止回调中访问已销毁对象                                      |
|  |                                                                   |
|  └─────────────────────────────────────────────────────────────┘    |
|                                                                      |
+----------------------------------------------------------------------+
```

### 6.2 SDP BYE 协商

当远端希望结束通话时，会发送 SDP BYE（一个空的或 m-line 为 0 的 SDP）：

```
+----------------------------------------------------------------------+
|                  SDP BYE 流程                                          |
+----------------------------------------------------------------------+
|                                                                      |
|  远端:                                                               |
|  ─────                                                               |
|  1. 应用层调用 close() 或发送 BYE 信令                                 |
|  2. 生成 SDP BYE:                                                     |
|     方式 A: m-line 端口设为 0 (拒绝媒体)                               |
|       m=audio 0 UDP/TLS/RTP/SAVPF  →  m=audio 0 ...                  |
|       m=video 0 UDP/TLS/RTP/SAVPF  →  m=video 0 ...                  |
|     方式 B: 完整的 SDP Offer (无媒体)                                   |
|       只包含 a=group 和 a=ice-options，不包含 m-line                   |
|  3. 通过信令通道发送 SDP BYE Offer 给本端                               |
|                                                                      |
|  本端:                                                               |
|  ─────                                                               |
|  1. 收到 SDP BYE → SetRemoteDescription(bye_sdp)                      |
|  2. DoSetLocalDescription 解析:                                       |
|     → 检测到 m-line 端口为 0 → 标记对应 Channel 为关闭                  |
|     → signaling_state: kHaveRemoteOffer → kStable                    |
|  3. 创建 Answer (空的或匹配的 BYE)                                     |
|     → 所有 m-line 端口设为 0                                          |
|  4. SetLocalDescription(answer)                                       |
|     → signaling_state: kStable → kHaveLocalOffer → kStable           |
|  5. 通过信令通道发送 Answer 给远端                                     |
|  6. 双方都进入 kStable 状态                                            |
|  7. 媒体流停止 (Channel 已标记关闭)                                     |
|  8. 如果应用决定完全关闭: 调用 pc->Close()                              |
|                                                                      |
|  关键点:                                                             |
|  - SDP BYE 只停止媒体流，不关闭 PeerConnection                         |
|  - 之后仍可发起新的通话 (需要新的 SDP 协商)                              |
|  - DTLS 和 ICE 连接保持 (除非调用 Close())                              |
|                                                                      |
+----------------------------------------------------------------------+
```

### 6.3 DTLS CloseNotify

```
+----------------------------------------------------------------------+
|                  DTLS CloseNotify 流程                                 |
+----------------------------------------------------------------------+
|                                                                      |
|  触发: DtlsTransport 销毁时 (在 TransportController 重置过程中)         |
|                                                                      |
|  +----------------+    +----------------+                            |
|  | DtlsTransport  |    | DTLS SSL 对象  |                            |
|  +----------------+    +----------------+                            |
|       |                                                      |        |
|       | ~DtlsTransport()                                     |        |
|       | ──────────────────────────────────────────────────▶  |        |
|       |                                                      |        |
|       | SSL_shutdown()                                       |        |
|       |   → 发送 DTLS CloseNotify 消息                        |        |
|       |   ──────────────────────────────────────────────────▶  |        |
|       |                                                      |        |
|       |                                                      | ←──────│ CloseNotify
|       |                                                      |        |
|       | ←──────────────────────────────────────────────────  |        |
|       |   接收 DTLS CloseNotify 消息                          |        |
|       |                                                      |        |
|       | SSL_shutdown() 完成                                  |        |
|       | → 关闭底层 SSL 连接                                  |        |
|       | → 释放 SSL 资源                                      |        |
|       |                                                      |        |
|       | SRTP 密钥材料清理                                     |        |
|       | → Zeroize SRTP 密钥 (安全清理)                        |        |
|       | → 防止密钥泄露 (如果内存被 dump)                       |        |
|                                                                      |
|  CloseNotify 的重要性:                                               |
|  - 对端知道 DTLS 连接正常关闭 (非异常断开)                              |
|  - 避免对端等待超时                                                   |
|  - 符合 TLS/DTLS RFC 规范                                            |
|                                                                      |
+----------------------------------------------------------------------+
```

### 6.4 ICE Connection Terminated

```
+----------------------------------------------------------------------+
|                  ICE 终止流程                                          |
+----------------------------------------------------------------------+
|                                                                      |
|  触发: IceTransport 销毁时                                            |
|                                                                      |
|  1. 停止候选收集                                                      |
|     PortAllocatorSession::StopCandidates()                            |
|     → 停止所有 STUN/TURN 请求                                         |
|     → 关闭所有 Port 的 Socket                                         |
|                                                                      |
|  2. 清理活跃连接                                                       |
|     Connection::Terminate()                                           |
|     → 停止所有 Connection 的 probe 定时器                              |
|     → 清空发送队列                                                     |
|     → 关闭 Socket                                                     |
|                                                                      |
|  3. 状态通知                                                          |
|     SignalIceConnectionState(kClosed)                                 |
|     → PeerConnection 收到 → 更新状态                                   |
|                                                                      |
|  4. 资源释放                                                          |
|     → Port 对象销毁                                                   |
|     → Connection 对象销毁                                             |
|     → Candidate 对象销毁                                              |
|                                                                      |
+----------------------------------------------------------------------+
```

### 6.5 资源清理顺序

```
+----------------------------------------------------------------------+
|                  资源清理顺序 (反向初始化)                              |
+----------------------------------------------------------------------+
|                                                                      |
|  清理顺序 (signaling_thread 主导):                                    |
|  ──────────────────────────────────                                   |
|                                                                      |
|  第 1 层: 应用层                                                     |
|  ────────────                                                        |
|  1. Transceiver Stop()                                               |
|     → 停止 Audio/Video Track 采集                                     |
|     → 停止 VideoSource 帧推送                                         |
|     → AudioSource 设置为 muted                                       |
|                                                                      |
|  第 2 层: MediaChannel 层                                            |
|  ────────────────────                                                |
|  2. Video Channel 销毁                                               |
|     → 停止 VideoSendStream                                            |
|     → 销毁 VideoReceiveStream                                         |
|     → 停止编码器 (VCM → VC)                                           |
|     → 清理 RTP Packetizer                                             |
|     → 清理 JitterBuffer                                               |
|                                                                      |
|  3. Audio Channel 销毁                                               |
|     → 停止 AudioSendStream                                            |
|     → 销毁 AudioReceiveStream                                         |
|     → 停止 AudioCoding 模块                                           |
|     → 清理 NetEq                                                      |
|                                                                      |
|  4. DataChannel Transport 销毁                                       |
|     → 停止 SCTP Transport                                             |
|     → 关闭所有 DataChannel                                            |
|     → 通知 DataChannelObserver OnClose()                              |
|                                                                      |
|  第 3 层: Transport 层                                               |
|  ────────────────                                                    |
|  5. SessionDescriptionFactory 重置                                    |
|     → 清理 pending SDP 操作                                           |
|                                                                      |
|  6. JsepTransportController 销毁                                     |
|     → DtlsTransport 销毁 (CloseNotify)                                |
|     → IceTransport 销毁 (停止收集)                                     |
|     → SCTPTransport 销毁                                              |
|     → 清理所有 Candidate                                              |
|                                                                      |
|  第 4 层: Call 层 (worker_thread)                                     |
|  ────────────────                                                    |
|  7. Call 销毁                                                        |
|     → AudioSendStream[] 销毁                                         |
|     → AudioReceiveStream[] 销毁                                      |
|     → VideoSendStream[] 销毁                                         |
|     → VideoReceiveStream[] 销毁                                      |
|     → GccCongestionController 销毁                                   |
|     → Pacer 销毁                                                     |
|     → RtpTransportControllerSend 销毁                                |
|     → RemoteBitrateEstimator 销毁                                    |
|     → ProcessThread 停止并销毁                                        |
|                                                                      |
|  第 5 层: 基础设施层                                                   |
|  ────────────────                                                    |
|  8. EventLog 销毁                                                    |
|     → 关闭日志文件                                                     |
|     → Zeroize 敏感数据                                                 |
|                                                                      |
|  9. PortAllocator 清理                                                |
|     → DiscardCandidatePool()                                         |
|     → 关闭所有 Socket                                                  |
|                                                                      |
|  10. Thread 停止 (如果由 PeerConnectionFactory 创建)                   |
|       → signaling_thread->Stop()                                     |
|       → worker_thread->Stop()                                        |
|       → network_thread->Stop()                                       |
|                                                                      |
|  关键保证:                                                           |
|  - 析构顺序严格反向于构造顺序                                          |
|  - 跨线程资源通过 Invoke/Post 在所属线程释放                            |
|  - scoped_refptr 确保引用计数正确归零                                  |
|  - WeakPtr 确保异步回调在销毁后不执行                                  |
|                                                                      |
+----------------------------------------------------------------------+
```

### 6.6 控制流时序图

```
+------------------------------------------------------------------+
|                  正常断开时序图                                    |
+------------------------------------------------------------------+
|                                                                  |
|  App       PeerConnection    TransportCtrl   DtlsTransport   Call|
|  ---       -------------    --------------   --------------   ----|
|                                                                  |
|  场景 A: 应用主动 Close()                                        |
|                                                                  |
|  pc->Close()                                                     |
|  │                                                                  |
|  │ signaling_state = kClosed                                       |
|  │ PeerConnectionState = kClosed                                   |
|  │──────────────────▶                                               |
|  │                                                                  |
|  │ Transceiver Stop()                                              |
|  │──────────────────▶                                               |
|  │                                  Stop SendStreams                 |
|  │                                  │                                |
|  │                                  ▼                                |
|  │                                  Destroy Channels                 |
|  │                                  │                                |
|  │                                  ▼                                |
|  │  DestroyAllChannels()                                           |
|  │──────────────────▶                                               |
|  │                                  Video Channel destroy            |
|  │                                  Audio Channel destroy            |
|  │                                  SCTP Transport destroy           |
|  │                                  │                                |
|  │                                  ▼                                |
|  │  transport_controller_.reset()                                  |
|  │──────────────────▶                                               |
|  │                                  DtlsTransport destroy            |
|  │                                  │  DTLS CloseNotify              |
|  │                                  │ ────────────▶ 网络             |
|  │                                  │ ◀──────────── 网络             |
|  │                                  │  DTLS CloseNotify ack          |
|  │                                  │                                |
|  │                                  IceTransport terminate           |
|  │                                  │                                |
|  │                                  ▼                                |
|  │  call_.reset() (worker_thread)                                   |
|  │─────────────────────────────────────────────────▶                |
|  │                                  Stop all streams                 |
|  │                                  Destroy encoder/decoder           |
|  │                                  Stop ProcessThread               |
|  │                                  Zeroize SRTP keys                |
|  │                                  │                                |
|  │  observer_->OnConnectionStateChange(kClosed)                     |
|  │◀─────────────────────────────────────────────────                |
|                                                                  |
|  场景 B: 远端发送 SDP BYE                                         |
|  ────────────────────────────────────────────────────────────    |
|                                                                  |
|  远端信令                                                         |
|  │                                                                  |
|  │ SDP BYE (m=0)                                                   |
|  │──────────────────────────────────────────────────────▶           |
|  │                                                                  |
|  │ SetRemoteDescription(bye_sdp)                                   |
| │──────────────────▶                                               |
| │                                                                  |
| │ Create Answer (m=0)                                               |
| │──────────────────▶                                               |
| │                                                                  |
| │ SetLocalDescription(answer)                                       |
| │──────────────────▶                                               |
| │                                                                  |
| │ Media channels marked closed                                     |
| │──────────────────▶                                               |
| │                                                                  |
| │ Send Answer (m=0)                                                 |
| │◀──────────────────────────────────────────────────────           |
| │                                                                  |
| │ 媒体流停止 (但 DTLS/ICE 仍保持)                                   |
| │──────────────────▶                                               |
|                                                                  |
+------------------------------------------------------------------+
```

### 6.7 C++ 知识点：RAII、析构顺序、资源泄漏防护

**6.7.1 RAII 在 WebRTC 资源管理中的应用**

WebRTC 大量使用 RAII (Resource Acquisition Is Initialization) 模式确保资源正确释放：

```cpp
// 1. unique_ptr — 独占所有权，析构时自动释放
class PeerConnection {
 private:
  std::unique_ptr<JsepTransportController> transport_controller_;
  std::unique_ptr<WebRtcSessionDescriptionFactory> webrtc_session_desc_factory_;

  ~PeerConnection() {
    // transport_controller_ 自动销毁 → 触发 DtlsTransport/IceTransport 析构
    // webrtc_session_desc_factory_ 自动销毁
    // 无需手动 delete
  }
};

// 2. scoped_refptr — 引用计数，最后一个 release 时销毁
class AudioSendStream {
  // 通过 scoped_refptr 在多个对象间共享
  // 当最后一个 scoped_refptr 离开作用域时，引用计数归零，自动销毁
};

// 3. 跨线程资源释放 — Invoke + unique_ptr
void PeerConnection::Close() {
  // call_ 必须在 worker_thread 上销毁
  worker_thread()->Invoke<void>(RTC_FROM_HERE, [this] {
    RTC_DCHECK_RUN_ON(worker_thread());
    call_.reset();  // unique_ptr reset → 在正确线程上销毁 Call 对象
    event_log_.reset();
  });
}
```

**6.7.2 析构顺序保证**

C++ 中成员变量的析构顺序与声明顺序相反。WebRTC 通过精心设计的声明顺序保证正确的析构顺序：

```cpp
class PeerConnection {
 public:
  ~PeerConnection() {
    // 不需要手动清理 — 依赖 C++ 析构顺序
    // 但需要确保跨线程对象在正确线程销毁
  }

 private:
  // 声明顺序决定析构顺序 (反向):
  // 1. observer_ (最后声明 → 最先析构)
  PeerConnectionObserver* observer_ = nullptr;

  // 2. stats_collector_
  std::unique_ptr<StatsCollector> stats_collector_;

  // 3. webrtc_session_desc_factory_ (最先声明 → 最后析构)
  //    必须最后销毁，因为 pending SDP 操作可能引用它
  std::unique_ptr<WebRtcSessionDescriptionFactory>
      webrtc_session_desc_factory_;

  // 4. transport_controller_
  //    必须在 session_desc_factory 之前销毁
  std::unique_ptr<JsepTransportController> transport_controller_;

  // 5. call_ (在 worker_thread 上通过 Invoke 销毁)
  std::unique_ptr<Call> call_;

  // 6. event_log_ (在 worker_thread 上通过 Invoke 销毁)
  //    必须比 call_ 晚销毁 (Call 可能引用 event_log)
  std::unique_ptr<RtcEventLog> event_log_;
};
```

**6.7.3 资源泄漏防护机制**

```cpp
// 防护 1: WeakPtr 防止回调已销毁对象
class PeerConnection {
  void CreateOffer(CreateSessionDescriptionObserver* observer) {
    auto weak = weak_ptr_factory_.GetWeakPtr();
    worker_thread_->Post([weak, observer] {
      if (!weak) return;  // 安全: PC 已销毁
      weak->DoCreateOffer(options, observer);
    });
  }
  rtc::WeakPtrFactory<PeerConnection> weak_ptr_factory_;
};

// 防护 2: scoped_refptr 防止 premature 释放
class AudioSendStream {
  void Start() {
    // encoder_ 是 scoped_refptr，确保编码器不被提前释放
    encoder_->Start();
  }
  rtc::scoped_refptr<AudioEncoder> encoder_;
};

// 防护 3: DTLS CloseNotify 防止对端等待超时
~DtlsTransport() {
  SSL_shutdown(ssl_);  // 发送 CloseNotify
  SSL_free(ssl_);      // 释放 SSL 资源
  ZeroMemory(srtp_key_, SRTP_KEY_LEN);  // 安全清理密钥
}

// 防护 4: Invoke 确保跨线程资源在正确线程释放
void Close() {
  worker_thread()->Invoke<void>(RTC_FROM_HERE, [this] {
    call_.reset();       // 在 worker_thread 上销毁
    event_log_.reset();  // 在 worker_thread 上销毁
  });
}
```

**6.7.4 内存安全总结**

```
┌────────────────────────────────────────────────────────────────────┐
│                    WebRTC 内存安全机制                               │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  机制              用途                  保证                       │
│  ───────          ───────                ───────                     │
│  unique_ptr       独占资源               析构时自动释放               │
│  scoped_refptr    共享资源               引用计数归零时释放           │
│  WeakPtr          异步回调               对象销毁后回调安全退出       │
│  Thread Affinity  跨线程访问             资源在所属线程释放           │
│  RAII             资源生命周期           构造即获取，析构即释放       │
│  sigslot          事件连接               对象销毁时自动断开连接       │
│  ZeroMemory       敏感数据               密钥清理防止泄露             │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## 第 7 章：阶段六 — 异常断开

> **触发条件**：网络中断、超时、编码器崩溃、远端无响应等异常事件。
> **核心特征**：不可预测、不可控；需要超时检测、回退策略、部分恢复机制。
> **关键原则**：优雅降级（Graceful Degradation）—— 尽量保持部分功能，而非全有或全无。

### 7.1 网络突然中断（断网）

```
+----------------------------------------------------------------------+
|                  断网处理流程                                          |
+----------------------------------------------------------------------+
|                                                                      |
|  场景: 设备网络完全断开（WiFi 断开、飞行模式、拔出网线）                |
|                                                                      |
|  检测机制:                                                           |
|  ──────────                                                          |
|                                                                      |
|  1. 操作系统网络变化通知                                               |
|  ──────────────────────────────                                       |
|  NetworkManager::OnNetworkChanged()                                   |
|  → 枚举网络接口 → 发现所有 IP 消失                                     |
|  → PortAllocator 停止候选收集                                          |
|  → 无新候选产生                                                       |
|                                                                      |
|  2. ICE 超时检测                                                       |
|  ────────────────────                                                 |
|  活跃候选对的 Connection 停止收到 STUN 响应                              |
|  → 每个 Connection 有 liveness 定时器                                   |
|  → 默认 15s 无响应 → 标记为 failed                                     |
|  → 所有候选对 failed → ICE state: connected → failed                  |
|                                                                      |
|  3. DTLS 超时                                                          |
|  ──────────────                                                       |
|  DTLS 层无内置超时检测                                                  |
|  → 依赖 ICE 状态变化通知                                                |
|  → ICE failed → JsepTransportController → 更新状态                    |
|  → PeerConnectionState: kConnected → kFailed                          |
|                                                                      |
|  媒体影响:                                                             |
|  ──────────                                                          |
|  发送端:                                                               |
|  - 编码继续 (CPU 正常)                                                  |
|  - RTP 包进入 Pacer 队列                                              |
|  - Socket 发送失败 (ECONNREFUSED/ENETUNREACH)                          |
|  - 队列积压 → 内存增长                                                  |
|  - 拥塞控制器检测到无 ACK → 码率降至 0                                   |
|                                                                      |
|  接收端:                                                               |
|  - 不再收到任何 RTP 包                                                  |
|  - JitterBuffer 缓冲耗尽                                               |
|  - NetEq 启动 PLC (丢包隐藏) → 输出静音                                |
|  - 视频: 最后一帧冻结，或插值填充                                        |
|  - RTCP RR 继续发送 (如果 RTCP 走不同路径)                              |
|                                                                      |
|  恢复策略:                                                             |
|  ──────────                                                          |
|  网络恢复后:                                                            |
|  1. NetworkManager 检测到网络恢复                                       |
|  2. PortAllocator 重新收集候选                                          |
|  3. ICE 检查新候选对                                                    |
|  4. 如果 ICE 连接恢复 → 媒体自动恢复                                    |
|  5. 如果 ICE 无法恢复 → 需要 ICE Restart (新 SDP)                       |
|                                                                      |
+----------------------------------------------------------------------+
```

### 7.2 ICE 超时与回退

```
+----------------------------------------------------------------------+
|                  ICE 超时处理                                          |
+----------------------------------------------------------------------+
|                                                                      |
|  ICE 超时计时器:                                                       |
|  ──────────────────                                                   |
|                                                                      |
|  Connection 级超时:                                                   |
|  - 每个 Connection 有独立的 liveness 定时器                              |
|  - 超时时间: 15s (默认)                                                |
|  - 检测: 发送 STUN Binding Request，等待响应                            |
|  - 重试: 指数退避 (2.5s, 5s, 10s, 15s, ...)                           |
|  - 最大重试: 7 次                                                      |
|  - 全部失败 → Connection 状态: checking → failed                      |
|                                                                      |
|  Transport 级超时:                                                     |
|  ──────────────────                                                   |
|  JsepTransportController::UpdateAggregateStates_n()                     |
|  → 聚合所有 Transport 的状态                                            |
|  → 如果任何 Transport failed → 整体 ICE state = failed                 |
|  → 如果所有 Transport completed → ICE state = completed               |
|  → 如果所有 Transport connected → ICE state = connected               |
|                                                                      |
|  PeerConnection 级超时:                                                |
|  ────────────────────────                                             |
|  PeerConnection 不直接设置 ICE 超时                                     |
|  → 依赖 ICE 状态变化信号                                                |
|  → ICE failed → PeerConnectionState: kConnected → kFailed             |
|  → 通知应用层 observer_->OnConnectionChange(kFailed)                    |
|                                                                      |
|  回退策略:                                                             |
|  ──────────                                                          |
|  1. TURN 回退                                                          |
|     → 如果 Host + SRFLX 全部失败                                      |
|     → 尝试 TURN Relay 候选 (需要 TURN 服务器)                           |
|     → TURN 成功率 > 直接连接 (但延迟高、带宽受限制)                       |
|                                                                      |
|  2. ICE Restart                                                        |
|     → ICE failed 后调用 CreateOffer(ice_restart=true)                   |
|     → 重新收集候选 (可能网络环境变化了)                                   |
|     → 通过信令通道交换新 SDP                                            |
|                                                                      |
|  3. 降级到信令通道传输                                                   |
|     → 极端情况下通过信令通道转发小数据                                   |
|     → 仅用于控制信令，不用于媒体                                         |
|                                                                      |
+----------------------------------------------------------------------+
```

### 7.3 DTLS 连接断开

```
+----------------------------------------------------------------------+
|                  DTLS 异常断开                                         |
+----------------------------------------------------------------------+
|                                                                      |
|  DTLS 断开的检测:                                                      |
|  ──────────────────                                                   |
|                                                                      |
|  WebRTC 中 DTLS 没有独立的超时检测机制                                  |
|  → DTLS 状态变化依赖于 ICE 状态                                         |
|  → ICE failed → DTLS 被视为不可达                                      |
|  → ICE disconnected → DTLS 状态不变 (可能仍通)                          |
|                                                                      |
|  DTLS 异常断开的场景:                                                  |
|  ──────────────────────                                               |
|                                                                      |
|  场景 1: 远端进程崩溃                                                   |
|  → 远端 TCP/UDP Socket 关闭                                            |
|  → 本端发送 DTLS 记录 → 收到 ECONNRESET                                |
|  → Socket 层检测到断开                                                 |
|  → DtlsTransport 收到信号                                              |
|  → DTLS 状态: Connected → Closed                                     |
|  → ICE 状态不受影响 (ICE 不感知 DTLS 层)                               |
|                                                                      |
|  场景 2: NAT 表超时                                                    |
|  → NAT 设备清除 UDP 映射 (通常 30s 无流量)                              |
|  → 本端发送 RTP 包 → 无响应                                            |
|  → ICE liveness 检测失败                                               |
|  → ICE state: connected → failed                                     |
|  → DTLS 层无感知 (依赖 ICE 通知)                                       |
|                                                                      |
|  场景 3: 防火墙规则变更                                                  |
|  → 中间防火墙阻断 UDP 端口                                             |
|  → 类似 NAT 超时                                                       |
|                                                                      |
|  DTLS 断开后的恢复:                                                    |
|  ──────────────────────                                               |
|  如果 ICE 仍连接但 DTLS 断开:                                          |
|  → 需要 DTLS 重握手 (Certificate Rotation 机制)                         |
|  → 或者 ICE Restart + 全新 DTLS 握手                                   |
|                                                                      |
|  如果 ICE 也断开:                                                      |
|  → ICE 恢复后 DTLS 自动恢复 (如果远端仍活跃)                              |
|  → 否则需要 ICE Restart + 全新 DTLS 握手                               |
|                                                                      |
+----------------------------------------------------------------------+
```

### 7.4 编码器崩溃与回退

```
+----------------------------------------------------------------------+
|                  编码器崩溃处理                                        |
+----------------------------------------------------------------------+
|                                                                      |
|  编码器崩溃的征兆:                                                     |
|  ──────────────────                                                   |
|  - 编码耗时突增 (编码器卡死)                                            |
|  - 编码输出停止 (编码器无响应)                                          |
|  - 编码器返回错误码                                                     |
|  - 进程 OOM Kill (内存溢出)                                            |
|                                                                      |
|  检测机制:                                                             |
|  ──────────                                                          |
|                                                                      |
|  1. CpuOveruseDetector                                                 |
|  ──────────────────────                                               |
|  - 监控编码耗时 / 帧率                                                  |
|  - encode_time_ms / frames_encoded > 阈值                              |
|  - CPU overuse 持续 2~3 秒 → 触发告警                                  |
|  - 不直接判断崩溃，但可触发降级                                          |
|                                                                      |
|  2. 编码器心跳检测 (应用层)                                              |
|  ────────────────────────────                                         |
|  - 应用层定期检查编码器健康状态                                          |
|  - 超过 N 秒无输出 → 标记为崩溃                                         |
|                                                                      |
|  回退策略:                                                             |
|  ──────────                                                          |
|                                                                      |
|  策略 1: 编码器重启                                                    |
|  → 销毁当前编码器实例                                                   |
|  → 创建新的编码器实例                                                   |
|  → 重新配置参数                                                         |
|  → 发送 PLI 请求关键帧                                                  |
|  → 恢复编码                                                             |
|                                                                      |
|  策略 2: 降级编码器                                                     |
|  → 从 AV1 降级到 VP8 (计算量更低)                                       |
|  → 从 VP9 降级到 VP8                                                   |
|  → 从 H264 High Profile 降级到 Baseline Profile                        |
|                                                                      |
|  策略 3: 完全禁用视频                                                   |
|  → 发送视频黑帧 (全黑 I 帧)                                             |
|  → 或发送静态图片                                                       |
|  → 通知远端 "视频暂停"                                                  |
|                                                                      |
|  策略 4: 音频优先                                                       |
|  → 视频崩溃时保持音频通道                                               |
|  → 应用层可选择完全断开或仅暂停视频                                      |
|                                                                      |
+----------------------------------------------------------------------+
```

### 7.5 远端无响应（Heartbeat 超时）

```
+----------------------------------------------------------------------+
|                  远端无响应检测                                        |
+----------------------------------------------------------------------+
|                                                                      |
|  WebRTC 原生不提供应用层 Heartbeat 机制                                 |
|  → 需要应用层自行实现                                                   |
|  → 可利用 RTCP 报文作为心跳                                              |
|                                                                      |
|  RTCP 心跳检测:                                                        |
|  ──────────────────                                                   |
|                                                                      |
|  发送端:                                                               |
|  - SR (Sender Report): 每 5s 自动发送                                  |
|  - RR (Receiver Report): 每 5s 自动发送                                |
|  - 如果 15s 未收到对端任何 RTCP → 标记为无响应                           |
|                                                                      |
|  应用层 Heartbeat:                                                     |
|  ──────────────────────                                               |
|  - 通过 DataChannel 定期发送心跳包 (如每 3s)                             |
|  - 超时 3 次未收到响应 → 标记远端无响应                                  |
|  - 触发应用层断开逻辑                                                   |
|                                                                      |
|  BWE 心跳 (GCC):                                                       |
|  ──────────────────                                                   |
|  - RemoteBitrateEstimator 检测 RTT                                    |
|  - 如果 RTT 无限增大 → 可能远端半断开                                   |
|  - 如果 BWE 降至 0 持续 10s → 可能远端无响应                            |
|                                                                      |
|  无响应后的行为:                                                       |
|  ──────────────────                                                   |
|  1. 发送端:                                                             |
|     → 继续发送媒体 (但队列积压)                                          |
|     → BWE 降至 0 → 码率降至 0                                          |
|     → Pacer 队列为空 → 无网络流量                                       |
|     → 应用层检测到无 RTCP 反馈 → 判定远端断开                            |
|     → 应用层调用 pc->Close()                                           |
|                                                                      |
|  2. 接收端:                                                             |
|     → 不再收到 RTP 包                                                   |
|     → JitterBuffer 耗尽 → 静音/冻结                                    |
|     → 不再发送 RTCP RR (无 SSRC 可报告)                                 |
|     → 发送端检测不到 RTCP → 确认断开                                    |
|                                                                      |
+----------------------------------------------------------------------+
```

### 7.6 部分媒体恢复（单方向恢复）

```
+----------------------------------------------------------------------+
|                  部分恢复场景                                          |
+----------------------------------------------------------------------+
|                                                                      |
|  场景: 网络恢复后，单向媒体恢复，另一方向仍不通                           |
|                                                                      |
|  典型场景:                                                             |
|  - NAT 不对称: 本端到远端通，远端到本端不通                              |
|  - 防火墙单向放行                                                       |
|  - TURN 服务器部分故障                                                 |
|                                                                      |
|  检测:                                                               |
|  ─────                                                               |
|  ICE 状态: connected (候选对连通)                                      |
|  DTLS 状态: Connected (DTLS 握手完成)                                  |
|  但:                                                                   |
|  - 发送端: RTP 包发送成功，但无 RTCP RR 反馈                            |
|  - 接收端: 不再收到 RTP 包                                             |
|                                                                      |
|  BWE 行为:                                                             |
|  - 发送端的 BWE 收到 RTCP RR → 认为连接正常                              |
|  - 但实际上接收端收不到包 → RR 是旧的或不存在                            |
|  → 这是一个经典问题: BWE 无法检测单向断开                                |
|                                                                      |
|  处理:                                                               |
|  ─────                                                               |
|  1. 发送端:                                                            |
|     → 继续发送媒体 (浪费带宽)                                            |
|     → 应用层需通过 DataChannel 心跳检测                                  |
|     → 心跳超时 → 判定单向断开                                           |
|                                                                      |
|  2. 接收端:                                                            |
|     → JitterBuffer 耗尽 → PLC 静音                                     |
|     → 视频冻结在最后一帧                                                 |
|     → 发送 RTCP PLI 请求关键帧 (但包发不出去)                             |
|                                                                      |
|  3. 恢复:                                                              |
|     → 网络修复后，接收端开始收到 RTP                                     |
|     → JitterBuffer 填充 → 恢复播放                                     |
|     → 如果有 PLI 缓存 → 请求关键帧 → 快速恢复                            |
|     → 恢复延迟: 取决于 JitterBuffer 大小和关键帧间隔                       |
|                                                                      |
+----------------------------------------------------------------------+
```

### 7.7 控制流时序图

```
+------------------------------------------------------------------+
|                  异常断开时序图                                    |
+------------------------------------------------------------------+
|                                                                  |
|  场景: 网络中断 → ICE 超时 → 恢复                                 |
|                                                                  |
|  NetMgr      PortAllocator     ICE Transport    PeerConnection   |
|  -------     --------------    --------------   --------------   |
|                                                                  |
|  网络断开                                                              |
|  │                                                                    |
|  │ Network down!                                                      |
|  │ OnNetworkChanged()                                                 |
|  │──────────────────▶                                                 |
|  │                                                                    |
|  │ 活跃候选对停止响应                                                    |
|  │  Connection liveness timer expires (15s)                           |
|  │  │                                                                 |
|  │  │ Connection state: connected → failed                             |
|  │  │─────────────────────────────▶                                    |
|  │  │                                                                  |
|  │  │ UpdateAggregateStates_n()                                        |
|  │  │─────────────────────────────▶                                    |
|  │  │                                                                  |
|  │  │ ICE state: connected → disconnected → failed                     |
|  │  │─────────────────────────────▶                                    |
|  │  │                                                                  |
|  │  │ PeerConnectionState: kConnected → kFailed                        |
|  │  │─────────────────────────────▶                                    |
|  │  │                                                                  |
|  │  │ 媒体影响:                                                          |
|  │  │ - 发送端: RTP 发送失败，队列积压                                    |
|  │  │ - 接收端: JitterBuffer 耗尽 → PLC 静音                             |
|  │  │                                                                  |
|  │ 网络恢复                                                              |
|  │                                                                    |
|  │ Network up!                                                        |
|  │ OnNetworkChanged()                                                 |
|  │──────────────────▶                                                 |
|  │                                                                    |
|  │ 新候选收集                                                            |
|  │ PortAllocator::StartGathering()                                     |
|  │──────────────────▶                                                 |
|  │                                                                    |
|  │ 新候选对检查                                                           |
|  │ Connection state: checking → completed                              |
|  │─────────────────────────────▶                                       |
|  │                                                                    |
|  │ ICE 恢复                                                             |
|  │ ICE state: failed → connecting → connected                          |
|  │─────────────────────────────▶                                       |
|  │                                                                    |
|  │ PeerConnectionState: kFailed → kConnecting → kConnected             |
|  │─────────────────────────────▶                                       |
|  │                                                                    |
|  │ 媒体恢复                                                              |
|  │ - JitterBuffer 重新填充                                              |
|  │ - PLC 静音停止                                                      |
|  │ - 视频恢复 (可能需要关键帧)                                            |
|  │                                                                    |
+------------------------------------------------------------------+
```

### 7.8 C++ 知识点：WeakPtr 防悬空、超时定时器、重试策略

**7.8.1 WeakPtr 在异常场景中的关键作用**

异常断开时，对象可能在任何时刻被销毁。WeakPtr 是防止悬空指针的核心机制：

```cpp
// 场景: ICE 超时回调时 PeerConnection 已被销毁
class PeerConnection {
 public:
  void OnIceTimeout() {
    // 捕获 WeakPtr，确保回调时对象仍存在
    auto weak = weak_ptr_factory_.GetWeakPtr();
    signaling_thread_->Post([weak] {
      if (!weak) {
        // PeerConnection 已被 Close() 销毁
        // 安全退出，不访问任何成员
        return;
      }
      // 安全: 对象仍存在
      weak->HandleIceTimeout();
    });
  }

 private:
  void HandleIceTimeout() {
    // 处理 ICE 超时
    SetIceConnectionState(kIceConnectionFailed);
    // ...
  }

  rtc::WeakPtrFactory<PeerConnection> weak_ptr_factory_;
};
```

**7.8.2 超时定时器模式**

WebRTC 使用 `AsyncInvoker` 和 ` rtc::Timer` 实现超时检测：

```cpp
class P2PTransportChannel : public sigslot::has_slots<> {
 public:
  void StartLivenessCheck() {
    // 启动 liveness 定时器
    liveness_timer_ = std::make_unique<rtc::Timer>(&event_queue_);
    liveness_timer_->StartMs(15000, &OnLivenessTimeout);
  }

 private:
  void OnLivenessTimeout() {
    // 15s 无响应
    if (state_ == kConnected) {
      // 尝试重发 STUN Binding
      ResendBindingRequest();
      // 重置定时器
      liveness_timer_->StartMs(15000, &OnLivenessTimeout);
    } else {
      // 状态已变化，不再检测
    }
  }

  std::unique_ptr<rtc::Timer> liveness_timer_;
};
```

**7.8.3 重试策略 (Exponential Backoff)**

```cpp
// WebRTC 中 ICE 候选检查的重试策略
class Connection {
 public:
  void SendBindingRequest() {
    // 指数退避重试
    static const int kInitialDelayMs = 2500;
    static const int kMaxDelayMs = 16000;
    static const int kMaxRetries = 7;

    if (retries_ >= kMaxRetries) {
      state_ = kFailed;
      SignalStateChanged(this, state_);
      return;
    }

    SendStunBinding();
    retries_++;

    // 指数退避: 2.5s, 5s, 10s, 10s, 10s, 10s, 10s
    int delay = std::min(kInitialDelayMs * (1 << (retries_ - 1)), kMaxDelayMs);
    invoker_.AsyncInvoke<void>(
        RTC_FROM_HERE,
        [this, delay] { SendBindingRequest(); },
        delay);
  }

 private:
  int retries_ = 0;
};
```

**7.8.4 部分恢复的状态管理**

```cpp
// 部分恢复场景下的状态机扩展
enum class MediaDirection {
  kNone,        // 双向都不通
  kSendOnly,    // 仅发送通
  kReceiveOnly, // 仅接收通
  kBoth,        // 双向都通
};

class ConnectionMonitor {
 public:
  void UpdateDirection(MediaDirection dir) {
    if (direction_ != dir) {
      direction_ = dir;
      // 部分恢复时触发应用层通知
      if (dir == MediaDirection::kReceiveOnly) {
        SignalOneWayMedia("receive_only");
      } else if (dir == MediaDirection::kSendOnly) {
        SignalOneWayMedia("send_only");
      }
    }
  }

  MediaDirection GetCurrentDirection() const {
    bool send_ok = rtp_packets_sent_ > 0 && socket_send_ok_;
    bool recv_ok = rtp_packets_received_ > 0;

    if (send_ok && recv_ok) return MediaDirection::kBoth;
    if (recv_ok) return MediaDirection::kReceiveOnly;
    if (send_ok) return MediaDirection::kSendOnly;
    return MediaDirection::kNone;
  }

 private:
  MediaDirection direction_ = MediaDirection::kNone;
  sigslot::signal1<const std::string&> SignalOneWayMedia;
};
```

**7.8.5 异常处理的防御性编程原则**

```
┌────────────────────────────────────────────────────────────────────┐
│                   异常处理防御原则                                    │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  1. 所有异步回调检查 WeakPtr                                         │
│  2. 所有定时器在对象析构时停止                                         │
│  3. 所有 unique_ptr 在所属线程销毁                                    │
│  4. 所有 scoped_refptr 不假设对象存活                                 │
│  5. 所有 sigslot 连接在对象析构时断开                                  │
│  6. 所有 Socket 在对象析构时关闭                                       │
│  7. 所有队列在对象析构时清空                                           │
│  8. 所有密钥在对象析构时 Zeroize                                      │
│  9. 所有状态变更检查 IsClosed() 前置条件                               │
│  10. 所有异常不抛出 (WebRTC 不用 C++ 异常，用 RTCError)               │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## 第 8 章：跨阶段协作关系总览

> **本章目标**：将前 7 章的碎片化知识串联为完整知识体系。
> **读者读完本章后应能**：看到任意模块，说出它在每个阶段的角色；看到任意协议，说出它在哪个阶段、哪条链路中运行。

### 8.1 各模块在五大阶段中的角色矩阵

```
+------------------------------------------------------------------------+
|                        模块-阶段角色矩阵                                 |
+------------------------------------------------------------------------+
|                                                                        |
|  模块                    | 初始化 | 协商  | 通话  | 链路变化 | 断开     |
|  ───────                 | ──── │ ──── │ ──── │ ────── │ ──────     |
|                                                                        |
|  PeerConnectionFactory   |  创建  |  提供  |  提供  |  提供   |  保留   |
|  PeerConnection          |  创建  |  核心  |  核心  |  核心   |  销毁   |
|  PeerConnectionFactory   |        |        |        |          |          |
|  ─────────────────       |        |        |        |          |          |
|  Proxy<PC>               |  创建  |  转发  |  转发  |  转发   |  释放   |
|                                                                        |
|  ChannelManager          |  创建  |  创建  |  维护  |  更新   |  销毁   |
|  WebRtcVoiceEngine       |  初始化|  配置  |  运行  |  重配   |  销毁   |
|  WebRTCVideoEngine       |  初始化|  配置  |  运行  |  重配   |  销毁   |
|                                                                        |
|  ADM (AudioDeviceModule) |  初始化|  使用  |  运行  |  切换   |  停止   |
|  APM (AudioProcessing)   |  初始化|  使用  |  运行  |  运行   |  停止   |
|  AudioCoding             |        |        |  运行  |  重配   |  销毁   |
|                                                                        |
|  Call                    |  创建  |  创建  |  核心  |  核心   |  销毁   |
|  AudioSendStream         |        |        |  运行  |  重配   |  销毁   |
|  AudioReceiveStream      |        |  创建  |  运行  |  运行   |  销毁   |
|  VideoSendStream         |        |  创建  |  运行  |  重配   |  销毁   |
|  VideoReceiveStream      |        |  创建  |  运行  |  运行   |  销毁   |
|                                                                        |
|  JsepTransportController |  创建  |  核心  |  维护  |  更新   |  销毁   |
|  IceTransport            |        |  创建  |  运行  |  重连   |  销毁   |
|  DtlsTransport           |        |  创建  |  运行  |  重握手 |  Close  |
|  SCTPTransport           |        |  创建  |  运行  |  运行   |  销毁   |
|                                                                        |
|  PortAllocator           |  创建  |  收集  |  监控  |  重收集 |  清理   |
|  UDPPort/TCP Port        |        |  创建  |  收发  |  新建   |  关闭   |
|                                                                        |
|  ProcessThread           |  创建  |  运行  |  运行  |  运行   |  停止   |
|  Pacer                   |        |        |  运行  |  重配   |  销毁   |
|  GccCongestionController |        |        |  运行  |  响应   |  销毁   |
|  RemoteBitrateEstimator  |        |        |  运行  |  响应   |  销毁   |
|                                                                        |
|  RtcEventLog             |  创建  |  记录  |  记录  |  记录   |  销毁   |
|                                                                        |
+------------------------------------------------------------------------+
```

### 8.2 协议栈交互图

```
+------------------------------------------------------------------------+
|                        WebRTC 协议栈交互                                 |
+------------------------------------------------------------------------+
|                                                                        |
|  应用层 (Application)                                                  |
|  ─────────────────                                                     |
|  API: CreateOffer/CreateAnswer/AddTrack/RemoveTrack/Close              |
|                                                                        |
|  ──────────────────────────────────────────────────────────────────    |
|                                                                        |
|  SDP (Session Description Protocol)                                    |
|  ─────────────────────────────────                                     |
|  职责: 媒体能力协商、编解码器选择、SSRC分配、BUNDLE/ICE参数              |
|  运行阶段: 协商、重新协商、SDP BYE                                      |
|  关键类: JsepSessionDescription, SessionDescriptionCreator             |
|                                                                        |
|  ──────────────────────────────────────────────────────────────────    |
|                                                                        |
|  ICE (Interactive Connectivity Establishment) / STUN                   |
|  ──────────────────────────────────────────────────────────────────    |
|  职责: NAT 穿透、候选发现、候选对检查、连接维护                           |
|  运行阶段: 协商(主要)、链路变化(主要)                                    |
|  关键类: PortAllocator, P2PTransportChannel, Connection                |
|                                                                        |
|  ──────────────────────────────────────────────────────────────────    |
|                                                                        |
|  DTLS (Data Transfer Layer Security)                                   |
|  ─────────────────────────────────                                     |
|  职责: 密钥交换、身份认证、SRTP 密钥派生                                  |
|  运行阶段: 协商(主要)、链路变化(重握手)、断开(CloseNotify)               |
|  关键类: DtlsTransport, SSLAdapter                                     |
|                                                                        |
|  ──────────────────────────────────────────────────────────────────    |
|                                                                        |
|  SCTP (Stream Control Transmission Protocol)                           |
|  ─────────────────────────────────                                     |
|  职责: DataChannel 传输层 (可靠/不可靠数据通道)                          |
|  运行阶段: 协商(创建)、通话(主要)、断开(销毁)                             |
|  关键类: SCTPTransport, DataChannel                                    |
|                                                                        |
|  ──────────────────────────────────────────────────────────────────    |
|                                                                        |
|  RTP (Real-time Transport Protocol)                                    |
|  ─────────────────────────────────                                     |
|  职责: 音视频媒体数据传输                                                 |
|  运行阶段: 通话(主要)、链路变化(维持)                                    |
|  关键类: RtpModule, Packetizer, Depacketizer                           |
|                                                                        |
|  RTCP (RTP Control Protocol)                                           |
|  ─────────────────────────────────                                     |
|  职责: 拥塞反馈(RR/REMB/TWCC)、质量监控(SR)、重传请求(NACK)             |
|  运行阶段: 通话(主要)、链路变化(响应)                                    |
|  关键类: RtcpModule, ReceiverReport, SenderReport, Nack                  |
|                                                                        |
|  ──────────────────────────────────────────────────────────────────    |
|                                                                        |
|  SRTP (Secure RTP)                                                     |
|  ─────────────────────                                                 |
|  职责: RTP/RTCP 加密 (基于 DTLS 派生密钥)                                |
|  运行阶段: 通话(主要)                                                    |
|  关键类: SrtpTransport, DtlsSrtpTransport                              |
|                                                                        |
+------------------------------------------------------------------------+
```

### 8.3 QoS 算法协作图

```
+------------------------------------------------------------------------+
|                        QoS 算法协作图                                   |
+------------------------------------------------------------------------+
|                                                                        |
|  音频 QoS 算法链:                                                      |
|  ──────────────────────                                                |
|                                                                        |
|  采集 → ADM → AEC → NS → AGC → VAD → AudioCoding → RTP               |
|                                                                        |
|  ADM: 硬件抽象层，提供原始 PCM                                            |
|  AEC: WebRtcAecm/AecmCore，消除本地回声 (参考发送音频)                    |
|  NS: WebRtcNs，抑制背景噪声 (FFT+频谱分析)                               |
|  AGC: WebRtcAgc，自动增益 (Fixed/Analog/Legacy 模式)                    |
|  VAD: WebRtcVad，语音活动检测 (输出 0/1 标记)                            |
|  AudioCoding: Opus/ISAC/G711 编码                                       |
|                                                                        |
|  视频 QoS 算法链:                                                      |
|  ──────────────────────                                                |
|                                                                        |
|  采集 → VPM → 预处理 → 编码 → NACK/FEC → RTP                           |
|                                                                        |
|  VPM: VideoProcessingModule，旋转/缩放/滤镜                              |
|  编码器: VP8/VP9/H264/AV1，I/P 帧编码                                   |
|  NACK: RTCP NACK 请求重传                                                |
|  FlexFEC: 前向纠错包生成                                                  |
|                                                                        |
|  拥塞控制算法链:                                                         |
|  ──────────────────────                                                |
|                                                                        |
|  发送端:                                                                 |
|  ───────                                                               |
|                                                                        |
|  DelayBasedBwe ─┐                                                      |
|                 ├─▶ Min() ─▶ RateController ─▶ Pacing ─▶ 网络           |
|  LossBasedBWE ──┘                                                      |
|                                                                        |
|  DelayBasedBwe:                                                        |
|  - LinkCapacityEstimator: 估计链路容量                                    |
|  - DelayIncreaseDetector: 检测排队延迟突增                                |
|  - TrendlineEstimator: 趋势线拟合                                        |
|                                                                        |
|  LossBasedBWE (RemoteBitrateEstimator):                                 |
|  - 分析 RTT + Loss 计算 BWE                                             |
|  - 基于 AIMD 算法                                                       |
|                                                                        |
|  RateController (GCC):                                                  |
|  - 增长: min(current * 1.05, BWE)  (每 RTT 最多 5%)                     |
|  - 下降: max(current * 0.85, BWE)  (每 RTT 最多 15%)                    |
|                                                                        |
|  接收端:                                                                 |
|  ───────                                                               |
|                                                                        |
|  RTP 接收 → NetEq (JitterBuffer) → 解码 → APM → ADM → 播放             |
|                                                                        |
|  RTCP RR: 每 5s 发送接收报告                                             |
|  RTCP NACK: 丢包时发送重传请求                                            |
|  RTCP REMB: 接收端估算的最大带宽                                          |
|  RTCP TWCC: Transport Wide Congestion Control 反馈                      |
|                                                                        |
|  视频自适应算法:                                                         |
|  ────────────────────                                                  |
|                                                                        |
|  BWE 变化 → RateController → VideoSendStream::SetBitrate()             |
|    │                                                                    |
|    ├──▶ Simulcast 层切换 (RID header)                                   |
|    │     HD → VGA → QVGA                                               |
|    │                                                                    |
|    ├──▶ 帧率调整 (30fps → 15fps → 8fps)                                 |
|    │                                                                    |
|    └──▶ 分辨率调整 (1080p → 720p → 480p)                                |
|                                                                        |
|  CPU 过载 → CpuOveruseDetector → 降低分辨率/帧率                         |
|                                                                        |
+------------------------------------------------------------------------+
```

### 8.4 完整端到端数据流图

```
+------------------------------------------------------------------------+
|                  完整端到端数据流 (发送 + 接收 + 控制面)                  |
+------------------------------------------------------------------------+
|                                                                        |
|  ┌───────────────────────────────────────┐   ┌──────────────────────┐  |
|  │            发送端 (Local)               │   │       接收端 (Remote)  │  |
|  ├───────────────────────────────────────┤   ├──────────────────────┤  |
|  │                                       │   │                      │  |
|  │  [音频路径]                            │   │                      │  |
|  │  麦克风 ─▶ ADM ─▶ AEC ─▶ NS ─▶ AGC   │   │                      │  |
|  │          ─▶ VAD ─▶ AudioCoding        │   │  AudioCoding ─▶ APM  │  |
|  │          ─▶ APM ─▶ AudioMixer ─▶ ADM  │   │          ─▶ 扬声器    │  |
|  │          │                            │   │                      │  |
|  │  [视频路径]                            │   │  视频 ─▶ JitterBuf   │  |
|  │  摄像头 ─▶ VPM ─▶ 预处理 ─▶ 编码       │   │          ─▶ 解码     │  |
|  │          ─▶ Simulcast ─▶ NACK/FEC     │   │          ─▶ 渲染     │  |
|  │          │                            │   │                      │  |
|  │  [RTP 封装]                           │   │  [RTP 解包]           │  |
|  │  Packetizer ─▶ RTP Header ─▶ SRTP    │   │  SRTP ─▶ Depacketizer│  |
|  │          │          │                  │   │          │           │  |
|  │  [拥塞控制]                           │   │  [RTCP 反馈]          │  |
|  │  BWE ─▶ RateCtrl ─▶ Pacing ─▶ 网络    │   │  RR/NACK/REMB/TWCC  │  |
|  │          │                              │   │         │           │  |
|  │  [RTCP 发送]                          │   │  [RTCP 接收]          │  |
|  │  SR/RR ──────────────────────────────▶│   │                      │  |
|  │                                       │   │                      │  |
|  │  [DataChannel]                         │   │  [DataChannel]        │  |
|  │  SCTP ─▶ DTLS ─▶ UDP ──────────────▶  │   │                      │  |
|  │                                       │   │                      │  |
|  └───────────────────────────────────────┘   └──────────────────────┘  |
|            网络 (UDP/IP)                                                    |
|            ──────────────────────────────────────────────────────────     |
|                                                                        |
|  控制面 (信令通道，不在 WebRTC 库内):                                     |
|  ──────────────────────────────────────                                   |
|  应用层信令: WebSocket/HTTP → SDP Offer/Answer → ICE Candidate         |
|                                                                        |
+------------------------------------------------------------------------+
```

### 8.5 线程间消息流总览

```
+------------------------------------------------------------------------+
|                        线程间消息流                                     |
+------------------------------------------------------------------------+
|                                                                        |
|  应用线程                                                               |
|  ───────────                                                            |
|  │ 创建 PCF/PC, 调用 API (CreateOffer/AddTrack/Close)                   |
|  │                                                                      |
|  │ Proxy::Call() → signaling_thread_                                    |
|  │ ──────────────────────────────────────────────────────────────────▶  │
|  │                                                                      |
|  signaling_thread_ (信令线程)                                           |
|  ──────────────────────                                                 |
|  │ SDP 生成/解析                                                         |
|  │ ICE 状态管理                                                          |
|  │ 媒体轨道管理                                                           |
|  │                                                                      |
|  │ AsyncInvoker → worker_thread_                                        |
|  │ ──────────────────────────────────────────────────────────────────▶  │
|  │                                                                      |
|  │ Invoke (synchronous) → worker_thread_                                |
|  │ ──────────────────────────────────────────────────────────────────▶  │
|  │                                                                      |
|  worker_thread_ (工作线程)                                              |
|  ──────────────────────                                                 |
|  │ Call 运行                                                             |
|  │ MediaEngine 运行                                                      |
|  │ RTP/RTCP 处理                                                         |
|  │ 编码器调度                                                             |
|  │ ProcessThread 循环 (10ms)                                             |
|  │                                                                      |
|  │ Socket 回调 → network_thread_ (间接，通过 Port)                       |
|  │ ──────────────────────────────────────────────────────────────────▶  │
|  │                                                                      |
|  ProcessThread (Call 内部，worker_thread_ 上)                            |
|  ──────────────────────────────────────────                              |
|  │ 每 10ms:                                                              |
|  │  - ADM::Process()      音频采集                                        |
|  │  - APM::Process()      音频处理                                        |
|  │  - AudioCoding::Process() 音频编码                                    |
|  │  - VCM::Process()      视频处理                                        |
|  │  - VC::Process()       视频编码                                        |
|  │  - RtpModule::Process() RTP/RTCP 处理                                 |
|  │  - CongestionController::Process() 拥塞控制                            |
|  │  - Pacer::Process()      pacing 调度                                  |
|  │                                                                      |
|  network_thread_ (网络线程)                                              |
|  ──────────────────────                                                 |
|  │ Socket I/O                                                            |
|  │ STUN/TURN 请求/响应                                                    |
|  │ ICE 候选收集                                                           |
|  │ UDPPort/TCP Port 的 recvfrom/sendto                                   |
|  │                                                                      |
|  │ Socket Signal → worker_thread_ (回调到 Port)                          |
|  │ ◀──────────────────────────────────────────────────────────────────  │
|  │                                                                      |
|  编码器线程 (Encoder Task Queue)                                         |
|  ───────────────────────────────────                                     |
|  │ 异步执行视频编码任务                                                     |
|  │ 避免阻塞 ProcessThread                                                  |
|  │                                                                      |
+------------------------------------------------------------------------+
```

### 8.6 关键对象生命周期总览

```
+------------------------------------------------------------------------+
|                    关键对象生命周期                                       |
+------------------------------------------------------------------------+
|                                                                        |
|  PeerConnectionFactory                                                |
|  ────────────────────                                                  |
|  创建: 应用线程 → new PeerConnectionFactory(deps)                       |
|  生命周期: 整个应用进程                                                   |
|  销毁: 应用退出时 (PCF 通常不被显式销毁)                                   |
|  线程: 不遵循线程亲和性，但其内部线程有亲和性                               |
|                                                                        |
|  PeerConnection                                                       |
|  ──────────────────                                                    |
|  创建: 应用线程 → Proxy::Call(signaling) → new PeerConnection()         |
|  生命周期: 一次通话 (从创建到 Close())                                    |
|  销毁: signaling_thread → ~PeerConnection()                             |
|       → DestroyAllChannels()                                            |
|       → transport_controller_.reset()                                   |
|       → worker_thread → call_.reset()                                   |
|  线程: 创建在 signaling_thread，所有 API 通过 Proxy 转发                   |
|                                                                        |
|  Call                                                                 |
|  ──────                                                                |
|  创建: signaling_thread → call_factory_->Create() → worker_thread       |
|  生命周期: 同 PeerConnection                                             |
|  销毁: worker_thread → ~Call()                                          |
|       → 销毁所有 AudioSend/ReceiveStream                                 |
|       → 销毁所有 VideoSend/ReceiveStream                                 |
|       → 销毁 ProcessThread                                              |
|       → 销毁拥塞控制器                                                    |
|  线程: 创建在 worker_thread，ProcessThread 在其上运行                     |
|                                                                        |
|  AudioSendStream / VideoSendStream                                    |
|  ─────────────────────────────────                                     |
|  创建: worker_thread → Call::CreateAudioSendStream()                    |
|  生命周期: 从创建到 RemoveTrack/Close()                                  |
|  销毁: worker_thread → ~AudioSendStream()                               |
|       → 停止编码器                                                       |
|       → 清理 RTP Packetizer                                             |
|  线程: worker_thread                                                     |
|                                                                        |
|  AudioReceiveStream / VideoReceiveStream                               |
|  ─────────────────────────────────────                                 |
|  创建: worker_thread → Call::CreateAudioReceiveStream()                 |
|  生命周期: 同 SendStream                                                 |
|  销毁: worker_thread → ~ReceiveStream()                                 |
|       → 清理 JitterBuffer/NetEq                                         |
|       → 停止解码器                                                       |
|  线程: worker_thread                                                     |
|                                                                        |
|  JsepTransportController                                              |
|  ────────────────────────────                                          |
|  创建: signaling_thread → new JsepTransportController(...)              |
|  生命周期: 同 PeerConnection                                             |
|  销毁: signaling_thread → ~JsepTransportController()                    |
|       → 销毁所有 JsepTransport                                           |
|       → 清理 ICE/DTLS/SCTP Transport                                    |
|  线程: 创建在 signaling_thread，但内部操作在 network_thread               |
|                                                                        |
|  IceTransport / DtlsTransport / SCTPTransport                          |
|  ──────────────────────────────────────────                            |
|  创建: network_thread → JsepTransport 内部创建                           |
|  生命周期: 同 JsepTransportController                                    |
|  销毁: network_thread → ~Transport()                                    |
|       → DTLS: CloseNotify → SSL_shutdown()                              |
|       → ICE: 停止候选收集 → 关闭 Socket                                  |
|       → SCTP: 关闭所有 DataChannel                                      |
|  线程: network_thread                                                    |
|                                                                        |
|  Port (Host/SRFLX/Relay)                                              |
|  ────────────────────                                                  |
|  创建: network_thread → PortAllocator 创建                               |
|  生命周期: 从创建到 Close() 或超时                                       |
|  销毁: network_thread → ~Port()                                         |
|       → 关闭 Socket                                                      |
|       → 清理 Candidate                                                   |
|  线程: network_thread                                                    |
|                                                                        |
|  scoped_refptr<T> (共享对象)                                           |
|  ────────────────────────                                              |
|  创建: 任意线程 → new T() → scoped_refptr<T>(ptr)                       |
|  生命周期: 引用计数管理                                                   |
|  销毁: 最后一个 scoped_refptr 离开作用域 → ptr->Release()               |
|       → Release() 在对象所属线程执行 → ~T() 在所属线程执行                |
|  线程: 销毁在对象所属线程 (thread-affine destruction)                     |
|                                                                        |
+------------------------------------------------------------------------+
```

### 8.7 状态机总览

```
+------------------------------------------------------------------------+
|                    完整状态机转换图                                      |
+------------------------------------------------------------------------+
|                                                                        |
|  PeerConnectionState (主状态机):                                       |
|  ──────────────────────────────                                        |
|                                                                        |
|      kNew                                                            |
|       │                                                              |
|       │ CreateOffer/CreateAnswer + SDP + ICE + DTLS                  |
|       ▼                                                              |
|      kConnecting ────────────────────────────────────┐                 |
|       │                                              │                 |
|       │ ICE Connected + DTLS Established             │ ICE Restart     |
|       ▼                                              │ (kConnected)    |
|      kConnected ◄────────────────────────────────────┘                 |
|       │                                                              |
|       │ 媒体流建立                                                     │ 网络断开/超时                            |
|       ▼                                                              ▼                 |
|      kCompleted                                              kFailed                 |
|       │                                                              │                 |
|       │ Close() / SDP BYE                                           │ (不可恢复)       |
|       ▼                                                              ▼                 |
|      kDisconnected                                            kClosed                |
|       │                                                              ▲                 |
|       │ ICE Restart + 恢复                                            │                 |
|       └──────────────────────────────────────────────────────────────┘                 |
|                                                                        |
|  signaling_state (信令状态):                                           |
|  ────────────────────────                                              |
|                                                                        |
|  kStable ──▶ CreateOffer ──▶ kHaveLocalOffer ──▶ SetRemoteDescription │
|       ▲                              │                                  |
|       │                              ▼                                  |
|       │                     kHaveRemoteOffer ──▶ SetLocalDescription   |
|       │                              │                                  |
|       │                              ▼                                  |
|       └────────────────────── kStable (完成)                             |
|                                                                        |
|  ICE ConnectionState:                                                  |
|  ──────────────────────                                                |
|                                                                        |
|  kNew ──▶ kChecking ──▶ kConnected ──▶ kCompleted                     |
|                            │         │                                  |
|                            │         ▼                                  |
|                            │     kFailed                                |
|                            │         │                                  |
|                            │         ▼                                  |
|                            │     kDisconnected ──▶ kChecking (重连)     |
|                            │                                              |
|                            └─────────▶ kClosed (显式关闭)               |
|                                                                        |
+------------------------------------------------------------------------+
```

### 8.8 依赖关系总图

```
+------------------------------------------------------------------------+
|                    模块依赖关系总图                                      |
+------------------------------------------------------------------------+
|                                                                        |
|  顶层依赖:                                                             |
|  ──────────                                                          |
|                                                                        |
|  PeerConnection                                                       |
|  ├── PeerConnectionFactory (工厂)                                      |
|  │   ├── ChannelManager                                                |
|  │   │   ├── WebRtcVoiceEngine                                        |
|  │   │   │   ├── ADM (AudioDeviceModule)                              |
|  │   │   │   ├── APM (AudioProcessing)                                |
|  │   │   │   ├── AudioCoding                                          |
|  │   │   │   └── AudioMixer                                           |
|  │   │   └── WebRTCVideoEngine                                        |
|  │   │       ├── VideoEncoderFactory (VP8/VP9/H264/AV1)               |
|  │   │       └── VideoDecoderFactory                                  |
|  │   ├── CallFactory                                                  |
|  │   │   └── Call                                                     |
|  │   │       ├── AudioSendStream[]                                    |
|  │   │       ├── AudioReceiveStream[]                                 |
|  │   │       ├── VideoSendStream[]                                    |
|  │   │       ├── VideoReceiveStream[]                                 |
|  │   │       ├── GccCongestionController                              |
|  │   │       ├── RemoteBitrateEstimator                               |
|  │   │       ├── Pacer                                                |
|  │   │       ├── ProcessThread                                        |
|  │   │       └── RtpTransportControllerSend                           |
|  │   └── RtcEventLog                                                  |
|  │                                                                      |
|  └── JsepTransportController                                          |
|      ├── IceTransport (P2PTransportChannel)                            |
|      │   ├── PortAllocator                                            |
|      │   │   ├── HostPort                                             |
|      │   │   ├── ServerReflexivePort                                  |
|      │   │   └── RelayPort (TURN)                                     |
|      │   └── Connection                                               |
|      ├── DtlsTransport                                                |
|      │   └── SSL (OpenSSL/boringssl)                                  |
|      └── SCTPTransport                                                |
|          └── DataChannel                                              |
|                                                                        |
+------------------------------------------------------------------------+
```

### 8.9 完整业务流程时间线

```
+------------------------------------------------------------------------+
|                    端到端时间线 (典型通话 5 分钟)                         |
+------------------------------------------------------------------------+
|                                                                        |
|  0ms       100ms     500ms    1s       5s        1min      5min       |
|  │          │         │        │         │         │        │         |
|  │          │         │        │         │         │        │         |
|  ├──────────┼─────────┼────────┼─────────┼─────────┼────────┼────────>│
|  │          │         │        │         │         │        │         |
|  │ 初始化完成 │ SDP完成  │ ICE    │ DTLS    │ 媒体流   │ 持续   │ Close │
|  │          │         │ 连接   │ 握手完成 │ 建立     │ 通话   │       │
|  │          │         │        │         │         │        │         |
|  │          │         │         │         │         │        │         |
|  │  ┌──────┐│  ┌────┐│  ┌───┐ │ ┌────┐  │ ┌────┐ │        │ ┌────┐ │
|  │  │ PCF  ││  │ SDP││  │ICE│ │ │DTLS│  │ │RTP │ │        │ │清理│ │
|  │  └──────┘│  └────┘│  └───┘ │ └────┘  │ └────┘ │        │ └────┘ │
|  │          │         │         │         │         │        │         |
|  │          │         │         │         │         │        │         |
|  │  ┌──────┐│  ┌────┐│  ┌───┐ │ ┌────┐  │ ┌────┐ │        │         |
|  │  │Thread││  │Codec││  │NAT│ │ │Cert │  │Media│ │        │         |
|  │  └──────┘│  └────┘│  └───┘ │ └────┘  │ └────┘ │        │         |
|  │          │         │         │         │         │        │         |
|  │          │         │         │         │ ┌────┐ │        │         |
|  │          │         │         │         │ │BWE │ │ 拥塞控制持续运行    │         |
|  │          │         │         │         │ └────┘ │        │         |
|  │          │         │         │         │ ┌────┐ │        │         |
|  │          │         │         │         │ │Adapt│ │ 自适应持续运行    │         |
|  │          │         │         │         │ └────┘ │        │         |
|  │          │         │         │         │ ┌────┐ │        │         |
|  │          │         │         │         │ │RTCP│ │ RTCP 每 5s     │         |
|  │          │         │         │         │ └────┘ │        │         |
|  │          │         │         │         │         │        │         |
|  │          │         │         │         │ ┌────┐ │        │ ┌────┐ │
|  │          │         │         │         │ │Data│ │ DataChannel │ │  │
|  │          │         │         │         │ │Chan│ │ 持续运行    │ │清理│ │
|  │          │         │         │         │ └────┘ │        │ └────┘ │
|  │          │         │         │         │         │        │         |
|                                                                        |
|  关键指标:                                                               |
|  ──────────                                                          |
|  初始化耗时: 50~200ms                                                    |
|  协商耗时: 200ms~2s                                                     |
|  端到端延迟: 音频 20~50ms, 视频 100~300ms                               |
|  RTCP 间隔: 5s                                                          |
|  BWE 更新: 每 500ms                                                     |
|  Pacing: 音频 ~8ms, 视频 ~1ms                                          |
|  JitterBuffer: 音频 20~100ms, 视频 50~200ms                             |
|                                                                        |
+------------------------------------------------------------------------+
```

---

## 总结

本文档从**初始化 → 协商 → 通话 → 链路变化 → 断开（正常/异常）**的完整业务流程出发，覆盖了 WebRTC 的六大阶段、二十余个子流程。核心要点：

1. **线程亲和性**是 WebRTC 并发模型的基础，所有跨线程操作通过 Proxy/Invoke/Post 完成
2. **状态机**驱动连接生命周期，确定性状态转换保证可预测性
3. **三层分离**（控制面/数据面/状态机）使复杂系统可管理
4. **事件驱动**（sigslot）实现低延迟、低开销的模块间通信
5. **RAII + scoped_refptr + WeakPtr** 构成完整的内存安全体系
6. **拥塞控制闭环**是通话质量的核心，BWE + GCC + Pacing 协同工作
7. **分层恢复**（ICE 重连/DTLS 重握手/码率自适应）保证连接的韧性

所有分析均基于 WebRTC 源码（`pc/`, `call/`, `modules/`, `p2p/`, `media/engine/` 等目录），可直接映射到 C++ 代码实现。

---

## 第 8.10 章：类生命周期时序图

> **说明**：与第 4.8 章的"控制流时序图"不同，本章聚焦**对象存活区间**——每个核心类从 new 到 delete 的完整生命周期，在时间轴上的起止点。

### 8.10.1 核心对象存活区间（ASCII 甘特图）

```
+========================================================================+
|                    核心对象存活区间 (从创建到销毁)                       |
+========================================================================+
|                                                                        |
|  时间轴:                                                               |
|  |<──── 初始化 ────|<── 协商 ──>|<── 通话 ────────────────>|<── 断开 ──>|
|  0ms               500ms          1s                     5min           |
|                                                                        |
|  对象存活区间 (横条长度 = 对象存活时间):                                 |
|  ────────────────────────────────────────────────────────────────────  |
|                                                                        |
|  PeerConnectionFactory          ████████████████████████████████████   |
|  ─────────────────────          (进程启动创建, 进程退出销毁)              |
|                                                                        |
|  signaling_thread               ████████████████████████████████████   |
|  ──────────────────               (与 PCF 同生命周期)                    |
|                                                                        |
|  worker_thread                  ████████████████████████████████████   |
|  ─────────────────                (与 PCF 同生命周期)                    |
|                                                                        |
|  network_thread                 ████████████████████████████████████   |
|  ──────────────────               (与 PCF 同生命周期)                    |
|                                                                        |
|  PeerConnection (Proxy)         ██████████████████████████████         |
|  ──────────────────               (创建到 Close())                      |
|                                                                        |
|  PeerConnection (实际对象)      ██████████████████████████████         |
|  ─────────────────                (signaling_thread 上, Close 时销毁)    |
|                                                                        |
|  Call                           ██████████████████████████             |
|  ─────                          (worker_thread 上, Close 时销毁)         |
|                                                                        |
|  ProcessThread                  ██████████████████████████             |
|  ─────────────                  (Call 创建时启动, Call 销毁时停止)        |
|                                                                        |
|  JsepTransportController        ██████████████████████████             |
|  ───────────────────            (PC 创建时, Close 时销毁)                |
|                                                                        |
|  IceTransport                   ██████████████████████████             |
|  ─────────────                  (协商时创建, Close 时销毁)               |
|                                                                        |
|  DtlsTransport                  ██████████████████████████             |
|  ──────────────                 (协商时创建, Close 时发送 CloseNotify)   |
|                                                                        |
|  SCTPTransport                  ██████████████████████████             |
|  ──────────────                 (协商时创建, Close 时销毁)               |
|                                                                        |
|  PortAllocator                  ██████████████████████████████         |
|  ─────────────                  (PC 创建时, Close 时清理)                |
|                                                                        |
|  UDPPort (Host)                 ██████████████████████████             |
|  ────────────                   (协商时收集, Close 时关闭)               |
|                                                                        |
|  UDPPort (SRFLX)                ██████████████████████████             |
|  ─────────────                  (协商时 STUN 获取, Close 时关闭)         |
|                                                                        |
|  UDPPort (Relay)                ██████████████████████████             |
|  ────────────                   (协商时 TURN 分配, Close 时释放)         |
|                                                                        |
|  WebRtcVoiceEngine              ██████████████████████████             |
|  ───────────────────            (ChannelManager 创建时, Close 时销毁)    |
|                                                                        |
|  WebRTCVideoEngine              ██████████████████████████             |
|  ───────────────────            (ChannelManager 创建时, Close 时销毁)    |
|                                                                        |
|  ADM                            ██████████████████████████████         |
|  ──────                         (VoiceEngine 创建时初始化, Close 时停止) |
|                                                                        |
|  APM                            ██████████████████████████████         |
|  ──────                         (VoiceEngine 创建时初始化, Close 时停止) |
|                                                                        |
|  AudioSendStream                ████████████████████████               |
|  ───────────────                (AddTrack 创建, RemoveTrack/Close 销毁) |
|                                                                        |
|  AudioReceiveStream             ████████████████████████               |
|  ───────────────────            (SetRemoteDescription 创建,            |
|                                  RemoveTrack/Close 销毁)                 |
|                                                                        |
|  VideoSendStream                ████████████████████████               |
|  ───────────────                (AddTrack 创建, RemoveTrack/Close 销毁) |
|                                                                        |
|  VideoReceiveStream             ████████████████████████               |
|  ───────────────────            (SetRemoteDescription 创建,            |
|                                  RemoveTrack/Close 销毁)                 |
|                                                                        |
|  Encoder (VP8/VP9/H264/AV1)     ████████████████████████               |
|  ──────────────────             (AudioSend/VideoSendStream 创建时,      |
|                                  销毁时释放)                             |
|                                                                        |
|  JitterBuffer (NetEq)           ████████████████████████               |
|  ───────────────                (AudioReceiveStream 创建时,             |
|                                  销毁时清理)                             |
|                                                                        |
|  Pacer                          ██████████████████████████             |
|  ──────                         (Call 创建时, Close 时销毁)              |
|                                                                        |
|  GccCongestionController        ██████████████████████████             |
|  ───────────────────            (Call 创建时, Close 时销毁)              |
|                                                                        |
|  RemoteBitrateEstimator         ██████████████████████████             |
|  ───────────────────            (Call 创建时, Close 时销毁)              |
|                                                                        |
|  RtcEventLog                    ██████████████████████████             |
|  ─────────────                  (PCF 创建时, Close 时销毁)               |
|                                                                        |
|  RTCCertificate                 ██████████████████████████████         |
|  ───────────────                (PC 创建时生成, Close 时释放)            |
|                                                                        |
|  DataChannel                    ████████████████████████               |
|  ──────────────                 (CreateDataChannel 创建,               |
|                                  Close/OnClose 销毁)                    |
|                                                                        |
|  scoped_refptr<VideoFrame>  (瞬态)                                      |
|  ~~~~                           (采集帧 → 编码, 编码完成后释放)           |
|  ~~~~~~~~                         (接收帧 → 解码 → 渲染, 渲染后释放)      |
|  ~~~                             (每帧存活 16~33ms, 零拷贝引用计数)       |
|                                                                        |
+========================================================================+
```

### 8.10.2 对象创建/销毁依赖图

```
+========================================================================+
|                    对象创建/销毁依赖关系                                  |
+========================================================================+
|                                                                        |
|  创建依赖 (谁创建谁):                                                    |
|  ────────────────────                                                   |
|                                                                        |
|  PeerConnectionFactory (应用线程)                                       |
|  ├── signaling_thread, worker_thread, network_thread                    |
|  │    └── PeerConnection (signaling_thread)                             |
|  │         ├── Call (worker_thread)                                     |
|  │         │   ├── AudioSendStream[]                                    |
|  │         │   ├── AudioReceiveStream[]                                 |
|  │         │   ├── VideoSendStream[]                                    |
|  │         │   ├── VideoReceiveStream[]                                 |
|  │         │   ├── ProcessThread                                        |
|  │         │   ├── Pacer                                                |
|  │         │   ├── GccCongestionController                              |
|  │         │   └── RemoteBitrateEstimator                               |
|  │         ├── JsepTransportController                                  |
|  │         │   ├── IceTransport                                         |
|  │         │   │   └── PortAllocator                                    |
|  │         │   │       ├── UDPPort (Host)                               |
|  │         │   │       ├── UDPPort (SRFLX)                              |
|  │         │   │       └── UDPPort (Relay)                              |
|  │         │   ├── DtlsTransport                                        |
|  │         │   │   └── RTCCertificate                                   |
|  │         │   └── SCTPTransport                                        |
|  │         │       └── DataChannel[]                                    |
|  │         └── ChannelManager                                           |
|  │             ├── WebRtcVoiceEngine                                    |
|  │             │   ├── ADM                                              |
|  │             │   ├── APM                                              |
|  │             │   ├── AudioCoding                                      |
|  │             │   └── AudioMixer                                       |
|  │             └── WebRTCVideoEngine                                    |
|  │                 └── VideoEncoderFactory[]                            |
|  └── RtcEventLog                                                        |
|                                                                        |
|  销毁顺序 (与创建顺序严格相反):                                          |
|  ──────────────────────────────                                         |
|  1. DataChannel (最内层依赖)                                             |
|  2. SCTPTransport                                                        |
|  3. DtlsTransport (发送 CloseNotify)                                     |
|  4. IceTransport + UDPPort[]                                             |
|  5. PortAllocator                                                        |
|  6. JsepTransportController                                              |
|  7. WebRTCVideoEngine                                                    |
|  8. WebRtcVoiceEngine                                                    |
|  9. VideoReceiveStream[] / AudioReceiveStream[]                          |
|  10. VideoSendStream[] / AudioSendStream[]                               |
|  11. Call (含 ProcessThread, Pacer, GCC)                                 |
|  12. PeerConnection (signaling_thread 上)                                |
|  13. PeerConnectionFactory (最后)                                        |
|                                                                        |
+========================================================================+
```

### 8.10.3 瞬态对象生命周期（VideoFrame）

```
+========================================================================+
|                    VideoFrame 零拷贝生命周期                             |
+========================================================================+
|                                                                        |
|  发送端:                                                               |
|  ───────                                                               |
|                                                                        |
|  采集线程              worker_thread (ProcessThread)                     |
|  ──────────              ───────────────────────────                    |
|                                                                        |
|  OnFrame(video_frame)                                                  |
|  │  scoped_refptr<VideoFrame> (I420, 16ms)                             |
|  │  引用计数: 1                                                         |
|  │                                                                      |
|  │  VideoSendStream::Encode(video_frame)                                |
|  │  │ 引用计数: 2 (编码器持有)                                           |
|  │  │                                                                  |
|  │  │ 编码器异步执行:                                                     |
|  │  │   EncodedImage created                                           |
|  │  │   video_frame 引用计数: 1 (释放)                                  |
|  │  │                                                                  |
|  │  │ Packetizer::Packetize(encoded_image)                              |
|  │  │   生成 RTP 包 → 释放 encoded_image                                 |
|  │  │                                                                  |
|  │  │ Pacer → Socket Send                                              |
|  │  │                                                                  |
|  └────────────────────────────────────────────────────────────────────  │
|                                                                        |
|  接收端:                                                               |
|  ───────                                                               |
|                                                                        |
|  network_thread          worker_thread (ProcessThread)                  |
|  ──────────────          ────────────────────────────                  |
|                                                                        |
|  RTP 包到达                                                       │     │
|  │                                                                      │     │
|  │ SRTP 解密 → Depacketizer                                             │     │
|  │ │  scoped_refptr<VideoFrame> (I420, 16ms)                            │     │
|  │ │  引用计数: 1                                                        │     │
|  │ │                                                                    │     │
|  │ │ VideoReceiveStream::Decoded(video_frame)                            │     │
|  │ │ │ 引用计数: 2 (解码器持有)                                           │     │
|  │ │ │                                                                  │     │
|  │ │ │ 解码器输出:                                                        │     │
|  │ │ │   I420 Frame                                                     │     │
|  │ │ │   video_frame 引用计数: 1 (释放)                                  │     │
|  │ │ │                                                                  │     │
|  │ │ │ VideoSink::OnFrame(video_frame)                                   │     │
|  │ │ │ │ 引用计数: 2 (渲染器持有)                                         │     │
|  │ │ │ │                                                                │     │
|  │ │ │ │ 渲染到 GPU:                                                      │     │
|  │ │ │ │   纹理上传                                                       │     │
|  │ │ │ │   video_frame 引用计数: 1 (释放)                                │     │
|  │ │ │ │                                                                │     │
|  │ │ │ │ 渲染完成:                                                        │     │
|  │ │ │ │   video_frame 引用计数: 0 (销毁)                                │     │
|  │ │ │                                                                │     │
|  └──────────────────────────────────────────────────────────────────────│     │
|                                                                        |
|  关键: 每个 VideoFrame 通过 scoped_refptr 零拷贝传递，                     |
|  引用计数精确控制生命周期，无内存拷贝。                                    |
|                                                                        |
+========================================================================+
```

### 8.10.4 重新协商时的对象生命周期变化

```
+========================================================================+
|                    重新协商时的对象生命周期变化                           |
+========================================================================+
|                                                                        |
|  场景: AddTrack (新增音频轨道)                                          |
|  ────────────────────────────                                          |
|                                                                        |
|  时间轴:                                                               |
|  |<──── 初次通话 ────>|<── AddTrack ──>|<── 继续通话 ────>|            |
|  0ms                  5s              5.5s              10s            |
|                                                                        |
|  已有对象 (不受影响):                                                   |
|  PeerConnection             ██████████████████████████████████         |
|  Call                       ██████████████████████████████████         |
|  AudioSendStream (旧)       ██████████████████████████████████         |
|  VideoSendStream (旧)       ██████████████████████████████████         |
|  IceTransport               ██████████████████████████████████         |
|  DtlsTransport              ██████████████████████████████████         |
|  Pacer                      ██████████████████████████████████         |
|  GccCongestionController    ██████████████████████████████████         |
|                                                                        |
|  新增对象 (AddTrack 时创建):                                            |
|  ──────────────────────────────────                                     |
|                                                                        |
|  MediaStream (新)                              ~~~~~~~~               |
|  AudioSendStream (新)                            ~~~~~~~~              |
|  AudioRtpSender (新)                               ~~~~                |
|  RtpTransceiver (新)                               ~~~~                |
|                                                                        |
|  销毁对象:                                                             |
|  ──────────                                                          |
|  无对象销毁 (增量修改)                                                    |
|                                                                        |
|  ────────────────────────────────────────────────────────────────────  |
|                                                                        |
|  场景: RemoveTrack (移除音频轨道)                                       |
|  ──────────────────────────────                                       |
|                                                                        |
|  时间轴:                                                               |
|  |<──── 通话 ──>|<── RemoveTrack ──>|<── 继续通话 ────>|              |
|  0ms              10s              10.5s             15s               |
|                                                                        |
|  已有对象 (不受影响):                                                   |
|  PeerConnection             ██████████████████████████████████         |
|  Call                       ██████████████████████████████████         |
|  VideoSendStream (旧)       ██████████████████████████████████         |
|  IceTransport               ██████████████████████████████████         |
|  DtlsTransport              ██████████████████████████████████         |
|                                                                        |
|  销毁对象 (RemoveTrack 时):                                             |
|  ──────────────────────────                                           |
|                                                                        |
|  AudioSendStream (旧)       ~~~~~~~~~~~~~~~~~~                         |
|  MediaStream (旧)           ~~~~~~~~~~~~                               |
|  AudioRtpSender (旧)        ~~~~~~~~~                                  |
|                                                                        |
|  ────────────────────────────────────────────────────────────────────  |
|                                                                        |
|  场景: ICE Restart                                                      |
|  ────────────────────                                                   |
|                                                                        |
|  时间轴:                                                               |
|  |<── 通话 ──>|<── ICE Restart ──>|<── 继续通话 ──>|                  |
|  0ms           10s              11s            16s                     |
|                                                                        |
|  已有对象 (不受影响):                                                   |
|  PeerConnection             ██████████████████████████████████         |
|  Call                       ██████████████████████████████████         |
|  AudioSendStream            ██████████████████████████████████         |
|  VideoSendStream            ██████████████████████████████████         |
|  DtlsTransport              ██████████████████████████████████         |
|  Pacer                      ██████████████████████████████████         |
|  GccCongestionController    ██████████████████████████████████         |
|                                                                        |
|  销毁对象:                                                               |
|  ──────────                                                          |
|  UDPPort (旧)           ~~~~~~~~~~~~ (旧候选废弃)                        |
|  Connection (旧)        ~~~~~~~~~~~~ (旧连接废弃)                        |
|                                                                        |
|  新增对象:                                                               |
|  ──────────                                                          |
|  UDPPort (新)           ~~~~~~~~~~~~ (新候选收集)                        |
|  Connection (新)        ~~~~~~~~~~~~ (新连接检查)                        |
|                                                                        |
+========================================================================+
```
