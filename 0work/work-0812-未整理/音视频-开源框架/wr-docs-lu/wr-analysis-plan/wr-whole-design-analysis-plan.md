# WebRTC 完整业务流程分析计划

## 目标
分析 WebRTC 从初始化 → 协商 → 通话 → 链路变化 → 断开（正常/异常）的完整业务流程，覆盖各层级、模块、协议（音视频/QoS/拥塞控制等）的流转协作、依赖关系、数据流与控制流。

## 读者画像
- 具备 C/C++ 经验，熟悉高级 C++ 用法但需要补充
- 已有 `wr-modules-analysis.md` 的模块认知，现在需要端到端的流程串联

## 章节大纲

### 第 1 章：全景概览
- 1.1 完整业务流程全景图（ASCII 流程图：初始化 → 协商 → 链路 → 通话 → 断开）
- 1.2 五大阶段定义与触发条件
- 1.3 控制流 vs 数据流 vs 状态机的三层分离
- 1.4 线程模型总览（信令线程 / worker 线程 / 网络线程 / 模块线程）

### 第 2 章：阶段一 — 初始化
- 2.1 创建 PeerConnectionFactory（编码器工厂、线程队列）
- 2.2 创建 PeerConnection（Call、JsepTransportController、MediaEngine）
- 2.3 MediaEngine 初始化（ADM、APE、AudioCoding、VideoCoding）
- 2.4 线程分配与 Proxy 创建
- 2.5 控制流时序图
- 2.6 C++ 知识点：unique_ptr 所有权转移、依赖注入模式

### 第 3 章：阶段二 — SDP 协商
- 3.1 本地 SDP 生成（Offer）：编解码器协商、SSRC 分配、RTP 扩展
- 3.2 ICE 候选收集：Host / Server-Reflexive / Relay 候选
- 3.3 远程 SDP 应用（Answer）：解析、Stream 创建、Codec 匹配
- 3.4 DTLS 握手：CertificateFingerprint、密钥交换
- 3.5 ICE 连接检查：Candidate Pair、Connection Check
- 3.6 控制流时序图（完整 Offer→Answer→ICE→DTLS）
- 3.7 C++ 知识点：absl::optional、async 回调链

### 第 3.5 章：重新协商 vs 初次协商（对比分析）
- 3.5.1 重新协商触发场景（应用层重新建连、add/remove track、ICE Restart、re-INVITE）
- 3.5.2 重新协商流程与初次协商的差异对比表
- 3.5.3 ICE Restart：完整 ICE 重建 vs 复用已有候选
- 3.5.4 DTLS 状态：已建立时跳过握手 vs 全新握手
- 3.5.5 状态机差异：New→Connecting vs Connected→Connecting→Connected
- 3.5.6 MediaStream 处理：全新创建 vs 增量修改（AddTrack/RemoveTrack）
- 3.5.7 SSRC 管理：全新分配 vs 保留/重新分配
- 3.5.8 控制流对比时序图（初次 vs 重新）

### 第 4 章：阶段三 — 通话进行中
- 4.1 音频发送链路（麦克风 → ADM → APE → 编码 → RTP → 网络）
- 4.2 音频接收链路（网络 → RTP → 解码 → APE → ADM → 扬声器）
- 4.3 视频发送链路（采集 → VPM → 编码 → NACK/FEC → RTP → 网络）
- 4.4 视频接收链路（网络 → RTP → JitterBuffer → 解码 → VPM → 渲染）
- 4.5 DataChannel 数据流（SCTP over DTLS）
- 4.6 拥塞控制闭环（BWE → GCC → Pacing → 码率调整）
- 4.7 视频自适应（分辨率/码率/帧率动态调整）
- 4.8 控制流时序图（实时交互）
- 4.9 C++ 知识点：Observer 模式、回调链、WeakPtr

### 第 5 章：阶段四 — 链路变化
- 5.1 网络切换（WiFi → 4G / IP 变更）
- 5.2 ICE 重连：新候选发现、Candidate Pair 更新
- 5.3 DTLS 重握手
- 5.4 拥塞控制响应：带宽骤降/恢复
- 5.5 视频自适应触发：质量降级/恢复
- 5.6 控制流时序图
- 5.7 C++ 知识点：状态机模式、事件驱动

### 第 6 章：阶段五 — 正常断开
- 6.1 应用主动关闭（Close）
- 6.2 SDP BYE 协商
- 6.3 DTLS CloseNotify
- 6.4 ICE Connection Terminated
- 6.5 资源清理顺序（Stream → Channel → Engine → Call）
- 6.6 控制流时序图
- 6.7 C++ 知识点：RAII、析构顺序、资源泄漏防护

### 第 7 章：阶段六 — 异常断开
- 7.1 网络突然中断（断网）
- 7.2 ICE 超时与回退
- 7.3 DTLS 连接断开
- 7.4 编码器崩溃与回退
- 7.5 远端无响应（Heartbeat 超时）
- 7.6 部分媒体恢复（单方向恢复）
- 7.7 控制流时序图
- 7.8 C++ 知识点：WeakPtr 防悬空、超时定时器、重试策略

### 第 8 章：跨阶段协作关系总览
- 8.1 各模块在五大阶段中的角色矩阵
- 8.2 协议栈交互图（SDP/ICE/DTLS/SCTP/RTP/RTCP）
- 8.3 QoS 算法协作图（BWE/AEC/NS/AGC/VAD/自适应）
- 8.4 完整端到端数据流图（发送 + 接收 + 控制面）
- 8.5 线程间消息流总览
- 8.6 关键对象生命周期总览
