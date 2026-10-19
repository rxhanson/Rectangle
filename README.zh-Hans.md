[English](README.md) | 简体中文

# Rectangle

Rectangle 是一款基于 Spectacle 的 macOS 窗口管理应用。

<img width="612" height="810" alt="Rectangle 的设置窗口（键盘快捷键）" src="https://github.com/user-attachments/assets/7db283bc-febb-4b83-87ca-20b9139352d4" />

## 系统要求

Rectangle 支持 macOS 14 及更高版本。

适用于 macOS 10.15 - 13：[v1.100](https://github.com/rxhanson/Rectangle/releases/tag/v1.100)

适用于 macOS 10.13 和 10.14：[v0.73](https://github.com/rxhanson/Rectangle/releases/tag/v0.73)

## 安装

可以从 <https://rectangleapp.com> 或 [Releases 页面](https://github.com/rxhanson/Rectangle/releases) 下载最新的 dmg。

或者通过 brew cask 安装：

```bash
brew install --cask rectangle
```

## 使用方法

[快捷键](https://support.apple.com/guide/mac-help/what-are-those-symbols-shown-in-menus-cpmh0011/mac)不言自明；至于吸附区域，如果你从未在 Windows 或其他窗口管理应用中使用过，则可能需要一些说明。

将窗口拖移到屏幕边缘。当鼠标指针到达屏幕边缘时，会显示吸附预览；松开鼠标时，Rectangle 会尝试按预览所示调整窗口的大小和位置。

| 吸附区域                                         | 对应操作                     |
|--------------------------------------------------|------------------------------|
| 左边缘或右边缘                                   | 左半屏或右半屏               |
| 顶部                                             | 最大化                       |
| 角落                                             | 对应角落的四分之一屏         |
| 左边缘或右边缘，紧邻角落的上方或下方             | 上半屏或下半屏               |
| 底部左侧、中间或右侧的三分之一区域               | 对应的三分之一屏             |
| 底部左侧或右侧的三分之一区域，然后拖移到底部中间 | 分别为左侧或右侧的三分之二屏 |

在**吸附区域**标签页中，启用**窗口动画（实验性）**可让窗口大小调整更加平滑；启用**模糊预览背景**则会以模糊效果显示吸附预览。两者默认均关闭。当应用限制其窗口大小或宽高比时，动画吸附会保持所选边缘或中心对齐。拖移已吸附的窗口时，窗口一经移动便会开始恢复先前的大小；若快速松开，剩余的恢复动画会继续播放。从标题栏最右侧拖移窗口时，仍可能出现明显的跳动。连按标题栏进行最大化/恢复时，所用的动画设置和时长与吸附相同。窗口动画在已知场景中已经过测试，但仍属实验性功能，因为在过渡期间反复更新窗口的大小和位置，在某些极端情况下可能会引发问题。

### 按行或按列平铺窗口

启用**在菜单中显示更多尺寸**，即可将「按行平铺窗口」和「按列平铺窗口」加入**平铺**子菜单。子菜单隐藏时，这两个操作的快捷键仍然可用。

前往设置 > 通用，点按**更多选项**，即可为**按行平铺窗口**和**按列平铺窗口**分别指定快捷键。每个操作都会排列当前聚焦的窗口所在显示器上、当前空间内的普通窗口，包括被其他窗口遮挡的窗口。如果没有普通窗口处于聚焦状态，则改用鼠标指针所在的显示器。**全部平铺**采用相同的显示器选择规则。通常情况下，其他显示器上的窗口会保持原位；如果目标显示器上没有窗口，则不会执行任何操作。当 Rectangle 的「将多个显示器视为一个」已启用、macOS 的「显示器具有单独的空间」已关闭时，「按行平铺窗口」和「按列平铺窗口」会改为在合并后的整个显示区域内平铺。行从上到下排列；列从左到右排列。无论哪个方向，Rectangle 都会根据各窗口移动前的左上角位置来决定排列顺序。

若当前布局无法识别，第一次按下时会从每行或每列一个窗口开始。重复执行该操作会在不同的网格布局之间循环切换。在设置 > 通用 > **更多选项**中，**每列最多窗口数**和**每行最多窗口数**各自独立控制相应的循环。两者的默认值均为 3，且与针对单个窗口的**重复命令**设置相互独立。将任一上限设为 1，即可让对应操作保持原先每行或每列一个窗口的行为。已保存的现有上限会被保留。

窗口会在已占用的行或列之间均衡分配，不会刻意留出空的单元格。例如，当列上限为 3 时，六个窗口会依次循环为六列各一个、三列各两个、两列各三个，然后重新开始。五个窗口则依次循环为各列窗口数 `1,1,1,1,1`、`2,2,1` 和 `3,2`。窗口较少的列仍会填满整个高度；行同样会填满整个宽度。重复的布局会被跳过，因此当上限为 3 时，四个窗口会在四组各一个与两组各两个之间交替。上限大于窗口数量时，不会增加新的布局。

在应用允许的情况下，各列宽度相等、各行高度相等，误差不超过一个显示器像素。网格会填满所选的工作区域，即扣除 macOS 预留区域（如菜单栏和程序坞）以及在 Rectangle 中设置的屏幕边缘空隙后的范围。应用的尺寸限制优先：如果两列共用 1000 像素，而其中一列至少需要 600 像素，那么 600/400 就是一种可行的分配方案。如果没有任何分配方案能满足所有应用的限制，Rectangle 仍会尝试执行该布局，这可能会留下空隙或造成重叠。如果某个应用未能及时响应，布局可能会不完整。

移动窗口、调整窗口大小、打开或关闭窗口，或者更改屏幕边缘空隙，都不会使窗口自动重新排列。下次按下同一操作时，会根据当前的窗口及其位置重新应用该操作当前生效的网格布局。如果某次按下不会使布局发生变化，则会直接切换到下一个布局。如果将上限降到低于当前生效布局的值，下次按下时会使用允许范围内最大的布局。Rectangle 仅在运行期间保留当前生效的布局。重新启动后，如果网格完整且可识别，第一次按下会从该网格切换到下一个布局；否则会从每行或每列一个窗口开始。

待办窗口会被排除在外，规则与 Rectangle 的其他多窗口操作相同。各行或各列的条带不会占用为待办侧边栏预留的现有空间。例如，可用空间为 1000 像素且侧边栏预留 200 像素时，其他窗口会在剩余的 800 像素内平铺，而待办窗口保持原位。

### 循环切换堆叠窗口

当多个窗口吸附到同一区域时（例如三个窗口都在左半屏），只有最前面的那个窗口可见。在设置 > **行为** > **堆叠窗口**中，为**循环切换堆叠窗口**和**反向循环切换堆叠窗口**指定按键。每按一次，就会把当前聚焦的窗口所属堆叠中的一个窗口移到最前面。

只要某个窗口与首次按下快捷键时聚焦的窗口位于同一位置，或者按照**窗口重叠时错开位置**的设定与之错开，无论大小，都属于该堆叠。开启**仅堆叠大小相同的窗口**后，该窗口还必须与之大小相同（宽度和高度相差均在 24 点以内，因此以整字符单元为单位吸附的终端窗口仍然算在内），所以与某个半屏共用一角的最大化窗口不属于该半屏的堆叠。堆叠窗口列表也遵循这一设置。**循环切换堆叠窗口**会先把堆叠最底部的窗口移到最前面；**反向循环切换堆叠窗口**则会先把紧跟在最前面窗口之后的那个窗口移到最前面。反复按下可依次遍历堆叠中的每一个窗口。若在聚焦堆叠之外的窗口时按下任一快捷键，则会从该窗口所属的堆叠重新开始。若当前聚焦的窗口没有任何与之堆叠的窗口，Rectangle 会发出提示音。

### 鼠标按钮快捷键

窗口操作的快捷键可以是鼠标按钮而不是按键，例如许多鼠标上都有的侧键。侧键非常适合与**循环切换堆叠窗口**和**反向循环切换堆叠窗口**搭配使用。要指定鼠标按钮，请在设置中点按该操作的快捷键栏（位于**键盘快捷键**标签页，或**行为** > **堆叠窗口**中），然后在指针悬停在设置窗口上时按下中键或其他附加按钮。按下按钮时按住 ⌃、⌥、⇧ 和 ⌘ 中的任意键，即可将其一并纳入快捷键，与键盘快捷键相同。每个操作只有一个快捷键，因此鼠标按钮会取代该操作的键盘快捷键。鼠标左键和右键无法指定。

按下已指定的按钮时，按下事件只会传给 Rectangle，因此指针下方的应用不会同时响应，例如不会让浏览器后退。未指定的按钮照常工作。与键盘快捷键一样，当被忽略的应用位于最前面或正在录制快捷键时，鼠标按钮快捷键会停用；将同一个按钮指定给多个操作时，会在这些操作之间循环切换。

鼠标按钮快捷键与键盘快捷键一样，作用于当前聚焦的窗口。若要改为作用于指针下方的窗口，请在**行为** > **更多选项**中开启**鼠标按钮快捷键作用于指针下方的窗口**。焦点会保持不变，但通过把窗口移到最前面来实现的操作（例如循环切换操作）除外。指针下方没有窗口时，Rectangle 会发出提示音。

如果按下某个按钮却没有被录制，可能是其他软件（例如鼠标附带的实用工具）在 Rectangle 接收到之前就重新映射了该按钮。

### 忽略应用

忽略某个应用意味着：当该应用位于最前面时，快捷键会从 macOS 取消注册；当该应用不再位于最前面时，快捷键会重新向 macOS 注册。如果某些应用与 Rectangle 使用相同的快捷键，而你又不想更改这些快捷键，这个功能就很有用。

1. 聚焦要忽略的应用（将该应用的某个窗口置于最前面）。
1. 打开 Rectangle 菜单，选择「忽略 <应用名>」

若要取消忽略之前已选择忽略的应用，只需再次将该应用置于最前面，打开 Rectangle 菜单，然后取消选中「忽略 <应用名>」。

## 通过 URL 执行操作

打开 URL `rectangle://execute-action?name=[name]`。请尽可能不要激活 Rectangle。

`[name]` 的可用值：`left-half`、`right-half`、`center-half`、`top-half`、`bottom-half`、`top-left`、`top-right`、`bottom-left`、`bottom-right`、`first-third`、`center-third`、`last-third`、`first-two-thirds`、`last-two-thirds`、`maximize`、`almost-maximize`、`maximize-height`、`smaller`、`larger`、`center`、`center-prominently`、`restore`、`next-display`、`previous-display`、`move-left`、`move-right`、`move-up`、`move-down`、`first-fourth`、`second-fourth`、`third-fourth`、`last-fourth`、`first-three-fourths`、`last-three-fourths`、`top-left-sixth`、`top-center-sixth`、`top-right-sixth`、`bottom-left-sixth`、`bottom-center-sixth`、`bottom-right-sixth`、`specified`、`reverse-all`、`top-left-ninth`、`top-center-ninth`、`top-right-ninth`、`middle-left-ninth`、`middle-center-ninth`、`middle-right-ninth`、`bottom-left-ninth`、`bottom-center-ninth`、`bottom-right-ninth`、`top-left-third`、`top-right-third`、`bottom-left-third`、`bottom-right-third`、`top-left-eighth`、`top-center-left-eighth`、`top-center-right-eighth`、`top-right-eighth`、`bottom-left-eighth`、`bottom-center-left-eighth`、`bottom-center-right-eighth`、`bottom-right-eighth`、`tile-all`、`tile-rows`、`tile-columns`、`cascade-all`、`cascade-active-app`、`cycle-stacked-windows`、`cycle-stacked-windows-backward`

示例（在 shell 中执行）：`open -g "rectangle://execute-action?name=left-half"`

URL 也可用于忽略/取消忽略应用。

```
rectangle://execute-task?name=ignore-app
rectangle://execute-task?name=unignore-app
```
还可以指定 bundle identifier，例如：
```
rectangle://execute-task?name=ignore-app&app-bundle-id=com.apple.Safari
```

## 隐藏偏好设置的终端命令

参见 [TerminalCommands.md](TerminalCommands.md)

## 与 Spectacle 的差异

* Rectangle 使用 [MASShortcut](https://github.com/rxhanson/MASShortcut) 来录制快捷键。Spectacle 使用的是自己的快捷键录制器。
* Rectangle 提供了额外的窗口操作：在不调整大小的情况下将窗口移动到各个边缘、仅最大化窗口高度，以及接近最大化窗口。
* 「下一个／上一个屏幕三等分」已改为明确的「左首１／３」、「左侧２／３」、「中间１／３」、「右侧２／３」和「右首１／３」。这些操作会根据屏幕方向而变化：例如，「左首１／３」在横屏时是左侧的三分之一，在竖屏时则是顶部的三分之一。
  * 不过，可以用「左首１／３」和「右首１／３」这两个操作来模拟 Spectacle 的三等分循环。也就是说，反复执行「左首１／３」会在各个三等分位置（左首、中间、右首）之间依次循环，反复执行「右首１／３」则反向循环。
* 提供了一个选项，可让窗口在连续执行向左或向右的操作时跨显示器移动。
* 将窗口拖移到屏幕边缘或角落时会自动吸附。此功能可以禁用。

## 常见已知问题

### Rectangle 无法将窗口移动到其他空间（桌面）

Apple 从未发布过用于实现此功能的公开 API。Rectangle Pro 提供「下一个／上一个空间」操作，但目前没有计划将其加入 Rectangle。

### 使用三等分或其他较小布局时窗口会重叠

某些应用会强制限定窗口的最小尺寸，而该尺寸大于所请求的布局。例如，最小宽度为 600 点的窗口无法放入显示器上 504 点宽的三等分区域。如果应用让窗口保持大于所请求的尺寸，Rectangle 会将窗口保留在屏幕内，并短暂显示一个带有窗口图标的「已达到窗口最小尺寸」HUD。请改用更大的布局（例如半屏），或手动缩小相邻的窗口。Rectangle 无法突破应用的最小窗口尺寸限制。

### iTerm2 的窗口大小调整略有偏差

默认情况下，iTerm2 只会以字符宽度为增量调整窗口大小。iTerm2 内部可能有设置可以禁用此行为，不过也可以用以下命令进行更改。

```bash
defaults write com.googlecode.iterm2 DisableWindowSizeSnap -integer 1
```

### Rectangle 似乎会导致通知中心停止响应

此问题似乎只影响少数用户。若要避免，请取消勾选「拖移以吸附窗口」复选框。
参见 issue [317](https://github.com/rxhanson/Rectangle/issues/317)。

### 故障排除

如果窗口没有按预期调整大小或移动，以下是一些有助于查明原因的初步排查步骤。此类问题大多是由其他应用引起的。

**快速修复（请先尝试这些）：**

1. **锁定并解锁 Mac**——这个简单的步骤能解决许多问题，尤其是在系统更新之后。
1. 确保 macOS 已更新到最新版本。
1. 重新启动 Mac（这通常能修复 macOS 刚更新后出现的问题）。

**诊断问题：**

4. **启用调试日志**（请参阅下一节中的说明）——这有助于确认 Rectangle 是否正常工作。
1. 日志内容很直观。如果计算得出的矩形与最终得到的矩形完全一致，那么很可能是另一个应用在造成问题。

**检查冲突：**

6. 确保没有其他窗口管理器应用正在运行。
1. 确保窗口行为异常的那个应用没有任何冲突的快捷键。
1. 尝试使用菜单项来执行窗口操作，或者把快捷键改成其他组合，这样就能判断问题是否出在快捷键上。

**高级故障排除：**

9. 如果怀疑可能是另一个应用在造成问题，请尝试新建一个 macOS 用户并以该用户身份登录。
1. 如果需要创建 issue，请保存日志以便附在其中。

#### 尝试重置 Rectangle 的 macOS 辅助功能权限：

```bash
tccutil reset All com.knollsoft.Rectangle
```

或者，也可以不使用 tccutil 终端命令，而是通过以下步骤完成。
1. 如果 Rectangle 正在运行，请先退出
2. 在系统设置 -> 隐私与安全性 -> 辅助功能中，先停用 Rectangle，然后用减号按钮将其移除。（务必按此顺序完成这两个步骤）
3. 重新启动 Mac。
4. 启动 Rectangle，并按提示启用相关设置。

## 查看调试日志

1. 在 Rectangle 菜单打开的状态下，按住 alt（option）键。
1. 选择「查看日志…」菜单项，它会出现在「关于」菜单项的位置上。
1. 执行 Rectangle 命令时，日志会显示在该窗口中。

## 导入与导出 JSON 配置

设置窗口的「应用设置」标签页中提供了通过 JSON 文件导入和导出配置的按钮。

启动时，如果存在配置文件 `~/Library/Application Support/Rectangle/RectangleConfig.json`，Rectangle 会加载该文件，并在文件名中加上日期时间戳将其重命名，以免在后续启动时再次读取。

## 偏好设置存储

Rectangle 的配置使用 NSUserDefaults 存储，也就是保存在以下位置：
`~/Library/Preferences/com.knollsoft.Rectangle.plist`
请注意，v0.41 及更高版本中的快捷键采用了不同的存储格式，无法在更早的版本中加载。

该文件可以备份，也可以转移到其他电脑上。

如果使用的是 Rectangle v0.44 及更高版本，还可以通过设置窗口中的导入/导出按钮，以 JSON 文件的形式在多台电脑之间共享偏好设置和快捷键。

> [!NOTE]  
> 如果配置选项在应用重新启动后无法保留，并且是通过 Homebrew 安装的，则需要使用 `--zap` 选项卸载后再重新安装。

```
brew uninstall --zap rectangle
brew install rectangle
```

## 卸载

退出应用并将其移到废纸篓即可卸载 Rectangle。可以使用以下终端命令，从电脑中移除 Rectangle 存储在 defaults 中的偏好设置：

```bash
defaults delete com.knollsoft.Rectangle
```

> [!TIP]  
> 如果是通过 Homebrew 安装的，卸载时应加上 `--zap` 选项，以确保同时移除 plist 条目。

```
brew uninstall --zap rectangle
```

---

## 参与贡献

[Multitouch](https://multitouch.app) 应用使用了 Rectangle 的逻辑。[Rectangle Pro](https://rectangleapp.com/pro) 应用则完全构建于 Rectangle 之上。如果你贡献的重要代码或本地化内容被合并进 Rectangle，给我发一封电子邮件即可免费获得一份 Multitouch 或 Rectangle Pro 的许可证。Sparkle、MASShortcut 或 Spectacle 的贡献者同样可以免费获得 Multitouch 或 Rectangle Pro 的许可证。

### 贡献更多尺寸与位置

Rectangle 的界面刻意保持简洁。如果想添加「键盘快捷键」标签页中没有的尺寸与位置，现在可以把它们添加到「额外快捷键」区域，该区域可通过「通用」标签页底部的省略号按钮打开。

### 本地化

如果想为本地化做贡献，所有翻译都保存在 Main.strings 中。

欢迎提交拉取请求，添加新的本地化或改进现有本地化。

### 在 Xcode 中运行应用（面向开发者）

Rectangle 使用 [Swift Package Manager](https://www.swift.org/package-manager/) 来安装 Sparkle 和 MASShortcut。

MASShortcut 的原始仓库已被归档，因此 Rectangle 使用的是我的[复刻版本](https://github.com/rxhanson/MASShortcut)。如果要做任何涉及 MASShortcut 的改动，请向我的复刻版本提交拉取请求。

由于新增了 Liquid Glass 图标并为较旧版本的 macOS 提供了回退方案，在低于 macOS 26 的版本上构建会失败。可以删除「Asset Catalog Other Flags」以便在低于 26 的版本上进行本地构建（但如果要创建拉取请求，请不要把这一改动一并提交）。

## 致谢

如上所述，Rectangle 使用了 [MASShortcut](https://github.com/rxhanson/MASShortcut) 的一个复刻版本（至今仍运行良好），并使用 [Sparkle](https://sparkle-project.org) 实现更新功能。

Rectangle 应用图标的 Big Sur 版本由 Giovanni Maria Cusaro（@gmcusaro）设计。应用图标的 Liquid Glass 版本由 [Alexander Käßner](https://www.alexkaessner.de)（@alexkaessner）设计。

当然，多年来还有许多来自社区的贡献 :)
