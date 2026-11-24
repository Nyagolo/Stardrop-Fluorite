# Stardrop 莹石版

[English](#stardrop-fluorite-edition)

当前改版版本：**1.0.2**。查看[本次更新说明](RELEASE-NOTES-1.0.2.md)。

这是基于 [Floogen/Stardrop](https://github.com/Floogen/Stardrop) 的非官方改版，用于管理《星露谷物语》的 SMAPI 模组。发布包基于上游 1.11.0 开发分支的 [e899ee7](https://github.com/Floogen/Stardrop/commit/e899ee7a6ffa3479d247e5626672e5d8c297f48e) 制作。保留原项目的 [GPL-3.0 许可证](LICENSE) 和[项目说明及贡献者名单](README.upstream.md)。

## 改版功能

### 分类与批量管理

- **自定义分类**：可在设置中开启，不改变原有文件夹目录。右键菜单按父子分类分层显示。
- **文件夹分类**：支持通过右键菜单将模组移动到其他分类文件夹。
- **同文件夹一起处理**：可选择「同时包含同文件夹下的其他模组」，快速整理同一模组的多个组件。
- **批量操作**：支持多选模组进行分类、删除等操作。也可以打开「分类管理」，选好分类后点「应用到所选模组」，并按需勾选「同时包含同文件夹下的其他模组」。
- **保留浏览位置**：归类针对实际右键点击的模组或当时的多选项。刷新后尽量保留原来的浏览位置和分类折叠状态。

例如，East Scarp 的以下组件可以通过同文件夹选项一起处理：

```text
East Scarp C#
East Scarp Core
East Scarp FTM
East Scarp NPCs
```

### 备注

- **两行预览**：列表最多显示两行，超出时用省略号。
- **单击编辑，双击展开**：单击可直接编辑；双击可打开完整备注窗口。
- **跨配置方案共享**：同一模组的备注在各配置方案之间同步。

### 缩略图

- **添加与替换**：双击缩略图或「＋」即可选择本地图片。
- **从模组目录选图**：选图窗口默认打开该模组所在文件夹，自定义图片优先显示。

### 其他优化

- **模组页面链接**：当更新接口没有返回页面地址时，使用有效的 Nexus 编号生成网页链接；接口提供的页面地址仍优先使用。
- **列表性能**：按需加载可见行的缩略图，分批处理缩略图缓存，并优化分类展开和折叠时的列表刷新。

## 你可能需要知道的操作

- **双击模组名称**，打开该模组所在的文件夹。
- **双击备注栏**，打开完整的备注窗口，可查看和编辑长备注。单击备注栏可直接在列表中编辑。
- **双击缩略图**，选择本地图片替换。没有图片时，双击「＋」即可添加。选图窗口会从该模组所在的文件夹开始。

## 使用 Windows 版

从本仓库的 Releases 下载 Windows x64 压缩包，完整解压到一个可写目录，再双击 `Stardrop.exe`。运行所需的 .NET 运行时已包含在压缩包中。首次运行按 Stardrop 提示设置游戏和模组路径。

## 一键更新

关闭 Stardrop，双击同目录的 `Update-Stardrop.cmd`。更新需要网络和 [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)。

更新工具会下载 Floogen/Stardrop 的 `development` 分支，应用随包附带的补丁，再编译并替换当前目录中的程序。替换前的文件会备份到 `Update Backups`。如果上游改动导致补丁无法应用，工具会停止，等待发布者更新补丁。

## 从源码构建

在源码根目录运行：

    dotnet publish Stardrop/Stardrop.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish

`Updater` 目录包含更新程序和补丁。原项目用于测试和发布的 GitHub Actions 工作流保存在 `upstream-workflows`，供参考。

## Stardrop Fluorite Edition

[简体中文](#stardrop-莹石版)

Current fork version: **1.0.2**. See the [release notes](RELEASE-NOTES-1.0.2.md).

This is an unofficial fork of [Floogen/Stardrop](https://github.com/Floogen/Stardrop), a SMAPI mod manager for Stardew Valley. The release is based on [commit e899ee7](https://github.com/Floogen/Stardrop/commit/e899ee7a6ffa3479d247e5626672e5d8c297f48e) from the upstream 1.11.0 development branch. See the original [GPL-3.0 license](LICENSE) and [project README and contributor credits](README.upstream.md).

### What’s different

#### Categories and batch management

- **Custom categories**: Enable them in Settings to organize mods without changing your folder structure. The right-click menu groups subcategories under their parents.
- **Folder-based categories**: Move mods to another category folder through the right-click menu.
- **Include other mods in the same folder**: Organize multiple components of a mod together using the same-folder option.
- **Batch operations**: Select multiple mods to categorize or delete them together. You can also open category management, choose a category, and apply it to the selected mods, optionally including other mods in the same folders.
- **Keep your place**: Category commands use the row you right-clicked or the mods selected at the time. Refreshing the list restores your browsing position and collapsed groups where possible.

For example, the following East Scarp components can be handled together using the same-folder option:

```text
East Scarp C#
East Scarp Core
East Scarp FTM
East Scarp NPCs
```

#### Notes

- **Two-line preview**: Notes show up to two lines in the list, with an ellipsis for longer text.
- **Single-click to edit, double-click to expand**: Edit directly in the list or open the full note editor.
- **Shared across profiles**: Notes for the same mod stay in sync across profiles.

#### Thumbnails

- **Add or replace images**: Double-click a thumbnail or **+** to choose a local image.
- **Start in the mod’s folder**: The image picker opens in the mod’s folder, and your custom image takes priority.

#### Other improvements

- **Mod page links**: If the update API does not return a page URL, a link is generated from a valid Nexus ID. A URL supplied by the API still takes priority.
- **List performance**: Thumbnails are loaded on demand for visible rows, cache updates run in batches, and the list refreshes more efficiently when categories expand or collapse.

### Shortcuts you might find useful

- **Double-click a mod name** to open the folder where the mod is installed.
- **Double-click a note cell** to read or edit the full note in a separate window. Single-click to edit it directly in the list.
- **Double-click a thumbnail** to replace it with a local image. If the mod has no thumbnail, double-click **+** to add one. The image picker starts in the mod’s folder.

### Install on Windows

Download the Windows x64 ZIP from Releases, extract it to a writable folder, and run `Stardrop.exe`. The .NET runtime is included. On first launch, follow Stardrop’s prompts to set the game and mod paths.

### One-click update

Close Stardrop and double-click `Update-Stardrop.cmd` in the same folder. Updating requires internet access and the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0).

The updater downloads the upstream `development` branch and applies the bundled patches. After a successful build, it installs the updated files and keeps the previous versions in `Update Backups`. If an upstream change prevents a patch from applying, the updater stops until a compatible patch is available.

### Build from source

Run this command from the repository root:

    dotnet publish Stardrop/Stardrop.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish

The update scripts and patches are in `Updater`. The original project’s GitHub Actions workflows are kept in `upstream-workflows` for reference.
