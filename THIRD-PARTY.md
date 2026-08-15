# 第三方组件与声明

本应用通过「AI 翻译引擎内置安装器」**按需下载**以下第三方组件（不随本应用仓库/Release 分发）。各组件的版权与许可证如下。

## Faster-Whisper-TransWithAI-ChickenRice

- 仓库：https://github.com/TransWithAI/Faster-Whisper-TransWithAI-ChickenRice
- 开发团队：AI汉化组 (https://t.me/transWithAI)
- 许可证：MIT License

```
MIT License

Copyright (c) 2025 TransWithAI

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## AI 模型（安装引擎时从 HuggingFace 下载）

| 模型 | 来源 | 说明 |
|---|---|---|
| Whisper 系列权重 | OpenAI（https://github.com/openai/whisper，MIT） | 基础模型；CTranslate2 转换版由社区/上游提供 |
| whisper-large-v2-translate-zh-v0.2-st-ct2 | https://huggingface.co/chickenrice0721/whisper-large-v2-translate-zh-v0.2-st-ct2 | 日→中翻译模型（ChickenRice 官方推荐） |
| whisper-ja-1.5B-ct2 | https://huggingface.co/TransWithAI/whisper-ja-1.5B-ct2 | 日文转录模型 |
| Whisper-Vad-EncDec-ASMR-onnx | https://huggingface.co/TransWithAI/Whisper-Vad-EncDec-ASMR-onnx | VAD 模型（基于 Silero VAD，MIT） |
| whisper-base 配置文件 | https://huggingface.co/openai/whisper-base | 特征提取配置（MIT） |

模型下载支持从 hf-mirror.com 镜像回退（与上游 download_models.py 行为一致）。

## 运行时依赖（随 ChickenRice 发行包分发）

ChickenRice 发行包内嵌的依赖（faster-whisper、CTranslate2、onnxruntime、transformers、ffmpeg 等）遵循各自的开源许可证，详见上游仓库说明。
