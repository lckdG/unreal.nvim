# Engine path

When Neovim starts, the plugin reads which Unreal Engine versions are installed:

| OS | Source |
| --- | --- |
| Windows | `%ProgramData%\Epic\UnrealEngineLauncher\LauncherInstalled.dat` (launcher) and the registry key `HKCU\Software\Epic Games\Unreal Engine\Builds` (source builds) |
| Mac | `~/Library/Application Support/Epic/UnrealEngineLauncher/LauncherInstalled.dat` |
| Linux | `~/.config/Epic/UnrealEngine/Install.ini` |

An engine folder is only used when it has `Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll` and a usable `dotnet`.

`dotnet` prioritizes the bundled executable from the engine (`Engine/Binaries/ThirdParty/DotNet/<version>/<os>-<arch>/`, newest version first), then the one from `$PATH`.

Commands that need the engine pick it in this order:

1. the folder set with `:Unreal Engine SetPath`
2. the installed engine named by the `.uproject`'s `EngineAssociation` field: a version such as `"5.4"` (the launcher lists it as `UE_5.4`) or the ID of a source build
3. otherwise they ask for the engine folder; the answer is used once and not remembered

`Project Open` also needs the engine's `UnrealEditor` program. `Build Clangd` only needs `dotnet` and UnrealBuildTool.

The project folder is the closest one above the working directory that has a `.uproject`. If there is none, the closest one with `.git` or `.p4ignore` is used, and finally the working directory itself. `.uproject` files are searched under it (at most 20). The chosen `.uproject` and the `Engine SetPath` folder are kept until Neovim closes or the working directory moves to another project folder. Nothing is saved to disk.
