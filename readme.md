# ⛩️ ASMurai

**The elegance of high-level scripting, the deadly precision of pure x86-64 Assembly.**

ASMurai is a custom programming language and transpiler written in Julia. It allows you to write code with a simple, Python/Ruby-like syntax, and compiles it directly into **pure, dependency-free x86-64 Assembly** for Windows. 

No interpreters, no virtual machines, no heavy C-Runtime (CRT). Just your logic talking directly to the CPU silicon.

## 🗡️ Philosophy
Writing raw Assembly is painful. Writing high-level code abstracts you away from the hardware. 
**ASMurai bridges the gap.** You get `while` loops, arrays, and high-level variables, but you retain the power to manipulate the stack directly, shift bits, and inject raw x86 instructions whenever you need to draw your katana.

## ✨ Features
*   **Zero Dependencies:** Output executables only rely on Windows `kernel32.dll` for basic I/O. 
*   **High-Level Flow:** `if / else`, `while`, and `goto` with conditional branching.
*   **Low-Level Power:** Pointers (`&var`, `*ptr`), raw memory offsets (`[base + 8]`), and Stack manipulation (`push`, `pop`).
*   **Bitwise Operations:** Full support for `&`, `|`, `^`, `<<`, `>>`.
*   **Hardware Access:** Seamless `asm ... end` blocks for inline assembly (e.g., reading CPU clock cycles via `rdtsc`).
*   **UTF-8 Native:** Forces the Windows console into Code Page 65001 to perfectly render modern ASCII/Unicode art.
*   **CPU Friendly:** Built-in `sleep` command to prevent 100% CPU usage in game loops.

## ⚙️ Prerequisites
To compile ASMurai code (`.sam`), you need:
1.  **[Julia](https://julialang.org/):** To run the transpiler.
2.  **[NASM](https://www.nasm.us/):** The Netwide Assembler (must be in your system PATH).
3.  **MSVC Linker:** Comes with Visual Studio / Build Tools (the transpiler automatically searches for `link.exe` and `kernel32.lib`). GCC/MinGW is also supported as a fallback.

## 🚀 Quick Start
Run the transpiler on a `.sam` file and automatically compile it to `.exe`:
```powershell
julia transpiler.jl your_script.sam output.asm --compile
.\output.exe