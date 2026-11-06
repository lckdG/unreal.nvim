# Engine path

Installed engines are read when Neovim starts:

| OS | Source |
| --- | --- |
| Windows | `%ProgramData%\Epic\UnrealEngineLauncher\LauncherInstalled.dat` and registry `HKCU\Software\Epic Games\Unreal Engine\Builds` (source builds) |
| Mac | `~/Library/Application Support/Epic/UnrealEngineLauncher/LauncherInstalled.dat` |
| Linux | `~/.config/Epic/UnrealEngine/Install.ini` |

An engine folder needs `Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll` and a `dotnet`: the engine's bundled one (`Engine/Binaries/ThirdParty/DotNet/`, newest first), else the one on `$PATH`.

Commands use, in order:

1. the folder from `:Unreal Engine SetPath`
2. the engine named by the `.uproject`'s `EngineAssociation` (e.g. `"5.4"` or a source build ID)
3. a prompt for the engine folder (not remembered)

`Project Open` also needs the editor; `Build Clangd` does not.

## Project folder

The closest folder above the working directory with a `.uproject`, else with `.git` or `.p4ignore`, else the working directory.

At startup and after `:cd` to another project, a `.uproject` directly in that folder is chosen (one is picked if there are several). If there is none, the first command that needs one searches subfolders (up to [uproject_limits](#uproject_limits)) and asks if it finds several.

The chosen `.uproject` and the `SetPath` folder last until Neovim closes or you `:cd` to another project. Nothing is saved to disk.
