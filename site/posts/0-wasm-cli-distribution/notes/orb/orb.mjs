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
