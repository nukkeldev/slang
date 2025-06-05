# slang

[slang](https://github.com/shader-slang/slang) built with [Zig](https://ziglang.org/).

## Installation

Add to `build.zig.zon` with:
```
zig fetch --save git+https://github.com/nukkeldev/slang
```
Optionally suffix the url with `#<ref>` to use a commit with a tag or a branch:
```
zig fetch --save git+https://github.com/nukkeldev/slang#main
```

## TODO

### Minimum required for `libslang` (Incomplete)

- [x] Dependencies packaged with Zig
  - [x] `unordered_dense`: nukkeldev
  - [x] `lz4`: AYC
  - [x] `lua`: AYC
  - [x] `miniz`: nukkeldev
  - [x] `SPIRV-headers`: nukkeldev
- [ ] Package tools
  - [ ] `slang-capability-generator`
  - [ ] `slang-embed`
  - [ ] `slang-fiddle`
  - [ ] `slang-lookup-generator`
  - [ ] `slang-spirv-embed-generator`
- [ ] Add CI
