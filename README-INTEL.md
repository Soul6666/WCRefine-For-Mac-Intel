# WCRefine for Mac — Intel（x86_64）移植分支

上游是 [plumblossom26/WCRefine-For-Mac](https://github.com/plumblossom26/WCRefine-For-Mac)
（Mac 微信增强：防撤回、消息屏蔽、复读、圆角头像、退群监控、禁用截图检测、多开等）。
上游只支持 Apple Silicon，本分支让它能在 Intel Mac 上编译运行。

**状态：部分可用。** 纯 swizzle 类功能可用，依赖机器码锚点的功能尚未在 x86_64 上登记。

- 移植细节、已完成改动、构建方法、以及锚点移植的坑：见 [INTEL-PORT.md](INTEL-PORT.md)
- 上游 README：见 [README.md](README.md)

构建：

```bash
make ARCH=x86_64 all
./build/wcrefine-check --app /Applications/WeChat.app
bash Installer/install.sh --app /Applications/WeChat.app
open -n ~/Applications/WCRefine-WeChat.app
```

MIT 许可，版权归上游作者。本分支非官方，问题请报到这里。
