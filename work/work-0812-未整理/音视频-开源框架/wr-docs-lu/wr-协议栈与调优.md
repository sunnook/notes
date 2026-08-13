



webrtc的协议有哪些参数，介绍一下，并列个表格，从常用到不常用


<think>
---
</think>好的，我们从 WebRTC 协议栈的角度来梳理。WebRTC 不是单一协议，而是一套协议集合，每个协议都有自己关键的参数和配置项。

---

## WebRTC 协议栈全景图

```
┌─────────────────────────────────────────────────┐
│                   应用层                          │
│         SDP (会话描述协议)                        │
├─────────────────────────────────────────────────┤
│             信令层 (Signaling)                    │
│      WebSocket / SIP / XMPP (非WebRTC规范)       │
├──────────────┬──────────────────────────────────┤
│   媒体层      │          数据层                   │
│  SRTP/SRTCP  │    SCTP (流控制传输协议)           │
├──────────────┤                                  │
│  RTP/RTCP    │                                  │
├──────────────┴──────────────────────────────────┤
│             传输层 (Transport)                    │
│  ICE (交互式连接建立)                             │
│  ├── STUN (会话穿透)                             │
│  └── TURN (中继穿透)                             │
├─────────────────────────────────────────────────┤
│             网络层                                │
│  UDP / TCP (DTLS 加密基于 UDP)                   │
└─────────────────────────────────────────────────┘
```

---

## 协议参数详解（从常用到不常用）

### 1. SDP（会话描述协议）— 最常用

SDP 是 WebRTC 的"配置单"，在建立连接前交换，描述媒体能力和网络信息。

| 参数分类 | 具体参数 | 说明 | 示例值 |
|---------|---------|------|--------|
| **会话级** | `v` | 协议版本 | `v=0` |
| | `o` | 会话发起者标识 | `o=- 123456 2 IN IP4 192.168.1.1` |
| | `s` | 会话名称 | `s=WebRTC Call` |
| | `t` | 会话时间 | `t=0 0`（持久会话） |
| **媒体级** | `m` | 媒体类型和端口 | `m=video 9 UDP/TLS/RTP/SAVPF 96 97` |
| | `a=rtpmap` | RTP 载荷类型映射 | `a=rtpmap:96 VP8/90000` |
| | `a=fmtp` | 编解码器特定参数 | `a=fmtp:96 profile-level-id=42e01f` |
| **网络** | `c` | 连接信息 | `c=IN IP4 192.168.1.1` |
| | `a=candidate` | ICE 候选地址 | `a=candidate:1 1 UDP 2130706431 192.168.1.1 8080 typ host` |
| | `a=ice-ufrag` | ICE 用户名片段 | `a=ice-ufrag:abcd` |
| | `a=ice-pwd` | ICE 密码 | `a=ice-pwd:1234567890` |
| **安全** | `a=fingerprint` | DTLS 证书指纹 | `a=fingerprint:sha-256 AB:CD:...` |
| | `a=setup` | DTLS 角色 | `a=setup:actpass` |

---

### 2. ICE（交互式连接建立）— 最常用

ICE 负责找到两个端点之间可用的网络路径。

| 参数 | 说明 | 典型值 |
|------|------|--------|
| **candidate** | 候选地址字符串 | `candidate:foundation component-id protocol priority ip port type` |
| **foundation** | 候选地址基础标识 | 同一物理接口的候选有相同 foundation |
| **component-id** | 组件 ID | `1`（RTP）、`2`（RTCP） |
| **protocol** | 传输协议 | `udp`、`tcp` |
| **priority** | 优先级（越大越优先） | `2130706431`（host 候选） |
| **type** | 候选类型 | `host`、`srflx`、`prflx`、`relay` |
| **ice-ufrag** | 用户名片段 | 随机字符串，用于 STUN 认证 |
| **ice-pwd** | 密码 | 随机字符串，用于 STUN 认证 |

**候选类型优先级（从高到低）：**

| 类型 | 说明 | 优先级计算 |
|------|------|-----------|
| `host` | 本地地址（直连） | 最高优先级 |
| `srflx` | 服务器反射地址（经 STUN） | 中优先级 |
| `prflx` | 对端反射地址（经 STUN） | 中优先级 |
| `relay` | 中继地址（经 TURN） | 最低优先级 |

---

### 3. STUN（NAT 会话穿透）— 常用

| 参数 | 说明 | 典型值 |
|------|------|--------|
| **STUN Server** | STUN 服务器地址 | `stun:stun.l.google.com:19302` |
| **Binding Request** | 绑定请求，获取公网地址 | 返回 `XOR-MAPPED-ADDRESS` |
| **XOR-MAPPED-ADDRESS** | 异或编码的公网 IP:Port | `192.168.1.1:12345` |

---

### 4. TURN（中继穿透）— 常用（作为备选）

| 参数 | 说明 | 典型值 |
|------|------|--------|
| **TURN Server** | TURN 服务器地址 | `turn:turn.example.com:3478` |
| **username** | 认证用户名 | `user` |
| **credential** | 认证密码 | `password` |
| **realm** | 认证域 | `example.com` |
| **Allocation** | 中继地址分配 | 服务器分配一个公网 IP:Port |
| **Permission** | 通信权限 | 允许特定对端 IP 发送数据 |
| **Channel** | 数据通道 | 绑定对端地址到一个通道号 |

---

### 5. DTLS（数据报传输层安全）— 常用

| 参数 | 说明 | 典型值 |
|------|------|--------|
| **cipher_suite** | 加密套件 | `TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256` |
| **certificate** | 证书 | 自签名证书 |
| **fingerprint** | 证书指纹 | `sha-256 AB:CD:EF:...` |
| **setup** | 角色协商 | `actpass`、`active`、`passive` |
| **version** | DTLS 版本 | `DTLS 1.2`（WebRTC 要求） |

---

### 6. RTP/RTCP（实时传输协议）— 常用

| 参数 | 说明 | 典型值 |
|------|------|--------|
| **payload type** | 载荷类型（编解码器） | `96`（VP8）、`111`（Opus） |
| **SSRC** | 同步源标识符 | 32 位随机数 |
| **CSRC** | 贡献源标识符 | 混音场景使用 |
| **sequence number** | 序列号 | 16 位，用于丢包检测 |
| **timestamp** | 时间戳 | 32 位，用于同步和抖动计算 |
| **marker bit** | 标记位 | 标记帧边界 |
| **PT** | 载荷类型 | 7 位，区分编解码器 |

**RTCP 包类型：**

| 包类型 | 缩写 | 说明 |
|--------|------|------|
| 200 | SR | 发送者报告（统计信息） |
| 201 | RR | 接收者报告（统计信息） |
| 202 | SDES | 源描述（CNAME 等） |
| 203 | BYE | 结束会话 |
| 204 | APP | 应用自定义 |

---

### 7. SRTP/SRTCP（安全实时传输协议）— 常用

| 参数 | 说明 | 典型值 |
|------|------|--------|
| **cipher** | 加密算法 | `AES_128_CM` |
| **auth** | 认证算法 | `HMAC_SHA1_80` |
| **key** | 密钥 | 由 DTLS 握手协商生成 |
| **salt** | 盐值 | 由 DTLS 握手协商生成 |

---

### 8. SCTP（流控制传输协议）— 较常用（DataChannel）

| 参数 | 说明 | 典型值 |
|------|------|--------|
| **port** | SCTP 端口 | `5000` |
| **streams** | 流数量 | 双向，默认 1024 |
| **ordered** | 是否有序传输 | `true`（有序）/ `false`（无序） |
| **maxRetransmits** | 最大重传次数 | `0`（不重传） |
| **maxPacketLifeTime** | 最大包生存时间 | `1000`（毫秒） |

---

### 9. 编解码器参数（不常用但重要）

| 编解码器 | 参数 | 说明 | 典型值 |
|---------|------|------|--------|
| **Opus** | `maxaveragebitrate` | 最大平均比特率 | `510000`（510kbps） |
| | `stereo` | 立体声 | `0`（单声道）/ `1`（立体声） |
| | `useinbandfec` | 带内前向纠错 | `0`（禁用）/ `1`（启用） |
| | `ptime` | 打包时长 | `20`（毫秒） |
| **VP8** | `profile-level-id` | 配置级别 | `42e01f` |
| | `max-fr` | 最大帧率 | `30` |
| | `max-fs` | 最大帧尺寸 | `12288`（宏块数） |
| **VP9** | `profile-id` | 配置 ID | `0`（8-bit）、`2`（10-bit） |
| **H.264** | `profile-level-id` | 配置级别 | `42e01f`（Baseline） |
| | `packetization-mode` | 打包模式 | `0`（单一NAL）/ `1`（非交错） |

---

### 10. 不常用但存在的参数

| 协议/功能 | 参数 | 说明 |
|----------|------|------|
| **RTCP Multiplexing** | `a=rtcp-mux` | RTP 和 RTCP 共用同一端口 |
| **RTP Multiplexing** | `a=rtcp-mux-only` | 仅 RTP 多路复用 |
| **BUNDLE** | `a=group:BUNDLE` | 多路媒体流共用同一传输 |
| **RTP Header Extension** | `a=extmap` | RTP 头扩展（如音频级别） |
| **FEC** | `a=rtpmap:120 ulpfec/90000` | 前向纠错 |
| **RED** | `a=rtpmap:121 red/90000` | 冗余编码 |
| **RTX** | `a=rtpmap:122 rtx/90000` | 重传 |
| **Transport-CC** | `a=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01` | 传输层拥塞控制 |
| **abs-send-time** | `a=extmap:4 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time` | 绝对发送时间 |

---

## 总结表格：从最常用到最不常用

| 优先级 | 协议 | 核心参数 | 使用场景 |
|-------|------|---------|---------|
| ⭐⭐⭐⭐⭐ | **SDP** | `m`, `a=rtpmap`, `a=fmtp`, `a=candidate`, `a=ice-ufrag`, `a=ice-pwd`, `a=fingerprint` | 会话建立，每次连接必用 |
| ⭐⭐⭐⭐⭐ | **ICE** | `candidate`, `type`, `priority`, `ice-ufrag`, `ice-pwd` | NAT 穿透，每次连接必用 |
| ⭐⭐⭐⭐ | **STUN** | `stun server`, `XOR-MAPPED-ADDRESS` | 获取公网地址 |
| ⭐⭐⭐⭐ | **TURN** | `turn server`, `username`, `credential` | 中继转发（备选） |
| ⭐⭐⭐⭐ | **DTLS** | `cipher_suite`, `fingerprint`, `setup` | 加密握手，每次连接必用 |
| ⭐⭐⭐⭐ | **RTP/RTCP** | `payload type`, `SSRC`, `sequence number`, `timestamp` | 媒体传输，每次连接必用 |
| ⭐⭐⭐⭐ | **SRTP/SRTCP** | `cipher`, `auth`, `key` | 媒体加密，每次连接必用 |
| ⭐⭐⭐ | **SCTP** | `port`, `streams`, `ordered`, `maxRetransmits` | DataChannel 数据传输 |
| ⭐⭐ | **Opus 参数** | `maxaveragebitrate`, `stereo`, `useinbandfec`, `ptime` | 音频质量调优 |
| ⭐⭐ | **VP8/VP9 参数** | `profile-level-id`, `max-fr`, `max-fs` | 视频质量调优 |
| ⭐ | **H.264 参数** | `profile-level-id`, `packetization-mode` | 视频编码配置 |
| ⭐ | **扩展参数** | `rtcp-mux`, `BUNDLE`, `extmap`, `FEC`, `RED`, `RTX`, `Transport-CC` | 高级优化和调试 |

---

**一句话总结：** SDP 和 ICE 是每次 WebRTC 连接都必用的核心，STUN/TURN 负责网络穿透，DTLS/SRTP 负责安全加密，RTP/RTCP 负责媒体传输，SCTP 负责数据通道，而编解码器参数和扩展参数主要用于性能调优和高级功能。









作为专业的媒体工程师，我要做一些性能调优和高级功能，展开讲讲


<think>
---
']

</think>好的，作为媒体工程师，性能调优和高级功能的实现需要对协议栈有更深层的理解。我们直接切入核心，从**网络传输、编解码、服务质量（QoS）** 三个维度展开，并给出具体的调优参数和策略。

---

## 一、网络传输层深度优化

网络是实时通信的物理基础，优化目标是在**带宽、延迟、丢包**的不可能三角中找到最佳平衡点。

### 1. ICE 与候选地址策略优化

**问题：** 默认的 ICE 策略可能选择次优路径（如走 TURN 中继），导致额外延迟。

**优化策略：**

| 策略 | 配置方式 | 效果 |
|------|---------|------|
| **优先 host 候选** | 调整 `candidate` 的 `priority` 计算公式 | 确保直连路径优先 |
| **禁用不必要候选** | 过滤 `relay` 类型候选 | 避免 TURN 中继的额外延迟 |
| **ICE 候选池预热** | 提前收集候选地址 | 减少连接建立时间 |
| **TCP 候选优化** | 设置 `iceTransportPolicy: "relay"` 仅在企业防火墙场景 | 避免 UDP 被阻断 |

**代码示例（JavaScript）：**
```javascript
const pc = new RTCPeerConnection({
  iceServers: [
    {
      urls: 'stun:stun.example.com:19302'
    },
    {
      urls: 'turn:turn.example.com:3478?transport=tcp',
      username: 'user',
      credential: 'pass'
    }
  ],
  iceTransportPolicy: 'all', // 'all' 或 'relay'
  iceCandidatePoolSize: 2    // 预取候选数量
});
```

### 2. DTLS 握手优化

**问题：** DTLS 握手需要 1-2 个 RTT，在弱网下可能耗时数秒。

**优化策略：**

| 策略 | 说明 |
|------|------|
| **DTLS 1.2 强制** | 避免旧版本兼容性开销 |
| **证书预生成** | 避免每次连接都生成新证书 |
| **TLS False Start** | 减少一次 RTT（需浏览器支持） |
| **会话恢复** | 使用 TLS Session Resumption 缓存握手状态 |

### 3. RTP/RTCP 多路复用与 BUNDLE

**问题：** 默认情况下，音频、视频、数据可能使用独立的传输通道，增加 NAT 穿透难度和带宽开销。

**优化策略：**

| 参数 | 说明 | 配置 |
|------|------|------|
| `rtcp-mux` | RTP 和 RTCP 共用同一端口 | `a=rtcp-mux`（强制） |
| `BUNDLE` | 音视频共用同一 ICE 传输 | `a=group:BUNDLE audio video` |
| `rtp-mux` | 仅 RTP 多路复用 | 实验性功能 |

**效果：** BUNDLE 可减少 50% 的 ICE 候选收集和连通性检查时间。

---

## 二、编解码器深度调优

编解码器是 CPU 消耗的大户，调优目标是在**画质/音质**与**计算资源**之间找到最佳平衡。

### 1. 视频编解码器高级参数

#### VP8 参数详解

| 参数 | 说明 | 调优建议 |
|------|------|---------|
| `profile-level-id` | 编码配置 | `42e01f`（标准） |
| `max-fr` | 最大帧率 | 根据场景设置（会议 15fps，直播 30fps） |
| `max-fs` | 最大帧尺寸（宏块数） | 720p = 3600，1080p = 8160 |
| `max-br` | 最大码率 | 720p 建议 800-1500kbps |
| `max-qp` | 最大量化参数 | 越低画质越好（0-63） |
| `min-qp` | 最小量化参数 | 控制最低画质 |
| `cpu-used` | CPU 使用率 | -16~16，负数画质好但慢，正数速度快但画质差 |
| `deadline` | 编码截止时间 | `realtime` 或 `good` |
| `error-resilient` | 错误恢复 | 弱网场景建议开启 |
| `screenshare` | 屏幕共享优化 | 屏幕共享场景必须开启 |

**代码示例（SDP 修改）：**
```
a=fmtp:96 profile-level-id=42e01f;max-fr=30;max-fs=3600;max-br=1500;cpu-used=-8;deadline=realtime
```

#### VP9 高级参数

| 参数 | 说明 | 调优建议 |
|------|------|---------|
| `profile-id` | 编码配置 | `0`（8-bit）、`2`（10-bit HDR） |
| `scalability` | 空间可伸缩性 | `L1T2`（2 层时间层） |
| `temporal-layers` | 时间层数量 | 2-3 层，用于 SVC |
| `spatial-layers` | 空间层数量 | 2-3 层，用于 SVC |
| `lossless` | 无损编码 | 特殊场景使用 |

#### H.264 高级参数

| 参数 | 说明 | 调优建议 |
|------|------|---------|
| `profile-level-id` | 编码配置 | `42e01f`（Baseline）、`4d0028`（Main）、`640028`（High） |
| `packetization-mode` | 打包模式 | `0`（单一NAL）、`1`（非交错，推荐） |
| `level-asymmetry-allowed` | 不对称级别 | `1`（允许） |
| `sprop-parameter-sets` | 序列参数集 | 包含 SPS/PPS 信息 |

### 2. 音频编解码器高级参数

#### Opus 深度调优

| 参数 | 说明 | 调优建议 |
|------|------|---------|
| `maxaveragebitrate` | 最大平均码率 | 语音 32kbps，音乐 128kbps |
| `maxplaybackrate` | 最大播放速率 | `48000`（48kHz） |
| `stereo` | 立体声 | 音乐场景 `1`，语音场景 `0` |
| `useinbandfec` | 带内前向纠错 | 弱网场景必须开启 |
| `usedtx` | 非连续传输 | 静音时不发送数据，节省带宽 |
| `ptime` | 打包时长（ms） | `20`（低延迟）或 `60`（高带宽效率） |
| `minptime` | 最小打包时长 | `10`（极低延迟场景） |
| `maxptime` | 最大打包时长 | `120`（高带宽效率） |

**代码示例（SDP 修改）：**
```
a=fmtp:111 minptime=10;useinbandfec=1;usedtx=1;stereo=0;maxaveragebitrate=32000
```

### 3. 硬件加速策略

| 策略 | 说明 | 实现方式 |
|------|------|---------|
| **硬件编码器优先** | 使用硬件 H.264/H.265 编码器 | 修改 SDP 编解码器优先级 |
| **零拷贝渲染** | 避免 CPU-GPU 数据拷贝 | 使用 `MediaStreamTrackProcessor` |
| **WebGL 渲染** | GPU 加速渲染 | 使用 `requestVideoFrameCallback` |

---

## 三、服务质量（QoS）与拥塞控制

这是媒体工程师的核心战场，需要深入理解 WebRTC 的拥塞控制算法。

### 1. 拥塞控制算法对比

| 算法 | 原理 | 适用场景 | 特点 |
|------|------|---------|------|
| **GCC** | 基于延迟的拥塞控制 | 默认算法 | 保守，延迟优先 |
| **BBR** | 基于带宽的拥塞控制 | 高带宽场景 | 激进，带宽优先 |
| **SCReAM** | 自时钟实时媒体 | 低延迟场景 | 适合视频会议 |
| **NADA** | 网络自适应 | 实验性 | 平衡延迟和带宽 |

**调优参数（GCC）：**

| 参数 | 说明 | 默认值 | 调优建议 |
|------|------|--------|---------|
| `loss-based control` | 基于丢包的控制 | 启用 | 弱网场景保持启用 |
| `delay-based control` | 基于延迟的控制 | 启用 | 低延迟场景保持启用 |
| `target bitrate` | 目标码率 | 自动 | 可手动设置上限 |
| `min bitrate` | 最小码率 | 30kbps | 弱网场景提高下限 |
| `max bitrate` | 最大码率 | 2.5Mbps | 根据场景限制 |

### 2. NACK 与 RTX（重传）

**问题：** 丢包导致视频卡顿，需要快速恢复。

**优化策略：**

| 参数 | 说明 | 配置 |
|------|------|------|
| `nack` | 否定确认 | `a=rtcp-fb:96 nack` |
| `nack pli` | 图像丢失指示 | `a=rtcp-fb:96 nack pli` |
| `rtx` | 重传流 | `a=rtpmap:97 rtx/90000` |
| `rtx-time` | 重传超时 | 默认 100ms |

**SDP 示例：**
```
a=rtcp-fb:96 nack
a=rtcp-fb:96 nack pli
a=rtpmap:97 rtx/90000
a=fmtp:97 apt=96;rtx-time=200
```

### 3. FEC（前向纠错）与 RED（冗余编码）

**问题：** 重传增加延迟，FEC 可提前恢复丢包。

**优化策略：**

| 参数 | 说明 | 配置 |
|------|------|------|
| `ulpfec` | 非等保护 FEC | `a=rtpmap:120 ulpfec/90000` |
| `flexfec` | 灵活 FEC | `a=rtpmap:121 flexfec/90000` |
| `red` | 冗余编码 | `a=rtpmap:122 red/90000` |
| `fec-mask` | FEC 掩码 | 控制 FEC 冗余度 |

**SDP 示例：**
```
a=rtpmap:120 ulpfec/90000
a=rtpmap:121 flexfec/90000
a=rtpmap:122 red/90000
a=fmtp:122 96/96
```

### 4. Jitter Buffer（抖动缓冲）

| 参数 | 说明 | 调优建议 |
|------|------|---------|
| **最小缓冲** | 最小缓冲时间 | 低延迟场景 20-30ms |
| **最大缓冲** | 最大缓冲时间 | 弱网场景 200-500ms |
| **自适应** | 自动调整缓冲大小 | 保持启用 |

---

## 四、高级功能实现

### 1. SVC（可伸缩视频编码）

**适用场景：** 多人会议、网络自适应

**实现方式：**

| 编码器 | 支持情况 | 配置 |
|--------|---------|------|
| **VP9** | 原生支持 | `scalability=L1T2` |
| **H.264 SVC** | 部分支持 | `sprop-scalability` |
| **AV1** | 实验性 | 未来趋势 |

**SDP 示例（VP9 SVC）：**
```
a=fmtp:98 profile-id=0;scalability=L2T2
```

### 2. Simulcast（同时联播）

**适用场景：** SFU 多人会议，不同接收端自适应

**SDP 示例（3 层 Simulcast）：**
```
a=rid:1 send
a=rid:2 send
a=rid:3 send
a=simulcast:send 1;2;3
```

### 3. Transport-CC（传输层拥塞控制）

**作用：** 更精确的带宽估计

**SDP 配置：**
```
a=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01
```

### 4. abs-send-time（绝对发送时间）

**作用：** 精确的延迟测量

**SDP 配置：**
```
a=extmap:4 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time
```

---

## 五、调优决策树

```
开始调优
│
├─ 延迟高？
│  ├─ 是 → 检查 ICE 路径（是否走 TURN）
│  │      ├─ 走 TURN → 优化 ICE 策略，优先直连
│  │      └─ 直连 → 检查 Jitter Buffer 大小
│  │              ├─ 缓冲大 → 减小最小缓冲时间
│  │              └─ 缓冲小 → 检查网络丢包
│  │                      ├─ 丢包高 → 启用 FEC/RED
│  │                      └─ 丢包低 → 检查编解码器延迟
│  │                              ├─ 软件编码 → 启用硬件加速
│  │                              └─ 硬件编码 → 降低编码复杂度
│  └─ 否 → 继续
│
├─ 画质差？
│  ├─ 是 → 检查码率
│  │      ├─ 码率低 → 提高目标码率上限
│  │      └─ 码率高 → 检查编码参数
│  │              ├─ QP 值高 → 降低 max-qp
│  │              └─ QP 值低 → 检查分辨率/帧率是否过高
│  └─ 否 → 继续
│
├─ 卡顿/丢帧？
│  ├─ 是 → 检查 CPU 占用
│  │      ├─ CPU 高 → 降低编码复杂度（cpu-used）
│  │      └─ CPU 正常 → 检查网络丢包
│  │              ├─ 丢包高 → 启用 NACK/RTX
│  │              └─ 丢包低 → 检查拥塞控制算法
│  └─ 否 → 继续
│
└─ 带宽占用高？
   ├─ 是 → 启用 usedtx（静音抑制）
   │      ├─ 视频 → 启用 Simulcast/SVC
   │      └─ 音频 → 降低 Opus 码率
   └─ 否 → 调优完成
```

---

**一句话总结：** 作为媒体工程师，性能调优的核心是**数据驱动**——通过 `getStats()` API 获取实时指标，结合 Wireshark 抓包分析，针对性地调整 ICE、编解码器、QoS 参数，最终在延迟、画质、流畅度之间找到最佳平衡点。










