# BeefGen
Utility to generate Beef bindings from C header files

## Dependencies
[libclang](https://releases.llvm.org/download.html) - copy libclang.lib & libclang.dll from downloaded archive into `BeefGen\libs\libclang\dist\win_x64`

## Usage
Currently there is no CLI so all generation settings needs to be controlled through code  
There is `Program.bf` which contains example on how to use the API

## Supported features
- Structs/Unions
    - nested types
    - anonymous & unnamed types
- Bitfields
- Enums
- Functions & function types
- Macro constants