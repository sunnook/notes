# hicore 代码架构深度分析

> 项目: hikcore (门口机/可视对讲主控程序)
> 版本: V3.14.0
> 平台: F1Plus / F2pro / A2S / AI2
> 语言: C, 构建: CMake

---

## 1. 项目入口与启动流程

### 1.1 入口函数: main()

**文件**: `app/src/mainCtrl/main.c`

```
main()
├── 1. PID文件检查 (防重复运行)
├── 2. base_log_init()           → 初始化基础日志系统
├── 3. signal_process()          → 注册信号处理器 (SIGPIPE/SIGTTIN/SIGTTOU)
├── 4. redirect_standard_input() → stdin重定向到 /dev/null
├── 5. aip_base()                → 平台基础初始化 (见1.2)
├── 6. user_sysinit()            → 系统级初始化 (见1.3)
├── 7. usrAppEntry()             → 应用业务初始化 (见1.4)
└── 8. while(1) sleep(100000)    → 主线程保持存活
```

### 1.2 aip_base() — 平台基础初始化

**文件**: `app/src/mainCtrl/main.c`

调用 `aip_service_start()` 启动 AIP (Application Integration Platform) 平台服务，配置包括:
- 硬件看门狗使能
- 软件看门狗使能
- 安全用户锁使能
- 安全事件回调注册 (`aip_call_back`)
- 时间管理类型 (本地时间/UTC)

### 1.3 user_sysinit() — 系统级初始化

**文件**: `app/src/mainCtrl/main.c`

按顺序执行:
```
user_sysinit()
├── chdir("/home/app")                    → 切换工作目录
├── opdevsdk_hwif_basic_init()            → 硬件接口基础初始化
├── sysInit()                             → 系统初始化 (boot param, CPLD info)
├── openssl_init()                        → OpenSSL 加密库初始化
├── init_store_encrypt_key()              → 存储加密密钥初始化
├── init_net_encrypt_key()                → 网络加密密钥初始化
├── sysglob_sem_init()                    → 全局信号量初始化 (globalMSem, g_param_mutexsem, videoSignalSem)
├── generate_dev_capa()                   → 生成设备能力集
├── generate_default_capa()               → 生成默认能力集
├── getDeviceCfgParams()                  → 加载设备配置文件
├── 老化测试标志判断 (SW_POWER_ON_AUTO_AGING_FUNC)
├── init_user_info_database()             → 用户信息数据库初始化
├── db_event_init_database()              → 事件数据库初始化
├── patch_dev_capa_from_config()          → 从配置补丁设备能力
├── register_dataMng_shell()              → 注册数据管理shell命令
├── sys_generate_hard_info()              → 生成硬件信息 (序列号等)
├── hoi_close_key_lamp_flicker()          → 关闭按键灯闪烁
├── setVSParams()                         → 设置视频参数
├── create_passwd_file()                  → 创建密码文件
├── init_net_interface()                  → 初始化网络接口
├── time_init()                           → 时间初始化
├── dsp_init()                            → DSP初始化 (音频编解码等)
├── delUpgradeFile()                      → 删除OTA升级残留文件
└── heop_init()                           → Android开放平台初始化 (如支持)
```

### 1.4 usrAppEntry() — 应用业务初始化

**文件**: `app/src/mainCtrl/usrAppEntry.c`

这是最核心的初始化入口，按顺序启动所有业务模块:

```
usrAppEntry()
│
├── [1] IPC 通信框架
│   ├── opdevsdk_ipc_init()              → IPC 基础初始化
│   ├── opdevsdk_ipc_center_init()       → IPC 中心初始化
│   ├── opdevsdk_ipc_server_start()      → 启动 hicore 服务端
│   └── opdevsdk_inproc_sub()            → 注册 pub-sub 订阅
│
├── [2] 内存与共享资源
│   ├── alloc_share_memory()             → 分配共享内存 (视频帧/JPEG)
│   └── image_snapshot_pool_init()       → 抓拍图像池初始化
│
├── [3] 安全与权限
│   ├── userSecurityInit()               → 用户安全初始化
│   ├── permission_check_module_startup()→ 权限校验模块
│   └── send_dsp_init_info()             → 上报DSP初始化信息
│
├── [4] 硬件相关
│   ├── mcu_module_startup()             → MCU 模块
│   ├── _usrMain_HAL_init()              → HAL 层初始化
│   ├── face_component_module_startup()  → 人脸模块 (如支持)
│   ├── fingerprint_module_startup()     → 指纹模块
│   ├── security_module_startup()        → 安全模块 (如支持)
│   └── comb_init() / combSec_init()     → COMB扩展模块
│
├── [5] 音视频
│   ├── ad_video_play_startup()          → 广告视频播放
│   ├── vis_audio_paly_module_startup()  → 音频播放
│   └── init_preview()                   → 预览组件初始化
│
├── [6] 网络服务
│   ├── dvrnet_server_module_startup()   → SDK服务端 (8000端口)
│   ├── dvrnet_tls_server_module_startup()→ SDK TLS服务端 (8443端口)
│   ├── visnet_server_module_startup()   → 私有协议服务端 (8102端口)
│   ├── net_broken_server_module_startup()→ 断线心跳服务 (6666端口)
│   ├── rtsp_server_module_startup()     → RTSP服务端
│   ├── rtsp_client_module_startup()     → RTSP客户端
│   ├── start_sadp_server/client()       → SADP协议
│   ├── onvif_module_startup()           → ONVIF协议
│   ├── exosipcIf_init()                 → SIP/exosip客户端
│   ├── ysip_server_process_startup()    → SIP服务端
│   └── init_websocket_server()          → WebSocket服务
│
├── [7] 业务模块
│   ├── event_ctrl_module_startup()      → 事件管理
│   ├── async_import_init()              → 权限异步导入
│   ├── person_verify_init()             → 真人校验
│   ├── devmgmt_task_start()             → 设备管理
│   ├── session_manage_startup()         → 会话管理
│   ├── alarm_probe_module_startup()     → 报警检测
│   ├── key_business_module_startup()    → 按键业务
│   ├── analog_handle_main_setup()       → 模拟对讲处理
│   ├── alarm_voice_module_startup()     → 报警语音
│   ├── real_time_broadcast_init()       → 实时广播
│   ├── rb_com_module_startup()          → 定时广播
│   ├── rtp_pager_multicast_init()       → RTP广播寻呼
│   ├── motion_detection_module_startup()→ 移动检测
│   ├── NPQ_Process_start()              → NPQ网络质量
│   ├── init_webserver()                 → Web服务器
│   ├── cstorComStart()                  → 云存储
│   ├── blueToothTask()                  → 蓝牙任务 (如支持)
│   ├── init_stor_system()               → 存储系统 (如支持)
│   ├── start_thermal_ctrl_proc()        → 热成像控制 (如支持)
│   ├── start_thermal_proc()             → 热成像数据处理 (如支持)
│   ├── ezviz_thread_task()              → 萤石任务
│   ├── isup_module_startup()            → Ehome协议
│   └── initPPP()                        → PPP拨号
│
└── [8] 收尾
    ├── delDavinciFile()                 → 删除临时文件
    ├── creat_support_dir()              → 创建支持目录
    ├── dai_light_init()                 → LED灯初始化
    ├── 老化测试循环 (如需要)
    ├── net_connect_process()            → 网络连接处理
    └── net_switch_notify_proc()         → 网络切换通知
```

---

## 2. 整体架构设计

### 2.1 分层架构

```
┌─────────────────────────────────────────────────────────────┐
│                    应用层 (Application Layer)                 │
│  ┌──────────┬──────────┬──────────┬──────────┬──────────┐   │
│  │ access   │ media    │ inter-   │ netConn  │ dataMng  │   │
│  │ Control  │ Play     │ comSys   │          │          │   │
│  │          │          │          │          │          │   │
│  │ 门禁/    │ 音视频   │ 对讲     │ 网络     │ 数据库/  │   │
│  │ 权限/    │ 广播/    │ 会话     │ 协议栈   │ 配置     │   │
│  │ 事件     │ 广告     │ 管理     │          │          │   │
│  └──────────┴──────────┴──────────┴──────────┴──────────┘   │
│  ┌──────────┬──────────┬──────────┬──────────┬──────────┐   │
│  │ thermal  │ storage  │ plan     │ product  │ log      │   │
│  │          │          │ Template │ Test     │ Manage   │   │
│  │ 热成像   │ 存储管理 │ 预案模板 │ 生产测试 │ 日志     │   │
│  └──────────┴──────────┴──────────┴──────────┴──────────┘   │
├─────────────────────────────────────────────────────────────┤
│                  通信层 (IPC / Network)                       │
│  opdevsdk (inproc/sub + IPC) │ RTSP │ SIP │ ONVIF │ SADP    │
├─────────────────────────────────────────────────────────────┤
│                    HAL 层 (Hardware Abstraction)              │
│  ┌──────────┬──────────┬──────────┬──────────┬──────────┐   │
│  │ HAL      │ DAL      │ HOI      │          │          │   │
│  │ 入口     │ 设备抽象 │ 硬件接口 │          │          │   │
│  │          │          │          │          │          │   │
│  │ hal_init │ 读卡器   │ RS485    │ 键盘     │ 门锁     │   │
│  │          │ 指纹仪   │ 串口     │ 显示屏   │ 扬声器   │   │
│  │          │ 摄像头   │ GPRS     │ 按键     │ 照明     │   │
│  │          │ 电梯     │ 蓝牙     │ 机械门铃 │ 红外     │   │
│  └──────────┴──────────┴──────────┴──────────┴──────────┘   │
├─────────────────────────────────────────────────────────────┤
│                硬件接口层 (Hardware Interface)                │
│  hardwareif/{F1Plus|F2pro|A2S|AI2}                          │
│  平台相关: GPIO, I2C, SPI, 时钟, 电源管理                    │
├─────────────────────────────────────────────────────────────┤
│                   平台层 (Platform / OS)                      │
│  Linux Kernel │ DSP (Davinci) │ MCU │ AIP Platform          │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 核心架构特征

1. **多平台适配**: 通过 `hardwareif/{PLATFORM}` 目录实现平台差异隔离
   - F1Plus: 海思平台 (ARM)
   - F2pro: 新一代海思平台
   - A2S: 另一海思平台
   - AI2: Android 平台

2. **IPC 通信**: 基于 opdevsdk 的进程间通信框架
   - inproc: 进程内 pub-sub 消息总线
   - IPC: 跨进程 req-resp 通信
   - hicore 作为 IPC 中心节点

3. **能力检测**: 通过 `check_capa_support()` 宏/函数动态检测硬件/软件能力
   - HW_CAPA: 硬件能力 (热成像、指纹、蓝牙等)
   - SW_CAPA: 软件能力 (人脸、广播、ONVIF等)

4. **配置驱动**: 设备行为由配置文件 + 能力集驱动
   - `DEVICECONFIG`: 全局配置结构
   - `generate_dev_capa()`: 运行时生成能力集

5. **模块化启动**: 每个业务模块独立初始化，通过 `*_module_startup()` 接口启动

---

## 3. 各模块文件作用详解

### 3.1 mainCtrl — 主控模块

**目录**: `app/src/mainCtrl/`

| 文件 | 作用 |
|------|------|
| `main.c` | **程序入口**。main()函数、user_sysinit()、user_syskill()、PID管理、信号处理、AIP平台初始化 |
| `usrMainApp.c` | **应用主入口**。usrAppEntry()启动所有业务模块，全局变量定义(pDevCfgParam, chanPara)，预览/编码相关接口 |
| `hal_init.c` | **HAL初始化**。生成HAL_ATTRS配置(读卡器、门锁、键盘、RS485、红外等)，调用hal_init() |
| `shareMem.c` | **共享内存管理**。视频帧和JPEG数据共享内存分配 |
| `sysLib.c` | **系统库封装**。底层系统调用封装 |
| `imageManager.c` | **图像管理**。图像抓拍、存储、传输管理 |
| `base_log.c` | **基础日志**。日志初始化与配置 |
| `upgrade_compatible_process.c` | **升级兼容**。OTA升级后的兼容性处理 |
| `dsp/dsp_init.c/h` | **DSP初始化**。音频编解码DSP参数配置 |
| `dsp/dsp_callback.c/h` | **DSP回调**。音频数据回调处理 |
| `dsp/dsp_command.c/h` | **DSP命令**。DSP指令下发 |
| `dsp/dsp_interface.c/h` | **DSP接口**。DSP功能对外接口 |
| `isp/isp_sensor_interface.c` | **ISP传感器接口**。图像传感器参数控制 |
| `isp/isp_sensor_setting.c` | **ISP传感器设置**。图像参数(曝光、白平衡等) |
| `version/version.c` | **版本管理**。固件版本信息 |

### 3.2 accessControl — 门禁控制模块

**目录**: `app/src/accessControl/`

#### 3.2.1 authorityManagement — 权限管理

| 文件 | 作用 |
|------|------|
| `authorityManagement.c/h` | **权限管理核心**。权限校验模块入口，权限消息分发 |
| `authInfoRightPlan.c/h` | **权限-方案关联**。权限卡与开门方案的绑定关系 |
| `authInfoUpload.c/h` | **权限上传**。权限数据上传至门禁控制器 |

#### 3.2.2 authorityAsyncImport — 权限异步导入

| 文件 | 作用 |
|------|------|
| `async_import.c/h` | **异步导入入口**。权限数据异步导入协调 |
| `async_import_check.c/h` | **异步导入校验**。权限数据完整性/合法性检查 |
| `async_import_do.c/h` | **异步导入执行**。实际执行权限数据导入 |

#### 3.2.3 eventCtrl — 事件管理

| 文件 | 作用 |
|------|------|
| `event_ctrl.c/h` | **事件管理核心**。事件采集、过滤、上传调度 |
| `event_log_ctrl.c/h` | **事件日志**。事件日志存储与管理 |
| `event_operate_log_ctrl.c` | **操作日志**。用户操作行为记录 |
| `uploadChannel/` | **上传通道**。事件数据上传通道管理 |

### 3.3 dataMng — 数据管理模块

**目录**: `app/src/dataMng/`

| 文件/目录 | 作用 |
|------|------|
| `dataMng_shell.c/h` | **数据管理Shell**。telnet/CLI命令接口注册 |
| `config/` | **配置管理**。参数库(paramLib)、配置读写 |
| `database/` | **数据库管理**。SQLite数据库操作 |
| `database/db.c` | 数据库核心操作 |
| `database/dbshell.c` | 数据库Shell命令 |
| `database/db_user_info_shell.c` | 用户信息数据库管理 |
| `database/db_event_info_shell.c` | 事件信息数据库管理 |
| `database/dbmigrate.c` | 数据库迁移/升级 |
| `database/dbutil.c` | 数据库工具函数 |
| `database/db_event_info_util.c` | 事件信息工具 |
| `database/db_user_info_util.c` | 用户信息工具 |
| `database/dbpatch.c/h` | 数据库补丁 |
| `database/db_user_info_patch.c/h` | 用户信息补丁 |
| `database/sqliteExtFuncs.c` | SQLite扩展函数 |

### 3.4 HAL — 硬件抽象层

**目录**: `app/src/HAL/`

```
HAL
├── hal.c              # HAL核心实现，设备注册与管理
├── hal_shell.c/h      # HAL Shell命令接口
├── basicFunc/
│   ├── tools.c        # 通用工具函数
│   ├── file_func.c    # 文件操作函数
│   └── rdwr.c         # 读写封装
└── DAL/               # Device Abstraction Layer
    ├── dal.c          # DAL核心
    ├── card_reader/   # 读卡器 (支持ephy_cdrd, rs485_cdrd, iphy_cdrd, mcu_cdrd)
    │   ├── card_reader.c
    │   ├── issue_card.c
    │   └── sub_drives/
    ├── door_ctrl/     # 门锁控制
    ├── fingerprintModule/  # 指纹模块 (K1001F, MCU, TCS2)
    ├── bluetooth/     # 蓝牙 (含arm/arm_no_firmware/mcu子模块)
    ├── gprs_module/   # GPRS模块
    ├── keyboard/      # 键盘 (含室内/室外键盘)
    ├── loudspeaker/   # 扬声器
    ├── mcu/           # MCU通信
    ├── screen/        # 显示屏
    ├── sdcard/        # SD卡
    ├── serial/        # 串口 (RS232/RS485/协议解析)
    ├── light/         # 照明控制
    ├── securityModule/# 安全模块
    ├── elevator/      # 电梯控制
    ├── mechanical_doorbell/ # 机械门铃
    ├── ill_monitor/   # 光照检测
    └── dabi/          # 红外/补光控制
```

### 3.5 hardwareif — 硬件接口层

**目录**: `app/src/hardwareif/{F1Plus|F2pro|A2S|AI2}/`

平台相关硬件接口实现:
- GPIO 控制
- I2C 总线
- SPI 总线
- 时钟配置
- 电源管理
- 平台特定初始化

### 3.6 mediaPlay — 媒体播放模块

**目录**: `app/src/mediaPlay/`

| 子目录 | 作用 |
|------|------|
| `mediaPlay_shell.c/h` | 媒体播放Shell命令 |
| `vis_audio.c` | 音频播放核心 (多语言语音提示) |
| `actionPriority/` | 动作优先级管理 (不同媒体冲突时的优先级) |
| `broadcast/` | 广播系统 |
| `broadcast/plan/` | 广播预案 (PtMain, PtStrategy, PtModule等) |
| `broadcast/real_time_broadcast/` | 实时广播 |
| `broadcast/regular_broadcast/` | 定时广播 (hik_rbCom) |
| `videoAds/` | 视频广告 (ad_video_core, ad_video_dsp, ad_video_client) |

### 3.7 intercomSystem — 对讲系统

**目录**: `app/src/intercomSystem/`

| 子目录 | 作用 |
|------|------|
| `voiceTalk_shell.c/h` | 对讲Shell命令 |
| `talkback_control/` | 对讲控制核心 |
| `talkback_control/number_rules/` | 号码规则 |
| `talkback_control/talkback_plan/` | 对讲预案 |
| `talkback_control/talkback_protocol/` | 对讲协议 |
| `talkback_control/talkback_rules/` | 对讲规则 |
| `talkback_control/talkback_session/` | 对讲会话管理 |
| `analog/` | 模拟对讲处理 |
| `analog/intercom_analog_main.c` | 模拟对讲主流程 |
| `analog/intercom_analog_sip_proc.c` | SIP协议处理 |
| `analog/intercom_analog_dsp_proc.c` | DSP处理 |
| `analog/intercom_analog_rs485_communication.c` | RS485通信 |
| `analog/intercom_analog_dispatcher.c` | 事件分发 |

### 3.8 netConn — 网络连接模块

**目录**: `app/src/netConn/` (最大模块，26个子目录)

| 子目录 | 作用 |
|------|------|
| `dvrNet.c` | 网络核心，SDK协议处理 |
| `dvrNetParam.c` | 网络参数配置 |
| `dvrNetVoiceTalk.c` | 网络语音对讲 |
| `netConn_shell.c/h` | 网络Shell命令 |
| `sdk_client/` | SDK客户端 |
| `netsdk_tls_server.c/h` | SDK TLS服务端 (8443端口) |
| `securityUser.c` | 网络安全用户认证 |
| **协议层** | |
| `ISAPI/` | ISAPI协议 (海康开放接口) |
| `ONVIF/` | ONVIF协议 (网络视频设备互操作) |
| `ISUP/` | Ehome/ISUP协议 (设备上报) |
| `sadp/` | SADP协议 (设备发现) |
| `sip/` | SIP协议 (ysip客户端/服务端) |
| `rtsp/` | RTSP协议 (流媒体) |
| `srtp/` | SRTP加密传输 |
| `https_client/` | HTTPS客户端 |
| **网络服务** | |
| `web/` | Web服务器 |
| `webSocket/` | WebSocket服务 |
| `devmgmt/` | 设备管理 |
| `netQos/` | 网络质量(NPQ) |
| `nicBrokenHeart/` | 网卡断线心跳 |
| `capturePacket/` | 网络抓包(wireshark) |
| `cstor/` | 云存储 |
| `ezviz/` | 萤石生态 |
| `PreNetwork/` | 网络预配置 |
| `ppp/` | PPP拨号 |
| `zeroconfig/` | 零配置网络 |
| `uuid/` | UUID生成 |
| `Tools/` | 网络工具 |

### 3.9 basefun_lib — 基础工具库

**目录**: `app/src/basefun_lib/`

| 子目录 | 作用 |
|------|------|
| `encrypt/` | 加密 (DES, MD5, Base64, SM4, HMAC, 文件加密) |
| `data_check/` | 数据校验 (checksum) |
| `ring_buffer/` | 环形缓冲区 |
| `math/` | 数学工具 |
| `time_deal/` | 时间处理 (时钟) |
| `string/` | 字符串工具 |
| `net_application/` | 网络应用 (FTP等) |
| `net_base_fun/` | 网络基础 (netconfig等) |
| `parse/` | 解析 (XML扩展, CGI页面, 正则) |
| `deelx/` | 正则表达式库 |
| `concurrent/` | 并发 (线程池) |
| `device_related/` | 设备相关 (SN生成等) |

### 3.10 deviceinfo — 设备信息模块

**目录**: `app/src/deviceinfo/`

| 子目录 | 作用 |
|------|------|
| `capability/` | 设备能力管理 |
| `capability/device_capa_interface.c` | 能力接口 (check_capa_support/get_devcapa_data) |
| `capability/device_capa_init.c` | 能力初始化 |
| `capability/device_ability.c` | 能力定义 |
| `capability/capa_base_fun.c` | 能力基础函数 |
| `capability/device_capa_xml.c` | 能力XML解析 |
| `capability/device_id.c` | 设备ID管理 |
| `devlist/{PLATFORM}/` | 设备列表 (各平台设备配置) |
| `devlist/F1Plus/DS_KV6114_WBE1.c` | 具体设备型号配置 |

### 3.11 storage — 存储模块

**目录**: `app/src/storage/`

包含 storLib 存储库:
- `Device/SataHD/` - SATA硬盘设备管理
- `Device/edev/` - 外置设备(USB/SD)管理
- `DeviceManage/` - 设备统一管理
- `FileManage/` - 文件管理
- `DataService/` - 数据服务
  - `Record/` - 录像服务
  - `Schedule/` - 计划任务
  - `Video/` - 视频数据
  - `Pic/` - 图片数据
  - `DataSearch/` - 数据搜索
  - `Tag/` - 标签

### 3.12 thermal — 热成像模块

**目录**: `app/src/thermal/`

| 子目录 | 作用 |
|------|------|
| `thermal_main/` | 热成像主入口 |
| `thermal_manage/` | 热成像管理 |
| `thermal_module/` | 热成像模块 |
| `thermal_protocol/` | 热成像协议 |
| `thermal_temperature/` | 温度处理 |

### 3.13 其他模块

| 目录 | 作用 |
|------|------|
| `planTemplate/` | 预案模板 (planTemplateCommon, keyPlanTemplate) |
| `productTest/` | 生产测试 (含各平台测试项) |
| `recognizer_component/` | 识别组件 (人脸、身份证、真人校验) |
| `system/devStatus/` | 系统设备状态监控 |
| `logManage/` | 日志管理 (日志上传) |
| `wifi/` | WiFi控制 |
| `mcu/` | MCU通信 |
| `ipc_unix/` | IPC Unix封装 (VOIP, SIP Server) |
| `netitf/` | 网络接口 (升级等) |
| `password_recovery/` | 密码恢复 |
| `zint/` | 二维码生成 |
| `heop_manager/` | Android开放平台管理 |
| `misc/` | 杂项工具 |
| `util/` | 通用工具 |

---

## 4. 数据流图

### 4.1 启动数据流

```
[Boot]
  │
  ├─ Linux Kernel 启动
  │   └─ 加载驱动 (GPIO, I2C, SPI, 串口, 摄像头, DSP)
  │
  └─ init → /home/app/hicore (main)
       │
       ├─ PID检查 ─→ 已运行则退出
       │
       ├─ aip_base()
       │   └─ aip_service_start() ─→ 看门狗/安全/时间管理
       │
       ├─ user_sysinit()
       │   ├─ opdevsdk_hwif_basic_init() ─→ 硬件接口层
       │   ├─ sysInit() ─→ 读取boot param, CPLD info
       │   ├─ openssl_init() ─→ 加密库
       │   ├─ generate_dev_capa() ─→ 设备能力集
       │   ├─ getDeviceCfgParams() ─→ 加载配置
       │   ├─ init_user_info_database() ─→ SQLite用户库
       │   ├─ db_event_init_database() ─→ SQLite事件库
       │   ├─ dsp_init() ─→ DSP音频初始化
       │   └─ heop_init() ─→ (Android)开放平台
       │
       └─ usrAppEntry()
           ├─ opdevsdk_ipc_init() ─→ IPC框架
           ├─ 各模块 *_module_startup() ─→ 并行启动
           │   ├─ 网络服务 (RTSP/SIP/ONVIF/Web等)
           │   ├─ 门禁模块 (权限/事件/异步导入)
           │   ├─ 音视频 (预览/播放/广播)
           │   └─ 业务 (对讲/存储/热成像)
           └─ bDevAppStarted = TRUE ─→ 系统就绪
```

### 4.2 门禁刷卡数据流

```
[IC卡/指纹/密码/身份证]
       │
       ▼
  [硬件传感器]
       │
       ▼
  [DAL层]
  ┌──────────────────────────────────────┐
  │ card_reader/  (读卡器)                │
  │ fingerprintModule/  (指纹)            │
  │ serial/  (RS485外部设备)              │
  └──────────┬───────────────────────────┘
       │
       ▼
  dal_cdrd_event_handle()  [hal_init.c]
  ┌──────────────────────────────────────┐
  │ CDRD_CARD_DATA ─→ dal_cdrd_card_handle│
  │   ├─ 生成 PERMISSION_CARD             │
  │   └─ permission_mqsend_cardNo()       │
  │ CDRD_KEY_DATA  ─→ dal_cdrd_key_handle │
  │   └─ permission_mqsend_pwd()          │
  │ CDRD_IDCARD_DATA ─→ id_card_info_process│
  └──────────┬───────────────────────────┘
       │
       ▼
  [IPC消息队列]
       │
       ▼
  accessControl/authorityManagement/
  permission_check_module_startup()
       │
       ├─ 权限校验 (authInfoRightPlan)
       │   ├─ 卡号匹配
       │   ├─ 时间方案匹配
       │   └─ 权限方案匹配
       │
       ├─ 开门方案执行 (door_ctrl)
       │   └─ 开锁GPO输出
       │
       └─ 事件记录 (eventCtrl)
           └─ 写入事件数据库
```

### 4.3 视频流数据流

```
[摄像头传感器]
       │
       ▼
  [ISP处理]
  isp_sensor_interface.c / isp_sensor_setting.c
       │
       ▼
  [DSP编解码]
  dsp_callback.c / dsp_interface.c
       │
       ├─ 主码流 ─→ 录像存储 (storage/storLib)
       │              └─ Schedule Record / Motion Record
       │
       ├─ 子码流 ─→ 预览 (preview_component)
       │              ├─ RTP/UDP ─→ 客户端
       │              ├─ RTSP ─→ 客户端
       │              ├─ WebSocket ─→ Web浏览器
       │              └─ VOIP ─→ 对讲画面
       │
       └─ JPEG抓拍 ─→ 共享内存
                       ├─ 事件截图
                       ├─ 定时截图
                       └─ 云存储上传
```

### 4.4 网络请求数据流

```
[远程客户端/平台]
       │
       ▼
  [网络端口]
  ┌──────────────────────────────────────────┐
  │ 8000  ─→ dvrnet_server (SDK协议)          │
  │ 8443  ─→ netsdk_tls_server (TLS加密)      │
  │ 8102  ─→ visnet_server (私有协议)          │
  │ 6666  ─→ net_broken_server (断线心跳)      │
  │ 554   ─→ rtsp_server (流媒体)             │
  │ 80    ─→ web_server (Web管理)             │
  │ 5060  ─→ ysip_server (SIP)               │
  └────┬─────────────────────────────────────┘
       │
       ▼
  [协议解析层]
  ┌──────────────────────────────────────────┐
  │ ISAPI/     ─→ CGI/ISAPI协议解析            │
  │ ONVIF/     ─→ ONVIF协议解析               │
  │ ISUP/      ─→ Ehome设备上报               │
  │ sadp/      ─→ 设备发现                     │
  │ sip/       ─→ SIP信令                     │
  └────┬─────────────────────────────────────┘
       │
       ▼
  [业务处理层]
  ┌──────────────────────────────────────────┐
  │ dvrNetParam.c    ─→ 参数配置              │
  │ dvrNetVoiceTalk.c ─→ 语音对讲              │
  │ sdk_client/      ─→ SDK客户端管理          │
  │ cstor/           ─→ 云存储                 │
  └────┬─────────────────────────────────────┘
       │
       ▼
  [数据层]
  ┌──────────────────────────────────────────┐
  │ dataMng/database/  ─→ SQLite读写          │
  │ HAL/DAL/           ─→ 硬件控制             │
  │ accessControl/     ─→ 权限校验             │
  └──────────────────────────────────────────┘
```

---

## 5. 分层控制流图

### 5.1 应用层控制流

```
                    ┌─────────────────────────┐
                    │    main() / usrAppEntry │
                    └───────────┬─────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
    ┌───────────────┐ ┌───────────────┐ ┌───────────────┐
    │  网络服务层    │ │  业务逻辑层   │ │  媒体服务层   │
    └───────┬───────┘ └───────┬───────┘ └───────┬───────┘
            │                 │                 │
    ┌───────┴───────┐ ┌───────┴───────┐ ┌───────┴───────┐
    │ RTSP Server   │ │ accessControl │ │ preview_comp  │
    │ SIP Server    │ │   └── perm    │ │ audio_play    │
    │ ONVIF/SADP    │ │   └── event   │ │ broadcast     │
    │ Web/WS Server │ │   └── async   │ │ video_ads     │
    │ Ehome/ISUP    │ │               │ │ ad_video      │
    │ SDK Server    │ │ dataMng       │ │               │
    └───────┬───────┘ │   └── config  │ └───────┬───────┘
            │         │       └── db    │         │
            ▼         └─────────────────┘         ▼
    ┌─────────────────────────────────────────────────┐
    │              IPC 消息总线 (opdevsdk)             │
    │  ┌───────────────────────────────────────────┐  │
    │  │ inproc: pub-sub (进程内消息广播)            │  │
    │  │ IPC: req-resp (跨进程请求响应)              │  │
    │  └───────────────────────────────────────────┘  │
    └─────────────────────────────────────────────────┘
                               │
                               ▼
                    ┌─────────────────────────┐
                    │     HAL 接口层           │
                    │  hal_init / hal_interface │
                    └───────────┬─────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
    ┌───────────────┐ ┌───────────────┐ ┌───────────────┐
    │   DAL层       │ │   HOI层       │ │  平台差异层   │
    │ ┌───────────┐ │ │ ┌───────────┐ │ │ ┌───────────┐ │
    │ │card_reader│ │ │ │  RS485    │ │ │ │hardwareif │ │
    │ │door_ctrl  │ │ │ │  GPIO     │ │ │ │  {F1Plus} │ │
    │ │fingerprint│ │ │ │  I2C      │ │ │ │  {F2pro}  │ │
    │ │keyboard   │ │ │ │  SPI      │ │ │ │  {A2S}    │ │
    │ │serial     │ │ │ │  MCU      │ │ │ │  {AI2}    │ │
    │ │sdcard     │ │ │ └───────────┘ │ └───────────┘ │
    │ │elevator   │ │ │               │                │
    │ │light      │ │ │               │                │
    │ └───────────┘ │ │               │                │
    └───────────────┘ └───────────────┘ └───────────────┘
                               │
                               ▼
                    ┌─────────────────────────┐
                    │    Linux Kernel + DSP    │
                    │  驱动层: 摄像头/音频/GPIO │
                    └─────────────────────────┘
```

### 5.2 HAL 层控制流

```
                    _usrMain_HAL_init() [hal_init.c]
                               │
                               ▼
                    create_attrs() → HAL_ATTRS
                               │
                    ┌──────────┴──────────┐
                    ▼                     ▼
           generate_hol_attrs()    generate_dal_attrs()
                    │                     │
                    ▼                     ├── generate_dal_kbd()
           RS485 配置               ├── generate_dal_dc()    (门锁)
                    │                 ├── generate_dal_illm() (光照)
                    │                 ├── generate_dabi()     (红外/补光)
                    │                 ├── generate_dal_cdrd() (读卡器)
                    │                 │       ├── iphy (内置)
                    │                 │       ├── ephy (RS485外置)
                    │                 │       └── mcu (MCU集成)
                    │                 ├── generate_dal_mdoorbell() (门铃)
                    │                 └── generate_dal_gprs_module()
                    │
                    ▼
               hal_init(p_hal_attrs)
                    │
                    ▼
           ┌───────────────────────┐
           │   HAL Core (hal.c)    │
           │  ┌─────────────────┐  │
           │  │ 设备注册与管理   │  │
           │  │ 初始化所有DAL设备│  │
           │  │ 建立HOI接口映射 │  │
           │  └─────────────────┘  │
           └───────────┬───────────┘
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
   ┌──────────┐ ┌──────────┐ ┌──────────┐
   │ card_    │ │ door_    │ │ fingerprint│
   │ reader   │ │ ctrl     │ │ Module   │
   │ DAL      │ │ DAL      │ │ DAL      │
   └────┬─────┘ └────┬─────┘ └────┬─────┘
        │            │            │
        ▼            ▼            ▼
   ┌─────────────────────────────────┐
   │      hardwareif/{PLATFORM}       │
   │   (底层驱动: I2C/SPI/GPIO/Serial)│
   └─────────────────────────────────┘
```

### 5.3 跨层调用关系

```
  应用层                    调用目标                    跨层接口
  ─────                    ────────                    ────────
  permission_check         → accessControl/authority   → IPC消息
  event_ctrl               → accessControl/eventCtrl   → 数据库
  dsp_if_netbuf_info       → mainCtrl/dsp              → DSP共享内存
  dsp_if_insert_iframe     → mainCtrl/dsp              → DSP命令
  _usrMain_HAL_init        → HAL/hal_init              → HAL_ATTRS
  permission_mqsend_cardNo → DAL/card_reader           → 消息队列
  generate_dev_capa        → deviceinfo/capability     → 能力检测
  vis_audio_paly_module    → mediaPlay/vis_audio       → 音频DSP
  init_preview             → mediaPlay/preview         → DSP回调
  init_stor_system         → storage/storLib           → 文件系统
  start_thermal_ctrl_proc  → thermal/thermal_main      → 热成像协议
  exosipcIf_init           → netConn/sip               → SIP信令
  rtsp_server_module       → netConn/rtsp              → RTSP流
  ad_video_play_startup    → mediaPlay/videoAds        → DSP+网络
  init_webserver           → netConn/web               → HTTP服务
  init_websocket_server    → netConn/webSocket         → WebSocket
  cstorComStart            → netConn/cstor             → 云存储
  start_sadp_server        → netConn/sadp              → 设备发现
  isup_module_startup      → netConn/ISUP              → Ehome上报
  face_component_startup   → recognizer_component      → AI推理
  fingerprint_module       → HAL/DAL/fingerprint       → 指纹硬件
  ezviz_thread_task        → netConn/ezviz             → 萤石平台
  NPQ_Process_start        → netConn/netQos            → 网络质量
```

### 5.4 模块间依赖关系图

```
                    ┌─────────────────────────────────────────────────┐
                    │                 deviceinfo/capability            │
                    │         (全局能力检测，被几乎所有模块依赖)         │
                    └──────────────────────┬──────────────────────────┘
                                           │
        ┌──────────────────────────────────┼──────────────────────────────────┐
        │                                  │                                  │
        ▼                                  ▼                                  ▼
┌───────────────┐              ┌──────────────────────┐            ┌──────────────┐
│  mainCtrl     │              │     dataMng          │            │   HAL/DAL    │
│  (主控/启动)  │◄─────────────┤  (数据库/配置)       │◄───────────┤ (硬件抽象)   │
└───────┬───────┘   配置参数    └──────────────────────┘   硬件属性    └──────┬───────┘
        │                                     ▲                              │
        │                                     │                              │
        ▼                                     │                              ▼
┌───────────────┐                              │               ┌──────────────┐
│  accessCtrl   │                              │               │hardwareif    │
│  (门禁/权限)  │──────────────────────────────┘               │ (平台硬件)   │
└───────┬───────┘        IPC消息/事件                         └──────────────┘
        │
        ▼
┌───────────────┐    ┌───────────────┐    ┌──────────────────────────┐
│  intercomSys  │    │   mediaPlay   │    │       netConn            │
│  (对讲)       │    │  (音视频)     │    │   (网络/协议)            │
└───────┬───────┘    └───────┬───────┘    └───────────┬──────────────┘
        │                   │                         │
        ▼                   ▼                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              IPC (opdevsdk) — 模块间通信总线                     │
└─────────────────────────────────────────────────────────────────┘
        ▲
        │
┌───────┴──────────┐  ┌──────────────┐  ┌──────────────────────────┐
│  recognizer_comp │  │  storage     │  │  thermal (可选)          │
│  (识别组件)      │  │  (存储)      │  │  (热成像可选)            │
└──────────────────┘  └──────────────┘  └──────────────────────────┘
```

---

## 6. 线程与模块映射

### 6.1 线程-模块映射总览

> 通过代码分析，KV6 项目中约有 **140+ 个线程创建调用**，分布在 **18 个模块**中。
> 线程创建统一使用自定义封装 `pthreadSpawn(ptid, priority, stacksize, funcptr, args, ...)`，
> 定义在 `include/pthread/pwrapper.h`。

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    线程 ↔ 模块映射总览                                          │
│                                                                              │
│  优先级            线程名              模块/目录                    栈大小     │
│  ───────         ─────────────────  ───────────────────────      ────────  │
│                                                                              │
│  ┌─ NET_SERVER_PRIO (80) 网络服务层 ────────────────────────────────┐       │
│  │ NET_SERVER_PRIO  dvrNetServer            netConn/dvrNet.c        IPC_SRVCOM │
│  │                  netsdk_tls_server_proc  netConn/ISAPI/network   IPC_SRVCOM │
│  │                  visNetServer            netConn/visNet.c        16 KB      │
│  │                  visNetServer_RL41       netConn/visNet.c        16 KB      │
│  │                  netsdk_tls_proc_client_req netConn/ISAPI/network 8 MB     │
│  │                  rtspoverhttprecv        netConn/web/            IPC_RTSPOVERHTTP │
│  │                  sipic_auto_notice_*     netConn/webSocket/      24 KB      │
│  └──────────────────────────────────────────────────────────────────┘       │
│                                                                              │
│  ┌─ ONVIFEVENT_PRIO (80) ───────────────────────────────────────────┐       │
│  │ ONVIFEVENT_PRIO  onvif_event_server      netConn/ONVIF/event     IPC_ONVIFEVENT │
│  │                  close_baseevent_fd      netConn/ONVIF/event     4 KB         │
│  │                  onvif_relayoutput_task  netConn/ONVIF/device    IPC_ONVIFRYOPTASK │
│  └──────────────────────────────────────────────────────────────────┘       │
│                                                                              │
│  ┌─ HD_CTRL_PRIO / NET_CTRL_PRIO / AUDIOSEND_PRIO (70) ────────────┐       │
│  │ HD_CTRL_PRIO   unicast_task          mediaPlay/broadcast        IPC_HDTASKCTRL │
│  │                multicast_task        mediaPlay/broadcast        IPC_HDTASKCTRL │
│  │                broadcast_task        mediaPlay/broadcast        IPC_HDTASKCTRL │
│  │                rtp_pager_multicast   mediaPlay/broadcast        HD_CTRL_PRIO   │
│  │                zeroConfig            netConn/zeroconfig          IPC_ZEROCONFIG │
│  │ AUDIOSEND_PRIO vis_audio_play_task   mediaPlay/vis_audio        IPC_AUDIOPLAY  │
│  └──────────────────────────────────────────────────────────────────┘       │
│                                                                              │
│  ┌─ EXCEPTION_PRIO / UPGRADE_PRIO / RTSP_PRIO / STREAM_*_PRIO (60) ─┐       │
│  │ EXCEPTION_PRIO eventCtrl_task         accessControl/eventCtrl      IPC_EXCEPTION │
│  │                event_delete_task      accessControl/eventCtrl      IPC_EXCEPTION │
│  │                alarm_ctrl_task        misc/alarmCtrl               IPC_EXCEPTION │
│  │                alarmIn_probe_task     misc/alarmCtrl               4 KB         │
│  │                motDetCtrlTask         misc/motDetCtrl              IPC_MOTDECCTRL │
│  │                pt_task                productTest/                   PRODUCT_TEST_STACK_SIZE │
│  │ UPGRADE_PRIO   sendClientUpgrading   netConn/dvrNet.c             4 KB         │
│  │                send_upgrade_file     netConn/dvrNetParam.c        4 KB         │
│  │                start_rtspc_interface  intercomSystem/analog        2 MB         │
│  │ RTSP_PRIO      start_rtsp_server     netConn/rtsp                 IPC_RTSPSERVER │
│  │ STREAM_REC_PRIO streamRecord          storage/storLib/Record       256 KB/通道  │
│  │                onvif_findevent_session netConn/ONVIF/event         4 KB         │
│  │ STREAM_NET_PRIO voiceTalkSendDataOut  netConn/dvrNet.c             IPC_VTALKSEND │
│  │                isapi_http_jpeg_preview netConn/ISAPI/sipc          8 KB         │
│  │                onvif_getevent_session  netConn/ONVIF/event         4 KB         │
│  │ STREAM_REC_PRIO isapi_heop_start_pb  netConn/ISAPI/heop           16/8 KB      │
│  │ EXCEPTION_PRIO security_token_clear  netConn/devmgmt              IPC_HIKSRITRANS │
│  └──────────────────────────────────────────────────────────────────┘       │
│                                                                              │
│  ┌─ COMMON_PRIO (50) 最大线程池 ──────────────────────────────────────┐       │
│  │ COMMON_PRIO  permission_check_task    accessControl/authorityMgmt    32 KB    │
│  │              async_import_data_mng    accessControl/asyncImport      1 MB     │
│  │              mcu_module_task          mcu/mcu_main                   1 MB     │
│  │              face_component_task      recognizer_component/face      8 KB     │
│  │              face_component_init      recognizer_component/face      16 KB    │
│  │              face_component_rebuild   recognizer_component/face      1 MB     │
│  │              fingerprint_module_task  HAL/DAL/fingerprintModule      8 MB     │
│  │              event_arming_sdk_upload  accessControl/eventCtrl/upload 32 KB   │
│  │              event_arming_isapi_upload accessControl/eventCtrl/upload 32 KB  │
│  │              event_ezviz_alarm_upload accessControl/eventCtrl/upload 32 KB  │
│  │              syslog_upload_process    accessControl/eventCtrl/upload 1 MB    │
│  │              sadp_client_proc         netConn/sadp                   8 MB     │
│  │              ws_server                netConn/sip/ysipc              8 MB     │
│  │              ws_session_task          netConn/sip/ysipc              2 MB     │
│  │              ws_ssl_server            netConn/sip/ysipc              8 MB     │
│  │              ws_preview_stream_task   netConn/webSocket              1 MB     │
│  │              websocket_playback_thread netConn/webSocket             256 KB   │
│  │              visNetProcessClientReq   netConn/visNet.c               128 KB   │
│  │              NPQ_Manage_Task          netConn/netQos                 16 KB    │
│  │              netBrokenDataRecv        netConn/nicBrokenHeart         32 KB    │
│  │              cstorComTask             netConn/cstorCom               128 KB   │
│  │              thermal_process_task     thermal/thermal_main           32 KB    │
│  │              thermal_task             thermal/thermal_manage         1 MB     │
│  │              thermal_data_task        thermal/thermal_manage         1 MB     │
│  │              backup_dev_cfg           mainCtrl/usrMainApp.c          64 KB    │
│  │              blueToothTask            mainCtrl/usrMainApp.c          32 KB    │
│  │              search_ctrl_task         storage/storLib/Search         256 KB   │
│  │              formatTask               storage/storLib/FileManage     128 KB   │
│  │              stor_bad_blocks_detect   storage/storLib/SataHD         256 KB   │
│  │              cdrd_kernel_task         HAL/DAL/card_reader            CDRD_STACK_SIZE │
│  │              dc_task                  HAL/DAL/door_ctrl              32 KB    │
│  │              dal_kbd_task             HAL/DAL/keyboard               32 KB    │
│  │              key_business_task_*      HAL/DAL/keyboard               32 KB    │
│  │              security_module_process  HAL/DAL/securityModule         64 KB    │
│  │              illm_task                HAL/DAL/ill_monitor            ILLM_PTHREAD_STACK_SIZE │
│  │              DABI_task                HAL/DAL/dabi                   DABI_CTRL_STACK_SIZE │
│  │              key_auth_light_ctrl      HAL/DAL/dabi                   DABI_CTRL_STACK_SIZE │
│  │              bluetooth_restart_task   HAL/DAL/bluetooth              32 KB    │
│  │              uni_reinit_net_if_task   netConn/ISAPI + netitf         32 KB    │
│  │              send_devmgmt_notify      netConn/devmgmt                32 KB    │
│  │              isapi_material_download  netConn/imageFtp               IPC_PREVCTRL │
│  │              isapi_reboot             netConn/ISAPI/publish          32/16 KB │
│  │              PPP_process              netConn/ppp                    32 KB    │
│  │              ONVIF_Initiate           netConn/ONVIF/onvif_init       IPC_ONVIFINIT │
│  │              onvif_probe_match        netConn/ONVIF/wsdiscovery      IPC_ONVIFINIT │
│  │              onvif_hello_server       netConn/ONVIF/wsdiscovery      IPC_ONVIFINIT │
│  │              onvif_exception          netConn/ONVIF/event            IPC_ONVIFEXCEPT │
│  │              recv_rs485_cmd_task      intercomSystem/analog          8 MB     │
│  │              analog_cmd_handle_task   intercomSystem/analog          8 MB     │
│  │              analog_session_ctrl_task intercomSystem/analog          8 MB     │
│  │              analog_rtspc_stop_stream intercomSystem/analog          32 KB    │
│  │              pt_module_task           mediaPlay/broadcast            64 KB    │
│  │              rb_com_module_task       mediaPlay/broadcast            64 KB    │
│  └──────────────────────────────────────────────────────────────────┘       │
│                                                                              │
│  ┌─ USER_MANAGE_PRIO (50) ──────────────────────────────────────────┐       │
│  │ USER_MANAGE_PRIO usrSecurityTask    misc/securityCtrl              IPC_USRSUCURTY │
│  └──────────────────────────────────────────────────────────────────┘       │
│                                                                              │
│  ┌─ 存储专用优先级 ─────────────────────────────────────────────────┐       │
│  │ STOR_STREAM_REC_PRIO streamRecord    storage/storLib/Record       256 KB/通道 │
│  │ STOR_SCHEDULE_PRIO recordSchedule    storage/storLib/Schedule     512 KB     │
│  │ STOR_HD_CTRL_PRIO  hdTaskCtrl        storage/storLib/SataHD       512 KB     │
│  │                  hdFlushTask         storage/storLib/SataHD       512 KB     │
│  │ STOR_COMMON_PRIO   orm_del_overdue   storage/storLib/DataService  512 KB     │
│  │                  sdTaskCtrl          storage/storLib/Device       128 KB     │
│  │                  sataTaskCtrl        storage/storLib/Device       128 KB     │
│  │                  hd_clone_read       storage/storLib/FileManage   128 KB     │
│  │                  hd_clone_write      storage/storLib/FileManage   128 KB     │
│  │                  stor_set_init_fat32 storage/storLib/FileManage   4 KB       │
│  │ STOR_COMMON_PRIO   record_wakeup_hd  storage/storLib/DataService  2 KB       │
│  └──────────────────────────────────────────────────────────────────┘       │
│                                                                              │
│  ┌─ 低优先级 ───────────────────────────────────────────────────────┐       │
│  │ PRIORITY_NORMAL  syslog_upload_process  accessControl/eventCtrl    1 MB    │
│  │ 30             log_upload               misc/alarmVoice + logManage 64 KB │
│  └──────────────────────────────────────────────────────────────────┘       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 栈大小差异分析

各线程栈大小从 **1 KB 到 8 MB** 不等，差异巨大的根本原因是 **线程职责不同导致的调用深度和局部变量需求不同**：

#### 8 MB 线程（最大栈）

| 线程 | 模块 | 为什么需要 8 MB |
|------|------|----------------|
| `fingerprint_module_task` | HAL/DAL/指纹 | 指纹识别涉及大量图像数据处理、AI 推理，调用链深，局部变量多 |
| `sadp_client_proc` | netConn/sadp | SADP 设备发现需要解析大量网络包，涉及 XML/二进制协议解析，递归调用 |
| `ws_server` / `ws_ssl_server` | netConn/sip/ysipc | WebSocket 服务需要处理 SSL/TLS 握手（RSA 2048 位加密的临时密钥交换可能占用数 MB 栈），加上协议解析 |
| `recv_rs485_cmd_task` / `analog_cmd_handle_task` / `analog_session_ctrl_task` | intercomSystem/analog | 模拟对讲涉及 RS485 协议栈 + SIP 信令 + RTP 媒体处理，多层嵌套调用 |

#### 1-2 MB 线程

| 线程 | 模块 | 为什么需要大栈 |
|------|------|---------------|
| `mcu_module_task` (1 MB) | mcu | MCU 通信涉及复杂的协议解析，处理多种外设命令（门锁、门铃、按键等） |
| `async_import_data_mng` (1 MB) | accessControl | 权限异步导入需要批量处理大量权限数据，可能涉及 XML 解析和数据库批量操作 |
| `syslog_upload_process` (1 MB) | accessControl | 日志上传涉及日志文件读取、压缩、网络传输，可能涉及 zlib 压缩的递归调用 |
| `face_component_rebuild_model` (1 MB) | recognizer | 人脸模型重建涉及大量图像处理算法和 AI 模型推理 |
| `thermal_task` / `thermal_data_task` (1 MB) | thermal | 热成像数据处理涉及红外图像解码、温度计算、图像处理算法 |
| `ws_session_task` (2 MB) | netConn | WebSocket 会话管理，处理多路并发会话的上下文 |
| `ws_preview_stream_task` (1 MB) | netConn | WebSocket 预览流推送，需要处理视频帧缓冲和 RTP 打包 |
| `visNetProcessClientRequest` (128 KB→1 MB 多处) | netConn | VIS 私有协议客户端请求处理，涉及复杂的协议解析 |
| `netsdk_tls_proc_client_request` (8 MB) | netConn | TLS 客户端请求处理，SSL/TLS 握手栈开销极大 |

#### 128-256 KB 线程（中等栈）

| 线程 | 模块 | 为什么需要中等栈 |
|------|------|----------------|
| `cstorComTask` (128 KB) | netConn/cstor | 云存储任务，涉及文件读写和网络传输，但调用链不深 |
| `hd_clone_read/write` (128 KB) | storage | 硬盘克隆，I/O 操作为主，栈需求中等 |
| `formatTask` (128 KB) | storage | 磁盘格式化，涉及文件系统操作 |
| `stor_bad_blocks_detect` (256 KB) | storage | 坏道检测，需要一定的缓冲区 |
| `search_ctrl_task` (256 KB) | storage | 搜索回放，涉及数据库查询和文件搜索 |
| `streamRecord` (256 KB/通道) | storage | 每通道一个录像线程，256 KB 足够处理编码码流的写入 |

#### 4-64 KB 线程（小栈）

| 栈大小 | 典型线程 | 为什么小栈够用 |
|--------|---------|---------------|
| 32 KB | permission_check_task, dc_task, dal_kbd_task 等 | 这些线程主要是事件循环模式：接收消息 → 简单处理 → 回复，调用链浅 |
| 16 KB | NPQ_Manage_Task, isapi_reboot | 轻量级任务，主要是状态管理和简单逻辑 |
| 4 KB | alarmIn_probe_task, sendClientUpgrading, close_baseevent_fd | 极简任务：发送心跳、关闭文件描述符等，几乎无局部变量 |
| 1 KB | product_test_net_service, audio_test | 生产测试中的极简任务 |

#### 栈大小设计原则总结

```
栈大小取决于三个因素:
  1. 调用深度    → SSL/TLS 握手、协议解析递归 → 大栈
  2. 局部变量    → 图像缓冲区、加密密钥临时存储 → 大栈
  3. 线程模式    → 事件循环(小栈) vs 批量处理(大栈)

  事件循环模式 (小栈够用):
    while(1) {
      接收消息/事件 → 简单处理 → 发送响应
    }
    调用深度通常 < 5 层

  批量处理模式 (需要大栈):
    读取大量数据 → 解析 → 转换 → 存储/发送
    调用深度可达 20+ 层，局部变量占用数 MB
```

### 6.3 栈空间总和估算

> 以下基于代码中实际栈大小参数累加估算（去重后约 140 个线程）：

```
栈空间分布统计:

  8 MB  ×  7 个线程  =  56 MB     (fingerprint, sadp_client, ws_server, ws_ssl_server, 模拟对讲×3)
  1-2 MB × 10 个线程  =  12 MB    (mcu, async_import, syslog_upload, face_rebuild, thermal×2,
                                    ws_session, ws_preview, visNetProcess, netsdk_tls_client)
  256 KB ×  8 个线程  =   2 MB    (search_ctrl, bad_blocks, streamRecord×2, hd_clone×2,
                                    ws_playback, record_wakeup_hd)
  128 KB × 10 个线程  =   1.25 MB (cstorCom, hd_clone×2, formatTask, hd_clone_read/write,
                                    sdTaskCtrl, sataTaskCtrl, stor_bad_blocks, visNetProcessClient)
  64 KB ×  6 个线程   =  384 KB   (backup_dev_cfg, security_module, pt_module_task,
                                    rb_com_module_task, vis_audio_play)
  32 KB × 30 个线程   =  960 KB   (permission_check, cdrd, dc, kbd, key_business×3,
                                    bluetooth_restart, uni_reinit, PPP, isapi_reboot×2,
                                    event_upload×4, netBrokenHeart, thermal_process,
                                    send_devmgmt_notify, onvif_probe/hello, analog_rtspc_stop)
  16 KB ×  6 个线程   =   96 KB   (NPQ_Manage, isapi_heop, upgrade_thermal, sys_restart)
   8 KB ×  2 个线程   =   16 KB   (face_component_task, isapi_http_jpeg_preview×2)
   4 KB ×  8 个线程   =   32 KB   (alarmIn_probe, sendClientUpgrading, close_baseevent_fd,
                                    onvif_findevent×2, stor_set_init_fat32)
  其他常量栈 × 20 个  ≈  500 KB  (IPC_* 常量定义的栈大小)

  ───────────────────────────────────
  估算总计: 约 72-75 MB

  对比: 项目 B (linux_indoor_baseline)
  ───────────────────────────────────
  项目 B 线程栈分布:
    128 KB × 1  (talkBackRtpTask)
     64 KB × 2  (APP_GuiMain, smarthome_coo_upgrade)
     32 KB × 8  (stor_AudioPicProcTask, talkBackDevInputTask 等)
     16 KB × 15 (dvrNetServer×2, visNetServer, eXosip, sqliteOpTask 等)
      4 KB × 12 (wifi_adjust_reminder, adjustTimeTask, watchdogTask 等)
  ───────────────────────────────────
  项目 B 估算总计: 约 350-400 KB

  差异原因:
    项目 A 栈总和使用约为项目 B 的 180-200 倍
    主要原因:
    1. 项目 A 有 8 MB 线程 (指纹、SADP、WebSocket SSL、模拟对讲)，项目 B 最大仅 128 KB
    2. 项目 A 线程数量 (~140) 是项目 B (~40) 的 3.5 倍
    3. 项目 A 大量使用 1-2 MB 栈处理批量数据，项目 B 线程多为轻量事件循环
```

### 6.4 IPC 通信框架详解

> KV6 使用 **opdevsdk** 作为模块间通信基础设施，这是与项目 B（纯共享内存+信号量）
> 最大的架构差异。

#### 6.4.1 opdevsdk 架构

```
┌─────────────────────────────────────────────────────────────────┐
│                      opdevsdk IPC 框架                           │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  inproc (进程内 pub-sub 消息总线)                          │   │
│  │  ────────────────────────────────────────────────────── │   │
│  │                                                          │   │
│  │  pub_service_task ← 所有模块订阅，接收广播消息             │   │
│  │         │                                             │   │
│  │         ▼                                             │   │
│  │  消息分发 → 各订阅模块的回调函数                         │   │
│  │                                                          │   │
│  │  用途: 事件广播、状态通知、配置更新                       │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  IPC (跨进程 req-resp 通信)                               │   │
│  │  ────────────────────────────────────────────────────── │   │
│  │                                                          │   │
│  │  opdevsdk_ipc_server_start(IPC_HICORE_APPID,             │   │
│  │      IPC_HIK_MAIN_SERVICE, main_service_task)            │   │
│  │         │                                                │   │
│  │         ▼                                                │   │
│  │  main_service_task ← 接收所有请求，分发处理               │   │
│  │         │                                                │   │
│  │         └── 响应请求 ← 调用方阻塞等待                      │   │
│  │                                                          │   │
│  │  用途: 配置查询/修改、设备控制、权限校验                   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  消息队列 (Message Queue)                                 │   │
│  │  ────────────────────────────────────────────────────── │   │
│  │                                                          │   │
│  │  mqOpen / mqSend / mqReceive (基于 POSIX mq)              │   │
│  │                                                          │   │
│  │  用途: 刷卡事件、按键事件、异步数据传递                     │   │
│  │  示例: permission_mqsend_cardNo() → 权限校验线程           │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 6.4.2 IPC 通道定义

```
关键 IPC 通道常量 (栈大小定义):

  IPC_HDTASKCTRL        广播控制线程栈大小
  IPC_AUDIOPLAY         音频播放线程栈大小
  IPC_EXCEPTION         异常事件线程栈大小 (EXCEPTION_PRIO 线程)
  IPC_RTSPSERVER        RTSP 服务线程栈大小
  IPC_DVRNETSERV        SDK 网络服务线程栈大小
  IPC_VTALKSEND         对讲数据发送线程栈大小
  IPC_SDKEXCHANGE       SDK 交互线程栈大小
  IPC_ONVIFEVENT        ONVIF 事件线程栈大小
  IPC_ONVIFINIT         ONVIF 初始化线程栈大小
  IPC_ONVIFEXCEPT       ONVIF 异常线程栈大小
  IPC_ONVIFRYOPTASK     ONVIF 读写操作线程栈大小
  IPC_ONVIFMULTICAST    ONVIF 组播线程栈大小
  IPC_PREVCTRL          预览控制线程栈大小
  IPC_SRVCOM            网络服务通用线程栈大小
  IPC_SIPC_MEDIA_CTRL   SIP 媒体控制线程栈大小
  IPC_RTSPOVERHTTP      RTSP over HTTP 线程栈大小
  IPC_MONITORUSB        USB 监控线程栈大小
  IPC_FMATEXCH          格式化交互线程栈大小
  IPC_HIKSRITRANS       海康私有传输线程栈大小
  IPC_EVTTRIGCAP        事件触发抓拍线程栈大小
  IPC_TIMETRIGCAP       定时触发抓拍线程栈大小
  IPC_WIFICTRLTASK      WiFi 控制线程栈大小
  IPC_USRSUCURTY        用户安全线程栈大小
  IPC_MOTDECCTRL        移动检测线程栈大小
  IPC_ZEROCONFIG        零配置网络线程栈大小
  IPC_UPGRADHEART       升级心跳线程栈大小
```

#### 6.4.3 IPC 与线程创建的关系

```
初始化顺序 (严格依赖):

  usrAppEntry()
    │
    ├─ 1. opdevsdk_ipc_init()              ← 必须先初始化 IPC 框架
    │   └─ system_service_task 注册         ← 接收系统级消息
    │
    ├─ 2. opdevsdk_ipc_center_init()       ← 初始化 IPC 中心
    │   └─ pub_service_task 注册             ← 接收广播消息
    │
    ├─ 3. opdevsdk_ipc_server_start()      ← 注册 hicore 服务
    │   └─ main_service_task 注册            ← 处理 req-resp 请求
    │
    └─ 4. 各模块 startup()                 ← 之后才能创建业务线程
        │
        ├─ permission_check_module_startup()  ← 通过 IPC 查询权限
        ├─ event_ctrl_module_startup()        ← 通过 IPC 上报事件
        ├─ devmgmt_task_start()               ← 通过 IPC 管理设备
        └─ ...
```

**关键约束**: 所有业务线程的创建都依赖于 IPC 框架的初始化完成。
如果 IPC 初始化失败，`usrAppEntry()` 会重试（goto REINIT1）。

---

## 7. 业务初始化、系统初始化与线程创建的关系

### 7.1 三阶段初始化模型

KV6 的启动过程分为三个严格串行的阶段，**线程创建只发生在最后一个阶段**：

```
main()
  │
  ├─ 阶段 1: 平台基础初始化 (aip_base)
  │   文件: main.c → aip_base()
  │   耗时: ~100ms
  │   内容:
  │     ├── aip_service_start()
  │     │     ├── 硬件看门狗使能
  │     │     ├── 软件看门狗使能
  │     │     ├── 安全用户锁使能
  │     │     └── 安全事件回调注册 (aip_call_back)
  │     ├── 时间管理类型设置 (本地时间/UTC)
  │     └── 网络管理类型设置
  │   ★ 不涉及任何线程创建
  │
  ├─ 阶段 2: 系统级初始化 (user_sysinit)
  │   文件: main.c → user_sysinit()
  │   耗时: ~2-5s
  │   内容:
  │     ├── chdir("/home/app")
  │     ├── opdevsdk_hwif_basic_init()      ← 硬件接口层初始化
  │     ├── sysInit()                        ← boot param, CPLD info
  │     ├── openssl_init()                   ← 加密库初始化
  │     ├── init_store_encrypt_key()         ← 存储加密密钥
  │     ├── init_net_encrypt_key()           ← 网络加密密钥
  │     ├── sysglob_sem_init()               ← 全局信号量 (globalMSem, g_param_mutexsem, videoSignalSem)
  │     ├── generate_dev_capa()              ← 生成设备能力集
  │     ├── generate_default_capa()          ← 生成默认能力集
  │     ├── getDeviceCfgParams()             ← 加载设备配置
  │     ├── 老化测试标志判断
  │     ├── init_user_info_database()        ← SQLite 用户数据库
  │     ├── db_event_init_database()         ← SQLite 事件数据库
  │     ├── patch_dev_capa_from_config()     ← 从配置补丁能力
  │     ├── register_dataMng_shell()         ← 注册数据管理 shell
  │     ├── sys_generate_hard_info()         ← 生成硬件信息 (序列号)
  │     ├── hoi_close_key_lamp_flicker()     ← 关闭按键灯闪烁
  │     ├── setVSParams()                    ← 设置视频参数
  │     ├── create_passwd_file()             ← 创建密码文件
  │     ├── init_net_interface()             ← 初始化网络接口
  │     ├── time_init()                      ← 时间初始化
  │     ├── dsp_init()                       ← DSP 初始化 (音频编解码)
  │     ├── delUpgradeFile()                 ← 删除 OTA 升级残留文件
  │     └── heop_init()                      ← Android 开放平台初始化
  │   ★ 不涉及任何线程创建，但为线程创建准备所有前置条件
  │
  └─ 阶段 3: 应用业务初始化 (usrAppEntry)
      文件: mainCtrl/usrAppEntry.c
      耗时: ~5-10s
      内容:
        │
        ├─ [1] IPC 通信框架 (所有业务线程的前置依赖)
        │   ├── opdevsdk_ipc_init()           ← 初始化 inproc pub-sub
        │   ├── opdevsdk_ipc_center_init()    ← 初始化 IPC 中心
        │   ├── opdevsdk_ipc_server_start()   ← 注册 hicore 服务
        │   └── opdevsdk_inproc_sub()         ← 注册 pub-sub 订阅
        │
        ├─ [2] 内存与共享资源
        │   ├── alloc_share_memory()          ← 视频帧/JPEG 共享内存
        │   └── image_snapshot_pool_init()    ← 抓拍图像池
        │
        ├─ [3] 安全与权限
        │   ├── userSecurityInit()
        │   └── permission_check_module_startup()
        │         └─→ pthreadSpawn → permission_check_task (32 KB)
        │
        ├─ [4] 硬件相关 (条件性创建线程)
        │   ├── mcu_module_startup()
        │   │   └─→ pthreadSpawn → mcu_module_task (1 MB)
        │   ├── _usrMain_HAL_init()           ← HAL 设备注册 (非线程)
        │   ├── face_component_module_startup()
        │   │   ├─→ face_component_task (8 KB)
        │   │   ├─→ face_component_init (16 KB)
        │   │   └─→ face_component_rebuild_model (1 MB)
        │   ├── fingerprint_module_startup()
        │   │   └─→ pthreadSpawn → fingerprint_module_task (8 MB)
        │   └── security_module_startup()
        │         └─→ pthreadSpawn → security_module_process (64 KB)
        │
        ├─ [5] 音视频
        │   ├── ad_video_play_startup()
        │   ├── vis_audio_paly_module_startup()
        │   │   └─→ pthreadSpawn → vis_audio_play_task (IPC_AUDIOPLAY)
        │   └── init_preview()
        │
        ├─ [6] 网络服务 (大量线程创建)
        │   ├── dvrnet_server_module_startup()
        │   │   └─→ pthreadSpawn → dvrNetServer (NET_SERVER_PRIO/80)
        │   ├── dvrnet_tls_server_module_startup()
        │   │   └─→ pthreadSpawn → netsdk_tls_server_proc (NET_SERVER_PRIO/80)
        │   ├── visnet_server_module_startup()
        │   │   └─→ pthreadSpawn → visNetServer (NET_SERVER_PRIO/80)
        │   ├── net_broken_server_module_startup()
        │   │   └─→ pthreadSpawn → netBrokenDataRecvServerTask (32 KB)
        │   ├── rtsp_server_module_startup()
        │   │   └─→ pthreadSpawn → start_rtsp_server (RTSP_PRIO/60)
        │   ├── rtsp_client_module_startup()
        │   ├── start_sadp_server/client()
        │   │   └─→ pthreadSpawn → sadp_client_proc (8 MB)
        │   ├── onvif_module_startup()
        │   │   └─→ 多个 ONVIF 线程 (ONVIFEVENT_PRIO/80, COMMON_PRIO/50)
        │   ├── exosipcIf_init()              ← SIP 客户端初始化
        │   ├── ysip_server_process_startup() ← SIP 服务器
        │   ├── init_websocket_server()
        │   │   └─→ pthreadSpawn → ws_server (8 MB) + ws_session_task (2 MB) + ws_ssl_server (8 MB)
        │   └── cstorComStart()
        │         └─→ pthreadSpawn → cstorComTask (128 KB)
        │
        ├─ [7] 业务模块
        │   ├── event_ctrl_module_startup()
        │   │   ├─→ pthreadSpawn → eventCtrl_task (EXCEPTION_PRIO/60)
        │   │   └─→ pthreadSpawn → event_delete_task (EXCEPTION_PRIO/60)
        │   ├── async_import_init()
        │   │   └─→ pthreadSpawn → async_import_data_mng_task (1 MB)
        │   ├── person_verify_init()
        │   ├── devmgmt_task_start()
        │   ├── session_manage_startup()
        │   ├── alarm_probe_module_startup()
        │   │   └─→ pthreadSpawn → alarm_ctrl_task + alarmIn_probe_task
        │   ├── key_business_module_startup()
        │   │   └─→ pthreadSpawn → key_business_task_mode_* (32 KB)
        │   ├── analog_handle_main_setup()
        │   │   ├─→ pthreadSpawn → recv_rs485_cmd_task (8 MB)
        │   │   ├─→ pthreadSpawn → analog_cmd_handle_task (8 MB)
        │   │   └─→ pthreadSpawn → analog_session_ctrl_task (8 MB)
        │   ├── alarm_voice_module_startup()
        │   ├── real_time_broadcast_init()
        │   │   └─→ pthreadSpawn → unicast/multicast/broadcast_task (HD_CTRL_PRIO/70)
        │   ├── rb_com_module_startup()
        │   │   └─→ pthreadSpawn → pt_module_task + rb_com_module_task (64 KB)
        │   ├── rtp_pager_multicast_init()
        │   ├── motion_detection_module_startup()
        │   │   └─→ pthreadSpawn → motDetCtrlTask (EXCEPTION_PRIO/60)
        │   ├── NPQ_Process_start()
        │   │   └─→ pthreadSpawn → NPQ_Manage_Task (16 KB)
        │   ├── init_webserver()
        │   └── init_stor_system()
        │         └─→ 多个存储线程 (streamRecord/recordSchedule/hdTaskCtrl 等)
        │
        └─ [8] 收尾
            ├── dai_light_init()
            ├── system("echo 3 > /proc/sys/vm/drop_caches")  ← 释放内存
            ├── SLEEP_SEC(30)
            ├── bDevAppStarted = TRUE    ← ★ 系统就绪标志
            ├── initPPP()
            ├── net_connect_process()
            └── net_switch_notify_proc()
```

### 7.2 初始化依赖关系图

```
  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
  │  阶段 1       │     │  阶段 2       │     │  阶段 3       │
  │  aip_base    │────▶│  user_sysinit │────▶│  usrAppEntry │
  └──────────────┘     └──────────────┘     └──────┬───────┘
                                                   │
                    ┌──────────────────────────────┼──────────────────────────────┐
                    │                              │                              │
                    ▼                              ▼                              ▼
            ┌───────────────┐            ┌─────────────────┐            ┌───────────────┐
            │  硬件就绪      │            │  数据就绪        │            │  线程创建     │
            │               │            │                 │            │               │
            │  GPIO/I2C/SPI │            │  SQLite 数据库   │            │  IPC 框架     │
            │  摄像头/DSP   │            │  Flash 配置加载  │            │  共享内存     │
            │  网络接口     │            │  设备能力集      │            │  业务线程     │
            │  加密库       │            │  密码文件        │            │  系统就绪     │
            └───────────────┘            └─────────────────┘            └───────────────┘
```

### 7.3 关键依赖关系

| 前置条件 | 依赖的线程创建 | 说明 |
|---------|--------------|------|
| `opdevsdk_ipc_init()` 成功 | **所有** 模块 startup | IPC 框架是模块间通信的基础，失败则重试 |
| `generate_dev_capa()` 完成 | `face_component_module_startup` 等条件线程 | 能力检测决定哪些线程需要创建 |
| `dsp_init()` 完成 | `vis_audio_play_task`、`init_preview` | DSP 未就绪无法处理音视频 |
| `init_user_info_database()` 完成 | `permission_check_task` | 权限校验需要查询用户数据库 |
| `init_net_interface()` 完成 | `dvrNetServer`、`visNetServer`、`sadp_client` | 网络接口未就绪无法监听端口 |
| `alloc_share_memory()` 完成 | `streamRecord`、`vis_audio_play_task` | 音视频线程需要共享内存缓冲区 |

---

## 8. 模块间线程协作关系

### 8.1 对讲呼叫流程（跨模块线程协作）

```
信令控制层              媒体处理层              事件/联动层
────────────────      ──────────────         ──────────────

ysip_server (netConn)
    │  SIP 信令接收/发送
    ▼
exosipcIf_init (netConn/sip)
    │  eXosip SIP 协议栈
    ├──▶ talkback_rules_module_init (intercomSystem)
    │     └── 加载对讲规则/预案/号码规则
    │
    ▼
analog_handle_main_setup (intercomSystem/analog)
    │  模拟对讲主流程
    ├── recv_rs485_cmd_task (8 MB, COMMON_PRIO)
    │     └── RS485 命令接收循环
    ├── analog_cmd_handle_task (8 MB, COMMON_PRIO)
    │     └── RS485 命令解析与分发
    └── analog_session_ctrl_task (8 MB, COMMON_PRIO)
          └── 对讲会话生命周期管理
               │
               ▼
        start_rtspc_interface (UPGRADE_PRIO/60, 2 MB)
              └── RTSP 客户端建立媒体流
               │
               ▼
        vis_audio_play_task (AUDIOSEND_PRIO/70, IPC_AUDIOPLAY)
              └── 音频解码与播放
               │
               ▼
        unicast_task / multicast_task / broadcast_task (HD_CTRL_PRIO/70)
              └── 实时广播控制
               │
               ▼
        rtp_pager_multicast_task (HD_CTRL_PRIO/70)
              └── RTP 广播寻呼

联动协作:
  eventCtrl_task (EXCEPTION_PRIO/60)
    └── 呼叫事件记录 → 写入事件数据库
  alarm_ctrl_task (EXCEPTION_PRIO/60)
    └── 报警联动 → 触发录像/截图
  permission_check_task (COMMON_PRIO/50)
    └── 呼叫权限校验 → 验证访客权限
  dc_task (COMMON_PRIO/50, 32 KB)
    └── 门锁控制 → 开门执行
```

### 8.2 门禁刷卡流程

```
硬件层                    DAL 层                    业务层
──────────              ──────────                ──────────

IC卡/指纹/密码/身份证
    │
    ▼
cdrd_kernel_task (HAL/DAL/card_reader)
    │
    ├── dc_task (门锁控制, 32 KB)          ← 开锁执行
    ├── dal_kbd_task (键盘, 32 KB)         ← 密码输入
    ├── fingerprint_module_task (8 MB)     ← 指纹匹配
    └── illm_task (光照检测)               ← 环境感知
         │
         ▼
permission_check_task (accessControl, 32 KB)
    │
    ├── 权限校验 (authInfoRightPlan)
    │     ├── 卡号匹配
    │     ├── 时间方案匹配
    │     └── 权限方案匹配
    │
    ├── async_import_data_mng_task (1 MB)  ← 权限数据异步导入
    │
    ▼
eventCtrl_task (EXCEPTION_PRIO/60)         ← 事件记录
    │
    ├── event_arming_sdk_upload_task       ← SDK 通道上传
    ├── event_arming_isapi_upload_task     ← ISAPI 通道上传
    ├── event_ezviz_alarm_upload_task      ← 萤石通道上传
    └── event_isup_upload_task             ← Ehome 通道上传
```

### 8.3 视频流数据流

```
DSP 编码                 预览组件                网络分发
──────────              ──────────              ──────────

dsp_callback.c
    │
    ▼
init_preview_component()
    │
    ├── 主码流 ─▶ streamRecord (STOR_STREAM_RECORD_PRIO, 256 KB/通道)
    │              │
    │              └▶ hdTaskCtrl (STOR_HD_CTRL_PRIO, 512 KB) ─▶ SATA/SD 存储
    │
    ├── 子码流 ─▶ dvrNetServer (NET_SERVER_PRIO/80) ─▶ SDK 客户端
    │              │
    │              ├── start_rtsp_server (RTSP_PRIO/60) ─▶ RTSP 客户端
    │              │
    │              ├── ws_preview_stream_task (50, 1 MB) ─▶ WebSocket 浏览器
    │              │
    │              └── isapi_http_jpeg_preview (60, 8 KB) ─▶ ISAPI 预览
    │
    └── JPEG 抓拍 ─▶ event_trigger_cappic / timing_trigger_cappic (COMMON_PRIO/50)
```

### 8.4 存储管理流程

```
存储管理线程                设备控制线程             文件系统
─────────────             ──────────────           ──────────

recordSchedule (512 KB)    hdTaskCtrl (512 KB)       stor_record_file_system
    │                        │                          │
    │                        ├── hdFlushTask (512 KB)   ├── hd_clone_read (128 KB)
    │                        │                          └── hd_clone_write (128 KB)
    ▼                        │
streamRecord (256 KB         sdTaskCtrl (128 KB)         formatTask (128 KB)
 /通道)                       │                          │
    │                        ├── sataTaskCtrl (128 KB)   └── stor_set_init_fat32_percent (4 KB)
    │                        │                          │
    ▼                        └── stor_bad_blocks_detect (256 KB)
orm_del_overdue_video        │
(512 KB)                      record_wakeup_hd (2 KB)
                             │
                             └── search_ctrl_task (256 KB) ← 搜索回放
```

### 8.5 事件处理流程

```
硬件中断/事件           alarmInCtrlTask          各联动动作
(serial/mcu)       ←→  (misc/alarmCtrl)    ←→    录像/截图/弹窗/上传
    │                       │
    ▼                       ▼
mcu_process_task      fingerprint_module_task
(mcu/mcu_main)        (HAL/DAL/fingerprint)
                            │
                            ▼
                     eventCtrl_task (EXCEPTION_PRIO/60)
                            │
                            ├── 事件入库 (dataMng/database)
                            ├── 事件上传 (SDK/ISAPI/萤石/Ehome)
                            └── 联动动作 (door_ctrl/vis_audio/led)
```

---

> 文档生成时间: 2026-08-06
> 分析版本: V3.14.0


