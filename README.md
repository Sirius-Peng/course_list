# 课表 · CourseList

面向 **iOS 26 锁屏**的轻量原生课程表，附 watchOS 26 App 和 WidgetKit 复杂功能。

## 已实现

- iPhone：今日课程卡片、横向可滚动周课表、课程详情、手动加课（单次 / 每周重复）、导入预览、学期日期设置、演示课表与清空。
- 锁屏：矩形（课程名 / 时间 / 地点）、圆形（课程进度或下一课时间）、单行摘要。
- WidgetKit：本地 App Group 缓存、上课/下课时间线、深链课程详情、单色及强调色显示。
- 课表核心：BIT101 已展开 ICS、时区、行折叠、转义、日/周重复、RDATE/EXDATE、稳定去重、校验与原子持久化。
- 学校拉取：BIT-Login challenge、图形/短信验证码、轮询、Bearer 课表导出、ICS 下载。
- ICS 订阅：HTTPS / webcal 链接预览与订阅、Keychain 保存、条件刷新、自动更新开关与停止订阅。
- Watch：课程卡片、今日列表、本地缓存、快照传输、版本/哈希校验与接收确认；iPhone 安装包内嵌完整 Watch App 与复杂功能扩展。
- 课前提醒：系统本地通知，支持提前 5 / 10 / 15 / 30 分钟；前台横幅、后台/锁屏通知，点击查看课程。提供 10 秒测试提醒。
- 图标：统一的青绿「日历 + 时钟」图标，iPhone 支持默认、深色、着色外观，Watch 使用同一视觉。矢量源见 `Assets/AppIcon.svg`。

学校拉取和 Watch 同步已有代码及模拟接口 / 核心协议测试；真实学校账号和配对设备联调单列为后续验收，不把 mock 测试当成线上可用证明。

## 打开工程

主工程：`CourseList.xcodeproj`。四个产品 Target 共用本地 `ScheduleCore` Swift Package。

```sh
git clone https://github.com/Sirius-Peng/course_list.git
cd course_list
open CourseList.xcodeproj
```

在 Xcode 为四个 Target 选择开发团队，将 Bundle ID 与 `group.dev.courselist.shared` 改为团队实际登记的标识，保持每台设备上 App 与扩展的 App Group 一致。随后用 `CourseListApp` scheme 安装到 iPhone；手表 App 作为 companion app 一同打包。发布签名和商店上传尚未执行。

如果本机只有 iOS 模拟器 runtime，可使用 `CourseListiPhoneOnly.xcodeproj`。它与主工程引用同一份 App / Widget 源码，仅不嵌入 Watch，便于先验证锁屏主链路。

重建工程需要 XcodeGen；iPhone-only 生成脚本还需要 Python PyYAML：

```sh
xcodegen generate
python3 Scripts/generate-iphone-project.py
```

## 体验锁屏小组件

1. 启动 App，选择“先体验演示课表”，或在“导入”中选择 `.ics` / 学校拉取。
2. 核对学期第一周周一、结束日期，然后预览并确认替换。
3. 长按 iPhone 锁屏 → 自定 → 锁定屏幕 → 添加小组件 → **课表**。
4. 矩形占两个小槽位；圆形占一个；单行可添加到时间上方的日期栏。
5. 上课时显示当前课程；空闲时显示整个有效学期内最近的下一课程。

演示课表明确显示“演示”，不假装真实学校数据。`Fixtures/example.ics` 是固定于 2026-10-13/14 的测试样例，导入时选择覆盖该日期的学期范围。

## 真实账号认证测试

登录入口支持 `courselist://login` 深链，直接打开“学校拉取”。默认服务已于 2026-10-13 无凭据检查：HTTP 200，响应 `BIT Login Services API is running`。

1. 在 App 的“学校拉取”中点“检查认证服务连接”。
2. 手动填写学号和统一认证密码；学期代码留空时请求当前学期。
3. 点“认证并获取课表”；按提示手动输入图形或短信验证码。
4. 下载成功后会显示课程数量和日期预览，核对校历日期，再点“确认替换并同步”。
5. 测试异常时记录所处阶段、HTTP 状态或屏幕提示，便于定位；密码和验证码不写入日志。

## 解析边界

首版支持 FREQ=DAILY/WEEKLY，INTERVAL、COUNT 或 UNTIL，以及 WEEKLY 的普通 BYDAY、WKST=MO、RDATE、EXDATE。MONTHLY、复杂 BY* 规则、RECURRENCE-ID 单次覆盖、RDATE PERIOD 会明确返回错误，不静默丢失课程。全天事件不视为有时段的课。

源 ICS 没有完整校历时，首周建议值须由用户核对；学期超过一年、课程超出学期、文件超过 4 MB 等情况会阻止替换。失败时保留原成功课表。学校密码、验证码与 challenge token 仅在内存中使用，不同步给 Watch / Widget。

## 验证

```sh
./Scripts/verify.sh
```

已验证：59 项核心 / 接口 XCTest 和 8 项 iPhone UI 测试通过，含手动加课持久化、每周重复、系统通知授权和前台横幅；iOS 26.4 模拟器锁屏实际显示了课程名、时间、地点与演示标识。锁屏截图保存于 `.implementation/screenshots/lock-screen.png`。

59 项 XCTest 覆盖课程边界、跨日、重复课、时区、哈希、缓存、同步顺序、认证 HTTP 合约和提醒的提前时间、过期过滤、排序、60 条队列边界。`UITests` 提供演示、导航、清空、导入表单和通知横幅测试。

在本机重跑 iPhone 编译或 UI 测试：

```sh
IOS_RUNTIME_BUILD=23E244 ./Scripts/verify-ios.sh build
IOS_RUNTIME_BUILD=23E244 ./Scripts/verify-ios.sh test
```

`IOS_RUNTIME_BUILD` 是本机已安装 iOS 26.4 的 build 编号；其他机器按实际 runtime 填写，匹配 SDK 时可省略。脚本自动选择已有 iOS 26 模拟器，或通过 `IOS_SIMULATOR_ID` 指定。

本机 Xcode 26.6 的 SDK 为 26.5，已安装的 iOS runtime 为 26.4。验证时临时选择已安装 runtime，结束后恢复原匹配设置。watchOS 26.5 runtime 已安装；0.2.0 的完整 Watch 图标资源、App、复杂功能扩展已编译签名，iPhone 与 Apple Watch 真机均已安装并启动。真实课程同步接收、复杂功能添加到表盘及手表通知镜像仍需分别验收。

WidgetKit 的刷新受系统调度影响，不以秒级切换作为保证。组件不会通过后台持续运行或频繁联网刷新。

## 参考

- [BIT101 课表入口](https://github.com/BIT101-dev/BIT101/blob/749ea4fe8fb2b26f874e758e232a62944359aa1d/src/views/Schedule.vue)
- [BIT-Login 接口说明](https://github.com/BIT101-dev/BIT-Login/blob/f999a47f4f99a68d2d087a3127feffdb9703caa1/docs/rest-api.md)
- [Apple 锁屏矩形样式](https://developer.apple.com/documentation/widgetkit/widgetfamily/accessoryrectangular)
- [Apple WidgetKit 时间线](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)

本项目独立实现客户端与课表模型，参考接口行为，未拷贝参考仓库的业务代码。

## 0.2.0 真机包与提醒设置

`CourseListDevice.xcodeproj` 可由下列脚本按自己的团队与 App Group 生成；该本机签名工程不提交到仓库。两个 App 与两个扩展须使用相同的已登记 App Group，Watch profile 须包含自己的手表 UDID。iPhone 安装包含 `Watch/CourseListWatchApp.app/PlugIns/CourseListWatchWidgets.appex`。

可复用构建命令（替换设备 UDID / 团队 / App Group）：

```sh
COURSELIST_TEAM=YOUR_TEAM_ID \
COURSELIST_APP_GROUP=group.dev.courselist.YOUR_TEAM_ID.shared \
IPHONE_DEVICE_UDID=YOUR_IPHONE_UDID \
WATCH_DEVICE_UDID=YOUR_WATCH_UDID \
IOS_RUNTIME_BUILD=23E244 ./Scripts/build-device.sh
```

开启提醒：App → 设置 → 课前提醒 → 开启课前弹窗提醒 → 允许通知 → 选择提前时间。导入或修改课表、清空课表、调整时间、关闭提醒都会重建/取消本 App 的提醒队列。最近最多 60 次未来提醒进入系统队列；打开 App 或系统允许的后台刷新时补排。已错过的提醒不会立即补发。提醒开关默认关闭，首次开启才申请通知权限，授权成功后保存开关与提前时间。

手机负责安排通知。手表通过 iPhone Watch App 的通知设置镜像，遵循系统的手机解锁/手表佩戴分流，不重复创建第二套提醒。通知横幅与声音仍受系统通知设置、专注模式等影响；后台刷新不保证固定周期。建议定期打开 App 补排长期课表。手表安装需开发者模式；当前为开发签名测试包，签名有效期见 `.implementation/releases/0.2.0/bundle-verification.json`。

本次安装包、源代码差异、验证记录、回滚脚本在 `.implementation/releases/0.2.0/`；回滚仅还原指定目录的源文件，不自动覆盖真机课表或卸载 App。本文提到的 `.implementation/` 日志、截图与签名包为本机验证产物，不随 Git 仓库分发。

## 0.3.0 手动添加课程

- 在“课表”右上角点 **＋**，或在已有课表的日期列下点 **＋**，填写名称、地点、日期、上/下课时间与备注。今日页与设置页也有“手动添加课程”入口。
- 支持单次上课，以及“每周重复”至所选截止日期（含当天）；按北京时间展开为每次课程。首次使用可直接创建学期，无需先导入学校课表。
- 当前学期已有数据时，仅追加课程，不替换导入课程。重叠课程会提示确认；相同名称、地点和时间的课程会阻止重复添加；空名称、倒置时间、跨天或超出学期会提示错误。
- 刷新 ICS / 学校课表会保留手动课程；新学期范围未涵盖已有手动课程时拒绝替换并保留原数据，请调整学期范围。导入预览数量指源文件课程数，最终课表另含保留的手动课程。
- 演示课表添加真实课程前会明确确认移除演示课程，避免混用。课程详情中可删除某一次手动课程，不影响同系列其他周。
- 保存/删除通过同一原子快照提交路径，刷新组件、发送 Watch 同步并重排已开启的提醒；手动操作不伪造学校课表的最近拉取时间。
- 快照新增可选 `manualCourseIDs`，旧快照缺省时仍按原 payload/hash 解码。含手动课程的快照需手机与手表均更新至 0.3.0 读取。清空课表仍会清除所有课程（包括手动课程）。

回归：40 项核心/认证/提醒/手动课程测试；UI 测试新增手动课程保存、重启保留、删除、取消与每周重复流程。具体执行结果见 `.implementation/releases/0.3.0/VERIFICATION.txt`。

## 0.3.1 Watch 视觉优化

- 保留 Watch App 首页改版：青绿渐变铺满屏幕；大字课程卡、状态色、课堂进度、彩色今日列表、下一课与同步信息分层；新增课程详情及复杂功能深链，长名称/地点可点开查看；40/42mm 使用紧凑字号与间距。
- 表盘复杂功能单独采用 `WatchComplicationView`，不再复用手机锁屏排版。矩形关闭 watchOS 默认内容边距，自行控制 2pt 内边距以利用槽位；强化课程名、时间、地点及状态，当前课程附系统原生进度条。
- 圆形使用铺满槽位的彩色外环、原生下课倒计时或下一课时间；单行保留课程摘要。倒计时/进度采用系统日期控件，不通过高频后台任务刷新。
- 彩色模式下当前课为青绿、下一课为琥珀；强调色模式通过 `widgetAccentable` 跟随表盘主题。Always On 减弱背景；可显示面积、背景是否保留及颜色由所选表盘/系统渲染模式决定，不扩大到槽位以外。
- iPhone 主界面、锁屏组件的原排版以及快照/认证/通知/同步数据路径保持不变。修正一项既有单元测试：比较解码后的快照，不依赖 JSON 对象键的输出顺序。
- `-WatchPreview current/upcoming/empty/expired/long/needsImport` 仅在 Debug 明确指定启动参数时启用只读布局样例，带演示标识，不保存/导入/发送样例。
- `.implementation/releases/0.3.1/preview-host` 是独立的原生布局 QA 宿主，复用真实组件 View；截图标注“表盘组件布局预览”，并不是已安装到真实表盘的截图。它不被打进 iPhone/Watch 的安装包。

验证：45 项核心测试、6 项 iPhone UI 回归测试；watchOS 26.5 原生组件布局预览覆盖 46mm、40mm 长名称、彩色/单色分支，Watch App 另检查小屏首页。实际表盘的系统裁剪、主题强调色与 Always On 显示仍需在所用表盘上验收。

参考：[Apple 的 WidgetRenderingMode](https://developer.apple.com/documentation/widgetkit/WidgetRenderingMode)、[额外平台/外观适配](https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances)、[内容边距控制](https://developer.apple.com/documentation/swiftui/widgetconfiguration/contentmarginsdisabled())。

## 0.4.0 ICS 链接订阅

1. 进入 **导入 → 链接订阅**，粘贴 HTTPS 或 `webcal://` 链接（会转换为 HTTPS）。链接不必以 `.ics` 结尾，支持带访问令牌的查询参数。
2. 点击“下载并预览”，核对课程与学期日期，再点“确认订阅并同步”。下载或预览本身不会改动当前课表或保存链接。
3. 在 **设置 → ICS 链接订阅** 查看来源域名、最近检查/内容更新时间；可以立即刷新、关闭自动更新、更换链接或停止订阅。

- 当前支持一个订阅源，负责替换“导入课程”部分，保留手动添加课程。停止订阅只停止更新，保留已有课程；清空、加载演示或确认导入学校/本地文件会停止旧订阅，防止后续自动覆盖新来源。
- 自动更新默认开启，打开 App 时及系统允许的 BGAppRefresh 中，距最近尝试至少 6 小时再检查；手动刷新不受间隔限制。后台执行时间由 iOS 调度，非固定周期保证。
- 使用 ETag / Last-Modified 条件请求，304 不当作空日历；成功确认未变化时仍更新缓存检查时间与设备快照新鲜度。失败时保留原课表与手动课程，并显示状态，后续可重试。
- HTTPS 下载最大 4 MB，流式读取时也检查上限；最多等待请求30秒/资源60秒。支持的 ICS 规则与文件导入一致。HTML 登录页、无效 UTF-8、HTTP 错误、越界学期、无效课程会阻止替换。
- 链接及订阅状态存入本机 Keychain（AfterFirstUnlockThisDeviceOnly、不同步 iCloud），不写入 UserDefaults、App Group 课程快照或 Watch 同步载荷。界面管理页只显示域名；下载异常不回显可能含令牌的 URL。HTTP/嵌入用户名密码的链接不接收，重定向也要求 HTTPS。
- 取消下载、停止订阅、更换来源会使旧请求失效，避免迟到的响应写回。文件源/学校源的切换在提交前校验，保存失败时保留原课表并恢复订阅配置。
- 测试：59项核心测试；UI新增订阅预览、Keychain重启持久化、304刷新、停止后保留课程、无效URL/HTML失败保留原课表、取消预览。Debug `-UITestICSFeed` 仅对 `fixture.invalid` 使用模拟响应，不包含真实订阅地址或账号。

本次日志、双端安装包、源差异及可执行回滚脚本位于 `.implementation/releases/0.4.0/`。尚未使用真实订阅 URL 做服务器联调；后台6小时刷新需在设备上长期观察。
