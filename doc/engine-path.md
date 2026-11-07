# Engine path

Installed engines are read when Neovim starts:

| OS | Source |
| --- | --- |
| Windows | `%ProgramData%\Epic\UnrealEngineLauncher\LauncherInstalled.dat` and registry `HKCU\Software\Epic Games\Unreal Engine\Builds` (source builds) |
| Mac | `~/Library/Application Support/Epic/UnrealEngineLauncher/LauncherInstalled.dat` |
| Linux | `~/.config/Epic/UnrealEngine/Install.ini` |

An engine folder needs `Engine/Build/BatchFiles/RunUBT.sh` (`RunUBT.bat` on Windows), the engine's script that runs UnrealBuildTool. The script sets up the engine's `dotnet` and builds UnrealBuildTool when needed.

Commands use, in order:

1. the folder from `:Unreal Engine SetPath`
2. the engine named by the `.uproject`'s `EngineAssociation` (e.g. `"5.4"` or a source build ID)
3. a prompt for the engine folder (not remembered)

`Project Open` also needs the editor; `Build Clangd` does not.

## Engine from source

No installed engine, or you need a version the launcher does not offer: build one from Epic's source code.

1. Set [engine_source](#engine_source) `clone_dir` to an existing folder. Each checkout gets its own subfolder, e.g. `<clone_dir>/5.4.4-release`.
2. `:Unreal Engine Checkout`: pick a release tag; only its latest commit is cloned. Epic's repository is private: link your GitHub account to your Epic Games account first, and make sure `git` can log in to GitHub (SSH key or credential helper).
3. `:Unreal Engine Build`: pick the checkout (or the project's engine or `SetPath` folder, if it was built from source) and confirm. Setup, project file generation and the editor build run in a terminal split; expect hours and tens of GB of disk.

The plugin does not register the built engine itself; it re-reads the installed engines when the build succeeds. If the new engine is still not found, point to it with `:Unreal Engine SetPath`.

## Project folder

The closest folder above the working directory with a `.uproject`, else with `.git` or `.p4ignore`, else the working directory.

At startup and after `:cd` to another project, a `.uproject` directly in that folder is chosen (one is picked if there are several). If there is none, the first command that needs one searches subfolders (up to [uproject_limits](#uproject_limits)) and asks if it finds several.

The chosen `.uproject` and the `SetPath` folder last until Neovim closes or you `:cd` to another project. Nothing is saved to disk.
