# 对话全流程要点、踩坑复盘（精简专业版）
## 一、核心业务场景
Android Compose + Hilt 依赖注入项目（AGP8.4、Kotlin1.9.22）构建编译排错，覆盖Gradle仓库配置、Hilt版本兼容、JDK环境、AS搜索操作四大模块。

## 二、关键知识点&规范要点
### 1. Hilt 版本体系与构件发布规则
1. Hilt完整构件包含三类：
   - `hilt-android`：运行时依赖
   - `hilt-android-compiler`：Android专属注解处理器
   - `hilt-compiler`：通用Java/Kotlin注解处理器
2. 高版本Hilt（≥2.50）新增配置项：`hilt { disableCrossVersionCheck = true }`，用于关闭版本交叉校验警告；2.49及更早版本无此字段，书写直接报语法未解析引用。
3. `androidx.hilt:hilt-navigation-compose` 适配Compose导航注入，需与Hilt主版本大版本对齐。

### 2. Gradle 仓库镜像配置规范
1. 国内开发推荐顺序：阿里云镜像前置 > Google官方仓 > MavenCentral，兼顾下载速度与完整性；
2. `RepositoriesMode.FAIL_ON_PROJECT_REPOS` 开启后，子模块无法自定义仓库，统一由根目录`settings.gradle.kts`管控；
3. 阿里云镜像存在**构件同步延迟/缺失问题**：部分小版本（2.49）官方仅推送Gradle插件，未上传`hilt-android-compiler`编译器构件，所有镜像均无法拉取。

### 3. Gradle JDK 优先级机制（极易踩坑）
1. 优先级从高到低：**Android Studio内置Gradle JDK设置 > gradle.properties中`org.gradle.java.home` > 系统环境变量JAVA_HOME**；
2. AGP 8.x 强制要求JDK17，JDK21/JDK26过高存在大量字节码、注解编译兼容异常，严禁使用；
3. 终端命令行执行`gradlew`仅读取系统`JAVA_HOME`，不会沿用AS内配置，极易出现路径失效报错。

### 4. Kapt注解处理器编译要求
1. 必须引入插件：`kotlin-kapt` + `hilt-android-gradle-plugin`；
2. 双编译器写法（2.48及以下稳定版）：同时引入两个kapt编译器，消除Hilt版本校验警告；
3. 单编译器兼容写法：仅保留`hilt-compiler`可绕开国内镜像缺失`hilt-android-compiler`的问题，Android注入功能完全不受影响。

## 三、全程踩坑清单（核心坑点）
### 坑1：盲目迭代Hilt版本，未核对构件发布完整性
- 问题：依次切换2.48→2.49→2.51，反复报`Could not find hilt-android-compiler`；
- 根源：2.49官方漏发Android专属编译器，阿里云同步不全；高版本国内拉取稳定性极差；
- 最优解：锁定**2.44**，阿里云镜像同步最全、无构件缺失，兼容性覆盖AGP8.4+Kotlin1.9。

### 坑2：混淆IDE编译与终端编译的JDK环境
- 问题：AS内可正常同步项目，PowerShell执行gradlew报错`JAVA_HOME路径无效`；
- 根源：AS使用内置JDK17，系统环境变量配置了不存在的JDK26，终端读取系统变量失效；
- 修复：临时终端覆写JAVA_HOME、gradle.properties指定JDK路径二选一。

### 坑3：高版本Hilt专属配置向下兼容错误
书写`disableCrossVersionCheck = true`在2.48/2.49版本，触发`Unresolved reference`语法报错；仅2.50+版本可使用该配置。

### 坑4：冗余依赖书写
Compose Material3重复引入两行依赖，无编译错误但增加打包体积；Hilt双编译器在2.50+版本属于冗余代码。

### 坑5：仓库配置顺序错误
国外源前置会导致国内网络下载超时、依赖拉取中断；单纯注释官方源又会导致极少数Android新构件无法获取。

## 四、最终稳定落地方案总结
1. Hilt锁定2.44，删除`hilt{}`配置块，仅保留`hilt-compiler`单注解处理器规避镜像缺失问题；
2. settings仓库：阿里云前置兜底官方源，兼顾速度与完整性；
3. JDK统一使用MS OpenJDK17，终端编译前临时覆写环境变量；
4. 精简冗余Compose依赖，规范Kapt插件引入。

## 五、附加：Android Studio搜索快捷键核心记忆点
1. 全局字符串检索：`Ctrl+Shift+F`；全局替换：`Ctrl+Shift+R`
2. 查找文件：`Ctrl+Shift+N`；查找类：`Ctrl+N`
3. 当前页查找：`Ctrl+F`；查看代码引用：`Alt+F7`
