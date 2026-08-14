# AsmrDownloader

[https://asmr.one](https://asmr.one/)的GUI下载工具，支持 Windows / macOS。建议搭配[zDll233/Again: flutter 本地(Windows)音声播放器](https://github.com/zDll233/Again)食用。

![image-20241207172351-veagtwx](screenshots/image-20241207172351-veagtwx.png)

## 使用方法

1. **搜索sourceId**：  
    左上搜索框输入`sourceId`​点击搜索，或者点击右方按钮读取剪贴板并搜索。只有`sourceId`​合法才能搜索。 

    合法的`sourceId`​：RJ, VJ或BJ开头再加上数字，忽略大小写。音声作品`sourceId`​绝大部分都是RJ号，少部分是VJ号，BJ没看到过不知道有没有，可能还有其他格式，后续再添加。
2. **选择下载任务进行下载：**   
    ![image-20241207172518-mticj41](screenshots/image-20241207172518-mticj41.png)​

    > 搜索框支持直接粘贴 asmr.one 作品页 URL（如 `https://asmr-200.com/work/RJ01619789?path=["RJ01619789","舔耳ONLY音轨"]#work-tree`），自动提取 sourceId 与音轨树目录。
3. 下载配置选项  
    ![image-20241207172605-5b40kae](screenshots/image-20241207172605-5b40kae.png)​

    1. 选择下载路径：点击文件夹按钮选择下载文件夹（默认下载位置在应用目录内）
    2. 下载封面：即搜索出来的左边图片。  
        不推荐勾选。因为分辨率不高，不如直接下载根目录下的附送图片。
    3. 启用代理：  
        检测并使用系统代理配置，**如果没有开启代理则无法勾选**。  
        一般也不需要勾选。原因见下一个配置项。
    4. api channel:  
        ![image-20241130171701-pzhxtq3](screenshots/image-20241130171701-pzhxtq3.png)  
        这个选项只会影响搜索的api，但是不同api提供的下载api是一样的，即不会影响下载本身。  
        只有asmr-100需要启用代理，asmr-200、asmr-300和文件下载都不需要。所以大部分时候不需要开启代理，除非asmr-200、asmr-300搜索不到，可以试试asmr-100。  
    5. 开启整理：  
        勾选后下载完成自动整理到 Navidrome 媒体库（见下方「Navidrome 整理」）。  
        旁边的「整理」按钮可随时手动整理当前作品。

## Navidrome 整理

将下载的作品整理成 [Navidrome](https://www.navidrome.org/) 媒体库结构，配合 Navidrome 的文件夹浏览（或后续用 mp3tag 等工具批量打标签）使用：

```
<整理路径>/<Circle名>/<RJ号> - <CV1&CV2...> - <作品标题>/<RJ号>/
├── cover.jpg                  ← 自动获取封面并重命名（Navidrome 自动识别专辑封面）
├── 00.规则说明.wav
├── ex01.杂谈.wav
├── ex02.杂谈.wav.lrc          ← 歌词/字幕一并整理
└── ...
```

- **音轨扁平化**：下载目录树（如 `音声/`、`特典/` 等）全部拍平到 RJ 目录，保留原名
- **字幕转歌词**：`.vtt` 字幕自动转换为 LRC——同名 `.lrc` 优先（人工字幕）；否则转换 `.vtt` 并内嵌为音频歌词标签，同时生成 `<音轨名>.lrc` 侧车文件
- **汉化版自动识别**：汉化版作品的 Circle 名是汉化组，整理时自动跟踪到原版作品取真实社团名（如 RJ01628652 → 空心菜館）
- **封面**：整理时复用封面下载功能获取封面，保存为 `cover.jpg`，Navidrome 自动识别
- **幂等**：重复整理自动跳过已存在且大小一致的文件
- **智能截断**：目录名过长时按字符/字节双上限截断（专辑名 ≤ 80 字符 / 240 字节，Circle 名 ≤ 50 字符 / 150 字节），保留 RJ 号、尾部加 `…`，兼容 Windows MAX_PATH 与 macOS 255 字节组件限制；已按旧长名整理的目录不会自动改名，重新整理（关闭「仅整理未整理的」）会生成截断后的新目录，旧目录可手动删除
- **自动整理**：勾选「开启整理」后，每次下载完成自动整理；整理路径未设置时自动整理会跳过（需先手动整理一次或配置路径）
- **批量整理**：下载完成后自动登记到注册表（存于应用数据目录，不在下载目录），点「整理全部」一次整理所有（或仅未整理的）作品，带进度/取消/结果列表；「注册表」可手动清理条目（含一键清理缺失目录的条目）
- **自动识别 RJ 号**：批量整理时自动扫描下载目录（≤ 4 层），识别带 `RJ`/`VJ`/`BJ` 前缀的目录（如 `RJ12345678`），未注册的作品自动补录注册表并整理：在线拉取元数据/封面，失败则降级为目录名解析（`CV&CV-标题`）；注册表中目录被移动过的条目也会自动修正路径
- **降级标签**：work info 接口获取不到数据时，标题依次降级为 tracks 接口携带的 workTitle → 粘贴 URL 里的音轨树目录名（`path` 参数面包屑）→ sourceId；artist 依次降级为 CV 名 → sourceId，保证目录结构与音乐标签不落空

## AI 字幕翻译（ChickenRice 联动）

可调用 [Faster-Whisper-TransWithAI-ChickenRice](https://github.com/TransWithAI/Faster-Whisper-TransWithAI-ChickenRice) 为作品生成 AI 中文字幕：

- **基于「同名字幕是否存在」自动判断**：若某个音轨已有 `.lrc` / `.vtt` / `.srt` 官方字幕，则跳过 AI 翻译（官方字幕够用，不浪费算力）；仅对**没有任何字幕的音轨**调用 AI 生成中文字幕。
- **用法**：
  1. 自行下载 ChickenRice 对应 release（按你的显卡选 CUDA/AMD/CPU 版本），解压到本地。
  2. 在应用搜索框右侧的 **AI字幕** 控件里点击 `code` 图标选择其 `infer.exe`。
  3. 选择任务（翻译=中文 / 转录=原文）和设备（auto/cuda/cpu）。
  4. 点 **字幕** 按钮手动为当前作品生成，或勾选 **自动** 在下载完成后自动翻译。
- 生成的字幕与音轨同名（`xxx.lrc`），Navidrome 整理时会被自动采纳并内嵌为歌词标签。
- 注意：首次运行会下载/加载 Whisper 模型，较耗时、占用 GPU 显存；进程可通过取消按钮中断。

## 功能特色

1. 断点续传：  
    应用下载之前会先检查本地是否有已下载的内容，检查文件是否下载完成。下载完成则跳过，没完成则继续下载。  
    所以你可以随意关闭应用取消下载，再重新下载，进度会被继承。  
    同理，如果网络不佳导致下载中断，应用会无限重试直到下载完成。
2. 快捷复制音声信息  
    点击即可复制。  
    ![image-20241207173053-auux9hi](screenshots/image-20241207173053-auux9hi.png)​

## 构建与发布

- **Windows**：`flutter build windows --release`
- **macOS**：`flutter build macos --release`（要求 Xcode 27+，部署目标 macOS 12.0+）
- **CI**：推送 `v*` tag 自动构建 Windows + macOS 并发布到 GitHub Release（tag 触发在 fork 仓库可能不生效，可用 `gh workflow run "AsmrDownloader Release Build" --ref main -f version=vX.Y.Z` 手动触发）
- macOS 产物未签名，首次打开需右键 → 打开

# 已知问题

1. 无法稳定触发的封面大小获取错误的问题。

# 其他

1. 这个只是单线程下载，所以下载速度不是很快，主要想自己写个能稳定下载的工具。  
    不过你可以打开多个应用手动多进程下载🙃
2. asmr api实现参考：[slqy123/ASMRManager: download, manage and play the voices on asmr.one](https://github.com/slqy123/ASMRManager)
3. 感谢 [https://asmr.one](https://asmr.one/)，网站运营不易，请合理使用本工具。
