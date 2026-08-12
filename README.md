# AsmrDownloader

[https://asmr.one](https://asmr.one/)的GUI下载工具，支持 Windows / macOS。建议搭配[zDll233/Again: flutter 本地(Windows)音声播放器](https://github.com/zDll233/Again)食用。

![image-20241207172351-veagtwx](screenshots/image-20241207172351-veagtwx.png)

## 使用方法

1. **搜索sourceId**：  
    左上搜索框输入`sourceId`​点击搜索，或者点击右方按钮读取剪贴板并搜索。只有`sourceId`​合法才能搜索。 

    合法的`sourceId`​：RJ, VJ或BJ开头再加上数字，忽略大小写。音声作品`sourceId`​绝大部分都是RJ号，少部分是VJ号，BJ没看到过不知道有没有，可能还有其他格式，后续再添加。
2. **选择下载任务进行下载：**   
    ![image-20241207172518-mticj41](screenshots/image-20241207172518-mticj41.png)​
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
- **汉化版自动识别**：汉化版作品的 Circle 名是汉化组，整理时自动跟踪到原版作品取真实社团名（如 RJ01628652 → 空心菜館）
- **封面**：整理时复用封面下载功能获取封面，保存为 `cover.jpg`，Navidrome 自动识别
- **幂等**：重复整理自动跳过已存在且大小一致的文件
- **自动整理**：勾选「开启整理」后，每次下载完成自动整理；整理路径未设置时自动整理会跳过（需先手动整理一次或配置路径）

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
