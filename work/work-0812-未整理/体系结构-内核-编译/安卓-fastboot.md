

目录: E:\平台&工具\安卓调试\adb_fastboot\adb_fastboot Mode LastWriteTime Length Name ---- ------------- ------ ---- d----- 2026/7/22 11:06 lib -a---- 2026/7/22 11:06 38319616 adb.exe -a---- 2026/7/22 11:06 97792 AdbWinApi.dll -a---- 2026/7/22 11:06 62976 AdbWinUsbApi.dll -a---- 2026/7/22 11:06 13015552 fastboot.exe PS E:\平台&工具\安卓调试\adb_fastboot\adb_fastboot> 这个adb怎么安装和使用


<think>
---


</think>你不需要“安装”这个 ADB，它已经是 **解压即用** 的绿色版。

看你的目录结构，`adb.exe`、`fastboot.exe` 和对应的 DLL 文件都在，直接就能用。

---

### 使用方法：分两步

#### 第一步：在当前目录临时使用（最简单）

直接在 PowerShell 里运行命令就行，但要注意 **前面要加 `.\`**，因为当前目录不在系统的搜索路径里：

```powershell
# 查看 adb 版本，确认能运行
.\adb.exe version

# 查看已连接的设备
.\adb.exe devices

# 进入设备 shell
.\adb.exe shell
```

---

#### 第二步：添加到系统 PATH，方便在任何地方使用（推荐）

如果你不想每次都跑到这个目录，或者每次都要加 `.\`，可以把它加到系统环境变量里：

**方法1：临时添加（仅当前 PowerShell 窗口有效）**
```powershell
$env:Path += ";E:\平台&工具\安卓调试\adb_fastboot\adb_fastboot"
```
然后你就可以在任何路径直接输入 `adb` 了，不需要 `.\`。

**方法2：永久添加（推荐）**
1. 按 `Win + X`，选择 **“系统”** → **“高级系统设置”**
2. 点击 **“环境变量”**
3. 在 **“系统变量”** 里找到 `Path`，双击
4. 点击 **“新建”**，粘贴路径：
   ```
   E:\平台&工具\安卓调试\adb_fastboot\adb_fastboot
   ```
5. 确定保存，**重新打开一个 PowerShell 窗口**
6. 输入 `adb version` 测试，如果显示版本信息就成功了

---

### 使用前提：手机端设置

在电脑上操作之前，手机需要先开启 USB 调试：

1. 手机进入 **设置 → 关于手机**
2. 连续点击 **“版本号”** 7 次，开启开发者模式
3. 回到 **设置 → 系统 → 开发者选项**
4. 开启 **“USB 调试”**
5. 用数据线连接电脑，手机上会弹出授权提示，勾选 **“一律允许”** 并确认

然后用 `adb devices` 就能看到你的设备了。

---

### 常用命令速查

| 命令 | 作用 |
|------|------|
| `adb devices` | 查看已连接设备 |
| `adb shell` | 进入手机命令行 |
| `adb install 应用.apk` | 安装 APK |
| `adb push 本地文件 手机路径` | 传文件到手机 |
| `adb pull 手机路径 本地路径` | 从手机拉文件 |
| `adb reboot` | 重启手机 |
| `adb reboot bootloader` | 重启到 fastboot 模式 |
| `fastboot devices` | 查看 fastboot 设备 |
| `fastboot flash 分区 镜像文件` | 刷入镜像 |

---

你现在就可以试试：用数据线连上手机，输入 `.\adb devices`，看看能不能识别到设备。有问题随时问我。








fastboot.exe 这个是干什么的

<think>
---

['{"webPages": [{"name": "fastboot的使用帮助.doc_淘豆网", "summary": "文档列表 文档介绍 Fastb oot 使用方式:f astbo ot[<选项>]<命令> 解释: []括起来表示这个是可选的. <> :upd ate <文件名>从官方 up date. zip u pdate .zip 必须是官方的 f lasha ll \'f lash boot\' +\'fl ash s ystem \' flash <分区名>[<文件名>] sy stem, recov ery,b oot,s plash 1,hbo ot,ra dio,u serda ta,ca che era se<分区名>清空一个分区. getva r<参数名>显示一个启动参数 boot <内核文件>[]将电脑上的内核下载到手机并用该内核启动系统. fla sh:ra wboo t<内核文件>[]创建 boot. img 并下载到手机启动系统. de vices 列出所有与电脑连接的设备. reboot 正常启动系统 reboo t-boo tload er启动系统到 hboot 选项:- r ecver y中的\\"w ipe d ata/f actor yrese t\\" -s<串口号>置顶要操作的设备的串口号-p<产品名> hero, bravo ,drea m... -c<命令行>用命令行替换系统的启动命令行. 分区解释: syste m: . use rdata :数据分区. cache :缓存分区 r ecove ry:Re cover ot: 存放内核和 ra mdisk oot: 这个是 SPL fa stboo . splas h1: adio: 这个是无线所在的分区. adb dev ices 查看已连接设备 adb rebo ot-bo otloa der 让手机进入 f astbo ot模式 fastb oot d evice s可以看到设备列表用下面的命令烧写", "url": "https://www.taodocs.com/p-72617494.html"}, {"name": "电脑fastboot有什么用", "summary": "Fast Boot是UEFI(Unified Extensible Firmware Interface)的一种规范,用于支持快速启动操作系统,它可以比传统的BIOS引导更快的启动电脑,将启动时间缩短到几秒钟内。 Fast Boot可以让电脑开机更快,在重启以及关机后,能够加快操作系统的启动速度,提高电脑的使用效率。", "url": "https://www.youfanx.com/baike/667551284072548212.html"}, {"name": "【免费】fastboot", "summary": "《深入理解Fastboot模式及其应用》Fastboot是一种低级别的恢复模式,它是Android系统中用于固件更新和设备恢复的重要工具。在这个模式下,设备的引导加载器允许通过USB接口与计算机进行通信,从而实现对硬件的直接控制,如安装、升级或擦除设备的系统分区。本文将深入探讨Fastboot的工作原理、使用方法以及其在实际操作中的应用。一、Fastboot工作原理Fastboot模式是Android设备启动流程的一部分,当设备启动时,如果按下特定的按键组合,就会进入这个模式。在Fastboot模式下,设备的处理器运行在简化的环境中,只加载必要的驱动程序和固件,这使得开发者可以对系统分区进行安全、精确的操作,而不会影响到正在运行的系统。二、Fastboot命令Fastboot模式下支持一系列命令,包括但不限于:1. `fastboot devices`:列出连接到电脑的所有处于Fastboot模式的设备。2. `fastboot flash partition image`:将指定的image文件刷入到特定分区,例如`fastboot flash boot boot.img`可将boot分区更新。3. `fastboot erase partition`:擦除指定分区的数据,如`fastboot erase cache`会清除缓存分区。4. `fastboot oem unlock`:解锁设备的Bootloader,允许进行自定义操作。5. `fastboot reboot`:重启设备,退出Fastboot模式。三、Fastboot的使用场景1. 系统更新:Fastboot常用于刷入官方或第三方的系统更新,特别是当系统出现问题,无法正常启动时,可以通过Fastboot模式进行修复。2. 解锁Bootloader:对于需要安装自定义ROM或者进行更高级别的系统修改的用户,必须", "url": "https://download.csdn.net/download/minyclub/3423813"}, {"name": "fastboot的使用帮助(国外英文资料).doc", "summary": "fastboot的使用帮助(国外英文资料)Fastboot usage: Fastboot [ option ] command Explanation:[] in parentheses, this is optional. , which means that this is necessary.Available commands:Update file name from the official update.zip upgrade system. The update.zip must be officialFlashall flash boot + flash systemFlash partition name / name will file is written to partition. The format of the file must be correct. Partition name, but not limited to the system, recovery, boot, splash1, hboot, radio, userdata, cacheErase partition name to empty a partition.Getvar the parameter name shows a start parameterThe boot kernel file [] downloads the kernel from the computer to the phone and starts the system with the kernel.Flash: raw boot kernel file [] create the boot.img and download it to the phone boot system.De", "url": "https://max.book118.com/html/2017/0610/113223430.shtm"}, {"name": "Fastboot配置使用指南_fastboot环境配置资源-CSDN文库", "summary": "\ue50a需积分: 49 \ue50b\ue50a20 浏览量 \ue50b\ue50a2018-09-21 \ue50b\ue50a10:43:59 \ue50b\ue50a上传 \ue50b\ue50a评论 \ue50b\ue50a2 \ue50b\ue50a收藏 \ue50b本文档主要介绍 fastboot烧写工具的使用方法,适用于一键烧写所有程序镜像到单板flash 上的场景、单板已有 bootrom可按地址烧写其他程序镜像到单板 flash 上的场景以及在空板上只烧写 boot到单板 flash上的场景。 fastboot驱动 浏览:136 fastboot驱动,手动安装版本fastboot驱动是不需要安装的,下载fastboot程序即可fastboot,英语翻译意思是快速启动。在安卓手机中fastboot是一种比recovery更底层的刷机模式。就是使用USB数据线连接手机的一种刷机模式。相对于某些系统(如ios)卡刷来说,线刷更可靠,安全。fastboot相当于电脑的BIOS是已经内刷在手机内的,而电脑端只需用程序连接即可,电脑 vbmeta.img文件的完整解析,对该文件的所有字段都做出了详细标注 浏览:64 vbmeta.img是Android AVB功能用到的。主要用于安全启动时的校验和dm-verity参数传递时的支持。 Android_boot_image_editor,用于解析和打包android boot.img/vbmeta.img的工具,支持android q预览.zip 浏览:122 Android_boot_image_editor,用于解析和打包android boot.img/vbmeta.img的工具,支持android q预览.zip fastboot工具及使用方法 浏览:84 4星·用户满意度95% 提供windows版fastboot工具,同时文档介绍fastboot的使用方法。 Android_boot_image_editor:解析并重新打包Android boot.imgvb", "url": "https://download.csdn.net/download/simonlv123/10680612"}, {"name": "fast boot下载-fast boot免费最新中文电脑版下载-游侠软件", "summary": "fast\\nboot是一款功能非常专业的修复工具,这款软件当中可以帮助用户的电脑快速进入到电脑的bios界面当中,利用其中的功能来对自己的电脑系统进行重置以及系统优化等功能,还是已非常推荐用户使用的。\\nfast\\nboot特色\\n1、电脑优化\\n软件当中通过快速启动bios之后就能利用其中的功能来对电脑进行优化了。\\n2、强制重启\\n支持强制化的对电脑进行重启,如果电脑出现卡死的情况就非常推荐使用这个功能。\\n3、系统重装\\n支持对现有的电脑系统进行重装,在bios界面当中一键点击即可重装当前的电脑系统。\\n4、快速启动\\n能够帮助用户对电脑进行快速启动,原来进入电脑桌面慢的话就可以利用其来进行优化。\\nfast\\nboot亮点\\n1、功能丰富\\n当前的软件功能还是非常丰富的,主要是用于对电脑当中的系统来进行优化。\\n2、主板调控\\n可以在bios界面来对电脑主板进行调控,通过一些参数的设置使得运行能够更流畅。\\n3、专业技术\\n采用了目前行业当中最专业的技术,在其中根据自己的使用需求来进行电脑的优化。\\n4、安全实用\\n是一款可以安全实用的优质工具,在软件主界面当中一键点击即可实现优化,非常指定推荐。\\nfast\\nboot怎么安装\\n1、在游侠下载这款软件的安装包打开点击安装。\\n2、安装完成之后打开进行使用即可。", "url": "https://soft.ali213.net/down/21101.html"}, {"name": "fastboot(诊断协议) - 搜狗百科", "summary": "Fastboot(快速启动)是一个诊断协议,主要用于由一台计算机通过USB连接Android智能手机,修改其闪存文件系统,是Android Debug Bridge库的一部分。 在安卓手机中fastboot是一种比recovery更底层的刷机模式(俗称引导模式)。相对于某些系统(如ios)卡刷来说,线刷更可靠,安全。 中文名 快速启动 外文名 Fastboot 类别 线刷 应用 安卓刷机 俗称 引导模式 特点 利用USB连接Android智能手机 词语解释 英语翻译: 快速启动。在 安卓手机中fastboot是一种比recovery更底层的 刷机模式。 fastboot是一种线刷,就是使用 USB数据线连接手机的一种刷机模式。相对于某些系统(如小米)卡刷来说,线刷更可靠,安全。 recovery是一种卡刷,就是将刷机包放在sd卡上,然后在recovery中刷机的模式。 使用方法 命令 从字面上来看是【快速启动】的意思,也算是一个刷机界面,不过比recovery更加底层.这个底层是更加接近硬件层的意思. 两个都很重要,不过fastboot更为主要.当你不能进入recovery的时候,不要紧张,你还能进fastboot挽救,不过当你连fastboot都不能进入的时候,那可就是砖了。 为了使用Fastboot功能, 应获得S-OFF的SPL.你的电脑还必须装有ADB驱动. 进入Fastboot的方式是关机状态下按返回+开机;主流Android手机进入Fastboot的方式为【音量-】+【电源键】. Fastboot使用方式: fastboot [ <选项> ] <命令> 解释 []括起来表示这个是可选的. <>括起来表示这个是必须的. 可用命令: update <文件名> 从官方update.zip升级系统.该update.zip必须是官方的 flashall \'flash bo", "url": "http://baike.sogou.com/v56096792.htm?fromTitle=fastboot"}, {"name": "fastboot", "summary": "Fastboot(5)\\nFastboot(快速启动)是一个诊断协议,主要用于由一台计算机通过USB连接Android智能手机,修改其闪存文件系统,是Android Debug Bridge库的一部分。\\n在安卓手机中fastboot是一种比recovery更底层的刷机模式(俗称引导模式)。相对于某些系统(如ios)卡刷来说,线刷更可靠,安全 [1] 。\\n中文名\\n快速启动\\n类别\\n线刷\\n俗称\\n引导模式\\n外文名\\nFastboot\\n应用\\n安卓刷机 [2]\\n特点\\n利用USB连接Android智能手机\\n目\\n录\\n1 词语解释 2 使用方法 命令 解释 选项 分区 3 进入模式\\n模式A 模式B 4 命令操作 准备工具 具体步骤 5 词条图册\\n1 词语解释\\n编辑\\nfastboot 英语翻译: 快速启动。在 安卓手机中fastboot是一种比recovery更底层的 刷机模式。\\nfastboot是一种线刷,就是使用 USB数据线连接手机的一种刷机模式。相对于某些系统(如小米)卡刷来说,线刷更可靠,安全。\\nrecovery是一种卡刷,就是将刷机包放在sd卡上,然后在recovery中刷机的模式。\\n2 使用方法\\n编辑\\n命令\\nfastboot 从字面上来看是【快速启动】的意思,也算是一个刷机界面,不过比recovery更加底层.这个底层是更加接近硬件层的意思.\\n两个都很重要,不过fastboot更为主要.当你不能进入recovery的时候,不要紧张,你还能进fastboot挽救,不过当你连fastboot都不能进入的时候,那可就是砖了。\\n为了使用Fastboot功能, 应获得S-OFF的SPL.你的电脑还必须装有ADB驱动.\\n进入Fastboot的方式是关机状态下按返回+开机;主流Android手机进入Fastboot的方式为【音量-】+【 电源键 】.\\nFastboot使用方式: fastboot", "url": "https://baike.sogou.com/v56096792.htm?fro"}, {"name": "fastboot安装包下载-fastboot工具官方版最新版2025下载v1.0.1.15-游侠软件", "summary": "fastboot安装包是一款专为设备维修人员及高级用户设计的安卓设备底层刷机工具,支持通过USB数据线对安卓设备进行Bootloader解锁、系统镜像刷写、分区管理等底层操作,并且可与ADB工具链协同工作,实现对安卓设备从引导层到系统层的全面控制。\\nfastboot安装包软件功能\\n1、Bootloader解锁\\n支持对符合条件的安卓设备进行Bootloader解锁,解锁后可刷入自定义Recovery或第三方ROM。\\n2、多分区刷写管理\u200b\\n允许用户针对系统核心分区进行精准操作,并支持.img格式镜像文件写入。\\n3、设备状态诊断\\n提供fastbootdevices命令检测设备连接状态,可通过getvar命令读取设备参数。\\n4、多模式重启控制\\n\u200b\\n一键将设备重启至系统、Recovery模式、Bootloader模式或Fastboot自身,方便在不同操作环节间快速切换。\\n5、批处理与脚本支持\u200b\\n可通过命令行参数组合实现批量操作,配合脚本自动化完成多设备刷机任务,提升运维效率。\\nfastboot安装包软件优势\\n1、官方底层兼容性\u200b\\n作为安卓原生工具链核心组件,完美适配所有通过谷歌认证的设备,确保刷机指令的标准化与可靠性。\\n2、轻量化绿色运行\u200b\\n软件包体积不足10MB,解压即用无需安装,不依赖.NET框架等运行库,不写入系统注册表。\\n3、跨平台统一体验\u200b\\nWindows、macOS、Linux三平台命令语法完全一致,用户无需重复学习,无缝切换操作环境。\\n4、故障安全机制\u200b\\n重要分区刷写前会进行校验提示,避免误操作导致设备变砖,并支持驱动自动重连,防止刷机过程中断。\\nfastboot安装包安装指南\\n1、在本站下载fastboot安装包安装包,打开点击安装。\\n2、安装完成之后打开进行使用即可。\\n常见问题解答\\nQ:设备连接后fastbootdevices无显示?\\nA:检查USB调试是否开启,", "url": "https://soft.ali213.net/down/33577.html"}, {"name": "2025 年 9月 16 日 随笔档案 - u95900090 - 博客园", "summary": "摘要:\\nFastboot是一个在Android开发环境中常用的工具,它是一个诊断工具,用于修改Android手机的固件。\\nfastboot\\ndevices:显示当前连接到计算机的设备。此命令用于检查设备是否成功进入fastboot模式并通过USB正确连接到计算机。\\nfastboot\\noem\\nunlock:解\\n阅读全文", "url": "https://www.cnblogs.com/I989809/p/archive/2025/09/16"}], "images": [{"url": "https://csdnimg.cn/release/downloadcmsfe/public/img/white-bg.ca8570fa.png"}, {"url": "https://view-cache.book118.com/view15/M03/29/2F/wKh2DmBFEb2AJ4QBAABBGGOKWjQ469.png"}, {"url": "https://dl-preview.csdnimg.cn/10680612/0001-d93a57d91099975025e32235659db1c3_thumbnail.jpeg"}, {"url": "https://soft.ali213.net/uploads/images/news/20250912/1757667997_436259.png"}, {"url": "https://soft.ali213.net/uploads/images/news/20250912/1757668002_867057.png"}, {"url": "https://pic.baike.soso.com/ugc/baikepic2/5066/cut-20211025200821-1459452595_jpg_479_320_12307.jpg/300"}, {"url": "https://pic.baike.soso.com/ugc/baikepic2/9582/20220319093030-52228981_jpeg_480_640_21396.jpg/300"}, {"url": "https://pic.baike.soso.com/ugc/baikepic2/5066/cut-20211025200821-1459452595_jpg_479_320_12307.jpg/300"}, {"url": "https://soft.ali213.net/uploads/images/news/20250912/1757667997_436259.png"}, {"url": "https://soft.ali213.net/uploads/images/news/20250912/1757668002_867057.png"}]}']
</think>`fastboot.exe` 是 Android 平台的**底层刷机工具**，比 ADB 更接近硬件层。

---

### 打个比方

| 工具 | 相当于 | 工作环境 |
|------|--------|----------|
| **ADB** | 遥控器 | 手机开机进入系统后，用电脑远程操控 |
| **Fastboot** | 手术刀 | 手机在"手术台"上（Fastboot 模式），系统没启动，直接操作底层分区 |

---

### 它能干什么

- **解锁 Bootloader**：刷机第一步，解除厂商锁定
- **刷入系统镜像**：刷 recovery、boot、system 等分区
- **救砖**：系统崩溃进不去时，用 Fastboot 模式抢救
- **重启设备**：重启到系统、Recovery、Bootloader 等不同模式

---

### 常用命令

```powershell
# 查看是否识别到设备（手机必须在 Fastboot 模式下）
.\fastboot.exe devices

# 解锁 Bootloader（会清除所有数据）
.\fastboot.exe oem unlock

# 刷入 recovery 镜像
.\fastboot.exe flash recovery recovery.img

# 重启手机
.\fastboot.exe reboot
```

---

### 如何进入 Fastboot 模式

大多数安卓手机：**关机状态下，同时按住【音量-】+【电源键】**，直到出现 Fastboot 界面。

也可以用 ADB 命令直接进入（如果手机还能正常开机）：
```powershell
.\adb.exe reboot bootloader
```

---

简单说：**ADB 管系统层面的事，Fastboot 管底层刷机救砖的事。** 你下载的这个包里两个工具都有，日常调试用 `adb`，刷机救砖才用 `fastboot`。








fastboot类似windows的bios吗

<think>
---


</think>**不完全是，但可以类比理解。**

---

### 更准确的类比

| 层级 | Android | Windows | 作用 |
|------|---------|---------|------|
| **最底层** | Bootloader（Fastboot 是它的一部分） | BIOS/UEFI | 硬件初始化、启动引导 |
| **恢复层** | Recovery | WinRE/WinPE | 系统修复、重置 |
| **系统层** | Android OS | Windows OS | 正常运行的操作系统 |

---

### 关键区别

**Fastboot ≠ BIOS，Fastboot 是 Bootloader 提供的一个“刷机接口模式”。**

- **BIOS/UEFI**：是一个完整的固件系统，有图形界面，能配置硬件、设置启动顺序等
- **Fastboot**：只是 Bootloader 的一个**命令行刷机模式**，没有图形界面，只能通过电脑发命令操作

更准确的类比是：

| Android | Windows |
|---------|---------|
| **Bootloader** | BIOS/UEFI |
| **Fastboot 模式** | BIOS 里的“从 U 盘启动”或“刷写固件”功能 |
| **Recovery** | Windows 恢复环境（WinRE） |

---

### 一句话总结

**Fastboot 更像是 BIOS 里那个“刷写固件”的通道，而不是整个 BIOS。** 它只负责接收电脑指令来刷分区、解锁等底层操作，不能像 BIOS 那样配置硬件参数。








<think>
---


</think>这两个命令用于配置 Android 设备的 USB 连接模式，具体作用如下：

## 1. `setprop sys.usb.config adb`
- **立即生效**，无需重启
- 将当前 USB 连接模式切换为 ADB（Android Debug Bridge）模式
- 重启后失效，会恢复为默认配置

## 2. `setprop persist.sys.usb.config adb`
- **持久化配置**，写入系统属性
- 设置下次启动时的 USB 默认模式为 ADB
- 重启后依然保持 ADB 模式
- 不会立即改变当前的 USB 连接状态

## 使用场景
通常这两个命令会**配合使用**：
```bash
setprop sys.usb.config adb           # 立即开启 ADB
setprop persist.sys.usb.config adb   # 确保重启后依然保持 ADB 模式
```

## 其他常见配置值
除了 `adb`，还可以设置为：
- `mtp` - 媒体传输协议（文件传输）
- `ptp` - 图片传输协议
- `rndis` - USB 网络共享
- `mass_storage` - USB 大容量存储
- `none` - 仅充电

**注意**：这些命令通常需要 root 权限才能执行。







adbd是什么，跟adb不一样吗

<think>
---


</think>## ADBD vs ADB 的区别

### **ADB (Android Debug Bridge)**
- 是一个**客户端-服务器程序**，包含三个组件：
  - **客户端**（`adb.exe`）：运行在电脑上，你通过命令行操作
  - **服务器**（`adb server`）：运行在电脑后台，管理客户端和守护进程的通信
  - **守护进程**（`adbd`）：运行在 Android 设备上

### **ADBD (ADB Daemon)**
- 是运行在 **Android 设备端**的后台进程
- 负责接收电脑端 ADB 发来的命令并执行
- 以 root 权限运行（如果设备已 root）

## 简单类比

```
电脑端：adb.exe (客户端) → adb server (服务器)
                            ↓ USB/TCP 连接
设备端：adbd (守护进程)
```

## 工作流程

1. 你在电脑执行 `adb shell`
2. 电脑的 `adb server` 通过 USB/TCP 发送命令
3. 设备的 `adbd` 接收命令并执行
4. 结果返回给电脑显示

## 为什么重启 adbd 可能有用

```bash
stop adbd   # 停止设备端守护进程
start adbd  # 重新启动守护进程
```

重启 `adbd` 可能会：
- 重新初始化 USB 连接
- 应用新的 USB 配置
- 解决 USB 模式切换问题

**注意**：`adbd` 重启后，你的 ADB 连接会断开，需要重新连接。







S C:\Users\luhonghao> adb root adb: unable to connect for root: device offline PS C:\Users\luhonghao> adb devices List of devices attached d07162935cd283cd offline

<think>
---


</think>你的设备显示 `offline`，这说明 `adbd` 重启后连接断开了，但设备还没有完全恢复在线状态。

## 解决方法

### 1. **等待设备重新上线**
```bash
# 等待 10-20 秒后重新检查
adb wait-for-device
adb devices
```

### 2. **如果还是 offline，尝试重新连接**
```bash
# 重启 ADB 服务
adb kill-server
adb start-server
adb devices
```

### 3. **物理重连 USB**
- 拔掉 USB 线
- 重新插入
- 在设备上允许 USB 调试授权（如果有弹窗）

### 4. **检查设备状态**
```bash
# 查看设备状态详情
adb devices -l
```

### 5. **如果设备已 root，重新获取 root 权限**
```bash
adb root
adb shell
```

## 常见 offline 原因

- **adbd 正在重启**：需要等待几秒
- **USB 调试授权过期**：需要重新授权
- **USB 线缆问题**：尝试更换 USB 端口或线缆
- **设备进入充电模式**：检查 USB 配置

**先执行第 1 步**，等待设备重新上线。如果长时间还是 offline，就拔插 USB 线试试。









am start -n com.android.launcher3/.uioverrides.QuickstepLauncher 
这个是回到主屏吗，有没有dhcp的命令？

<think>
---


</think>是的，`am start -n com.android.launcher3/.uioverrides.QuickstepLauncher` 是回到主屏幕的命令，它会启动启动器的主界面。

关于 DHCP 的命令，Android 中可以通过以下方式操作：

## 查看 DHCP 信息
```bash
# 查看当前 DHCP 租约信息
cat /data/misc/dhcp/dhcpcd-wlan0.lease

# 或者查看 DHCP 客户端状态
getprop dhcp.wlan0.ipaddress
getprop dhcp.wlan0.gateway
getprop dhcp.wlan0.dns1
```

## 重新获取 DHCP
```bash
# 重启 DHCP 客户端（需要 root）
dhcpcd -k wlan0  # 停止 DHCP
dhcpcd wlan0     # 启动 DHCP

# 或者使用 netcfg 重新配置
netcfg wlan0 dhcp

# 较新版本 Android 使用 cmd 命令
cmd wifi set-wifi-enabled enabled
cmd wifi reconnect
```

## 使用 dumpsys 查看网络信息
```bash
# 查看 WiFi 和 DHCP 详细信息
dumpsys wifi | grep -i dhcp
dumpsys netd | grep -i dhcp
```

注意：大部分 DHCP 操作需要 root 权限，普通用户通常只能查看信息。


