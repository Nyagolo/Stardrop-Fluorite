# Stardrop 自定义版

这是基于 [Floogen/Stardrop](https://github.com/Floogen/Stardrop) 的非官方改版，用于管理《星露谷物语》的 SMAPI 模组。发布包基于上游 1.11.0 开发分支的 [e899ee7](https://github.com/Floogen/Stardrop/commit/e899ee7a6ffa3479d247e5626672e5d8c297f48e) 制作。保留原项目的 [GPL-3.0 许可证](LICENSE) 和[项目说明及贡献者名单](README.upstream.md)。

## 改版功能

- 三级自定义分类，支持批量归类、折叠子分类、重命名、删除和查看模组数量。移动分类时保留列表位置。
- 备注在列表中最多显示两行。单击可行内编辑，双击可打开完整编辑窗口。同一模组的备注可跨配置方案使用。
- 双击缩略图或「＋」可添加或替换本地图片。选图窗口从该模组所在目录开始。自定义图片优先于 Nexus 图片。
- 改进了大列表的缩略图加载和分类展开表现。

## 使用 Windows 版

从本仓库的 Releases 下载 Windows x64 压缩包，完整解压到一个可写目录，再双击 `Stardrop.exe`。运行所需的 .NET 运行时已包含在压缩包中。首次运行按 Stardrop 提示设置游戏和模组路径。

## 一键更新

关闭 Stardrop，双击同目录的 `Update-Stardrop.cmd`。更新需要网络和 [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)。

更新工具会下载 Floogen/Stardrop 的 `development` 分支，应用随包附带的补丁，再编译并替换当前目录中的程序。替换前的文件会备份到 `Update Backups`。如果上游改动导致补丁无法应用，工具会停止，等待发布者更新补丁。

## 从源码构建

在源码根目录运行：

    dotnet publish Stardrop/Stardrop.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish

`Updater` 目录包含更新程序和补丁。原项目用于测试和发布的 GitHub Actions 工作流保存在 `upstream-workflows`，供参考。
