# BeefGen
Utility to generate Beef bindings from C header files

## Dependencies
[libclang](https://releases.llvm.org/download.html) - copy libclang.lib & libclang.dll from downloaded archive into `BeefGen\libs\libclang\dist\win_x64`

## Usage
For CLI interface options use `--help`, if you wish to have finer control over generation
there is `Program.bf` which contains non CLI example on how to use the API

## Supported features
- Structs/Unions
    - nested types
    - anonymous & unnamed types
- Bitfields
- Enums
- Functions & function types
- Macro constants