Giggy
=====

A handcrafted ECS in Zig, built the hard way while making a fun game (hopefully).

This ECS uses:
- Archetype-based storage
- Struct-of-Arrays (SoA) layout
- Compile-time reflection for components and metadata
- Explicit APIs with minimal hidden behavior

---

## Setup project
If you do not have raylib installed, which you can do by taking a look at [raylib-supported-platforms](https://www.raylib.com/#supported-platforms), then run:
```bash
REPO=$PWD
mkdir -p ./{dep,include,lib}

# clone and compile raylib
cd dep
git clone --depth 1 https://github.com/raysan5/raylib.git raylib
cd raylib/src
make clean || exit 1
make PLATFORM=PLATFORM_DESKTOP || exit 1
cp libraylib.a  $REPO/lib/
cp *.h $REPO/include/

# now build project
cd $REPO
zig build run
```

Otherwise you can just run:

```bash
zig build run
```

---

## Philosophy
- Build a real game, not a framework demo
- Favor clarity and explicitness over abstraction
- Accept refactors when real pain appears
- ECS exists to serve gameplay, not the other way around

![Giggy](assets/images/giggy.png)

---

## Zen

```
$ zig zen

 * Communicate intent precisely.
 * Edge cases matter.
 * Favor reading code over writing code.
 * Only one obvious way to do things.
 * Runtime crashes are better than bugs.
 * Compile errors are better than runtime crashes.
 * Incremental improvements.
 * Avoid local maximums.
 * Reduce the amount one must remember.
 * Focus on code rather than style.
 * Resource allocation may fail; resource deallocation must succeed.
 * Memory is a resource.
 * Together we serve the users.
```
