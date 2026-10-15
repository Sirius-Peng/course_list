# iOS / watchOS 课程表 App 实施方案

更新日期：2026-10-13。项目现已建立原生工程；首版以 iOS 26 锁屏小组件为重点。实施现状与运行步骤见 README.md；真实学校账号和双端真机仍列为后续验收。

## 1. 目标与首版范围

建立一个轻量原生课程表 App，iPhone 负责导入、刷新和管理课表，Apple Watch 负责离线查看。两端共享课程计算逻辑。

| 场景 | 显示内容 |
| --- | --- |
| 正在上课 | 当前课程名称、开始—结束时间、地点；较大界面附下一节 |
| 当前空闲 | 下一课程名称、开始—结束时间、地点；跨天时标明日期 |
| 今日课程结束 | “今日课程已结束”，并显示最近未来课程，而非只搜索今天 |
| 学期内无后续课程 | “暂无后续课程” |
| 尚未导入 / 缓存已超出有效学期 | “请导入课表” / “请更新课表” |

首版包含：iPhone 周课表、今日列表、课程详情、学期切换、手动刷新、ICS 导入、学校课表拉取、Watch 今日列表、Watch 表盘复杂功能、iPhone 锁屏小组件、同步状态和离线缓存。

后续再加入：手动调课与补课、课前通知、桌面小组件、Smart Stack 专门优化、iCloud 跨 iPhone 同步、系统日历导出、Live Activities。首版不做社区、成绩、地图或独立 Watch 登录。

## 2. 参考项目的实际数据链路

用户提供的 BIT101 是 Vue Web 前端。其课表页调用 `bitLoginRequest`，指定 `jxzxehall` 服务，向 `/api/jxzxehall/schedule_ics` 提交学期 `kksj`，取得 `{url, note}`；App 需要继续下载 ICS，再解析为自身模型。[课表入口源码](https://github.com/BIT101-dev/BIT101/blob/749ea4fe8fb2b26f874e758e232a62944359aa1d/src/views/Schedule.vue)

认证入口采用 challenge 与 access token，并包含等待短信等状态。[认证客户端源码](https://github.com/BIT101-dev/BIT101/blob/749ea4fe8fb2b26f874e758e232a62944359aa1d/src/utils/bit-login.ts)

相关 BIT-Login 服务端还提供 `/api/jxzxehall/courses` 结构化课表接口及图形验证码交互。首版建议以 ICS 为主线，保留独立数据源协议，后续接结构化接口以获得周次和节次等更多元数据。[服务端说明](https://github.com/BIT101-dev/BIT-Login/blob/f999a47f4f99a68d2d087a3127feffdb9703caa1/README.md)

同组织已有 BIT101-iOS 仓库，包含课表、Watch 和 Widget 相关模块，可对照模块划分与同步实现；当前项目仍建议做独立的小型原生 App。[iOS 仓库说明](https://github.com/BIT101-dev/BIT101-iOS/blob/5740495c67501d37f8167ada596f0c8b35ca411f/README.md)

### 导入流程

1. iPhone 输入账号与认证信息，选择学期，发起 challenge。
2. 按状态展示图形验证码或短信验证码输入，处理取消、过期、失败和超时。
3. 认证完成后，用 challenge ID 与 Bearer token 获取 ICS 链接。
4. 下载 ICS，校验文件格式、日期范围、课程时间与课程数量。
5. 解析并展示导入预览；成功后原子替换该学期缓存，生成共享快照并发起 Watch 同步。
6. 导入失败时保留上一份成功课表，显示失败原因及上次成功更新时间。

学校拉取由 iPhone 主 App 执行，小组件和 Watch 不处理登录或验证码。服务地址通过配置注入；开发第一阶段确认现有服务可用性与真实返回格式，再确定使用已有服务还是部署可维护的 BIT-Login 实例。这里的“本地优先”指课表存储与显示，不表示认证完全在设备内完成。

提供 Files 选择 `.ics` 文件及分享导入入口，方便先验证解析、显示和双端同步；该导入方式与学校自动拉取使用同一模型，替代数据源不会改变界面逻辑。

## 3. 原生技术架构

建议采用 Swift + SwiftUI + WidgetKit + WatchConnectivity。按当前需求，首版最低版本设为 iOS 26 / watchOS 26，锁屏显示优先；锁屏 accessory 小组件和 WidgetKit 复杂功能的能力起点是 iOS 16 / watchOS 9。[Apple 平台说明](https://developer.apple.com/videos/play/wwdc2022/10050/)

建立四个产品 Target 和一个共享 Swift Package：

```text
CourseListApp                 iPhone App
CourseListWidgets             iPhone 锁屏小组件扩展
CourseListWatchApp            Apple Watch App
CourseListWatchWidgets        Watch WidgetKit 复杂功能扩展
ScheduleCore                  数据模型、ICS 解析、状态计算、时间线生成
```

共享包使用 Foundation，避免依赖平台 UI、登录和网络副作用。两端界面各自适配。SwiftUI 的布局复用不等于四个产品 Target 合并。

```text
学校认证 / ICS 文件
        ↓
iPhone 数据源适配 → ScheduleCore → iPhone 本地快照
                                  ├→ iPhone 周课表
                                  ├→ iPhone App Group → 锁屏小组件
                                  └→ WatchConnectivity → Watch 本地快照
                                                       ├→ Watch App
                                                       └→ Watch App Group → 复杂功能
```

App Groups 只用于同一设备上 App 与扩展共享数据，iPhone 和 Watch 之间另走 WatchConnectivity。[App Groups 文档](https://developer.apple.com/documentation/xcode/configuring-app-groups)

首版可采用版本化 Codable JSON 快照与原子文件写入，不急于引入数据库。主 App 和扩展读取同一设备上的已验证快照，不让每个扩展自行维护一份独立课表。

## 4. 数据与计算规则

### 核心模型

- `Semester`：学期 ID、显示名、校历第一周起始日、结束日、学校时区。
- `CourseOccurrence`：稳定 ID、课程名称、开始时间、结束时间、地点、可选教师、来源、所属学期。
- `ScheduleSnapshot`：schemaVersion、accountEpoch、revision、contentHash、fetchedAt、有效日期范围、学期与课程实例。
- `CourseDisplayState`：正在上课、空闲且有下一节、无后续课程、未导入、缓存超期；同时携带课程摘要和更新时间信息。

ICS 已展开的事件直接形成课程实例；结构化课表则通过校历、周次、星期、节次表展开。首周基准来自学校校历或明确配置，不将首次导入日期当作开学日期。校园、季节或作息版本变化时允许更换节次表。

### 状态算法

- 当前课程集合满足 `start <= now && now < end`，即结束时刻不再视为当前课。
- 下一课程集合取 `start > now` 中最早开始的一组，搜索整个有效学期。
- 同一时间重叠课程显示冲突提示；完整界面列出所有课程，小组件使用稳定排序的主课程并提示“另有 N 门”。
- 连堂课按照导入事件时间区间显示；若源数据拆为多个事件，只有名称、地点、来源标识一致且规则明确时才合并。默认课间仍为空闲。
- 地点为空显示“地点待定”，课程名较长时使用单行省略，详情页保留全文。
- 内部使用绝对 Date，课表与周次按学校时区 `Asia/Shanghai` 计算；跨时区旅行时明确标注“北京时间”，不随设备时区改变课程时刻。
- 正常课程显示与“数据可能未更新”是独立维度；缓存尚在有效学期内时继续显示课程并附旧数据标识，不把联网失败误判为无课。

### ICS 特别处理

实现行折叠、转义、SUMMARY、LOCATION、DTSTART、DTEND、TZID 与 UTC 时间解析；仅日期的全天事件不判为“正在上课”。外部导入遇到 RRULE、RDATE、EXDATE、RECURRENCE-ID 时需要正确展开、应用例外与取消状态，未实现的规则明确反馈，避免静默漏课。[iCalendar 格式规范](https://www.rfc-editor.org/rfc/rfc5545)

BIT-Login 当前生成器按周次展开为 VEVENT，而且每次导出重新生成 UUID。因此同学期刷新采用“整批校验后替换”，而不是按 ICS UID 追加；本地幂等指纹结合来源、学期、课程名、时间和地点，避免重复导入。[ICS 生成器源码](https://github.com/BIT101-dev/BIT-Login/blob/f999a47f4f99a68d2d087a3127feffdb9703caa1/bit-login/src/jvmShared/kotlin/cn/bit101/bitlogin/api/jxzxehall/Course.kt)

## 5. 双端同步与离线策略

iPhone 是首版唯一课表写入端，Watch 是离线只读端。“双端同步”指课表、展示配置和同步状态一致，不引入两端同时编辑的冲突合并。

- 小体积的最新快照或版本清单用 `updateApplicationContext`；可达时用 `sendMessage` 做即时请求和确认；完整学期数据较大时用 `transferFile`。[WatchConnectivity 示例](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)
- 同步版本带账号代次与单调递增 revision；文件到达后校验 schema、内容哈希、账号代次和有效范围，忽略旧版本，避免排队中的旧文件覆盖新课表。
- Watch 保存整学期已展开课程，在手机不在附近时继续计算当前课和下一课。
- 两端各自生成时间线，不同步每分钟变化的“当前课程字符串”。
- Watch 持久化成功后回复接收确认；iPhone 分别显示“已发送 / 等待手表 / 手表已接收”，不把传输发起当作同步完成。
- 安装、配对或重连后比较 revision 并补发；启动会话前产生的快照保留待发送。
- 退出、切换账号或删除课表生成带新版本的清空记录，并刷新本机小组件；Watch 收到后清空。断连设备在接收前仍可能保留旧缓存，界面显示其最后同步时间。

账号与凭据只留在 iPhone 认证模块；需要保存的 token 放 Keychain，密码默认不持久化。Watch 与 Widget 仅接收课程快照，不接收密码、验证码或认证 Cookie。

## 6. 锁屏小组件与表盘复杂功能

两个平台都使用 WidgetKit；优先实现矩形样式，再补圆形和单行样式。矩形 accessory 可用于 iPhone 锁屏和支持对应槽位的 Watch 表盘。[矩形样式文档](https://developer.apple.com/documentation/widgetkit/widgetfamily/accessoryrectangular)

| 样式 | 首版内容 |
| --- | --- |
| accessoryRectangular | 状态与课程名 / 开始—结束时间 / 地点，共三行 |
| accessoryInline | “上课中·高数·A201”或“10:00 高数” |
| accessoryCircular | 当前进度或下一课时间，附短地点；点击看完整信息 |
| accessoryCorner | Watch 后续增强，短地点和时间标签 |

用户在系统锁屏编辑界面或 Watch 表盘编辑界面手动添加。不同表盘提供的槽位不同，完整三要素以矩形为主，小尺寸按信息优先级精简。点击组件深链进入对应日期和课程详情。

### “实时显示”的实现定义

课表本身具有可预测的上课和下课边界。每次读到最新缓存后，预生成未来 72 小时的状态时间线：当前条目、各课程开始/结束边界、跨日边界和窗口末尾条目；同一时刻去重，过近边界按实测合并。每个条目使用相同状态算法。

系统在时间线边界切换显示；课表变更、成功同步或配置变化时调用 `WidgetCenter.reloadTimelines` 请求重建。数据源刷新与显示状态切换分别处理：前者需要重新拉取，后者可完全依靠本地课表。WidgetKit 的预算与系统调度影响刷新时机，验收不承诺秒级精确切换。此处不是每分钟联网轮询。[Apple 时间线与刷新说明](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)

时间线窗口到期时请求补充；若系统延迟重新加载，终止条目避免把上一门课永久显示为上课中，并保留可理解的日期/更新时间提示。新课表到达也可能延迟显示，要在真机测试中记录延迟和低电量表现。

## 7. App 界面

### iPhone

建议三个顶层入口：

1. **课表**：顶部“第 N 周”与日期范围，左右切换周次，周一至周日网格；课程颜色稳定，今天与当前课高亮；点击展开详情。
2. **今日**：顶部当前/下一课卡片，下方今日课程列表；当天结束后显示下一次课程日期。
3. **设置**：导入与刷新、学期选择、首周和作息配置、最近更新时间、Watch 同步状态、锁屏/表盘添加教程。

首版只读课程详情；任意课程编辑、调课和个人修订留到第二版，以免刷新时覆盖用户修改。

### Apple Watch

以当前/下一课卡片及今日纵向列表为主，用 Digital Crown 滚动；可查看最近未来课程及完整地点。入口提供“请求手机同步”，同时显示上次接收时间。Watch 不照搬手机的七列周网格。

## 8. 分阶段交付

以下是单名熟悉 Apple 平台开发者的工作量估计，不是固定完成日期；假设开发签名、iPhone/Watch 真机和测试用课表可用。认证适配与服务部署是最大变量。

| 阶段 | 估计工作日 | 可验收成果 |
| --- | --- | --- |
| P0 数据验证 | 2–3 | 确认登录状态、验证码、ICS 和结构化字段，确定服务方式，建立脱敏 fixture |
| P1 核心与 iPhone | 4–6 | 共享包、ICS 导入、状态单测、周课表、今日页与本地缓存 |
| P2 学校数据接入 | 3–5 | 认证界面、学期选择、真实拉取、错误恢复、刷新幂等 |
| P3 Watch 同步 | 3–4 | Watch 今日列表、快照版本协议、确认状态与离线运行 |
| P4 外部展示 | 3–4 | 锁屏矩形组件、Watch 矩形复杂功能、圆形/单行适配与时间线 |
| P5 联调与交付 | 3–5 | 边界测试、长时间真机观察、低电量/断连测试、可安装测试版本 |

合计约 18–27 个工作日，约 4–6 周。涉及新增服务运维、直接移植认证或发布审核时另计。开发先用脱敏 ICS 完成核心与两端显示，再接真实认证，防止外部接口拖住所有功能。

## 9. 验收与测试清单

### 自动测试

- 时间为 07:59 / 08:00 / 09:39 / 09:40 时，08:00–09:40 课程分别得到空闲、上课中、上课中、空闲状态。
- 测试下一课跨日、周末、单/双周、临时取消、重叠课程、连堂、学期最后一课与无课学期。
- ICS 测试包含中文、折行、转义、空地点、UTC/TZID、全天事件、重复规则与异常输入。
- 同学期重复导入不增长课程数量；无效下载不覆盖旧快照；随机 UID 变化不制造重复课程。
- 相同 fixture 和 now 输入在 iPhone、Watch、Widget 使用的共享逻辑中得到相同结果。
- 同步测试覆盖乱序、重复消息、旧账号迟到文件、未知 schema、哈希失败、清空记录和重连补发。

### 真机验收

- 用户能在锁屏和支持矩形槽位的表盘找到并添加组件。
- 上课/下课前后对照系统时间记录切换延迟，不用前台运行效果替代后台表现。
- 手机离线或远离后，Watch 用已同步课表继续显示，并正确跨日。
- 测试前台、后台、重启、系统终止进程、低电量、Always On、不同字号和长课程名称。
- 实测首次导入和更新后的接收确认；断连时显示待同步，重连后内容最终一致。
- 没有通知或日历权限时，核心课表及小组件仍正常使用；首版不依赖 EventKit 写入系统日历。

## 10. 下一步实施顺序

先完成 P0 的真实数据契约确认，同时以 fixture 建立 ScheduleCore 和四个 Target。第一项纵向交付是“导入一份 ICS → iPhone 今日页 → Watch 离线今日页 → 两端矩形组件”。此后补齐学校认证、周视图、版本恢复与完整验收。

需要在开发启动时确定的产品参数：实际设备支持范围、课表服务部署方式、默认学期与作息表、测试账号认证流程。方案默认是 iOS 26 / watchOS 26、iPhone 主导写入、Watch 离线只读、ICS 优先。
