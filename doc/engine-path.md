# Engine path

Each project remembers its own engine path in `stdpath('data')/unreal.nvim/lock.dat`. The project folder is the closest one above the working directory that has a `.uproject`. If there is none, the closest one with `.git` or `.p4ignore` is used, and finally the working directory itself.

An engine path is accepted when it has `Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll` and a usable `dotnet`.

`dotnet` prioritizes the bundled executable from the engine (`Engine/Binaries/ThirdParty/DotNet/<version>/<os>-<arch>/`, newest version first), then the one from `$PATH`.

Commands that need the engine prompt for a path when none is saved, the saved one is no longer valid, or the working directory moved to another project.
