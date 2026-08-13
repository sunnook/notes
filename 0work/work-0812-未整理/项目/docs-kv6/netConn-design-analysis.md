# netConn 网络协议架构深度分析

> 项目路径：`app/src/netConn/`
> 代码规模：约 645 个源文件，30+ 个子目录
> 厂商：杭州海康威视数字技术股份有限公司
> 设备类型：DVR / NVR / IPC / 可视对讲终端

---

## 第1章：协议总览表

### 1.1 协议一览表

| 协议名称 | 全称 | 开源 | OSI分层 | 默认端口 | 作用 | 代码位置 |
|---------|------|------|---------|---------|------|---------|
| **Hikvision SDK** | 海康私有网络SDK协议 | 否 | 应用层 | 8000 | 设备与客户端之间的核心控制/预览/回放协议 | `dvrNet.c`, `dvrNetParam.*` |
| **RTSP** | Real Time Streaming Protocol (RFC 2326) | 是(IETF) | 应用层 | 554 | 视频流媒体控制协议，用于实时预览和回放 | `rtsp/` |
| **RTP** | Real-time Transport Protocol (RFC 3550) | 是(IETF) | 传输层(应用下) | 动态 | 音视频数据传输 | `rtsp/`, `srtp/` |
| **RTCP** | Real-Time Control Protocol (RFC 3550) | 是(IETF) | 传输层(应用下) | 动态 | RTP控制通道，传输QoS信息 | `rtsp/` |
| **SRTP** | Secure RTP (RFC 3711) | 是(IETF) | 传输层(应用下) | 动态 | RTP加密传输，保护媒体流 | `srtp/` |
| **ONVIF** | Open Network Video Interface Forum | 是(联盟) | 应用层 | 80/443 | 开放视频设备标准协议，设备互操作 | `ONVIF/` |
| **WS-Discovery** | Web Services Dynamic Discovery (WS-Discovery) | 是(WS-I) | 应用层 | 3702 UDP | ONVIF设备发现协议 | `ONVIF/wsdiscovery/` |
| **ISAPI** | ISAPI (海康私有) | 否 | 应用层 | 80 | 海康RESTful API，替代旧CGI | `ISAPI/` |
| **ISUP/EHOME** | iHoneyUp / EHOME (海康私有) | 否 | 应用层 | 动态 | 设备主动上行协议，向平台上报数据 | `ISUP/` |
| **SIP** | Session Initiation Protocol (RFC 3261) | 是(IETF) | 应用层 | 5060 | 可视对讲信令协议 | `sip/` |
| **HTTPS** | HTTP over TLS/SSL | 是(IETF) | 应用层 | 443 | 安全Web访问、云连接加密通道 | `https_client/` |
| **WebSocket** | WebSocket (W3C) | 是(W3C) | 应用层 | 443/80 | 浏览器与设备的双向实时通信 | `webSocket/` |
| **HTTP** | HyperText Transfer Protocol (RFC 7230) | 是(IETF) | 应用层 | 80 | Web管理界面、ISAPI传输层 | `web/`, `ISAPI/` |
| **FTP** | File Transfer Protocol (RFC 959) | 是(IETF) | 应用层 | 21 | 报警图片/录像上传 | `imageFtp.c` |
| **SMTP** | Simple Mail Transfer Protocol (RFC 5321) | 是(IETF) | 应用层 | 25/465 | 邮件报警通知发送 | `chgsmtp.c` |
| **UPnP** | Universal Plug and Play (UPnP) | 是 | 应用层 | 1900 UDP | 路由器端口自动映射 | `upnp_portmap.c` |
| **SADP** | Smart Address Discovery Protocol | 否(海康) | 应用层 | 动态 UDP | 海康设备局域网发现工具协议 | `sadp/` |
| **ZeroConf** | Zero Configuration Networking (RFC 3927) | 是(IETF) | 网络层 | 169.254.x.x | IPv4链路本地地址自动分配 | `zeroconfig/` |
| **PPP** | Point-to-Point Protocol (RFC 1661) | 是(IETF) | 数据链路层 | N/A | 拨号网络连接 | `ppp/` |
| **PreNetwork** | 海康预配置协议 | 否(海康) | 应用层 | 80 | WiFi配网、AP热点配置 | `PreNetwork/` |
| **NetQos** | 海康QoS协议 | 否(海康) | 网络层 | 动态 | 网络服务质量保障、带宽自适应 | `netQos/` |
| **HTTP Client** | HTTP/HTTPS Client | 是(通用) | 应用层 | 动态 | 通用HTTP客户端（curl） | `https_client/` |

### 1.2 协议分类

#### 按用途分类：

```
┌─────────────────────────────────────────────────────────────────┐
│                        netConn 协议分类                          │
├──────────────┬──────────────────────────────────────────────────┤
│  视频流传输   │  RTP/RTCP, SRTP, RTSP Server                     │
├──────────────┼──────────────────────────────────────────────────┤
│  控制信令     │  SDK私有协议, ISAPI, ONVIF, SIP, ISUP/EHOME     │
├──────────────┼──────────────────────────────────────────────────┤
│  设备发现     │  SADP, WS-Discovery, ZeroConf, UPnP             │
├──────────────┼──────────────────────────────────────────────────┤
│  云连接       │  萤石Ezviz私有协议 (HTTPS + 私有信令)             │
├──────────────┼──────────────────────────────────────────────────┤
│  Web访问      │  HTTP, HTTPS, WebSocket, AppWeb                 │
├──────────────┼──────────────────────────────────────────────────┤
│  配置管理     │  PreNetwork (WiFi配网), PPP (拨号)              │
├──────────────┼──────────────────────────────────────────────────┤
│  辅助服务     │  FTP, SMTP, NetQos, 心跳检测                     │
├──────────────┼──────────────────────────────────────────────────┤
│  安全         │  TLS/SSL (OpenSSL), SRTP, SHA1/MD5/UUID         │
└──────────────┴──────────────────────────────────────────────────┘
```

### 1.3 开源协议说明

| 开源属性 | 协议 | 说明 |
|---------|------|------|
| **开源(IETF标准)** | RTSP, RTP, RTCP, SRTP, ONVIF, SIP, HTTP, HTTPS, FTP, SMTP, UPnP, WS-Discovery, ZeroConf, PPP | 基于开放标准实现 |
| **开源(其他)** | WebSocket (W3C) | Web标准协议 |
| **闭源(厂商私有)** | Hikvision SDK, ISAPI, ISUP/EHOME, SADP, PreNetwork, NetQos, 萤石Ezviz协议 | 海康或萤石专有协议 |

---

## 第2章：核心架构与入口

### 2.1 整体架构

netConn 是整个设备的**网络通信中枢**，采用"主服务器 + 每连接工作线程"模型：

```
                    ┌─────────────────────────────────────┐
                    │         dvrNetServer()               │
                    │    (netSvrTaskId 线程)               │
                    │                                      │
                    │  TCP Listen 8000                     │
                    │  accept() → 每连接 spawn 线程         │
                    └──────┬──────────────────────────────┘
                           │
              ┌────────────┼────────────────┐
              ▼            ▼                ▼
    ┌────────────────┐ ┌──────────┐ ┌──────────────┐
    │ processClient  │ │process   │ │  process     │
    │  Request #1    │ │Request #2│ │  Request #N  │
    │                │ │          │ │              │
    │  SDK命令分发    │ │ SDK命令  │ │ SDK命令分发   │
    │  switch(netCmd)│ │ 分发     │ │  switch(netCmd)│
    └────┬───────────┘ └────┬─────┘ └──────┬───────┘
         │                  │               │
         ▼                  ▼               ▼
    ┌─────────────────────────────────────────────┐
    │           协议处理层                          │
    │  netClientLogin / netClientPreview /        │
    │  netClientFindFile / netClientSoftUpgrade /  │
    │  sdkIsapiProc / dvrNetVoiceTalk / ...       │
    └─────────────────────────────────────────────┘
```

### 2.2 核心文件：dvrNet.c

**文件角色**：SDK TCP 服务器主入口，约 3000+ 行代码，是整个 netConn 模块的"心脏"。

**核心流程**：

1. **`dvrnet_server_module_startup()`** — 设备启动时创建 `netSvrTaskId` 线程
2. **`dvrNetServer()`** — 主循环：
   - 创建 TCP Socket（端口 8000，可配置）
   - `accept()` 接受客户端连接
   - 限制最大连接数 `MAX_SDK_LINK`
   - 每接受一个连接，`pthreadSpawn()` 创建 `processClientRequest` 线程
3. **`processClientRequest()`** — 每个客户端连接的处理器：
   - 读取 4 字节长度头 → 读取完整命令
   - 解析 `NETCMD_HEADER`（V4 IPv4 头）或 `NETCMD_HEADER_V6`（V6 IPv6 头）
   - 校验和验证（`checkCheckSum`）
   - 设备激活状态检查
   - 按 `netCmd` 字段分发到对应处理函数

### 2.3 SDK 命令分发机制

```
processClientRequest() 中的核心分发逻辑：

读取命令 → 校验和验证 → 设备激活检查 → 权限验证 → switch(netCmd)
                                                                        │
    ┌───────────────────────────────────────────────────────────────────┤
    ▼                                                                   ▼
NETCMD_LOGIN                                    其他所有命令
(用户登录)                                      switch-case 表：
NETCMD_RELOGIN                                  - NETCMD_LOGIN/RELOGIN/LOGOUT
NETCMD_LOGOUT                                   - NETCMD_GET/SET_*CFG (配置类)
NETCMD_GET_CAPABILITES                          - NETCMD_GET/SET_USERCFG (用户管理)
NETCMD_USEREXCHANGE                             - NETCMD_PREVIEW (视频预览)
DVR_GET/SET_SDK_ISAPI                           - NETCMD_FIND_FILE / FIND_FILE_V30
DVR_JSON_CONFIG                                 - NETCMD_SOFT_UPGRADE_V30
NETCMD_GET/SET_FACE_CFG                         - NETCMD_GET/SET_ALARM_* (报警)
NETCMD_GET/SET_FACE_PIC                         - NETCMD_GET/SET_* (各类配置)
NETCMD_GET/SET_FINGERPRINT_CFG                  - NETCMD_GET/SET_SERIAL (串口)
NETCMD_GET_SECURITYCFG                          - NETCMD_GET/SET_VOICE_TALK (对讲)
NETCMD_DVR_ACTIVATE                             - 等等...
```

### 2.4 连接模型

```c
// 全局连接计数
int gNetConns;      // 普通网络连接数
int gSdkConns;      // SDK 连接数（受 MAX_SDK_LINK 限制）

// 每个连接通过 NET_CONNECT 结构体管理
// 连接类型枚举 NETSDK_CONNECT_TYPE_E:
//   NETSDK_TYPE_NORMAL     — 普通 TCP 连接
//   NETSDK_TYPE_OVER_TLS   — TLS 加密连接
//   NETSDK_TYPE_INVALID    — 无效连接
```

### 2.5 安全机制

- **校验和验证**：`checkCheckSum()` 使用用户随机数 + 挑战字符串 + 客户端MAC地址进行完整性校验
- **设备激活检查**：未激活设备仅允许 `NETCMD_DVR_ACTIVATE` 命令
- **权限验证**：`netClientMsgTransform()` 在命令处理前进行权限检查
- **登录状态管理**：通过 `userID` 关联用户权限

---

## 第3章：SDK 私有协议详解

### 3.1 协议格式

SDK 协议基于 TCP，采用"长度头 + 命令体"的二进制帧格式：

```
┌──────────────────────────────────────────────────────────────┐
│  IPv4 命令帧 (NETCMD_HEADER)                                  │
├──────────────────────────────────────────────────────────────┤
│  4字节: length    (网络字节序，包含length自身)                 │
│  1字节: version   (协议版本)                                  │
│  1字节: ipVer     (1=IPv6, 0=IPv4)                           │
│  1字节: headType  (头部类型)                                  │
│  1字节: reserved  (保留)                                      │
│  4字节: netCmd    (命令码，网络字节序)                         │
│  4字节: userID    (登录会话ID，0=未登录)                       │
│  4字节: sequence  (序列号，用于请求-响应匹配)                   │
│  4字节: checkSum  (校验和)                                    │
│  4字节: randomData1                           │
│  4字节: randomData2                           │
│ 16字节: challengeString                       │
│  8字节: clientMac     (客户端MAC地址)                          │
│  4字节: clientType    (客户端类型)                             │
│  4字节: sdkVersion    (SDK版本号)                              │
│  4字节: sdkSubVersion                         │
│  4字节: netCmdEx    (扩展命令码)                               │
│  4字节: length64    (64位长度扩展)                             │
│  4字节: userIDHigh    (64位userID高32位)                       │
│     ...                                                           │
│  N字节: 命令参数 (按netCmd类型变化)                              │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  IPv6 命令帧 (NETCMD_HEADER_V6)                               │
├──────────────────────────────────────────────────────────────┤
│  4字节: length    (网络字节序)                                │
│  1字节: ipVer     (固定为1，表示IPv6)                         │
│  1字节: headType  (头部类型)                                  │
│  1字节: reserved  (保留)                                      │
│  1字节: headSize    (头部大小)                                │
│  1字节: reserved2                                 │
│  4字节: netCmd    (命令码，网络字节序)                         │
│  4字节: userID    (登录会话ID)                                │
│  4字节: sequence  (序列号)                                    │
│  4字节: checkSum  (校验和)                                    │
│ 16字节: srcIp       (源IP地址，IPv6 128位)                    │
│ 16字节: dstIp       (目的IP地址，IPv6 128位)                  │
│  4字节: srcPort     (源端口)                                  │
│  4字节: dstPort     (目的端口)                                │
│  4字节: randomData1                           │
│  4字节: randomData2                           │
│ 16字节: challengeString                       │
│  8字节: clientMac     (客户端MAC地址)                          │
│  4字节: clientType    (客户端类型)                             │
│  4字节: sdkVersion    (SDK版本号)                              │
│  4字节: netCmdEx    (扩展命令码)                               │
│  4字节: length64    (64位长度扩展)                             │
│  4字节: userIDHigh    (64位userID高32位)                       │
│     ...                                                           │
│  N字节: 命令参数                                              │
└──────────────────────────────────────────────────────────────┘
```

### 3.2 命令分类

根据 `dvrNet.c` 中的 switch-case 分发表，SDK 命令可分为以下类别：

#### 3.2.1 会话管理命令

| 命令码 | 功能 | 处理函数 |
|--------|------|---------|
| `NETCMD_LOGIN` | 用户登录（挑战-响应认证） | `netClientLogin()` |
| `NETCMD_RELOGIN` | 重新登录（续会话） | `netClientReLogin()` |
| `NETCMD_LOGOUT` | 注销 | `netClientLogout()` |
| `NETCMD_USEREXCHANGE` | 用户信息交换 | `netClientUserExchange()` |

#### 3.2.2 设备能力查询

| 命令码 | 功能 | 处理函数 |
|--------|------|---------|
| `NETCMD_GET_CAPABILITES` | 获取设备能力（编码、通道数等） | `netClientGetCapability()` |

#### 3.2.3 视频预览命令

| 命令码 | 功能 | 处理函数 |
|--------|------|---------|
| `NETCMD_PREVIEW` | 实时预览 | `netClientPreview()` |

预览模式枚举：
- `TCPMODE` — TCP 传输（可靠但开销大）
- `UDPMODE` — UDP 传输（低延迟）
- `MCASTMODE` — 组播传输（一对多）
- `RTPMODE` — RTP 传输（标准流媒体）

#### 3.2.4 录像回放命令

| 命令码 | 功能 | 处理函数 |
|--------|------|---------|
| `NETCMD_FIND_FILE` | 查找录像文件 | `netClientFindFile()` |
| `NETCMD_FIND_FILE_V30` | 查找录像文件 V30 | `netClientFindFileV30()` |
| `NETCMD_PLAYBACK_EXCHANGE` | 回放数据交换 | `read_playback_exchange_data()` |

#### 3.2.5 固件升级命令

| 命令码 | 功能 | 处理函数 |
|--------|------|---------|
| `NETCMD_SOFT_UPGRADE_V30` | 固件升级 V30 | `netClientSoftUpgradeV30()` |

升级分块大小：`UPGRADE_ONCE_LEN = 32KB`
升级心跳：每 100ms 发送一次升级状态

#### 3.2.6 配置管理命令（GET/SET 模式）

配置类命令覆盖以下领域：

```
设备配置：     NETCMD_GET/SET_DEVICECFG / DEVICECFG_V40
网络配置：     NETCMD_GET/SET_NETCFG / NETCFG_V30
网络应用配置：  NETCMD_GET/SET_NETAPPCFG (DNS/NTP/DDNS/EMAIL)
NTP配置：      NETCMD_GET/SET_NTPCFG
DDNS配置：     NETCMD_GET/SET_DDNSCFG_EX / DDNSCFG_V30
压缩配置：     NETCMD_GET/SET_COMPRESSCFG / COMPRESSCFG_EX / COMPRESSCFG_EX_V30
用户配置：     NETCMD_GET/SET_USERCFG / USERCFG_V30 / USERCFG_EX
OSD配置：      NETCMD_GET/SET_OSDCFG / OSDCFG_V30
视频配置：     NETCMD_GET/SET_PICCFG / PICCFG_V30 / PICCFG_EX / VIDEOEFFECT
视频效果：     NETCMD_GET/SET_VIDEOEFFECT
报警配置：     NETCMD_GET/SET_ALARM_IN/OUTCFG / ALARM_IN/OUTCFG_V30
异常配置：     NETCMD_GET/SET_EXCEPTIONCFG / EXCEPTIONCFG_V30
音频配置：     NETCMD_GET/SET_VOICE_TALK_PARAM / AUDIO_VOLUME / AUDIO_INPUT_TYPE
串口配置：     NETCMD_GET/SET_RS232CFG / RS232CFG_V30 / RS485CFG
PTZ控制：      NETCMD_GET/SET_PTZPOINT
FTP配置：      NETCMD_GET/SET_FTPCFG / FTPCFG_V40
Upnp配置：     NETCMD_GET/SET_UPNPCFG
SNMP配置：     NETCMD_GET/SET_SNMPCFG_V30
QoS配置：      NETCMD_GET/SET_QOSCFG
IP过滤：       NETCMD_GET/SET_IPADDR_FILTERCFG
安全配置：     NETCMD_GET/SET_SECURITYCFG
用户解锁：     NETCMD_SET_USER_UNLOCK / GET_LOCKED_INFO
设备激活：     NETCMD_DVR_ACTIVATE
```

#### 3.2.7 人脸/指纹/卡片命令

```
人脸：    NETCMD_GET/SET/DEL_FACE_CFG, NETCMD_CAPTURE_FACE_INFO
指纹：    NETCMD_GET/SET/DEL_FINGERPRINT_CFG[_V50], NETCMD_CAPTURE_FINGERPRINT_INFO
卡片：    NETCMD_GET/SET_CARD_CFG[_V50], NETCMD_GET/SET_CARD_READER_CFG_V50
```

#### 3.2.8 ISAPI 透传命令

```
DVR_GET_SDK_ISAPI    — GET 请求透传
DVR_SET_SDK_ISAPI    — SET 请求透传
DVR_POST_SDK_ISAPI   — POST 请求透传
DVR_DEL_SDK_ISAPI    — DELETE 请求透传
DVR_JSON_CONFIG      — JSON 配置透传
```

#### 3.2.9 对讲与语音

```
NETCMD_VOICE_TALK          — 语音对讲
NETCMD_VOICE_TALK_V30      — 语音对讲 V30
dvrNetVoiceTalk.c          — 对讲模块实现
```

### 3.3 响应格式

所有 SDK 响应遵循统一格式：

```
┌──────────────────────────────────────────────┐
│  4字节: retVal  (返回码，网络字节序)          │
│  N字节: 响应数据 (按命令类型变化)              │
└──────────────────────────────────────────────┘

常见返回码：
  NETRET_QUALIFIED        — 成功
  NETRET_NO_USERID        — 无效用户ID
  SDK_SRV_ERROR_*         — 服务器错误码
  SDK_SRV_ERROR_DEVICE_NOT_ACTIVATED — 设备未激活
```

### 3.4 登录认证流程

```
客户端                          设备
  │                             │
  │  NETCMD_LOGIN               │
  │  (username + password)      │
  │────────────────────────────▶│
  │                             │  1. 生成 randomData1/2
  │                             │  2. 生成 challengeString
  │                             │  3. 验证用户名密码
  │                             │  4. 计算 checkSum
  │                             │     = Hash(randomData1 || randomData2 ||
  │                             │       challengeString || password || clientMAC)
  │  NETRET_HEADER              │
  │  (retVal + userID +         │
  │   randomData1/2 +            │
  │   challengeString)           │
  │◀────────────────────────────│
  │                             │
  │  NETCMD_RELOGIN             │  后续所有命令使用 userID
  │  (userID + checkSum)        │     进行认证
  │────────────────────────────▶│
  │                             │
  │  NETRET_HEADER              │
  │  (retVal + userID)          │
  │◀────────────────────────────│
  │                             │
  │  后续命令 (带 userID)        │
  │────────────────────────────▶│
```

---

## 第4章：RTSP 协议

### 4.1 RTSP 在系统中的角色

RTSP（Real Time Streaming Protocol）在此项目中具有**双重角色**：

1. **RTSP Server**（`rtsp_server.c`）：设备作为流媒体服务器，向客户端推送视频流
2. **RTSP Client**（`rtsp_client.c`）：设备作为 RTSP 客户端，从其他设备拉取视频流

### 4.2 RTSP Server 模式

**文件**：`rtsp/rtsp_server.c`

**核心功能**：
- 监听 RTSP 端口（默认 554，可配置）
- 支持 `DESCRIBE`、`SETUP`、`PLAY`、`PAUSE`、`TEARDOWN` 标准方法
- 为每个通道（channel）维护客户端状态 `Mpeg4ClientInfo`
- 最大客户端数：`MAX_RTSP_CLIENT * MAX_CHANNUM`

**客户端状态结构**：
```c
struct Mpeg4ClientInfo {
    // 客户端连接信息
    // 视频流通道索引
    // RTP/RTSP 会话状态
    // 客户端IP和端口
};
```

**支持的流类型**：
- `RtspMpeg4ClientInfo` — MPEG4 视频流
- `RtspAudioClientInfo` — 音频流

**配置获取**：
```c
GetDevconfig(RTSPDEVCONFIG *pRtspConfig)
// 获取：匿名登录设置、用户名、密码、IP地址、
//       组播IP、MAC地址
```

### 4.3 RTSP Client 模式

**文件**：`rtsp/rtsp_client.c`, `rtsp/rtspc_app.h`

**核心功能**：
- 设备作为 RTSP 客户端连接外部流媒体服务器
- DSP 解码支持（本地硬件解码远程流）
- 子码流捕获支持（`g_sub_capture_fd`）

**关键接口**：
```c
set_rtspc_handle(int)     // 设置 RTSP 客户端句柄
get_rtspc_handle(void)    // 获取 RTSP 客户端句柄
start_dsp_decode(void)    // 启动 DSP 解码
stop_dsp_decode(void)     // 停止 DSP 解码
```

### 4.4 RTP/RTCP 传输

**RTP**（Real-time Transport Protocol）负责实际的音视频数据传输：

- 视频编码：MJPEG、MPEG4、H.264、H.265（根据设备能力）
- 音频编码：G.711A、G.726、AAC（通过 `audio_enctype` 配置）
- 传输方式：TCP 内带 / UDP 外带 / RTP over RTSP

**RTCP**（Real-Time Control Protocol）提供控制通道：
- 传输发送者报告（SR）
- 传输接收者报告（RR）
- 传输同步源信息（SSRC）

### 4.5 SRTP 加密

**文件**：`srtp/srtp_api.c`

**用途**：对 RTP 媒体流进行加密，保护视频/音频传输安全。

**实现**：
- 基于 `libsrtp2` 库
- 使用 `OpenSSL` 的 `RAND_bytes` 生成密钥
- 支持 4 个独立会话：
  - `srtp_send_audio_session` — 发送音频
  - `srtp_send_video_session` — 发送视频
  - `srtp_recv_audio_session` — 接收音频
  - `srtp_recv_video_session` — 接收视频

**密钥管理**：
```c
// SRTP 密钥生成（Base64 编码）
srtp_generate_key_b64(char *outValue, int outLen)
// 密钥长度：SRTP_AES_ICM_128_KEY_LEN_WSALT (16字节密钥 + 14字节盐)

// 会话初始化状态检查
srtp_is_session_init_success(UINT8 type)
```

### 4.6 RTSP 与 SDK 预览的关系

```
客户端请求预览
       │
       ▼
┌─────────────────────┐
│  dvrNet.c (SDK TCP) │ ← 主入口
│  netClientPreview() │
└─────────┬───────────┘
          │
    ┌─────┴─────┐
    ▼           ▼
SDK预览        RTSP预览
(TCP/UDP/      (RTSP协议
 RTP/MCAST)    +RTP传输)
    │           │
    ▼           ▼
┌─────────────────────┐
│   视频编码层         │   ← DSP 硬件编码
│   H.264/H.265/MJPEG │
└─────────┬───────────┘
          │
    ┌─────┴─────┐
    ▼           ▼
RTP打包       SRTP加密(可选)
    │           │
    ▼           ▼
  网络发送     加密网络发送
```

---

## 第5章：ONVIF 协议

### 5.1 ONVIF 概述

ONVIF（Open Network Video Interface Forum）是开放的视频接口标准，本实现基于 **ONVIF 2.1** 版本。

**编译开关**：`CONFIG_ONVIF_SUPPORT` → 定义 `DONVIF` 和 `DONVIF_VER_2DOT1`

### 5.2 ONVIF 模块结构

```
ONVIF/
├── onvifcommon/          # 公共模块：SOAP 处理、XML 解析
├── device/               # Device Service：设备管理
├── deviceio/             # Device IO：I/O 控制
├── media/                # Media Service：视频流配置
├── imaging/              # Imaging Service：图像参数
├── event/                # Event Service：事件订阅/通知
├── analytics/            # Analytics Service：分析服务
├── recording/            # Recording Service：录制管理
├── recordsearch/         # RecordSearch Service：录像搜索
├── replay/               # Replay Service：回放控制
└── wsdiscovery/          # WS-Discovery：设备发现
```

### 5.3 WS-Discovery 设备发现

WS-Discovery 是基于 UDP 的多播协议，用于局域网内自动发现 ONVIF 设备：

```
客户端                          设备
  │  M-SEARCH * HTTP/MC        │  (UDP 3702 多播)
  │────────────────────────────▶│
  │                            │
  │  Probe Match               │  设备响应
  │  (XML 响应)                │  (UDP 单播)
  │◀───────────────────────────│
```

### 5.4 核心 ONVIF 服务

#### 5.4.1 Device Service (`device/`)
- `GetCapabilities` — 获取设备能力
- `GetDeviceInformation` — 获取设备信息（厂商、型号、序列号等）
- `SystemTime` — 系统时间设置
- `Reboot` — 重启设备
- `Upgrade` — 固件升级

#### 5.4.2 Media Service (`media/`)
- `GetProfiles` — 获取视频配置档案
- `GetStreamUri` — 获取 RTP 流 URI（RTSP URI）
- `SetSynchronizationPattern` — 流同步

#### 5.4.3 Event Service (`event/`)
- `Subscribe` — 订阅事件
- `Unsubscribe` — 取消订阅
- `PullMessage` — 拉取事件消息
- 支持报警输入、移动检测等事件

#### 5.4.4 Imaging Service (`imaging/`)
- `GetVideoSourceMode` — 获取视频源模式
- `SetVideoSourceMode` — 设置视频源模式
- 图像参数调整（亮度、对比度、饱和度等）

### 5.5 ONVIF 数据格式

ONVIF 使用 **SOAP over HTTP**，消息格式为 XML：

```
POST /onvif/device HTTP/1.1
Host: 192.168.1.168:80
Content-Type: application/xml
SOAPAction: "http://www.onvif.org/ver10/device/wsdl/GetDeviceInformation"

<?xml version="1.0" encoding="utf-8"?>
<SOAP-ENV:Envelope xmlns:SOAP-ENV="..." xmlns:tds="...">
  <SOAP-ENV:Body>
    <tds:GetDeviceInformation/>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
```

### 5.6 ONVIF 与 SDK 的关系

ONVIF 协议与 SDK 私有协议**并行独立**：
- ONVIF 通过 HTTP 服务器（AppWeb）提供 REST/SOAP 接口
- SDK 通过 TCP 8000 端口提供私有二进制协议
- 两者共享底层视频编码和存储资源

---

## 第6章：ISAPI 协议

### 6.1 ISAPI 概述

ISAPI（Internet Service API）是海康威视的 RESTful API 协议，用于替代旧的 CGI 接口。基于 HTTP + XML/JSON 格式。

**入口文件**：`ISAPI/isapi_entry.c`

### 6.2 URL 路由与分发

```
HTTP 请求
    │
    ▼
┌─────────────────────────┐
│  isapi_entry.c          │
│  preNetwork_entry()     │  ← URL 路由入口
│                         │
│  /ISAPI/Security/*      │ → isapi_security_do.h
│  /ISAPI/Stream/*        │ → stream 模块
│  /ISAPI/System/*        │ → system 模块
│  /ISAPI/PTZ/*           │ → PTZ 控制
│  /ISAPI/Event/*         │ → 事件管理
│  /ISAPI/Video/*         │ → 视频配置
│  /ISAPI/Image/*         │ → 图像参数
│  /ISAPI/Intelligent/*   │ → 智能分析
│  /ISAPI/Finger/*        │ → 指纹管理
│  ...                    │
└─────────────────────────┘
```

### 6.3 权限验证机制

ISAPI 支持多种认证方式（`isapi_entry.c` 中实现）：

```c
enum CHECK_ID_ERR_NO {
    CHECK_BAD_AUTHOR     = -1,  // 认证未通过
    CHECK_SESSION_OK     = 0,   // Session 认证通过
    CHECK_TOKEN_OK       = 1,   // Token 认证通过
    CHECK_DIGEST_OK      = 2,   // 摘要认证通过
    CHECK_NO_NEED        = 3,   // 无需认证
};
```

**免认证 URL**（`isapi_is_need_authcheck_url`）：
- `/ISAPI/Security/challenge` — 获取认证挑战
- `/ISAPI/Security/sessionLogin` — Session 登录
- `/ISAPI/Security/userCheck` — 用户检查
- `/ISAPI/System/activate` — 设备激活
- `/ISAPI/System/DeviceLanguage` — 语言设置
- `/ISAPI/Security/questionConfiguration` — 安全问题
- `/ISAPI/Security/email/*` — 邮件配置
- `/ISAPI/SDK/language` — SDK 语言

### 6.4 ISAPI 模块分类

```
ISAPI/
├── isapi_entry.c          # 入口：URL 路由、认证
├── isapi_common.c         # 公共函数
├── isapi_xml.c            # XML 解析/生成
├── cJSON_tool.c           # JSON 解析/生成
├── hicore_protocol.c      # HiCore 协议
├── root/                  # 根节点管理
├── schema/                # Schema 验证
├── security/              # 安全模块
├── stream/                # 视频流管理
├── system/                # 系统管理
├── event/                 # 事件管理
├── video/                 # 视频配置
├── image/                 # 图像参数
├── PTZ/                   # PTZ 控制
├── intelligent/           # 智能分析
├── sipc/                  # SIP 对讲 ISAPI 封装
├── private_sip/           # 私有 SIP 协议
├── thermal/               # 热成像
├── vcs/                   # 视频对讲
├── videointercom/         # 视频对讲
├── network/               # 网络配置
├── serial/                # 串口管理
├── io/                    # I/O 控制
├── audio/                 # 音频配置
├── snapshot/              # 抓拍
├── publish/               # 发布管理
├── finger/                # 指纹管理
├── AccessControl/         # 门禁控制
├── securitycp/            # 安全密码
├── smart/                 # 智能功能
├── heop/                  # 海康扩展操作协议
└── docs/                  # ISAPI 文档
```

### 6.5 HiCore 协议

`hicore_protocol.c` 实现了海康 HiCore 内部通信协议，用于模块间消息传递。

### 6.6 ISAPI 与 SDK 的集成

通过 `sdk_isapi_proc.c` 实现 SDK 到 ISAPI 的透传：

```
SDK 客户端                    设备                    ISAPI 引擎
    │                           │                         │
    │  DVR_GET_SDK_ISAPI        │                         │
    │  (二进制封装)              │                         │
    │──────────────────────────▶│                         │
    │                           │  解析 HTTP 请求          │
    │                           │  匹配 URL 路由           │
    │                           │────────────────────────▶│
    │                           │                         │
    │                           │  XML/JSON 响应           │
    │                           │◀────────────────────────│
    │  二进制响应                │                         │
    │◀──────────────────────────│                         │
```

---

## 第7章：ISUP (EHOME) 协议

### 7.1 ISUP/EHOME 概述

ISUP（iHoneyUp），也称为 EHOME，是海康威视的**设备主动上行协议**。与 SDK 的"客户端主动连接"模式不同，EHOME 是**设备作为客户端主动连接到平台**。

**编译开关**：`CONFIG_EHOME_SUPPORT` → 定义 `DSUPPORT_EHOME`

### 7.2 架构特点

```
设备 (EHOME Client)          平台 (EHOME Server)
     │                              │
     │  TCP 主动连接                  │  监听端口
     │─────────────────────────────▶│
     │                              │
     │  注册/心跳                     │
     │  (Protocol Buffers)           │
     │◀─────────────────────────────│
     │                              │
     │  上行数据流                    │
     │  (视频/报警/对讲)              │
     │─────────────────────────────▶│
     │                              │
     │  下行控制命令                  │
     │◀─────────────────────────────│
```

### 7.3 模块结构

```
ISUP/
├── Include/
│   ├── ExportClassHeader/     # 导出类定义
│   ├── google/protobuf/       # Protocol Buffers 运行时
│   └── PublicUtils/           # 公共工具
└── HCEComMain/
    ├── src/
    │   ├── Alarm/             # 报警上行
    │   ├── Protocol/          # 协议层实现
    │   ├── ReadFile/          # 文件读取（录像回放）
    │   ├── Stream/            # 视频流传输
    │   ├── Talkback/          # 对讲功能
    │   ├── Utils/             # 工具函数
    │   └── mbedtls/           # TLS 加密
    └── ...
```

### 7.4 Protocol Buffers 序列化

ISUP 使用 Protocol Buffers 进行二进制序列化，相比 XML/JSON 具有：
- 更小的消息体积
- 更快的编解码速度
- 强类型定义

### 7.5 核心功能模块

| 模块 | 功能 | 说明 |
|------|------|------|
| **Protocol** | 协议控制 | 连接管理、心跳、注册 |
| **Stream** | 视频流上行 | 实时视频推送到平台 |
| **Alarm** | 报警上报 | 报警事件主动推送 |
| **Talkback** | 对讲上行 | 音频流上行 |
| **ReadFile** | 文件读取 | 录像回放支持 |

---

## 第8章：SIP 协议

### 8.1 SIP 概述

SIP（Session Initiation Protocol，RFC 3261）用于可视对讲场景，支持标准 SIP 和萤石私有 SIP 两种模式。

### 8.2 SIP 架构

```
sip/
├── ysipc/                    # 萤石私有 SIP 实现
│   ├── ysipClientInterface.cpp  # SIP 客户端接口
│   ├── ysipXmlProc.c          # XML 消息处理
│   ├── ysipMediaStream.c      # 媒体流管理
│   ├── ysipNoticeCallLogic.c  # 通知/呼叫逻辑
│   ├── ysipConfig.c           # SIP 配置
│   └── sipc_reg_manager.cpp   # 注册管理器
└── exosipcApp/               # ExoSIP 应用层
    ├── sipc_message_proc.c    # 消息处理
    ├── sipc_media_trans.c     # 媒体传输
    └── sipc_app_api.c         # 应用 API
```

### 8.3 注册管理

```c
// SIP 注册目标
#define REG_TO_SIP_SERVER 1    // 注册到标准 SIP 服务器
#define REG_TO_MAIN_DOOR  2    // 注册到主机门铃

// 注册流程
ysipClientInterface.cpp
    ├── sipc_reg_manager.cpp    // 注册状态管理
    ├── ysipXmlProc.c           // SIP 消息 XML 解析
    └── sipc_app_api.c          // 应用层接口
```

### 8.4 呼叫控制

```
呼叫方                          被叫方（设备）
  │                                │
  │  INVITE (SIP)                   │
  │  (携带 SDP 媒体协商)             │
  │───────────────────────────────▶│
  │                                │  振铃
  │  180 Ringing                   │
  │◀───────────────────────────────│
  │                                │  用户接听
  │  200 OK                        │
  │◀───────────────────────────────│
  │  ACK                           │
  │───────────────────────────────▶│
  │                                │
  │  RTP 媒体流 ←────────────→ RTP │
  │                                │
```

### 8.5 媒体传输

- 音频编码：G.711A、G.726、AAC
- 视频编码：H.264、MJPEG
- 传输：RTP over UDP
- 加密：可选 SRTP

### 8.6 设备管理（devmgmt）

`devmgmt` 模块负责可视对讲场景下的设备管理，包括：
- 房间设备配置同步
- NTP 配置同步
- 批量升级
- 设备激活流程
- IOT 信息同步

通过 shell 命令 `DEVMGMT` 进行调试：
```
DEVMGMT:10.7.114.3:1      # 室内机配置测试
Synchronize:enable         # 启用配置同步
prtRegist                  # 打印注册用户信息
```

---

## 第9章：云连接协议（萤石 Ezviz）

### 9.1 萤石云架构

萤石（Ezviz）是海康旗下子品牌，提供云平台服务。设备通过萤石私有协议接入云平台，实现外网远程访问。

**编译开关**：`CONFIG_SUPPORT_EZVIZ_V20` → 定义 `DSUPPORT_EZVIZ_V20`

### 9.2 模块结构

```
ezviz/
├── base_module/           # 基础模块：登录、注册、连接管理
│   ├── ezviz_app_base.cpp
│   └── ezviz_app_base.h
├── preview_module/        # 实时预览模块
│   ├── ezviz_app_preview.cpp
│   ├── ezviz_preview_function.cpp
│   └── ezviz_send_stream.cpp
├── playback_module/       # 录像回放模块
│   ├── ezviz_app_playback.cpp
│   ├── ezviz_app_playback_stream.cpp
│   └── sipc_rtp.c
├── talk_module/           # 语音对讲模块
│   ├── ezviz_app_talk.cpp
│   └── ezviz_app_audio_talk.cpp
├── protocol_module/       # 协议扩展
│   ├── ezviz_sdk_ext_function_alarm.cpp
│   ├── ezviz_sdk_ext_function_upgrade.cpp
│   └── ezviz_sdk_ext_function_disk.cpp
├── alarm_module/          # 报警模块
├── control_module/        # 控制模块（PTZ等）
├── sub_module/            # 子设备管理
├── thirdparty_module/     # 第三方平台对接
├── special_module/        # 特殊功能
├── openssl_module/        # OpenSSL 加密传输
│   └── openssl_socket.cpp
├── transProtocol/         # 协议转换层
│   └── ezviz_trans_parse.cpp
├── common/                # 公共函数
├── tool/                  # 工具函数
└── kernel_module/         # 内核级功能
```

### 9.3 连接流程

```
设备                          萤石云平台
  │                              │
  │  TCP 连接                      │
  │  (test.ys7.com /              │
  │   dev.ys7.com)                │
  │─────────────────────────────▶│
  │                              │
  │  设备注册                      │
  │  (SN + 密钥)                   │
  │─────────────────────────────▶│
  │                              │
  │  注册成功 + Token              │
  │◀─────────────────────────────│
  │                              │
  │  心跳保活                      │
  │◀─────────────────────────────│
  │                              │
  │  远程预览请求                  │
  │◀─────────────────────────────│
  │                              │
  │  RTP 视频流（加密）             │
  │─────────────────────────────▶│
  │                              │
```

### 9.4 服务器地址

支持多环境服务器：
- `test.ys7.com` — 测试环境（默认）
- `test2.ys7.com` — 测试环境2
- `dev.ys7.com` — 开发环境
- `t2dev.tus.ezvizlife.com` — 开发环境
- `dev.ezvizlife.com` — 正式环境
- `t2dev.ezvizlife.com` — 正式环境

### 9.5 QR 码绑定

```
用户手机                    设备                    萤石云
   │                         │                       │
   │  扫描二维码               │                       │
   │◀─────────────────        │                       │
   │                         │                       │
   │  绑定请求                 │                       │
   │────────────────────────────────────────────────▶│
   │                         │                       │
   │  绑定成功                 │                       │
   │◀────────────────────────────────────────────────│
   │                         │                       │
   │  通知设备绑定              │                       │
   │                         │◀──────────────────────│
   │                         │                       │
```

### 9.6 Shell 调试命令

通过 `netConn_shell.c` 注册的 `EZVIZ` 命令：
```
getEzvizStat           # 获取萤石注册状态
setEzvizserver:[addr]  # 设置萤石服务器
setEzvizlog:[level]    # 设置日志级别
showEzvizstream        # 显示当前预览/对讲/回放链路状态
showEzvizserver        # 显示当前连接的萤石服务器
ezviz_upgrade_query    # 查询升级包
ezviz_upgrade_start    # 开始升级
creatEzvizQR           # 创建萤石二维码
```

---

## 第10章：设备发现与零配置

### 10.1 SADP（Smart Address Discovery Protocol）

**文件**：`sadp/sadp_server.c`, `sadp/sadp_client.c`

SADP 是海康威视的设备发现协议，用于局域网内自动发现海康设备并获取其 IP 配置信息。

**工作流程**：
```
客户端（SADP工具）              设备
     │                            │
     │  UDP 多播 M-SEARCH         │
     │  (发现请求)                 │
     │───────────────────────────▶│
     │                            │
     │  UDP 单播响应               │
     │  (设备IP/MAC/型号)          │
     │◀───────────────────────────│
     │                            │
     │  修改设备IP                 │
     │  (配置更新)                 │
     │───────────────────────────▶│
     │                            │
     │  确认响应                   │
     │◀───────────────────────────│
```

### 10.2 ZeroConf（IPv4 Link-Local Address）

**文件**：`zeroconfig/llad.c`

基于 RFC 3927 的 IPv4 链路本地地址自动分配协议。当设备无法通过 DHCP 获取 IP 时，自动分配 `169.254.x.x` 段地址。

**实现来源**：代码源自 Busybox 的 zcip applet，经过简化优化。

**核心状态机**：
```
初始化
  │
  ▼
随机选择 169.254.x.x 地址
  │
  ▼
ARP 探测（Probing）
  │  → 地址冲突？→ 重新选择
  │  ↓ 无冲突
  │
  ▼
地址分配（Assigned）
  │
  ▼
定期 ARP 检测（Renewing）
  │  → 地址冲突？→ 回到随机选择
  │  ↓ 无冲突
  │  ...（循环）
```

### 10.3 PreNetwork（预网络配置）

**文件**：`PreNetwork/preNetwork_entry.c`

PreNetwork 是海康的预配置协议，主要用于 WiFi 配网和 AP 热点配置场景。

**核心功能**：
- 基于 HTTP + JSON 的 RESTful 接口
- URL 路由：`/PreNetwork/*`
- 支持 JSON 和 XML 格式（当前仅支持 JSON）

**配网流程**：
```
手机/PC                    设备（AP热点）
    │                            │
    │  连接设备AP热点              │
    │  (192.168.x.x)             │
    │───────────────────────────▶│
    │                            │
    │  HTTP GET /PreNetwork/     │
    │  WiFi 列表查询              │
    │───────────────────────────▶│
    │                            │
    │  JSON WiFi 列表             │
    │◀───────────────────────────│
    │                            │
    │  HTTP POST                 │
    │  WiFi SSID + 密码           │
    │───────────────────────────▶│
    │                            │
    │  连接成功确认                 │
    │◀───────────────────────────│
    │                            │
    │  切换到有线网络              │
    │  (eth0 获取 DHCP IP)        │
    │────────────────────────────│
```

### 10.4 PPP（拨号连接）

**目录**：`ppp/`

支持通过 PPP 协议进行拨号网络连接，适用于无以太网的特殊场景。

### 10.5 UPnP 端口映射

**文件**：`upnp_portmap.c`

UPnP 允许设备在路由器上自动创建端口映射，实现外网访问：

```
外网客户端              路由器              设备(8000端口)
    │                      │                      │
    │  外网:8000 → 内网:8000                        │
    │  (UPnP 映射)        │                      │
    │────────────────────▶│──────────────────────▶│
```

## 第11章：Web 与 WebSocket

### 11.1 AppWeb 嵌入式 Web 服务器

**文件**：`web/appweb/appweb.c`

AppWeb 是 Embedthis 公司开发的轻量级嵌入式 Web 服务器，适用于资源受限的嵌入式设备。本设备使用 AppWeb 提供 HTTP/HTTPS 服务，作为设备 Web 管理界面的后端。

**核心职责**：
- 提供 HTTP/HTTPS 服务（端口 80/443）
- 处理 Web 管理界面的所有请求
- 与 ISAPI 模块协同，将 API 请求路由到相应处理器
- 支持静态页面托管和动态 CGI 处理

**编译开关**：`CONFIG_APPWEB_SUPPORT` → 定义 `APPWEB`、`APPWEB_PLAYBACK`

### 11.2 WebServiceMng（Web 服务管理）

**文件**：`web/webmanage/webServiceMng/`

WebServiceMng 是 Web 服务管理层，负责将 HTTP 请求分发到不同的协议处理器：

```
webServiceMng/
├── isapihandler.c      # ISAPI 请求处理器
├── onvifhandler.c      # ONVIF 请求处理器
├── prenetworkhandler.c # PreNetwork 请求处理器
├── rtsphttphandler.c   # RTSP over HTTP 处理器
└── websconfig.c        # Web 配置管理
```

**请求分发流程**：
```
HTTP 请求
  │
  ▼
AppWeb (appweb.c)
  │
  ▼
WebServiceMng (isapihandler/onvifhandler/...)
  │
  ├── ISAPI 路径 (/ISAPI/*) → isapihandler.c → ISAPI 子模块
  ├── ONVIF 路径 (/onvif/*) → onvifhandler.c → ONVIF 服务
  ├── PreNetwork 路径 (/PreNetwork/*) → prenetworkhandler.c → PreNetwork 模块
  └── RTSP HTTP 路径 → rtsphttphandler.c → RTSP 模块
```

### 11.3 WebSocket 双向通信

**目录**：`webSocket/`

WebSocket 提供全双工通信通道，用于实时数据推送和远程控制场景。

**模块结构**：
```
webSocket/
├── common/
│   └── src/               # 公共 WebSocket 库
│       ├── websockets.c   # WebSocket 协议实现
│       └── websocket_service.c  # WebSocket 服务管理
├── ws_preview.c           # WebSocket 实时预览
├── ws_playback.c          # WebSocket 录像回放
└── ws_webssh.c            # WebSocket SSH 终端
```

**核心实现**：基于 libwebsockets 库。

#### 11.3.1 WebSocket 实时预览（ws_preview）

**文件**：`webSocket/ws_preview.c`

通过 WebSocket 将实时视频流推送到浏览器，支持最多 6 个并发会话（`SESSION_NO = 6`）。

**工作流程**：
```
浏览器                    设备                      编码器
  │                         │                         │
  │  WebSocket 连接建立       │                         │
  │  (握手)                 │                         │
  │────────────────────────▶│                         │
  │                         │                         │
  │  请求 SDP 信息           │                         │
  │◀────────────────────────│                         │
  │                         │  获取媒体 SDP            │
  │                         │  (ws_get_media_sdp_info)│
  │                         │                         │
  │  SDP 响应               │                         │
  │◀────────────────────────│                         │
  │                         │                         │
  │  接收 RTP 媒体流         │  从 RTSP/RTP 获取流      │
  │  (WebSocket 二进制帧)    │────────────────────────▶│
  │◀────────────────────────│                         │
```

#### 11.3.2 WebSocket 录像回放（ws_playback）

**文件**：`webSocket/ws_playback.c`

支持通过 WebSocket 在浏览器中回放录像文件，包含文件分段读取、流控、时间戳规范化等功能。

**关键结构**：
- `WS_SEND_FILE_PARAM`：文件发送参数，包含文件描述符、偏移量、分段索引等
- `WS_SEND_FILE_MISC`：发送缓冲区管理，包含流控时间计算
- 支持时移回放（seek 操作）

#### 11.3.3 WebSocket SSH（ws_webssh）

**文件**：`webSocket/ws_webssh.c`

通过 WebSocket 提供 Web SSH 终端功能，允许用户在浏览器中直接访问设备命令行。

**核心特性**：
- 使用 `forkpty` 创建伪终端
- 日志文件下载（Flash 存储 2M 缓冲 / 40M 文件，RAM 存储 1M 缓冲 / 2M 文件）
- 日志路径：`/home/config/webssh/`（Flash）或 `/home/app/webssh/`（RAM）
- 消息类型：`WS_WEBSSH_MSG_DATA (0x16)`、`WS_WEBSSH_MSG_CMD (0x17)`

### 11.4 WebSIO（串行 IO 过 Web）

**文件**：`web/websio/webs_io.c`

WebSIO 通过 Web 接口暴露设备串行端口，允许远程客户端通过串行协议控制设备。

**应用场景**：
- 远程串口设备管理（如云台控制）
- 工业场景中的串行通信过网桥

## 第12章：辅助与安全协议

### 12.1 UPnP 端口映射

**文件**：`upnp_portmap.c`

UPnP（Universal Plug and Play）允许设备在路由器上自动创建端口映射，实现外网访问内网设备。

**映射端口**：
- `g_mapped_ctrl_port`：SDK 控制端口
- `g_mapped_http_port`：HTTP 端口
- `g_mapped_rtsp_port`：RTSP 端口
- `g_mapped_rtsptcp_port`：RTSP TCP 端口

**核心参数**：
- `DEFAULT_NOTIFY_EXPIRE_TIME`：60*60 秒（默认通知过期时间）
- `MAX_RETRY_PORT_CNT`：16（最大重试端口数）
- `CHECK_UPNP_SEARCH_INTERVAL`：120 秒（检测 UPnP 变更间隔）

**设备描述 XML**：
```xml
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <deviceType>urn:schemas-upnp-org:device:EmbeddedNetDevice:1</deviceType>
    <friendlyName>%s</friendlyName>
    <manufacturer>%s</manufacturer>
  </device>
</root>
```

**工作流程**：
```
设备                    路由器（UPnP Control Point）          外网
  │                          │                                │
  │  IGD 发现请求（UDP 多播）  │                                │
  │─────────────────────────▶│                                │
  │                          │  响应（描述 URL）               │
  │◀─────────────────────────│                                │
  │                          │                                │
  │  AddPortMapping          │                                │
  │  (SDK 8000 → 内网:8000)   │                                │
  │─────────────────────────▶│───────────────────────────────▶│
  │                          │                                │
  │  获取外部 IP              │                                │
  │◀─────────────────────────│                                │
```

### 12.2 FTP 图片上传（imageFtp）

**文件**：`imageFtp.c`

实现报警触发的图片抓拍并上传到 FTP 服务器，支持多种触发源。

**触发类型**：
| 触发类型 | 常量 | 说明 |
|---------|------|------|
| 定时抓拍 | TIMING | 按设定间隔自动抓拍 |
| 移动侦测 | MOTDEC | 视频分析移动侦测触发 |
| 报警输入 | ALARMIN | 物理报警输入触发 |
| 无线报警 | WIRELESSALARM | 无线报警设备触发 |
| PIR 报警 | PIRALARM | 红外人体感应触发 |
| 紧急求助 | CALLHELPALARM | 紧急求助按钮触发 |

**核心配置**：
- 默认用户名：`imguser`
- 默认密码：`imguser`
- 默认端口：21
- 重试次数：`RE_SEND_PIC_TIMES = 5`
- 触发间隔：`DEFAULT_ALARM_INTERVAL = 10*1000`（10秒）
- 消息队列：`IMAGE_MSGQ_NUMS = 32`

**工作流程**：
```
报警事件              imageFtp              FTP 服务器
  │                      │                      │
  │  触发（侦测/输入等）    │                      │
  │─────────────────────▶│                      │
  │                      │  抓拍图片             │
  │                      │  (从编码器获取)         │
  │                      │                      │
  │                      │  FTP 连接             │
  │                      │  (PORT 模式)          │
  │                      │─────────────────────▶│
  │                      │  STOR 文件名          │
  │                      │─────────────────────▶│
  │                      │  上传成功确认          │
  │                      │◀─────────────────────│
  │                      │                      │
  │                      │  断开连接             │
  │                      │─────────────────────▶│
```

### 12.3 SMTP 邮件通知（chgsmtp）

**文件**：`chgsmtp.c`

设备通过 SMTP 协议向指定邮箱发送报警/异常通知邮件。

**编译开关**：`CONFIG_EMAIL_SUPPORT` → 定义 `NET_EMAIL`

**邮件结构**：
- 发件人：`pEmailserverParam->account` / `sender.address`
- 收件人：最多 3 个（`RECEIVER_NUM = 3`）
- 字符集：`gb2312`
- 优先级：`"2"`（高优先级）
- 附件：支持多张 JPEG 图片（`MAX_JPEG_ATTACHMENT`）

**邮件内容**：
- 主题：异常类型（`LENGTH_EMAIL_HEADLINE`）
- 正文：事件信息（`eventinfo`）

### 12.4 NetQos 网络服务质量

**目录**：`netQos/`
**核心文件**：`netQos/netQosApi.c`

NetQos（NPQ - Network Quality）模块负责网络带宽管理和 QoS 保障，通过动态调整码率、丢包重传策略等机制，确保在网络拥塞情况下的基本通信能力。

**核心数据结构**：
- `NPQ_BUNDLE_INFO_T gNpqBundle[NPQ_STREAM_MAX_NUM]`：每路流的带宽包信息
- `NPQ_STRATEGY_INFO_T gNpqStrategy`：QoS 策略配置
- `NPQ_INFO_ST g_stNpqInfo`：全局 QoS 状态（视频/音频 socket、流 ID 等）

**消息队列**：使用 POSIX mq（`mqd_t gNpqMqId`）进行模块间通信。

**回调机制**：
- `NPQSenderDataCbFun`：发送数据回调
- `NPQRecvierDataCbFun`：接收数据回调

**功能**：
- 带宽自适应调整
- 视频/音频流独立 QoS 管理
- 丢包率监测与重传
- 码率动态限制

### 12.5 网络抓包（capturePacket）

**目录**：`capturePacket/`
**核心文件**：`capturePacket/capture.cpp`

基于 libpcap 的网络抓包模块，支持将设备网络接口上的数据包保存到 pcap 格式文件，用于协议分析和故障排查。

**核心结构**：
```c
typedef struct packet_user_arg {
    pcap_dumper_t *dumper;    // pcap 转储文件句柄
    int id;                   // 抓包 ID
    int cur_size;             // 当前文件大小
    int max_size;             // 最大文件大小
    int max_time;             // 最大抓包时间
    int cap_time;             // 已抓包时间
    void* pWeb;               // Web 会话指针
    int save_mode;            // 保存模式
} packet_user_arg;
```

**功能**：
- 通过 ISAPI 接口控制抓包（`isapi_network_capture_send_data` / `isapi_network_capture_close_con`）
- 支持按大小和时间限制文件大小
- 输出标准 pcap 格式，可用 Wireshark 打开分析
- 线程安全：使用 `g_pcap_mutex` 保护

### 12.6 心跳机制（nicBrokenHeart）

**目录**：`nicBrokenHeart/`
**核心文件**：`nicBrokenHeart/netBrokenHeartServer.c`

心跳模块用于检测网络连接的健康状态，通过定期发送心跳包保持连接活跃，并在连接断开时触发重连。

**核心文件**：
- `netBrokenHeartServer.c`：心跳服务端
- `netBrokenHeartServer.h`：心跳接口定义

**功能**：
- 定期向已连接客户端发送心跳探测
- 超时检测：客户端无响应则断开连接
- 触发重连或告警

### 12.7 安全用户管理（securityUser）

**文件**：`securityUser.c`

安全用户模块负责设备访问的身份验证和权限管理，支持 SDK 协议、RTSP、ISAPI 三种访问通道的统一认证。

**核心功能**：
- **Digest 认证 Realm 生成**：`security_auth_realm_create()`
  - Realm = `DS-` + SHA256(MAC + ProdNo) 前8位
  - 确保 RTSP、ISAPI 使用相同 Realm
- **用户锁管理**：`security_user_lock_init()`
  - 本地锁（`SECURITY_USER_LOCLA_LOCK_NUM`）
  - 远程锁（`SECURITY_USER_REMOTE_LOCK_NUM`）
- **安全事件**：通过 `aip_security_event.h` 上报安全事件
- **设备锁定**：通过 `aip_security_lock_manage.h` 管理设备锁定状态

**依赖模块**：
- `securityMng/`：安全管理子模块（用户工具、事件、锁定管理）
- OpenSSL MD5：密码哈希计算
- 数据库：`dbshell.h` / `dbutil.h` 持久化用户信息

## 第13章：协议交互分层控制流图

### 13.1 SDK TCP 连接完整控制流

这是设备作为 SDK TCP 服务器（端口 8000）接收客户端请求的完整流程：

```
SDK 客户端                          设备 (dvrNet.c)                        协议处理层
  │                                     │                                    │
  │  TCP 连接 (端口 8000)                │                                    │
  │────────────────────────────────────▶│                                    │
  │                                     │  accept() → 创建连接               │
  │                                     │                                    │
  │  发送: [4字节长度][NETCMD_HEADER][消息体]                                 │
  │────────────────────────────────────▶│                                    │
  │                                     │  读取 4 字节长度                   │
  │                                     │  ntohl(cmdLength)                │
  │                                     │                                    │
  │                                     │  读取消息体                       │
  │                                     │  memcpy(&netCmdHeader, ...)      │
  │                                     │                                    │
  │                                     │  ┌── 校验和验证 ──────────┐       │
  │                                     │  │ checkCheckSum()        │       │
  │                                     │  │ 失败 → sendNetRetval() │       │
  │                                     │  └────────────────────────┘       │
  │                                     │                                    │
  │                                     │  ┌── 设备激活检查 ────────┐       │
  │                                     │  │ if_get_device_status() │       │
  │                                     │  │ 未激活 → 仅允许激活    │       │
  │                                     │  └────────────────────────┘       │
  │                                     │                                    │
  │                                     │  ┌── 权限验证 ────────────┐       │
  │                                     │  │ (除登录/激活/ISAPI透传) │       │
  │                                     │  │ netClientMsgTransform()│       │
  │                                     │  │ 失败 → sendNetRetval() │       │
  │                                     │  └────────────────────────┘       │
  │                                     │                                    │
  │                                     │  switch(netCmdHeader.netCmd)      │
  │                                     │  ┌─────────────────────────┐     │
  │                                     │  │ NETCMD_LOGIN      → netClientLogin()      │
  │                                     │  │ NETCMD_LOGOUT     → netClientLogout()     │
  │                                     │  │ NETCMD_GET_CAPABILITES → netClientGetCapability() │
  │                                     │  │ NETCMD_USEREXCHANGE → netClientUserExchange() │
  │                                     │  │ DVR_GET_SDK_ISAPI   → sdkIsapiProc()      │
  │                                     │  │ DVR_JSON_CONFIG     → sdkIsapiLongConProc() │
  │                                     │  │ NETCMD_PREVIEW_START  → netClientPreviewStart() │
  │                                     │  │ NETCMD_PLAYBACK_START → netClientPlaybackStart() │
  │                                     │  │ NETCMD_UPLOAD_ALARMIN → netClientAlarmUpload() │
  │                                     │  │ NETCMD_UPGRADE_START  → netClientUpgrade()  │
  │                                     │  │ ... (100+ 命令) ...                       │
  │                                     │  └─────────────────────────┘       │
  │                                     │                                    │
  │                                     │  构建响应                         │
  │                                     │  [4字节长度][NETCMD_HEADER][响应体]                                 │
  │  ←─────────────────────────────────│────────────────────────────────────│
  │  接收响应                           │                                    │
  │                                     │  关闭连接 (或保持长连接)             │
  │  TCP 断开                           │                                    │
  │────────────────────────────────────▶│                                    │
```

### 13.2 ISAPI HTTP 请求控制流

```
HTTP 客户端                        AppWeb                      ISAPI              子模块
  │                                    │                          │                  │
  │  HTTP GET/PUT/POST /ISAPI/xxx     │                          │                  │
  │──────────────────────────────────▶│                          │                  │
  │                                    │                          │                  │
  │                                    │  解析 URL               │                  │
  │                                    │  /ISAPI/Security/AccessControl/AccessAuthority/1/1/1   │
  │                                    │                          │                  │
  │                                    │  提取路径               │                  │
  │                                    │  → "/Security/..."      │                  │
  │                                    │                          │                  │
  │                                    │  查找 URL 路由表         │                  │
  │                                    │  prenetwork_getRequestFunc()│                 │
  │                                    │                          │                  │
  │                                    │  ┌── 权限验证 ──────┐    │                  │
  │                                    │  │ checkAuthType() │    │                  │
  │                                    │  │ IP白名单         │    │                  │
  │                                    │  │ 用户认证         │    │                  │
  │                                    │  │ (Basic/Digest)   │    │                  │
  │                                    │  └─────────────────┘    │                  │
  │                                    │                          │                  │
  │                                    │  调用对应处理函数         │                  │
  │                                    │  → Security_handler()  │                  │
  │                                    │                          │                  │
  │                                    │                          │  执行业务逻辑      │
  │                                    │                          │  → 数据库/配置    │
  │                                    │                          │                  │
  │                                    │                          │  返回结果         │
  │                                    │◀─────────────────────────│                  │
  │  HTTP 响应 (JSON/XML)              │                          │                  │
  │◀──────────────────────────────────│                          │                  │
```

### 13.3 RTSP 实时预览控制流（设备作为服务器）

```
客户端                           RTSP Server              RTSP Client         RTP/RTCP
  │                                  │                        │                  │
  │  OPTIONS                         │                        │                  │
  │─────────────────────────────────▶│                        │                  │
  │  200 OK                          │                        │                  │
  │◀─────────────────────────────────│                        │                  │
  │                                  │                        │                  │
  │  DESCRIBE → SDP 请求              │                        │                  │
  │─────────────────────────────────▶│                        │                  │
  │                                  │                        │                  │
  │                                  │  获取编码器 SDP         │                  │
  │                                  │  (从预览组件)           │                  │
  │                                  │                        │                  │
  │  200 OK → SDP 响应               │                        │                  │
  │◀─────────────────────────────────│                        │                  │
  │                                  │                        │                  │
  │  SETUP → Transport: RTP/AVP     │                        │                  │
  │  UDP/TCP;unicast;...            │                        │                  │
  │─────────────────────────────────▶│                        │                  │
  │                                  │                        │                  │
  │  200 OK → Transport 响应         │                        │                  │
  │◀─────────────────────────────────│                        │                  │
  │                                  │                        │                  │
  │  PLAY → RTSP URL                │                        │                  │
  │─────────────────────────────────▶│                        │                  │
  │                                  │  启动视频流             │                  │
  │                                  │                        │                  │
  │  200 OK                          │                        │                  │
  │◀─────────────────────────────────│                        │                  │
  │                                  │                        │                  │
  │  ←──── RTP 数据包 (H.264/AAC) ───│───────────────────────▶│                  │
  │  ←──── RTCP RR (接收报告) ───────│◀───────────────────────│                  │
  │                                  │                        │                  │
  │  TEARDOWN                        │                        │                  │
  │─────────────────────────────────▶│                        │                  │
  │  200 OK                          │                        │                  │
  │◀─────────────────────────────────│                        │                  │
```

### 13.4 云连接（萤石）数据流

```
设备                              萤石云平台                     互联网
  │                                    │                           │
  │  OpenSSL TLS 连接建立               │                           │
  │───────────────────────────────────▶│                           │
  │  (加密通道)                          │                           │
  │                                    │                           │
  │  登录注册消息                       │                           │
  │───────────────────────────────────▶│                           │
  │                                    │                           │
  │  注册成功                           │                           │
  │◀───────────────────────────────────│                           │
  │                                    │                           │
  │  手机 App 请求预览                   │                           │
  │                                    │◀─────────────────────────▶│
  │                                    │                           │
  │                                    │  查询设备在线状态           │
  │                                    │──────────────────────────▶│
  │                                    │                           │
  │                                    │  设备在线 → 转发预览请求    │
  │                                    │◀─────────────────────────│
  │                                    │                           │
  │  ←─── 预览连接请求 ─────────────────│                           │
  │───────────────────────────────────▶│                           │
  │                                    │                           │
  │  获取 SDP 信息                      │                           │
  │  (从 RTSP 模块)                     │                           │
  │                                    │                           │
  │  SDP 响应                           │                           │
  │───────────────────────────────────▶│                           │
  │                                    │                           │
  │  RTP 媒体流 (加密)                   │                           │
  │───────────────────────────────────▶│─────────────────────────▶│
  │                                    │  (转发到手机 App)          │
  │                                    │                           │
  │  手机 App ←── 媒体流 ──────────────│◀─────────────────────────│
  │                                    │                           │
  │  PTZ 控制 (手机 → 设备)              │                           │
  │◀───────────────────────────────────│◀─────────────────────────│
```

### 13.5 报警上报数据流（ISUP/EHOME）

```
报警源                    报警管理                ISUP 模块              平台服务器
  │                          │                      │                      │
  │  物理输入触发              │                      │                      │
  │─────────────────────────▶│                      │                      │
  │                          │                      │                      │
  │                          │  生成报警事件          │                      │
  │                          │                      │                      │
  │                          │  编码 (Protobuf)     │                      │
  │                          │─────────────────────▶│                      │
  │                          │                      │  TCP 连接建立         │
  │                          │                      │─────────────────────▶│
  │                          │                      │  主动上报              │
  │                          │                      │─────────────────────▶│
  │                          │                      │                      │
  │                          │                      │  确认响应            │
  │                          │                      │◀─────────────────────│
  │                          │◀─────────────────────│                      │
  │                          │  报警完成             │                      │
```

### 13.6 WebSocket 实时预览控制流

```
浏览器                    WebSocket 服务              RTSP Client         RTP
  │                            │                        │                  │
  │  WebSocket 连接             │                        │                  │
  │  (浏览器 → 设备:8000/443)   │                        │                  │
  │───────────────────────────▶│                        │                  │
  │                            │                        │                  │
  │  请求预览 SDP               │                        │                  │
  │───────────────────────────▶│                        │                  │
  │                            │  创建 RTSP Client      │                  │
  │                            │  (rtsp_client.c)      │                  │
  │                            │                        │                  │
  │  SDP 响应                   │                        │                  │
  │◀───────────────────────────│                        │                  │
  │                            │                        │                  │
  │  接收 RTP 帧               │  从 RTSP 获取 RTP      │                  │
  │  (WebSocket 二进制帧)       │  转换为 WS 帧          │                  │
  │◀───────────────────────────│◀──────────────────────│◀─────────────────│
  │                            │                        │                  │
  │  发送停止命令               │                        │                  │
  │───────────────────────────▶│                        │                  │
  │                            │  关闭 RTSP 连接         │                  │
  │                            │───────────────────────▶│                  │
  │                            │                        │                  │
  │  WebSocket 关闭             │                        │                  │
  │───────────────────────────▶│                        │                  │
```

## 第14章：数据流图

### 14.1 视频预览数据流

设备作为 RTSP 服务器推送实时视频流的完整数据路径：

```
摄像头传感器              编码器                    RTSP Server           网络
  │                         │                         │                   │
  │  模拟信号               │                         │                   │
  │────────────────────────▶│                         │                   │
  │                         │  H.264/MJPEG 编码        │                   │
  │                         │  (DSP/硬件编码器)         │                   │
  │                         │                         │                   │
  │                         │  获取视频帧              │                   │
  │                         │  (preview_component)    │                   │
  │                         │                         │                   │
  │                         │  封装 RTP 包             │                   │
  │                         │  (PS 封装)               │                   │
  │                         │                         │                   │
  │                         │  RTSP SETUP             │                   │
  │                         │  分配 RTP 端口           │                   │
  │                         │                         │                   │
  │                         │  RTSP PLAY              │                   │
  │                         │                         │                   │
  │                         │  RTP over UDP/TCP       │                   │
  │                         │  (每包 ~1400 字节)       │──────────────────▶│
  │                         │                         │                   │
  │                         │  RTCP RR (接收报告)     │                   │
  │                         │◀───────────────────────│                   │
  │                         │                         │                   │
  │  可选: SRTP 加密         │  AES-128 加密 RTP 包    │                   │
  │  (srtp_api.c)           │────────────────────────▶│                   │
```

**关键组件**：
- `rtsp_server.c`：RTSP 服务端，每通道独立客户端跟踪
- `preview_component.h`：预览组件接口，获取视频帧
- `srtp_api.c`：SRTP 加密，OpenSSL 密钥生成
- RTP 包大小：~1400 字节（MTU 优化）

### 14.2 配置管理数据流

SDK 协议配置 GET/SET 的数据路径：

```
SDK 客户端                    dvrNet.c               配置管理层            数据库
  │                              │                      │                   │
  │  SET: DVR_SET_NET_ETHER      │                      │                   │
  │  (设置网络配置)               │                      │                   │
  │─────────────────────────────▶│                      │                   │
  │                              │                      │                   │
  │                              │  解析 NETCMD_HEADER  │                   │
  │                              │  校验和验证          │                   │
  │                              │  权限验证            │                   │
  │                              │                      │                   │
  │                              │  netClientSetNet()  │                   │
  │                              │                      │                   │
  │                              │                      │  uni_set_net_cfg()│
  │                              │                      │──────────────────▶│
  │                              │                      │                   │
  │                              │                      │  保存配置          │
  │                              │                      │  save_net_config()│
  │                              │                      │──────────────────▶│
  │                              │                      │                   │
  │                              │                      │  通知相关模块      │
  │                              │                      │  (SIP重注册等)    │
  │                              │                      │──────────────┐   │
  │                              │                      │              │   │
  │  响应 (OK/ERROR)             │◀─────────────────────│──────────────┘   │
  │◀─────────────────────────────│                      │                   │
```

**配置管理关键文件**：
- `dvrNet.c`：SDK 协议入口，命令分发
- `dvrNetParam.h`：200+ 配置命令参数声明
- `paramLib.h`：参数库接口
- `database/dbshell.h`：数据库操作接口
- `Davinci/netconfig.h`：网络配置接口

### 14.3 报警上报数据流

```
报警源              报警控制               图片处理               上传模块           外部系统
  │                   │                      │                      │                    │
  │  移动侦测触发      │                      │                      │                    │
  │──────────────────▶│                      │                      │                    │
  │                   │  event_ctrl 生成事件  │                      │                    │
  │                   │                      │                      │                    │
  │                   │  触发多路动作          │                      │                    │
  │                   │  (报警联动)            │                      │                    │
  │                   │  ├─ FTP 图片上传      │                      │                    │
  │                   │  ├─ SMTP 邮件         │                      │                    │
  │                   │  ├─ ISUP 平台上报     │                      │                    │
  │                   │  └─ 本地声音报警      │                      │                    │
  │                   │                      │                      │                    │
  │                   │                      │  抓拍图片             │                    │
  │                   │                      │  (从编码器)           │                    │
  │                   │                      │─────────────────────▶│                    │
  │                   │                      │                      │                    │
  │                   │                      │  FTP 上传             │                    │
  │                   │                      │                      │───────────────────▶│
  │                   │                      │                      │  (FTP Server)      │
  │                   │                      │                      │                    │
  │                   │                      │  SMTP 邮件            │                    │
  │                   │                      │                      │───────────────────▶│
  │                   │                      │                      │  (SMTP Server)     │
  │                   │                      │                      │                    │
  │                   │  Protobuf 编码        │                      │                    │
  │                   │─────────────────────▶│                      │                    │
  │                   │                      │  ISUP TCP 连接        │                    │
  │                   │                      │                      │───────────────────▶│
  │                   │                      │                      │  (平台服务器)      │
```

**报警联动路径**：
1. **FTP 路径**：`alarmCtrl.h` → `imageFtp.c` → `ftpLib.h` → FTP Server
2. **邮件路径**：`alarmCtrl.h` → `chgsmtp.c` → `smtp.h` → SMTP Server
3. **平台上报**：`alarmCtrl.h` → `ISUP/HCEComMain/src/Alarm` → TCP → 平台

### 14.4 云连接数据流

```
手机 App              萤石云               设备 (萤石模块)        本地编码器
  │                     │                      │                    │
  │  远程预览请求        │                      │                    │
  │────────────────────▶│                      │                    │
  │                     │  查询设备状态          │                    │
  │                     │  (通过互联网)          │                    │
  │                     │                      │                    │
  │                     │  转发预览请求          │                    │
  │                     │  (OpenSSL 加密通道)    │                    │
  │                     │─────────────────────▶│                    │
  │                     │                      │                    │
  │                     │                      │  获取 SDP          │                    │
  │                     │                      │  (rtsp_client)    │                    │
  │                     │                      │                    │
  │                     │                      │  RTP 视频流        │                    │
  │                     │                      │  (从编码器)        │                    │
  │                     │                      │───────────────────▶│
  │                     │                      │                    │
  │                     │                      │  加密 RTP          │                    │
  │                     │                      │  (SRTP/OpenSSL)   │                    │
  │                     │                      │───────────────────▶│
  │                     │                      │                    │
  │                     │  加密媒体流转发        │                    │
  │                     │  (萤石云 → 手机)      │                    │
  │                     │◀─────────────────────│                    │
  │◀────────────────────│                      │                    │
  │  播放视频            │                      │                    │
  │                     │                      │                    │
  │  PTZ 控制命令        │                      │                    │
  │────────────────────▶│                      │                    │
  │                     │  PTZ 控制              │                    │
  │                     │  (OpenSSL 加密)        │                    │
  │                     │─────────────────────▶│                    │
  │                     │                      │  PTZ 指令           │                    │
  │                     │                      │───────────────────▶│
  │                     │                      │                    │  云台转动
  │                     │                      │                    │
  │  远程录像回放请求    │                      │                    │
  │────────────────────▶│                      │                    │
  │                     │  回放请求              │                    │
  │                     │  (OpenSSL 加密)        │                    │
  │                     │─────────────────────▶│                    │
  │                     │                      │  读取录像文件       │                    │
  │                     │                      │  (search_manager)  │                    │
  │                     │                      │                    │
  │                     │                      │  RTP 回放流        │                    │
  │                     │                      │  (从录像文件)      │                    │
  │                     │                      │───────────────────▶│
  │                     │                      │                    │
  │                     │  加密回放流转发        │                    │
  │                     │  (萤石云 → 手机)      │                    │
  │                     │◀─────────────────────│                    │
  │◀────────────────────│                      │                    │
```

**云连接关键模块**：
- `ezviz/preview_module/`：云预览模块
- `ezviz/playback_module/`：云回放模块
- `ezviz/talk_module/`：云对讲模块
- `ezviz/openssl_module/`：加密传输模块
- `ezviz/transProtocol/`：协议转换层

## 第15章：构建系统与配置

### 15.1 CMakeLists.txt 编译配置

**文件**：`app/src/netConn/CMakeLists.txt`

CMakeLists.txt 是 netConn 模块的构建入口，负责定义编译宏、头文件路径和源文件收集。

**构建流程**：
```
CMakeLists.txt
  ├── 平台判断 (PLAT_FORM)
  │     ├── r2 → -DR2_64
  │     ├── r3 → -DR3_32
  │     └── others → 默认宏
  │
  ├── 功能宏定义 (add_definitions)
  │     ├── CONFIG_APPWEB_SUPPORT → APPWEB, APPWEB_PLAYBACK
  │     ├── CONFIG_ONVIF_SUPPORT → ONVIF, ONVIF_VER_2DOT1
  │     ├── CONFIG_RTSP_SUPPORT → RTSP
  │     ├── CONFIG_WIFI_SUPPORT → SUPPORT_WIFI
  │     ├── CONFIG_SUPPORT_GUI → SUPPORT_GUI
  │     ├── CONFIG_RTCP_SUPPORT → RTP_RTCP
  │     ├── CONFIG_EMAIL_SUPPORT → NET_EMAIL
  │     ├── CONFIG_SUPPORT_FACE → SUPPORT_FACE
  │     ├── CONFIG_SUPPORT_FP → SUPPORT_FP
  │     ├── CONFIG_SUPPORT_EZVIZ_V20 → SUPPORT_EZVIZ_V20
  │     ├── CONFIG_SUPPORT_WIRESHARK → SUPPORT_WIRESHARK
  │     ├── CONFIG_EHOME_SUPPORT → SUPPORT_EHOME
  │     └── CONFIG_SUPPORT_RECORD → SUPPORT_RECORD
  │
  ├── 头文件路径 (INCLUDE_DIRECTORIES)
  │     ├── modules/basefun/parse
  │     ├── modules/encrypt/src
  │     ├── netConn/include
  │     ├── netConn/ISAPI
  │     ├── netConn/ONVIF
  │     ├── netConn/ISUP/... (条件)
  │     ├── netConn/web/websio
  │     ├── netConn/web/webmanage
  │     ├── netConn/web/appweb
  │     └── netConn/webSocket + webSocket/common/include
  │
  └── 源文件收集 (AUX_SOURCE_DIRECTORY)
        ├── ISAPI/* (25+ 子目录)
        ├── ISUP/* (条件)
        ├── ONVIF/* (10+ 子目录)
        ├── web/* (appmanage, websio, appweb)
        ├── ezviz/* (15+ 子目录)
        ├── rtsp/*
        ├── sip/* (ysipc, exosipcApp)
        ├── webSocket/*
        ├── netQos/*
        ├── srtp/*
        ├── sadp/*
        ├── zeroconfig/*
        ├── PreNetwork/*
        ├── ppp/*
        ├── Davinci/*
        ├── devmgmt/*
        ├── capturePacket/*
        ├── nicBrokenHeart/*
        ├── sdk_client/*
        ├── cstor/*
        └── netConn/* (根目录)
```

### 15.2 条件编译宏速查表

| CMake 配置 | 定义宏 | 影响的协议/模块 |
|-----------|--------|----------------|
| `CONFIG_APPWEB_SUPPORT=y` | `APPWEB`, `APPWEB_PLAYBACK` | AppWeb Web 服务器 |
| `CONFIG_ONVIF_SUPPORT=y` | `ONVIF`, `ONVIF_VER_2DOT1` | ONVIF 2.1 全套 |
| `CONFIG_RTSP_SUPPORT=y` | `RTSP` | RTSP Server/Client |
| `CONFIG_RTSP_SUPPORT=y` | `RTP_RTCP` | RTP/RTCP 传输 |
| `CONFIG_WIFI_SUPPORT=y` | `SUPPORT_WIFI` | WiFi 配网/管理 |
| `CONFIG_EMAIL_SUPPORT=y` | `NET_EMAIL` | SMTP 邮件 |
| `CONFIG_SUPPORT_FACE=y` | `SUPPORT_FACE` | 人脸功能 |
| `CONFIG_SUPPORT_FP=y` | `SUPPORT_FP` | 指纹功能 |
| `CONFIG_SUPPORT_EZVIZ_V20=y` | `SUPPORT_EZVIZ_V20` | 萤石云连接 |
| `CONFIG_SUPPORT_WIRESHARK=y` | `SUPPORT_WIRESHARK` | 网络抓包 |
| `CONFIG_EHOME_SUPPORT=y` | `SUPPORT_EHOME` | ISUP/EHOME 上行 |
| `CONFIG_SUPPORT_GUI=y` | `SUPPORT_GUI` | GUI 支持 |
| `CONFIG_NEUTRAL=y` | `NEUTRAL` | 中性版本 |

### 15.3 平台适配

**R2 平台 (64-bit)**：
```cmake
IF ("${PLAT_FORM}" STREQUAL "r2")
    add_definitions(-DR2_64)
```
- 64 位 ARM 架构
- 定义宏：`R2_64`

**R3 平台 (32-bit)**：
```cmake
IF ("${PLAT_FORM}" STREQUAL "r3")
    add_definitions(-DR3_32)
```
- 32 位 ARM 架构
- 定义宏：`R3_32`

**公共宏**（所有平台）：
- `WEBS`：启用 Web 服务
- `UEMF`：统一事件框架
- `LINUX`：Linux 平台
- `USE_ASP`：ASP 支持
- `NEW_NET_APP`：新版网络应用
- `DAVINCI`：达芬奇平台
- `DEV`：开发模式
- `OPENSSL`：OpenSSL 加密
- `NO_BALLOC`：禁用 BALLOC
- `INCLUDE_NFS`：包含 NFS 支持
- `MEGA_IPC`：大内存 IPC
- `FOR9000`：9000 系列设备
- `USEIMG`：图片功能（FTP 上传等）

### 15.4 端口汇总

| 端口 | 协议 | 模块 | 条件编译 |
|------|------|------|---------|
| 8000 | TCP | SDK 私有协议 | 始终启用 |
| 80 | HTTP | AppWeb/ISAPI | 始终启用 |
| 443 | HTTPS | AppWeb + SSL | OPENSSL |
| 554 | TCP/UDP | RTSP Server | RTSP |
| 8000+ | TCP/UDP | RTP/RTCP | RTP_RTCP |
| 8000 | UDP | ONVIF WS-Discovery | ONVIF |
| 8000 | UDP | SADP | 始终启用 |
| 1900 | UDP | UPnP | UPNP |
| 21 | TCP | FTP | USEIMG |
| 25/465/587 | TCP | SMTP | NET_EMAIL |
| 5060 | UDP | SIP | SUPPORT_EHOME |
| 169.254.x.x | - | ZeroConf | 始终启用 |
