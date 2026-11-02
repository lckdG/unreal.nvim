# Engine path

The engine path is stored per project, keyed by the nearest `.uproject` directory found upward from the working directory, in `stdpath('data')/unreal.nvim/lock.dat`.

A path is valid only if it contains `Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll`. Commands that need the engine prompt for a path when none is saved, the saved one is no longer valid, or the working directory moved to another project.
