# Stardrop 莹石版

[English](#stardrop-fluorite-edition)

当前改版版本：**1.0.2**。查看[本次更新说明](RELEASE-NOTES-1.0.2.md)。

这是基于 [Floogen/Stardrop](https://github.com/Floogen/Stardrop) 的非官方改版，用于管理《星露谷物语》的 SMAPI 模组。发布包基于上游 1.11.0 开发分支的 [e899ee7](https://github.com/Floogen/Stardrop/commit/e899ee7a6ffa3479d247e5626672e5d8c297f48e) 制作。保留原项目的 [GPL-3.0 许可证](LICENSE) 和[项目说明及贡献者名单](README.upstream.md)。

## 改版功能

| 问题 | 解决方案 |
| --- | --- |
| 模组一多，两级分类不够用，右键菜单也很难找。 | 新增三级自定义分类。设置开启，不会改变原有文件夹目录，右键菜单按父子分类分层显示。 |
| 分类和子分类太多，查找和整理费时。 | 「分类管理」支持重命名和删除。分类树可折叠，每个分类旁显示模组数量。 |
| 多个模组要归入同一分类，逐个操作太慢。 | 在列表里多选模组，打开「分类管理」，选好分类后点「应用到所选模组」。也可以勾选「同时包含同文件夹下的其他模组」。 |
| 右键归类有时会移错模组，列表刷新后还得重新找位置。 | 归类针对实际右键点击的模组或当时的多选项。刷新后尽量保留原来的浏览位置和分类折叠状态。 |
| 长备注占用列表空间，切换配置方案后还得重新找备注。 | 列表最多显示两行，超出时用省略号。单击可直接编辑，双击可打开完整备注窗口。同一模组的备注在各配置方案之间共享。 |
| 模组没有缩略图，或者希望换掉 Nexus 提供的图片。 | 双击缩略图或「＋」可添加或替换图片。选图窗口从该模组所在目录开始，自定义图片优先显示。 |
| 模组已填写 Nexus 更新编号，右键菜单却没有「打开模组页面」。 | 当更新接口没有返回页面地址时，使用有效的 Nexus 编号生成网页链接；接口提供的页面地址仍优先使用。 |
| 模组很多时，加载缩略图和展开分类容易卡顿。 | 按需加载可见行的缩略图，分批处理缩略图缓存，并优化分类展开和折叠时的列表刷新。 |

## 你可能需要知道的操作

- **双击模组名称**，打开该模组所在的文件夹。
- **双击备注栏**，打开完整的备注窗口，可查看和编辑长备注。单击备注栏可直接在列表中编辑。
- **双击缩略图**，选择本地图片替换。没有图片时，双击「＋」即可添加。选图窗口会从该模组所在的文件夹开始。
- **右键新建分类**，先输入名称并点勾。同文件夹还有其他模组时，可以选择「文件夹内全部」或「仅所选」。点提示框右上角的「×」可取消。

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

| Problem | Solution |
| --- | --- |
| Two category levels are not enough for a large mod library, and categories are hard to find in a crowded right-click menu. | Enable three-level custom categories in Settings. Your existing mod folder structure stays intact, and the right-click menu groups subcategories under their parent categories. |
| Finding and organizing categories takes time when there are many subcategories. | Use category management to rename and delete categories. The category tree can be collapsed, and each category shows its mod count. |
| Assigning several mods to the same category one at a time takes too long. | Select multiple mods, open category management, choose a category, and apply it to the selected mods. You can also include other mods in the same folders. |
| Right-clicking to reassign a mod could affect the wrong row, and refreshing the list could make you lose your place. | Category commands use the row you right-clicked or the mods you had selected at the time. The list restores your previous position and collapsed groups where possible. |
| Long notes take up space in the list, and notes can differ across profiles. | The list shows up to two lines with an ellipsis for longer notes. Single-click to edit in place or double-click for the full editor. Notes for the same mod are shared across profiles. |
| Some mods lack thumbnails, or you want a different image from the one provided by Nexus. | Double-click the thumbnail or **+** to add or replace an image. The picker starts in the mod’s folder, and your image takes priority. |
| A mod has a Nexus update key, but the right-click menu does not offer to open its mod page. | If the update API does not return a page URL, a link is generated from a valid Nexus ID. A URL supplied by the API still takes priority. |
| Large mod lists can lag when loading thumbnails or expanding categories. | Thumbnails are loaded on demand for visible rows, cache updates run in batches, and the list refreshes more efficiently when categories expand or collapse. |

### Shortcuts you might find useful

- **Double-click a mod name** to open the folder where the mod is installed.
- **Double-click a note cell** to read or edit the full note in a separate window. Single-click to edit it directly in the list.
- **Double-click a thumbnail** to replace it with a local image. If the mod has no thumbnail, double-click **+** to add one. The image picker starts in the mod’s folder.
- **Create a category from the right-click menu** by entering a name and confirming it first. If there are other mods in the same folder, choose **Include others** or **Selected only**. Click **×** in the top-right corner to cancel.

### Install on Windows

Download the Windows x64 ZIP from Releases, extract it to a writable folder, and run `Stardrop.exe`. The .NET runtime is included. On first launch, follow Stardrop’s prompts to set the game and mod paths.

### One-click update

Close Stardrop and double-click `Update-Stardrop.cmd` in the same folder. Updating requires internet access and the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0).

The updater downloads the upstream `development` branch and applies the bundled patches. After a successful build, it installs the updated files and keeps the previous versions in `Update Backups`. If an upstream change prevents a patch from applying, the updater stops until a compatible patch is available.

### Build from source

Run this command from the repository root:

    dotnet publish Stardrop/Stardrop.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish

The update scripts and patches are in `Updater`. The original project’s GitHub Actions workflows are kept in `upstream-workflows` for reference.
