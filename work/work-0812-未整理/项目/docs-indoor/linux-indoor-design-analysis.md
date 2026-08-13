# Linux Indoor Baseline 系统架构分析

> 项目：海康威视可视门铃/室内基站系统（hicore）
> 平台：HI3531 等多平台（B1pro/B2/B2pro/B3pro/B4/R0/F4）
> 语言：C/C++，多线程嵌入式 Linux 应用

---

## 目录

1. [入口与启动流程](#1-入口与启动流程)
2. [整体架构](#2-整体架构)
3. [线程与模块映射](#3-线程与模块映射)
4. [各目录/文件作用](#4-各目录文件作用)
5. [数据流图](#5-数据流图)
6. [分层控制流图](#6-分层控制流图)

---

## 1. 入口与启动流程

### 1.1 程序入口

**入口文件**: `APPS/system/init/dvr.c` → `main()`

程序名为 `hicore`（根据平台不同有 `hicore_8M`、`hicore_16M`、`hicore_1024_600` 等变体）。

### 1.2 main() 启动流程（2179 行）

```
main()
│
├─ 1. 信号与进程初始化
│   ├─ analysis_custom_info()          // 分析自定义信息
│   ├─ initEtherIf()                   // 初始化网卡（非调试模式）
│   ├─ sysInit()                        // 系统初始化
│   ├─ abi_device_ability_init()        // 初始化设备能力 ABI
│   ├─ 时间校验与设置                   // devBootTime, RTC
│   ├─ ddm_open_common_fd()            // 打开公共文件描述符
│   ├─ signalIgnored()                  // 忽略 SIGPIPE 等信号
│   ├─ g_pid = getpid()
│   ├─ heap_init()                      // 堆初始化
│   ├─ sysWdInit()                      // 硬件看门狗
│   └─ util_timer_init()                // 定时器初始化
│
├─ 2. 存储与升级
│   └─ autoUpgradeProcess()            // U盘/TF卡自动升级
│
├─ 3. 编码器与通道初始化
│   ├─ getEncodeChans()                // 获取编码通道数
│   ├─ security_resource_init()        // 安全资源初始化
│   ├─ getDeviceCfgParams()            // 获取设备配置参数
│   ├─ abi_set_alarm()                 // 报警设置
│   ├─ init_the_multi_lang_audio()     // 多语言音频初始化
│   ├─ generate_key()                  // 生成密钥
│   ├─ dpi_init_db()                   // 数据库初始化
│   ├─ sys_passwd_set("root")          // root 密码设置
│   ├─ init_dsp_if()                   // DSP 接口初始化
│   ├─ 音频音量设置                    // setAoVolume, setAiVolume
│   ├─ adjustSysDateFromRTC()          // 从 RTC 调整系统时间
│   ├─ initRs485MSem()                // RS485 信号量
│   ├─ openPreview()                   // 打开预览（HI_3520A）
│   ├─ initDhcpCtrl()                  // DHCP 控制
│   ├─ aip_base()                       // IPv6 初始化
│   ├─ initNetIf()                      // 网络接口初始化
│   ├─ userSecurityInit()              // 用户安全初始化
│   ├─ dvrLogLibInit()                 // 日志库初始化
│   ├─ syslog_upload()                 // 系统日志上传
│   ├─ initEncodeChan()                // 初始化所有编码通道
│   ├─ initIPCamera()                   // 初始化 IPC 资源
│   ├─ image_initPool()                // 图像池初始化
│   ├─ delFile()                       // 删除临时文件
│   ├─ flashWriteParamServer()         // Flash 参数写入
│   └─ init_en_scene_database()        // 场景数据库初始化
│
├─ 4. 线程创建（核心服务）
│   ├─ wifi_adjust_reminder()          // WiFi 调整提醒
│   ├─ adjustTimeTask()                // 时间校准任务
│   ├─ alarmInCtrlTask()               // 报警输入控制
│   ├─ SSL_library_init()              // SSL 初始化
│   ├─ init_genarate_cert()            // 证书生成
│   ├─ sip_server_start()              // SIP 服务器（可视对讲）
│   ├─ talkBackExtensionPro()          // 对讲分机处理
│   ├─ eXosip_client_task()            // eXosip 客户端
│   ├─ sqliteOpTask()                  // SQLite 操作任务
│   ├─ ipDADTask()                     // IP 冲突检测
│   ├─ dvrNetServer()                  // 网络 SDK 服务器（x2 TLS/非 TLS）
│   ├─ netsdk_link_limit_task()        // SDK 连接限制
│   ├─ NPQ_Process_start() / set_local_ssrc()  // QoS
│   ├─ web_service_init()              // Web 服务 (appweb)
│   ├─ visNetServer()                  // VIS 网络服务器
│   ├─ startSntpClient()               // SNTP 客户端
│   ├─ agingForNoGui()                 // 无 GUI 老化测试
│   ├─ startEncodeChan()               // 启动所有编码通道
│   ├─ initWifi()                      // WiFi 初始化
│   ├─ APP_GuiMain()                   // GUI 主线程（SUPPORT_GUI）
│   ├─ start_sadp_server()             // SADP 设备发现
│   ├─ stor_AudioPicProcTask()         // 音频/图片处理
│   ├─ cmd_server_init()               // 命令服务器（RS485/RS232）
│   ├─ rest_srv_recover_space_task()   // REST 空间恢复
│   ├─ watchdogTask()                  // 软件看门狗
│   ├─ app_register_ezviz_info()       // 蛋石信息注册
│   ├─ ip_filter_connlimit_init()       // IPTABLES 过滤
│   ├─ setBlockWhiteListIPTablesRules() // IP 白/黑名单
│   ├─ rtsps_module_init()             // RTSP 服务器
│   ├─ talkBackVideoProcess()          // 对讲视频处理
│   ├─ talkBackDevInputTask()          // 对讲设备输入
│   ├─ talkBackCvbsInputTask()         // 模拟对讲 CVBS 输入
│   ├─ talkBackCvbsManageTask()        // 模拟对讲 CVBS 管理
│   ├─ sdkUploadTask()                 // SDK 上传任务
│   ├─ talkBackIoOutEventTask()        // 对讲 IO 输出事件
│   ├─ talkBackRoomIoInEventTask()     // 对讲房间 IO 输入事件
│   ├─ talkBackRtpTask()               // RTP 对讲任务
│   ├─ zigbeeDeviceStartProcTask()     // Zigbee 设备处理
│   ├─ smarthome_coo_upgrade()         // 智能家居升级
│   ├─ sub1gDeviceStartProcTask()       // Sub-1G 设备处理
│   ├─ isapi_start_web_server()        // ISAPI Web 服务器
│   ├─ door_visitor_task_init()        // 访客任务
│   ├─ http_client_start()             // HTTP 客户端
│   ├─ porchSendStart()                // 门铃发送
│   ├─ net_dvr_device_manager_proc_task_init() // 设备管理
│   ├─ storage_register_info()         // 存储注册
│   └─ checkMemLeakByThread/Malloc()   // 内存泄漏检测
│
└─ 5. 主循环
    └─ while(1) { pause(); }           // 挂起等待信号
```

### 1.3 GUI 入口

**入口文件**: `APPS/gui/guiApp/netraApp/src/main.c` → `initMenuMain()`

```
initMenuMain()
├─ initDeepHomeBkgRes()              // 初始化深色调背景资源
├─ InitGUI() / InitGUIWithoutWin()   // 初始化 GUI 引擎（MGUI）
├─ delGuiFile()                      // 删除内存中 UI 资源（节省内存）
├─ killShowLogo()                    // 杀除 showlogo 进程
├─ init_utf8_logfont()               // 初始化 UTF-8 字体
├─ interface_set_menuReadyFlg()      // 设置菜单就绪标志
├─ CreateMainWindow()                // 创建主窗口
├─ RegisterKeyMsgHook()              // 注册按键消息钩子
├─ RegisterMouseMsgHook()            // 注册鼠标消息钩子
└─ while(GetMessage) {              // 消息循环
       TranslateMessage
       DispatchMessage
    }
```

---

## 2. 整体架构

### 2.1 架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│                      hicore (主进程)                              │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   GUI 层      │  │  事件层       │  │    网络服务层         │  │
│  │ (MGUI 框架)   │  │              │  │                      │  │
│  │ - 主窗口消息   │  │ - 报警控制    │  │ - SIP 对讲服务器     │  │
│  │ - 菜单导航     │  │ - 交互控制    │  │ - RTSP 服务器        │  │
│  │ - 页面渲染     │  │ - 异常控制    │  │ - HTTP/Web 服务      │  │
│  │ - 设备管理UI   │  │ - IO 事件     │  │ - SDK 网络服务       │  │
│  └──────┬───────┘  │ - 门铃事件    │  │ - SADP 发现          │  │
│         │          │ - Sub-1G      │  │ - SNTP               │  │
│         │          │ - Zigbee      │  │ - ONVIF              │  │
│         │          │ - WiFi        │  │ - eXosip (SIP 协议)  │  │
│         │          └──────┬───────┘  │ - EZVIZ 协议         │  │
│         │                 │          └──────────┬───────────┘  │
│         │                 │                     │              │
│  ┌──────▼───────┐  ┌──────▼───────┐  ┌─────────▼───────────┐  │
│  │  接口层       │  │  数据处理层   │  │    ABI 能力层        │  │
│  │              │  │              │  │                      │  │
│  │ - DSP 接口   │  │ - 预览       │  │ - 设备能力查询       │  │
│  │ - GUI 接口   │  │ - 回放       │  │ - 编解码能力         │  │
│  │ - Kernel 接口│  │ - 流接收     │  │ - 平台差异化         │  │
│  │              │  │ - 流转换     │  │ - 功能开关           │  │
│  └──────┬───────┘  │ - 流分析     │  └─────────┬───────────┘  │
│         │          │ - 图像管理   │             │              │
│         │          └──────┬───────┘             │              │
│         │                 │                     │              │
│  ┌──────▼─────────────────▼─────────────────────▼───────────┐  │
│  │              系统基础层                                     │  │
│  │                                                            │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │  │
│  │  │ 串口通信  │ │ 存储管理  │ │ 数据库    │ │ 系统初始化    │  │  │
│  │  │ RS232/   │ │ - 硬盘管理│ │ - SQLite  │ │ - 参数管理    │  │  │
│  │  │ RS485/   │ │ - SD卡   │ │ - Flash   │ │ - 升级管理    │  │  │
│  │  │ T1/MCU   │ │ - ANR    │ │          │ │ - 看门狗      │  │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │  │
│  │                                                            │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │  │
│  │  │ 工具库    │ │ 加密安全  │ │ 调试日志  │ │ 系统服务      │  │  │
│  │  │ - cjson  │ │ - SSL/TLS │ │ - dvrLog  │ │ - DHCP       │  │  │
│  │  │ - deelx  │ │ - 数据库  │ │          │ │ - SNTP       │  │  │
│  │  │ - wrapper│ │ - 加密    │ │          │ │ - 用户管理    │  │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │              平台 BSP 层 (VIS_PLATFORM)                      │  │
│  │  DSP SDK / 驱动 / 硬件抽象 / 各平台库                        │  │
│  └────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 关键架构特征

| 特征 | 说明 |
|------|------|
| **单进程多线程** | 所有功能以线程形式运行在 hicore 单进程内，通过 pthread 管理 |
| **ABI 能力抽象** | 通过 `abi_ability` 层屏蔽平台差异（B1pro/B2/B3pro/B4/R0/F4） |
| **条件编译** | 大量 `#ifdef` 控制功能开关（WiFi、GUI、SADP、EZVIZ 等） |
| **MGUI 框架** | 自研 GUI 框架，基于消息循环模式 |
| **SIP 对讲** | 基于 eXosip2 实现可视对讲协议栈 |
| **DSP 编码** | 海思 HI3531 等平台的 DSP 硬件编码 |
| **SQLite 配置** | 配置数据存储在 SQLite 数据库中 |

### 2.3 线程与模块映射

主进程 `hicore` 采用**单进程多线程**模型，所有功能以 pthread 线程形式运行。
下表将 `main()` 中创建的所有线程按模块归类，帮助理解代码架构。

#### 2.3.1 线程-模块映射表

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    线程 ↔ 模块映射总览                                          │
│                                                                              │
│  优先级            线程名              模块/目录                    功能       │
│  ───────         ─────────────────  ───────────────────────      ────────  │
│                                                                              │
│  ┌─ 网络服务层 (net/) ──────────────────────────────────────────────┐        │
│  │ NET_SERVER_PRIO  dvrNetServer      net/sdkService/              SDK 网络服务 │
│  │                  (×2: TLS/非TLS)    dvrNetServer()               远程客户端   │
│  │                                    连接接入与协议处理              接入/配置    │
│  │ NET_SERVER_PRIO  visNetServer      net/vis/                     VIS 协议服务  │
│  │ NET_SERVER_PRIO  eXosip_client_task net/sipClient/ 或 net/ezviz/ SIP 客户端   │
│  │                                    eXosip2 协议栈                SIP INVITE/  │
│  │                                    消息处理                    注册/消息收发    │
│  │ NET_SERVER_PRIO  sip_server_start  net/sipServer/              SIP 服务器      │
│  │                                    sip_server.c                接听/挂断控制    │
│  │ NET_SERVER_PRIO  talkBackExtensionPro net/sipServer/            SIP 分机处理   │
│  │ NET_SERVER_PRIO  netsdk_link_limit_task net/sdkService/         SDK 连接限制   │
│  │                  NPQ_Process_start  net/                       QoS 流量整形    │
│  │                  set_local_ssrc                                              │
│  │ TIMING_PRIO      ipDADTask         net/                         IP 冲突检测    │
│  └──────────────────────────────────────────────────────────────────┘        │
│                                                                              │
│  ┌─ Web / 云服务 ───────────────────────────────────────────────────┐       │
│  │ COMMON_PRIO      web_service_init  net/webServiceMng/            Web 服务器  │
│  │                  (appweb)          web_service.c                 REST API   │
│  │ COMMON_PRIO      isapi_start_web_server net/nui/restSrv/isapi/  ISAPI 协议   │
│  │ COMMON_PRIO      start_sadp_server net/netService/sadpLib/      SADP 设备发现 │
│  │                  door_visitor_task_init net/ezviz/               蛋石访客服务  │
│  └──────────────────────────────────────────────────────────────────┘        │
│                                                                              │
│  ┌─ 对讲 / SIP 媒体 ────────────────────────────────────────────────┐       │
│  │ COMMON_PRIO      talkBackVideoProcess event/alarmCtrl/          对讲视频处理 │
│  │                  talkBackDevInputTask  音频采集与编码              麦克风输入  │
│  │ COMMON_PRIO      talkBackIoOutEventTask event/ioEvent/           对讲 IO 输出 │
│  │ COMMON_PRIO      talkBackRoomIoInEventTask event/ioEvent/        房间 IO 输入 │
│  │ COMMON_PRIO      talkBackCvbsInputTask event/alarmCtrl/          模拟输入    │
│  │                  talkBackCvbsManageTask event/alarmCtrl/          模拟管理    │
│  │ COMMON_PRIO      talkBackRtpTask      net/netService/rtpSession/ RTP 媒体传输 │
│  │                  (128KB 栈)           talkBackRtpSession.c       VoIP 语音    │
│  └──────────────────────────────────────────────────────────────────┘        │
│                                                                              │
│  ┌─ 事件 / 外设层 (event/) ─────────────────────────────────────────┐       │
│  │ COMMON_PRIO      alarmInCtrlTask   event/alarmCtrl/              报警输入控制 │
│  │                  (EXCEPTION_PRIO)   alarmCtrl.c                   优先级最高  │
│  │ TIMING_PRIO      wifi_adjust_reminder event/wifi/wifiLib/        WiFi 调整提醒 │
│  │ COMMON_PRIO      initWifi          event/wifi/wifiLib/           WiFi 连接管理 │
│  │ COMMON_PRIO      zigbeeDeviceStartProcTask event/zigbee/         Zigbee 设备  │
│  │                  smarthome_coo_upgrade dataManagement/smarthome/ Zigbee 升级   │
│  │ COMMON_PRIO      sub1gDeviceStartProcTask event/sub1g/           Sub-1G 射频   │
│  │ COMMON_PRIO      mcu_process_task   serial/mcu/                  MCU 通信     │
│  └──────────────────────────────────────────────────────────────────┘        │
│                                                                              │
│  ┌─ 数据存储层 (dataManagement/) ───────────────────────────────────┐       │
│  │ COMMON_PRIO      sqliteOpTask      dataManagement/database/      SQLite 操作 │
│  │                  stor_AudioPicProcTask dataManagement/audio/     音频/图片处理 │
│  │                  rest_srv_recover_space_task net/nui/restSrv/   REST 空间恢复 │
│  │                  storage_register_info dataManagement/storMgmt/ 存储注册信息   │
│  └──────────────────────────────────────────────────────────────────┘        │
│                                                                              │
│  ┌─ 数据处理层 (dataApplication/) ──────────────────────────────────┐       │
│  │ COMMON_PRIO      startEncodeChan   dataApplication/preview/      启动编码通道 │
│  │                  (实为函数而非线程)   initEncodeChan()             配置 DSP 编码 │
│  │                  sdkUploadTask      net/sdkService/              SDK 录像上传   │
│  └──────────────────────────────────────────────────────────────────┘        │
│                                                                              │
│  ┌─ 串口 / 通信 (serial/) ──────────────────────────────────────────┐       │
│  │ COMMON_PRIO      cmd_server_init   serial/shellCmd/              RS485/RS232 │
│  │                  命令服务           shellCmd.c                     串口命令解析 │
│  └──────────────────────────────────────────────────────────────────┘        │
│                                                                              │
│  ┌─ 系统服务 ───────────────────────────────────────────────────────┐       │
│  │ COMMON_PRIO      startSntpClient   net/netService/sntpLib/      SNTP 时间同步 │
│  │ COMMON_PRIO      agingForNoGui     system/                       无 GUI 老化   │
│  │                  测试              agingTest.c                   工厂老化测试   │
│  │ SW_WATCHDOG_PRIO watchdogTask      system/watchdog/             软件看门狗     │
│  │ TIMING_PRIO      adjustTimeTask    system/clock/                时间校准任务   │
│  │ COMMON_PRIO      http_client_start net/netService/httpClient/  HTTP 客户端     │
│  │ COMMON_PRIO      net_dvr_device_manager_proc_task_init net/sdkService/ 设备管理 │
│  │ COMMON_PRIO      porchSendStart    event/porchEvent/            门铃发送       │
│  │ COMMON_PRIO      app_register_ezviz_info net/ezviz/            蛋石信息注册   │
│  └──────────────────────────────────────────────────────────────────┘        │
│                                                                              │
│  ┌─ 调试 / 辅助 ────────────────────────────────────────────────────┐       │
│  │ CHECK_MEM    checkMemLeakByThread   system/checkMemInfo/       内存泄漏检测 │
│  │                  checkMemLeakByMallocNum system/checkMemInfo/  分配点追踪     │
│  └──────────────────────────────────────────────────────────────────┘        │
│                                                                              │
│  ┌─ GUI 层 (gui/) ──────────────────────────────────────────────────┐       │
│  │ MENU_PRIO      APP_GuiMain       gui/guiApp/netraApp/           GUI 主线程 │
│  │                  (64MB 栈)        main.c + gui_*.c (~260页面)    消息循环    │
│  └──────────────────────────────────────────────────────────────────┘        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

#### 2.3.2 线程优先级分层

```
优先级从高到低（共 6 级）:

  EXCEPTION_PRIO   ← 最高
    └── alarmInCtrlTask (报警输入)
         └── 必须在异常时第一时间响应

  COMMON_PRIO
    ├── mcu_process_task          (MCU 串口通信)
    ├── startEncodeChan           (视频编码启动)
    ├── stor_AudioPicProcTask     (音频/图片处理)
    ├── sdkUploadTask             (SDK 录像上传)
    ├── talkBackIoOutEventTask    (对讲 IO 输出)
    ├── talkBackRoomIoInEventTask (房间 IO 输入)
    ├── sip_server_start          (SIP 服务器)
    ├── talkBackExtensionPro      (对讲分机)
    ├── talkBackVideoProcess      (对讲视频处理)
    ├── talkBackDevInputTask      (对讲设备输入)
    ├── talkBackCvbsInputTask     (模拟 CVBS 输入)
    ├── talkBackCvbsManageTask    (模拟 CVBS 管理)
    ├── eXosip_client_task       (SIP 客户端)
    ├── sqliteOpTask             (SQLite 操作)
    ├── zigbeeDeviceStartProcTask (Zigbee 设备)
    ├── sub1gDeviceStartProcTask  (Sub-1G 设备)
    ├── rest_srv_recover_space_task (REST 空间恢复)
    ├── cmd_server_init          (串口命令服务)
    ├── checkMemLeakByThread     (内存检测)
    └── checkMemLeakByMallocNum  (内存检测)

  NET_SERVER_PRIO
    ├── dvrNetServer (×2: TLS/非TLS)  (SDK 网络服务)
    ├── visNetServer                   (VIS 协议服务)
    └── netsdk_link_limit_task        (连接数限制)

  TIMING_PRIO
    ├── wifi_adjust_reminder           (WiFi 调整提醒)
    ├── adjustTimeTask                 (时间校准)
    └── ipDADTask                     (IP 冲突检测)

  SW_WATCHDOG_PRIO
    └── watchdogTask                   (软件看门狗)

  MENU_PRIO  ← 最低（但栈最大 64MB）
    └── APP_GuiMain                   (GUI 主线程)
```

#### 2.3.3 模块间线程协作关系

```
对讲呼叫流程（跨模块线程协作）:

  信令控制                 媒体处理                事件响应
  ─────────                ─────────             ─────────
  sip_server_start    ←→  talkBackVideoProcess  ←→  talkBackIoOutEventTask
  (net/sipServer)            │                        (event/ioEvent)
       │                      ▼
       │              talkBackDevInputTask      ←→  talkBackRoomIoInEventTask
       │              (event/alarmCtrl)               (event/ioEvent)
       │                      │
       │                      ▼
       │              talkBackCvbsInputTask   ←→  talkBackCvbsManageTask
       │              (event/alarmCtrl)              (event/alarmCtrl)
       │                      │
       │                      ▼
  eXosip_client_task     talkBackRtpTask        (仅模拟对讲)
  (net/sipClient)           │
       │              (net/rtpSession)
       │                      │
       ▼                      ▼
  云端/SIP 服务器      G711/AAC 编码 → RTP 网络发送

存储管理流程:

  stor_AudioPicProcTask  ←── 接收对讲录音/截图
       │
       ▼
  storage_register_info  ←── 注册到存储管理
       │
       ▼
  dataManagement/storManagement  ←── 写入硬盘/SD卡

事件处理流程:

  硬件中断/串口          alarmInCtrlTask        各联动动作
  (serial/mcu)      ←→  (event/alarmCtrl)  ←→  录像/截图/弹窗/上传
       │                      │
       ▼                      ▼
  mcu_process_task    zigbeeDeviceStartProcTask
  (serial/mcu)        sub1gDeviceStartProcTask
                      (event/zigbee/sub1g)
```

#### 2.3.4 线程创建条件编译汇总

很多线程受 `#ifdef` 条件编译控制，不同平台/配置启动的线程不同：

| 条件宏 | 线程/服务 | 说明 |
|--------|----------|------|
| `SUPPORT_DOORPHONE` | `mcu_process_task` | 门铃 MCU 通信 |
| `SUPPORT_IPV6` | `aip_base()` | IPv6 网络初始化 |
| `VIS_VILLA_ADJUST_WIFI` | `wifi_adjust_reminder` | WiFi 调整提醒 |
| `SUPPORT_WEBSERVER` | `web_service_init`, `isapi_start_web_server` | Web 服务 |
| `SUPPORT_GUI` | `APP_GuiMain` | GUI 主线程 |
| `SUPPORT_SADP_COMPONENT` / `SUPPORT_SADP` | `start_sadp_server` | SADP 设备发现 |
| `_SUPPORT_RTSP_SERVER` | `rtsps_module_init` | RTSP 服务器 |
| `SUPPORT_WIFI` | `initWifi` | WiFi 管理 |
| `SUPPORT_VOIP` | `talkBackRtpTask` | VoIP 语音会话 |
| `SUPPORT_SMARTHOME` | `zigbeeDeviceStartProcTask`, `smarthome_coo_upgrade` | Zigbee 智能家居 |
| `SUPPORT_SUB1G` | `sub1gDeviceStartProcTask` | Sub-1G 射频通信 |
| `SUPPORT_EZVIZ_PROTOCOL` | `app_register_ezviz_info`, `door_visitor_task_init` | 蛋石云平台 |
| `SUPPORT_HTTP_CLIENT` | `http_client_start` | HTTP 客户端 |
| `SUPPORT_VIDEO_RECORD` | `porchSendStart`, `net_dvr_device_manager_proc_task_init` | 录像功能 |
| `SUPPORT_NPQ` / `SUPPORT_QOS` | `NPQ_Process_start` / `set_local_ssrc` | QoS |
| `SUPPORT_IPTABLES` | `ip_filter_connlimit_init` | 防火墙规则 |
| `CHECK_MEMINFO` | `checkMemLeakByThread`, `checkMemLeakByMallocNum` | 内存泄漏检测 |
| `RESOLUTION_480_272` | (影响 GUI 和多语言初始化) | 分辨率适配 |
| `HI_3520A` | `openPreview()` | 预览通道 |

#### 2.3.5 线程栈空间分配

```
线程栈大小一览:

  128 KB  ─── talkBackRtpTask          (VoIP RTP 媒体，栈最大)
  64 KB   ─── APP_GuiMain              (GUI 主线程)
            ├── smarthome_coo_upgrade  (Zigbee 升级)
  32 KB   ─── stor_AudioPicProcTask    (音频/图片处理)
            ├── talkBackDevInputTask   (对讲输入)
            ├── talkBackIoOutEventTask (对讲 IO)
            ├── talkBackRoomIoInEventTask (房间 IO)
            ├── checkMemLeakByThread   (内存检测)
            ├── mcu_process_task       (MCU 通信)
            ├── startEncodeChan        (编码启动)
            └── ...
  16 KB   ─── dvrNetServer             (SDK 网络服务)
            ├── visNetServer           (VIS 服务)
            ├── eXosip_client_task     (SIP 客户端)
            ├── talkBackExtensionPro   (对讲分机)
            ├── sqliteOpTask           (SQLite)
            ├── ipDADTask              (IP 检测)
            ├── netsdk_link_limit_task (连接限制)
            ├── startSntpClient        (SNTP)
            ├── agingForNoGui          (老化测试)
            └── ...
   4 KB   ─── wifi_adjust_reminder     (WiFi 提醒)
            ├── adjustTimeTask         (时间校准)
            ├── watchdogTask           (看门狗)
            ├── rest_srv_recover_space_task (REST 恢复)
            └── ...
```

---

## 3. 各目录/文件作用

### 3.1 目录结构总览

```
APPS/
├── Makefile                  # 主构建文件，链接所有子模块
├── include/                  # 公共头文件（~100+ 个 .h）
│   ├── config.h              # 系统配置定义
│   ├── configDefine.h        # 配置项定义（109KB）
│   ├── abi_interface.h       # ABI 接口定义（80KB）
│   ├── db_api.h              # 数据库 API 定义
│   ├── dvrMacro.h            # 宏定义
│   ├── visUtil.h             # 视觉工具函数
│   └── ...
├── system/                   # 系统核心
│   ├── init/dvr.c            # ★ 主入口，main() 函数
│   ├── ability/abi_ability.c # ★ 设备能力管理（212KB，核心）
│   ├── ability/abi_ability.h # 能力结构体定义
│   ├── param/                # 参数管理（Flash/SQLite 持久化）
│   ├── upgrade/              # 固件升级
│   ├── clock/                # 时钟服务
│   ├── user/                 # 用户管理
│   ├── version/              # 版本管理
│   ├── watchdog/             # 看门狗
│   └── checkMemInfo/         # 内存检测
├── interface/                # 硬件接口抽象
│   ├── dsp/                  # DSP 接口（编码/解码）
│   ├── gui/                  # GUI 接口
│   └── kernel/               # 内核接口（驱动交互）
├── dataApplication/          # 数据处理应用
│   ├── preview/preview.c     # 实时预览
│   ├── play/                 # 录像回放
│   ├── streamReceive/        # 网络流接收
│   ├── streamConv/           # 流格式转换（PS/RTP）
│   └── streamAnalysis/       # 流分析
├── dataManagement/           # 数据管理
│   ├── storManagement/       # 存储管理（硬盘/SD/ANR）
│   ├── database/             # 数据库操作（SQLite）
│   ├── imageManagement/      # 图像管理
│   ├── logManagement/        # 日志管理
│   ├── smarthome/            # 智能家居管理
│   └── audio/                # 音频管理（WAV）
├── event/                    # 事件处理层
│   ├── alarmCtrl/            # 报警控制（对讲、回呼）
│   ├── interactCtrl/         # 交互控制
│   ├── exceptionCtrl/        # 异常控制
│   ├── ioEvent/              # IO 事件
│   ├── porchEvent/           # 门铃事件
│   ├── sub1g/                # Sub-1G 无线通信
│   ├── zigbee/               # Zigbee 智能家居
│   ├── wifi/wifiLib/         # WiFi 管理
│   └── instance/             # 传感器实例（距离传感器等）
├── net/                      # 网络服务层
│   ├── ipc/                  # IPC 协议（海私协议）
│   ├── ipc/ipcService/       # IPC 服务
│   ├── netService/           # 网络服务
│   │   ├── rtspServer/       # RTSP 服务器
│   │   ├── httpClient/       # HTTP 客户端
│   │   ├── netdaLib/         # 网络数据库
│   │   ├── sadpLib/          # SADP 设备发现
│   │   ├── sntpLib/          # SNTP 时间同步
│   │   ├── net_base_op/      # 网络基础操作
│   │   ├── rtpSession/       # RTP 会话（对讲/家庭语音）
│   │   └── serviceInt/       # 服务接口
│   ├── sdkService/           # SDK 服务（设备接入）
│   ├── sipServer/            # SIP 服务器（可视对讲）
│   ├── sipClient/            # SIP 客户端
│   ├── ezviz/                # 蛋石云协议
│   ├── nui/                  # NUI 框架（comm/restSrv/sdkXmlSrv）
│   ├── webServiceMng/        # Web 服务管理
│   ├── multicast/            # 组播
│   └── accessControl/        # 门禁控制
├── serial/                   # 串口通信
│   ├── rs232/                # RS232 通信
│   ├── rs485/                # RS485 通信（传感器）
│   ├── shellCmd/             # Shell 命令（RS485 从设备）
│   ├── shellCmd2/            # Shell 命令 v2
│   ├── t1/                   # T1 通信协议
│   └── mcu/                  # MCU 通信
├── storage/                  # 存储设备
│   └── edev/                 # 外部设备（硬盘/SD卡）
├── util/                     # 工具库
│   ├── common/               # 通用工具
│   ├── debug/                # 调试工具
│   ├── deelx/                # 正则表达式库
│   └── wrapper/              # 系统 API 封装（线程/定时器/信号量）
├── gui/                      # GUI 层
│   └── guiApp/netraApp/      # ★ NETRA GUI 应用（~260个页面）
│       ├── main.c             # GUI 入口 initMenuMain()
│       ├── src/               # GUI 源文件
│       └── include/           # GUI 头文件
│   ├── guiRes/               # GUI 资源
│   └── guiRelyLib/           # GUI 依赖库（jpeg, freetype, png）
└── lib/                      # 平台库（按平台分类）
    ├── lib_B1pro/
    ├── lib_B2/
    ├── lib_B2pro/
    ├── lib_B3pro/
    ├── lib_B4/
    ├── lib_F4/
    └── lib_R0/
```

### 3.2 核心文件详解

#### 3.2.1 系统核心

| 文件 | 大小 | 作用 |
|------|------|------|
| `system/init/dvr.c` | 55KB | **主程序入口**，包含 main() 函数，负责所有子系统初始化和线程创建 |
| `system/ability/abi_ability.c` | 212KB | **设备能力管理核心**，维护 ABI_ABILIYY_T 结构体，查询/设置设备能力（编解码、预览模式、IPC支持、功能开关等） |
| `system/ability/abi_ability.h` | 37KB | 能力位掩码定义，定义所有硬件/软件能力的位标志 |
| `include/configDefine.h` | 109KB | 配置项定义，所有配置参数的 ID 和结构定义 |
| `include/abi_interface.h` | 80KB | ABI 接口函数声明，对外暴露的能力查询 API |

#### 3.2.2 GUI 层

| 文件 | 数量 | 作用 |
|------|------|------|
| `gui/guiApp/netraApp/src/main.c` | 1 | GUI 入口，消息循环 |
| `gui/guiApp/netraApp/src/gui_*.c` | ~260 | GUI 页面实现（设置、预览、回放、设备管理等） |
| `gui/guiApp/netraApp/include/gui_*.h` | ~260 | GUI 页面头文件 |
| `include/9000menu.h` | 18KB | 菜单结构定义 |

GUI 页面按平台分为通用版本（`gui_*.c`）和平台特定版本（`gui_b1pro_*.c`）。

#### 3.2.3 网络服务

| 目录 | 作用 |
|------|------|
| `net/sipServer/` | SIP 可视对讲服务器，基于 eXosip2 |
| `net/netService/rtspServer/` | RTSP 流媒体服务器 |
| `net/netService/httpClient/` | HTTP 客户端 |
| `net/netService/sadpLib/` | SADP 局域网设备发现协议 |
| `net/netService/sntpLib/` | SNTP 时间同步客户端 |
| `net/netService/rtpSession/` | RTP 会话管理（对讲、家庭语音） |
| `net/sdkService/` | 设备 SDK 服务（远程接入） |
| `net/ezviz/` | 蛋石云平台协议 |
| `net/nui/` | NUI 框架（REST API + XML RPC） |
| `net/ipc/` | 海康 IPC 私有协议 |

#### 3.2.4 事件层

| 目录 | 作用 |
|------|------|
| `event/alarmCtrl/` | 报警控制，对讲回呼数据接收 |
| `event/porchEvent/` | 门铃事件管理 |
| `event/sub1g/` | Sub-1G 射频通信（传感器） |
| `event/zigbee/` | Zigbee 智能家居设备管理 |
| `event/wifi/` | WiFi 连接管理 |
| `event/instance/` | 传感器驱动（VL53LX 距离传感器等） |

#### 3.2.5 数据处理

| 目录 | 作用 |
|------|------|
| `dataApplication/preview/` | 实时视频预览 |
| `dataApplication/play/` | 录像回放与搜索 |
| `dataApplication/streamReceive/` | 网络流接收 |
| `dataApplication/streamConv/` | 流格式转换（PS ↔ RTP） |
| `dataApplication/streamAnalysis/` | 流分析 |
| `dataManagement/storManagement/` | 存储管理（硬盘、SD卡、ANR 断网续传） |
| `dataManagement/database/` | SQLite 数据库操作 |

---

## 5. 数据流图

### 4.1 视频数据流

```
┌──────────┐     ┌──────────┐     ┌──────────────┐     ┌──────────┐
│ 摄像头    │────▶│ VI (视频输入) │────▶│ DSP 编码     │────▶│ 编码码流  │
│ (Sensor) │     │          │     │ (HI3531)     │     │ (H.264)  │
└──────────┘     └──────────┘     └──────────────┘     └─────┬────┘
                                                            │
                   ┌────────────────────────────────────────┘
                   │
                   ▼
        ┌──────────────────────┐
        │   CHAN_PARA 通道控制块 │
        │   (netBuf / netPool) │
        └──────────┬───────────┘
                   │
        ┌──────────┴───────────┐
        │                      │
        ▼                      ▼
 ┌─────────────┐       ┌──────────────┐
 │ 本地存储      │       │ 网络分发       │
 │ (H.264 TS)  │       │ (PS/RTP)     │
 │ storManage  │       │ ┌──┬──┬──┐   │
 └─────────────┘       │S|S|R|O  │   │
                       │D|N|T|N  │   │
                       │C|K|P|V  │   │
                       │/ | | |  │   │
                       └──┴──┴──┘   │
                          │  │      │
                       SDK RTSP Web ONVIF
```

### 4.2 对讲数据流（可视对讲）

```
┌─────────┐    ┌──────────┐    ┌────────────┐    ┌──────────┐
│ 麦克风   │───▶│ AI 采集   │───▶│ G711/AAC  │───▶│ RTP 发送  │
│ (Mic)   │    │          │    │ 编码        │    │ 网络层    │
└─────────┘    └──────────┘    └────────────┘    └────┬─────┘
                                                       │
                                                       │ SIP + RTP
                                                       ▼
                                               ┌───────────────┐
                                               │ 远端 APP/设备   │
                                               │ (手机/室内机)   │
                                               └───────┬───────┘
                                                       │
                                                       │ RTP + SIP
                                                       ▼
                                               ┌───────────────┐
                                               │ RTP 接收       │
                                               │ 解码           │
                                               │ AO 输出        │
                                               └───────┬───────┘
                                                       │
                                                       ▼
                                               ┌─────────┐
                                               │ 扬声器   │
                                               └─────────┘
```

关键线程协作：
- `sip_server_start()` — SIP 信令控制（呼叫建立/挂断）
- `talkBackVideoProcess()` — 对讲视频处理
- `talkBackDevInputTask()` — 对讲设备输入
- `talkBackRtpTask()` — RTP 数据传输
- `eXosip_client_task()` — eXosip SIP 协议栈

### 4.3 配置数据流

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│ GUI/SDK  │────▶│ 配置 API  │────▶│ SQLite   │────▶│ Flash    │
│ Web/IPC  │     │ db_api   │     │ 数据库    │     │ 存储      │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
                                              │
                                              ▼
                                       ┌──────────┐
                                       │ 上电加载  │
                                       │ sysInit() │
                                       └──────────┘
```

### 4.4 事件触发流

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ 硬件中断/事件  │───▶│ 事件采集层     │───▶│ 事件分发       │
│ (IO/传感器/   │    │ serial/rs485 │    │ alarmCtrl    │
 │ 门铃/WiFi)   │    │ mcu          │    │ exceptionCtrl│
└──────────────┘    └──────────────┘    └──────┬───────┘
                                               │
                    ┌──────────────────────────┼──────────────┐
                    │                          │              │
                    ▼                          ▼              ▼
             ┌───────────┐          ┌───────────┐   ┌──────────────┐
             │ 报警输出    │          │ 通知上传    │   │ 联动动作      │
             │ alarmOut  │          │ 云平台     │   │ - 录像       │
             │ 蜂鸣器     │          │ SDK 上报   │   │ - 截图       │
             │ LED 闪烁   │          │            │   │ - 弹窗       │
             └───────────┘          └───────────┘   └──────────────┘
```

---

## 6. 分层控制流图

### 5.1 分层架构

```
┌─────────────────────────────────────────────────────────────────┐
│  L4  表现层 (Presentation Layer)                                  │
│  ─────────────────────────────────────────────────────────────  │
│  GUI (MGUI)  │  Web Server (appweb)  │  SDK (远程客户端)        │
│  页面渲染     │  ISAPI/REST API       │  设备控制/配置           │
└─────────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────────┐
│  L3  业务逻辑层 (Business Logic Layer)                            │
│  ─────────────────────────────────────────────────────────────  │
│  事件处理  │  对讲控制  │  存储管理  │  网络服务  │  设备管理     │
│  alarmCtrl │ talkBack  │ storManage │ netService │ sdkService   │
│  porchEvent│ SIP/eXosip│ database   │ rtsp/http│ nui框架       │
│  zigbee    │ ezviz     │ smarthome  │ sadp/sntp│ onvif         │
└─────────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────────┐
│  L2  数据/服务层 (Data/Service Layer)                             │
│  ─────────────────────────────────────────────────────────────  │
│  视频处理  │  串口通信  │  存储设备  │  工具库  │  系统服务       │
│  preview   │ rs232/rs485│ edev      │ wrapper  │ clock/watchdog │
│  play      │ mcu/t1     │ database  │ debug    │ user/upgrade   │
│  streamConv│            │           │ deelx    │ param          │
└─────────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────────┐
│  L1  能力抽象层 (Ability/ABI Layer)                               │
│  ─────────────────────────────────────────────────────────────  │
│  abi_ability.c — 设备能力统一查询接口                              │
│  - 编解码能力  - 预览模式  - IPC 支持  - 功能开关                  │
│  - 硬件资源   - 网络资源   - 存储资源                             │
└─────────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────────┐
│  L0  平台 BSP 层 (Board Support Package)                          │
│  ─────────────────────────────────────────────────────────────  │
│  VIS_PLATFORM — 海思 DSP SDK / 驱动 / 硬件抽象                   │
│  各平台专用库 (lib_B1pro / lib_B2 / lib_B3pro / ...)            │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 main() 控制流（详细）

```
main()
│
├──[阶段1] 进程与环境初始化
│   ├── run_cmd("killall hicore")          // 防止重复启动
│   ├── analysis_custom_info()
│   ├── initEtherIf()                      // 网络接口
│   ├── sysInit()                          // 系统级初始化
│   ├── abi_device_ability_init()          // 加载设备能力表
│   ├── 时间初始化                         // RTC → 系统时间
│   ├── ddm_open_common_fd()
│   ├── signalIgnored()                    // 忽略后台信号
│   ├── heap_init()
│   ├── sysWdInit()                        // 硬件看门狗
│   └─ util_timer_init()
│
├──[阶段2] 配置加载
│   ├── getDeviceCfgParams()               // 从 Flash/DB 加载配置
│   ├── dpi_init_db()                      // 初始化数据库
│   ├── sys_passwd_set()                   // 设置 root 密码
│   └── init_en_scene_database()           // 场景数据库
│
├──[阶段3] 硬件/DSP 初始化
│   ├── init_dsp_if()                      // DSP 驱动接口
│   ├── initEncodeChan()                   // 初始化编码器
│   │   └── initEncoderParam(chan)         // 每个通道
│   │       └── setEncoderParam()          // DSP 编码参数
│   ├── initIPCamera()                     // IPC 通道
│   ├── 音频初始化                         // 音量/采样率
│   └── image_initPool()                   // 图像缓冲区
│
├──[阶段4] 网络服务启动
│   ├── initDhcpCtrl()
│   ├── initNetIf()                        // 网络接口配置
│   ├── startSntpClient()                  // 时间同步
│   ├── dvrNetServer() x2                  // SDK 服务 (TCP/TLS)
│   ├── web_service_init()                 // Web 服务器
│   ├── visNetServer()                     // VIS 服务
│   ├── start_sadp_server()                // 设备发现
│   ├── rtsps_module_init()                // RTSP 服务器
│   └── http_client_start()                // HTTP 客户端
│
├──[阶段5] 对讲/SIP 服务
│   ├── SSL_library_init()                 // SSL
│   ├── sip_server_start()                 // SIP 服务器
│   ├── eXosip_client_task()              // SIP 客户端线程
│   ├── talkBackVideoProcess()            // 视频处理
│   ├── talkBackDevInputTask()            // 设备输入
│   ├── talkBackRtpTask()                 // RTP 传输
│   └── talkBackExtensionPro()            // 分机处理
│
├──[阶段6] 事件与外设服务
│   ├── alarmInCtrlTask()                  // 报警输入
│   ├── cmd_server_init()                  // RS485/232 命令
│   ├── porchSendStart()                   // 门铃
│   ├── zigbeeDeviceStartProcTask()        // Zigbee
│   ├── sub1gDeviceStartProcTask()         // Sub-1G
│   └── stor_AudioPicProcTask()            // 音频/图片
│
├──[阶段7] GUI 启动
│   ├── semInit(&sem_uiready)
│   ├── APP_GuiMain()                     // GUI 主线程
│   │   └── while(GetMessage) { ... }      // 消息循环
│   └── semWait(&sem_uiready)             // 等待 GUI 就绪
│
├──[阶段8] 辅助服务
│   ├── adjustTimeTask()                   // 时间校准
│   ├── watchdogTask()                     // 软件看门狗
│   ├── ipDADTask()                        // IP 冲突检测
│   ├── sdkUploadTask()                    // SDK 上传
│   ├── rest_srv_recover_space_task()      // 空间恢复
│   ├── agingForNoGui()                    // 老化测试
│   └── checkMemLeakByThread()             // 内存检测
│
└──[阶段9] 主循环
    └── while(1) { pause(); }              // 挂起，等待信号
```

### 5.3 线程关系与优先级

```
┌─────────────────────────────────────────────────────────────┐
│                        优先级从高到低                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  COMMON_PRIO    ─┐                                            │
│                  ├── mcu_process_task         (MCU 通信)      │
│                  ├── startEncodeChan        (视频采集)        │
│                  ├── stor_AudioPicProcTask  (音频/图片)       │
│                  ├── sdkUploadTask          (SDK 上传)        │
│                  ├── talkBackIoOutEventTask (对讲 IO)         │
│                  ├── talkBackRoomIoInEventTask (房间 IO)      │
│                  ├── sip_server_start       (SIP 服务器)      │
│                  ├── talkBackExtensionPro   (对讲分机)        │
│                  ├── talkBackVideoProcess   (对讲视频)        │
│                  ├── talkBackDevInputTask   (对讲输入)        │
│                  ├── talkBackCvbsInputTask  (模拟输入)        │
│                  ├── talkBackCvbsManageTask (模拟管理)        │
│                  ├── eXosip_client_task    (SIP 客户端)       │
│                  ├── sqliteOpTask          (SQLite 操作)      │
│                  ├── zigbeeDeviceStartProcTask (Zigbee)       │
│                  ├── sub1gDeviceStartProcTask  (Sub-1G)       │
│                  ├── rest_srv_recover_space_task (REST 恢复)   │
│                  ├── cmd_server_init       (命令服务)         │
│                  ├── checkMemLeakByThread  (内存检测)         │
│                  └── checkMemLeakByMallocNum (内存检测)       │
│                                                             │
│  NET_SERVER_PRIO  ─┐                                        │
│                  ├── dvrNetServer (SDK 服务)                 │
│                  ├── visNetServer (VIS 服务)                 │
│                  └── netsdk_link_limit_task (连接限制)       │
│                                                             │
│  TIMING_PRIO    ───┐                                        │
│                  ├── wifi_adjust_reminder (WiFi 提醒)        │
│                  ├── adjustTimeTask (时间校准)               │
│                  └── ipDADTask (IP 冲突检测)                 │
│                                                             │
│  EXCEPTION_PRIO   ─┐                                       │
│                  └── alarmInCtrlTask (报警输入)              │
│                                                             │
│  SW_WATCHDOG_PRIO ─┐                                       │
│                  └── watchdogTask (软件看门狗)               │
│                                                             │
│  MENU_PRIO      ───┐                                        │
│                  └── APP_GuiMain (GUI 主线程, 64MB 栈)       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.4 关键数据结构

#### CHAN_PARA — 通道控制块

```c
typedef struct {
    UINT32  channel;              // 通道号
    BOOL    bEncodeStarted;       // 编码是否启动
    BUF     netBuf;               // 网络数据缓冲区
    BUF     subNetBuf;            // 子码流缓冲区
    LIST    netConnectList;       // 网络连接列表
    LIST    subNetConnectList;    // 子码流连接列表
    pthread_mutex_t mutexSem;     // 互斥锁
    pthread_mutex_t mutexSem4Rcv; // 接收锁
    // ... 更多字段
} CHAN_PARA;
```

#### ABI_ABILIYY_T — 设备能力结构

```c
typedef struct {
    // 硬件能力
    UINT8  cbFlashSize;            // Flash 大小
    UINT8  cbArmMemSize;           // ARM 内存
    UINT8  cbVideoInNum;           // 视频输入数
    UINT8  cbDecChanNum;           // 解码通道数
    UINT8  cbEncDSpNum;            // 编码 DSP 数
    // ...

    // 编解码能力
    ABI_COMPRESS_ABILITY_T stru_CompressMainChan;  // 主码流
    ABI_COMPRESS_ABILITY_T stru_CompressSubChan;   // 子码流

    // 功能能力
    UINT32 iFunctionList;          // 功能位掩码
    UINT32 iFunctionExtList;       // 扩展功能
    UINT32 soft_ability;           // 软件能力
    UINT32 soft_ability2;          // 软件能力2

    // 资源限制
    UINT16 iUserLoginMaxNum;       // 最大登录用户
    UINT16 iDevNetLinkMaxNum;      // 设备最大连接
    UINT16 iChanNetLinkMaxNum;     // 通道最大连接
    UINT8  cbIpcMaxNum;            // 最大 IPC 数
    // ...
} ABI_ABILIYY_T;
```

---

## 附录：构建系统

### Makefile 结构

```
build/Rules.make          ← 全局编译规则（交叉编译器、路径、标志）
    │
    ▼
APPS/Makefile             ← 主 Makefile
    │
    ├── VPATH 收集所有子目录源文件
    ├── 条件编译 (CONFIG_SUPPORT_WIFI, CONFIG_SUPPORT_GUI 等)
    ├── 链接第三方库 (libIPCM, libRtspC, libeXosip2, libsqlite3...)
    │
    ▼
    输出: hicore (strip 后)
    ├── hicore.nostrip    ← 调试版本
    ├── ${G_DIR_BIN}/debug/hicore
    └── ${G_DIR_BIN}/release/hicore
```

### 平台变体

| 平台 | 目标名 | 特殊说明 |
|------|--------|---------|
| B1pro | hicore / hicore_8M / hicore_16M | 室内基站，Sub-1G |
| B2 | hicore_1024_600 / ... | 带屏室内机 |
| B2pro | hicore / hicore_8M / ... | 增强版室内基站 |
| B3pro | hicore / hicore_8M / ... | 新一代室内基站 |
| B4 | hicore | 最新室内基站 |
| R0 | hicore | 室内机，支持 cam_hal |
| F4 | hicore | 室外摄像机 |
