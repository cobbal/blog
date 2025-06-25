---
title: "Cross-platform binaries with swift, wasm, and NPM"
author: Andrew Cobb
date: Jun 24, 2025
tags: [ wasm, swift ]
---

## Why

Distributing a cross-platform binary is a pain. Mostly because of windows. Linux isn't helping much either. And macOS
isn't great. Dependencies and/or docker are a pain to manage.

## Who

- swift
- wasm
- node.js / NPM

## How

1. Create a command-line program

Package.swift:
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "orb",
    targets: [
        .executableTarget(
            name: "orb",
            path: ".",
            sources: ["orb.swift"]
        )
    ]
)
```

And the CLI "utility" itself in orb.swift:
```swift
func asciiImage(_ pixelAt: (Double, Double) -> Double) -> String {
    let gradient = "@%#*+=-:. ".map { "\($0)" }
    return (0..<50).map { y in
        (0..<100).map { x in
            let pixel = pixelAt(Double(x) / 50 - 1, Double(y) / 25 - 1)
            let iPixel = Int(pixel * Double(gradient.count))
            return gradient[max(0, min(iPixel, gradient.count))]
        }.joined()
    }.joined(separator: "\n")
}

let theOrb = asciiImage { x, y in
    let z = (1 - (x * x + y * y)).squareRoot()
    return z.isNaN ? 1 : (2 * x - 3 * y + 6 * z) / 7
}

print(theOrb)
```

2. Install the <a href="https://book.swiftwasm.org/getting-started/setup.html">swift-wasm toolchain</a>
3. Compile for wasm (I'm using swift and swift-wasm 6.1):
```bash
swiftly run +6.1 swift build --swift-sdk wasm32-unknown-wasi
```

4. Grab the binary at .build/wasm32-unknown-wasi/debug/orb.wasm and construct a node package

package.json:
```json
{
    "name": "wasm-orb",
    "version": "0.0.1",
    "description": "The Orb",
    "files": ["orb.wasm"],
    "bin": { "orb": "orb.js" },
    "engines": { "node": ">=19" }
}
```

orb.mjs:
```javascript
#!/usr/bin/env node --disable-warning=ExperimentalWarning

// Adapted from sample code at https://nodejs.org/api/wasi.html
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { argv, env, cwd } from 'node:process';

const wasi = new WASI({
  version: 'preview1',
  args: argv.slice(1),
  env: {
    ...env,
    PWD: cwd(),
  },
  preopens: { "/": "/" },
});

const wasm = await WebAssembly.compile(
  await readFile(new URL('./orb.wasm', import.meta.url)),
);
const instance = await WebAssembly.instantiate(wasm, wasi.getImportObject());
wasi.start(instance);
```

5. Invoke the orb
```
$ npm exec orb
                                                  +
                                    *+++=====------------------=+
                               *+++====-------:::::::::::::::::::----=
                           *+++====------:::::::::::::........:::::::::---
                       #**++====------:::::::::.......................:::::--=
                    %**+++====-----::::::::...............................::::--
                  #**+++====-----::::::::.............             ..........::::--
                #***+++===------:::::::...........                      ........:::--
              ##**+++====-----:::::::..........                            .......:::--
            %##**+++====-----:::::::..........                               .......:::-=
          @%#***+++====-----:::::::.........                                   ......:::--+
         %%#***+++====------::::::..........                                     .....::::-=
        %%##**++++====-----:::::::.........                                       .....::::-=
       %%##***+++====------::::::..........                                        .....::::-=
      @%##***++++====-----:::::::.........                                         ......::::-=
     @%%##***+++=====-----:::::::..........                                         ......:::--=
    @%%##***++++=====-----:::::::..........                                         ......::::--=
   @@%%##***++++=====-----::::::::.........                                         .......:::--==
  @@@%%##***++++=====------:::::::..........                                        .......::::--=*
  @@%%###***++++=====------::::::::..........                                       .......::::--==
  @@%%###****++++=====------::::::::...........                                    .......:::::--==
 @@@%%###****++++=====------:::::::::...........                                  ........:::::--==+
 @@@%%%###***+++++=====------:::::::::............                               .........::::---==+
 @@@%%%###****++++======------:::::::::..............                          ..........:::::---==+
 @@@@%%###****+++++======------::::::::::...............                    ............:::::----==+
@@@@@%%%###****+++++======-------:::::::::....................        .................::::::---===+
 @@@@@%%####****+++++======-------:::::::::::........................................:::::::----==++
 @@@@@%%%###*****+++++======--------:::::::::::....................................::::::::----===++
 @@@@@@%%%###*****+++++=======--------:::::::::::::.............................:::::::::-----===++*
 @@@@@@%%%%###*****+++++=======---------:::::::::::::::.....................::::::::::::-----====++*
  @@@@@@%%%%###*****++++++=======----------:::::::::::::::::::::::::::::::::::::::::::------====++*
  @@@@@@@%%%%####*****++++++=======-----------:::::::::::::::::::::::::::::::::::::-------====+++*#
  @@@@@@@@%%%%####*****+++++++========------------::::::::::::::::::::::::::::::--------=====+++**%
   @@@@@@@@%%%%#####*****+++++++=========---------------:::::::::::::::::::-----------======+++**#
    @@@@@@@@@%%%%####******+++++++==========---------------------------------------=======++++**#
     @@@@@@@@@%%%%#####******++++++++===========--------------------------------========++++**##
      @@@@@@@@@@%%%%#####******+++++++++==============--------------------===========+++++***##
       @@@@@@@@@@%%%%%#####*******++++++++++======================================++++++***##%
        @@@@@@@@@@@%%%%%######*******++++++++++++============================++++++++****###%
         @@@@@@@@@@@@%%%%%#######********+++++++++++++++++===========+++++++++++++*****###%@
           @@@@@@@@@@@@@%%%%%#######**********++++++++++++++++++++++++++++++++******####%%
            @@@@@@@@@@@@@@%%%%%%########**************+++++++++++++++++**********####%%%@
              @@@@@@@@@@@@@@@%%%%%%%#########********************************#####%%%@@
                @@@@@@@@@@@@@@@@@%%%%%%%#############****************##########%%%%@@
                  @@@@@@@@@@@@@@@@@@@%%%%%%%%%###########################%%%%%%@@@@
                    @@@@@@@@@@@@@@@@@@@@@@%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@@@@@
                       @@@@@@@@@@@@@@@@@@@@@@@@@@@%%%%%%%%%%%%%%%%%@@@@@@@@@@@
                           @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                               @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@
```

## Possible next steps

Theoretically, this could be used to distribute non-orb software as well, but I'm not sure why anyone would want to.

## Limitations

 - File system is a little janky: TODO: use PWD env var
     - wasi is unix-like. It may struggle with windows paths passed into the program.
 - No networking, no threads, no libdispatch
 - Swift package and dependencies must compile to wasm. Many do, including C/C++ dependencies, many do not.
 - This is not a secure sandbox. Binaries distributed this way have access to the system (both a feature and a limitation). See [node's documentation](TODO)
 - The binaries are large-ish. This can be mitigated slightly by using [wasm-opt](TODO) and compiling in release mode
 - Debugging support is... very limited. Debug a native binary instead.
