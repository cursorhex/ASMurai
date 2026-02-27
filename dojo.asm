; Generato da TinyASM v2 Transpiler (target: Windows x64)
; nasm -f win64 output.asm -o output.obj
; link output.obj kernel32.lib /nologo /subsystem:console /entry:main /out:output.exe

section .data
    frame    dq 0
    mod    dq 0
    p    dq 0
    q    dq 0
    r    dq 0
    ritardo_max    dq 0
    _t_s0    db  "INIZIALIZZAZIONE SEQUENZA GENETICA...", 10, 0
    _t_s1    db  "▓▓▓▓▓▓▓▓▓▓        \          /        ▓▓▓▓▓▓▓▓▓▓", 10, 0
    _t_s2    db  "▓▓▓▓▓▓▓▓▓▓▓        \        /        ▓▓▓▓▓▓▓▓▓▓▓", 10, 0
    _t_s3    db  "▓▓▓▓▓▓▓▓▓▓▓▓        \      /        ▓▓▓▓▓▓▓▓▓▓▓▓", 10, 0
    _t_s4    db  "▓▓▓▓▓▓▓▓▓▓▓▓▓        | == |        ▓▓▓▓▓▓▓▓▓▓▓▓▓", 10, 0
    _t_s5    db  "▓▓▓▓▓▓▓▓▓▓▓▓        /      \        ▓▓▓▓▓▓▓▓▓▓▓▓", 10, 0
    _t_s6    db  "▓▓▓▓▓▓▓▓▓▓▓        /        \        ▓▓▓▓▓▓▓▓▓▓▓", 10, 0
    _t_s7    db  "▓▓▓▓▓▓▓▓▓▓        /          \        ▓▓▓▓▓▓▓▓▓▓", 10, 0
    _t_s8    db  "▓▓▓▓▓▓▓▓▓        |  ======  |        ▓▓▓▓▓▓▓▓▓", 10, 0

section .bss
    _t_hout    resq 1
    _t_nwr     resd 1
    _t_ibuf    resb 24

section .text
    global main
    extern ExitProcess
    extern GetStdHandle
    extern WriteConsoleA

main:
    sub    rsp, 40
    call   _t_init
    add    rsp, 40

    ; frame = 0
    mov    rax, 0
    mov    [rel frame], rax

    ; ritardo_max = 15000000
    mov    rax, 15000000
    mov    [rel ritardo_max], rax

    ; echo "INIZIALIZZAZIONE SEQUENZA GENETICA..."
    lea    rcx, [rel _t_s0]
    mov    rdx, 38
    sub    rsp, 40
    call   _t_print_str
    add    rsp, 40

loop_infinito:

    ; q = frame / 8
    mov    rax, [rel frame]
    mov    r11, 8
    xor    rdx, rdx
    idiv   r11
    mov    [rel q], rax

    ; p = q * 8
    mov    rax, [rel q]
    mov    r11, 8
    imul   rax, r11
    mov    [rel p], rax

    ; mod = frame - p
    mov    rax, [rel frame]
    mov    r11, [rel p]
    sub    rax, r11
    mov    [rel mod], rax

    ; if mod == 0
    mov    rax, [rel mod]
    mov    r11, 0
    cmp    rax, r11
    jne    _t_else_0

    ; echo "▓▓▓▓▓▓▓▓▓▓        \          /        ▓▓▓▓▓▓▓▓▓▓"
    lea    rcx, [rel _t_s1]
    mov    rdx, 49
    sub    rsp, 40
    call   _t_print_str
    add    rsp, 40
    jmp    _t_endif_1
_t_else_0:
_t_endif_1:

    ; if mod == 1
    mov    rax, [rel mod]
    mov    r11, 1
    cmp    rax, r11
    jne    _t_else_2

    ; echo "▓▓▓▓▓▓▓▓▓▓▓        \        /        ▓▓▓▓▓▓▓▓▓▓▓"
    lea    rcx, [rel _t_s2]
    mov    rdx, 49
    sub    rsp, 40
    call   _t_print_str
    add    rsp, 40
    jmp    _t_endif_3
_t_else_2:
_t_endif_3:

    ; if mod == 2
    mov    rax, [rel mod]
    mov    r11, 2
    cmp    rax, r11
    jne    _t_else_4

    ; echo "▓▓▓▓▓▓▓▓▓▓▓▓        \      /        ▓▓▓▓▓▓▓▓▓▓▓▓"
    lea    rcx, [rel _t_s3]
    mov    rdx, 49
    sub    rsp, 40
    call   _t_print_str
    add    rsp, 40
    jmp    _t_endif_5
_t_else_4:
_t_endif_5:

    ; if mod == 3
    mov    rax, [rel mod]
    mov    r11, 3
    cmp    rax, r11
    jne    _t_else_6

    ; echo "▓▓▓▓▓▓▓▓▓▓▓▓▓        | == |        ▓▓▓▓▓▓▓▓▓▓▓▓▓"
    lea    rcx, [rel _t_s4]
    mov    rdx, 49
    sub    rsp, 40
    call   _t_print_str
    add    rsp, 40
    jmp    _t_endif_7
_t_else_6:
_t_endif_7:

    ; if mod == 4
    mov    rax, [rel mod]
    mov    r11, 4
    cmp    rax, r11
    jne    _t_else_8

    ; echo "▓▓▓▓▓▓▓▓▓▓▓▓        /      \        ▓▓▓▓▓▓▓▓▓▓▓▓"
    lea    rcx, [rel _t_s5]
    mov    rdx, 49
    sub    rsp, 40
    call   _t_print_str
    add    rsp, 40
    jmp    _t_endif_9
_t_else_8:
_t_endif_9:

    ; if mod == 5
    mov    rax, [rel mod]
    mov    r11, 5
    cmp    rax, r11
    jne    _t_else_10

    ; echo "▓▓▓▓▓▓▓▓▓▓▓        /        \        ▓▓▓▓▓▓▓▓▓▓▓"
    lea    rcx, [rel _t_s6]
    mov    rdx, 49
    sub    rsp, 40
    call   _t_print_str
    add    rsp, 40
    jmp    _t_endif_11
_t_else_10:
_t_endif_11:

    ; if mod == 6
    mov    rax, [rel mod]
    mov    r11, 6
    cmp    rax, r11
    jne    _t_else_12

    ; echo "▓▓▓▓▓▓▓▓▓▓        /          \        ▓▓▓▓▓▓▓▓▓▓"
    lea    rcx, [rel _t_s7]
    mov    rdx, 49
    sub    rsp, 40
    call   _t_print_str
    add    rsp, 40
    jmp    _t_endif_13
_t_else_12:
_t_endif_13:

    ; if mod == 7
    mov    rax, [rel mod]
    mov    r11, 7
    cmp    rax, r11
    jne    _t_else_14

    ; echo "▓▓▓▓▓▓▓▓▓        |  ======  |        ▓▓▓▓▓▓▓▓▓"
    lea    rcx, [rel _t_s8]
    mov    rdx, 47
    sub    rsp, 40
    call   _t_print_str
    add    rsp, 40
    jmp    _t_endif_15
_t_else_14:
_t_endif_15:

    ; r = 0
    mov    rax, 0
    mov    [rel r], rax

aspetta:

    ; r = r + 1
    mov    rax, [rel r]
    mov    r11, 1
    add    rax, r11
    mov    [rel r], rax

    ; goto aspetta if r < ritardo_max
    mov    rax, [rel r]
    mov    r11, [rel ritardo_max]
    cmp    rax, r11
    jl    aspetta

    ; frame = frame + 1
    mov    rax, [rel frame]
    mov    r11, 1
    add    rax, r11
    mov    [rel frame], rax

    ; goto loop_infinito
    jmp    loop_infinito

    ; ── ExitProcess(0) ──────────────────────────────────
    xor    rcx, rcx
    sub    rsp, 40
    call   ExitProcess

; ─────────────────────────────────────────────────────────────────────────────
; TinyASM Runtime — WriteConsoleA nativa (kernel32), zero CRT
; ─────────────────────────────────────────────────────────────────────────────

_t_init:
    push   rbp
    mov    rbp, rsp
    sub    rsp, 32
    mov    rcx, -11                 ; STD_OUTPUT_HANDLE
    call   GetStdHandle
    mov    [rel _t_hout], rax
    mov    rsp, rbp
    pop    rbp
    ret

; rcx = puntatore stringa, rdx = numero caratteri
_t_print_str:
    push   rbp
    mov    rbp, rsp
    sub    rsp, 48
    mov    r8,  rdx
    mov    rdx, rcx
    mov    rcx, [rel _t_hout]
    lea    r9,  [rel _t_nwr]
    mov    qword [rsp+32], 0        ; lpReserved = NULL
    call   WriteConsoleA
    mov    rsp, rbp
    pop    rbp
    ret

; valore intero da stampare in rax
_t_print_int:
    push   rbp
    push   rbx
    push   rdi
    push   rsi
    sub    rsp, 40
    mov    rbx, rax
    xor    rdi, rdi
    test   rax, rax
    jns    .pos
    neg    rbx
    mov    rdi, 1
.pos:
    lea    rsi, [rel _t_ibuf + 21]
    mov    byte [rsi], 10           ; newline
    dec    rsi
    mov    rax, rbx
    mov    rcx, 10
.loop:
    xor    rdx, rdx
    div    rcx
    add    dl, '0'
    mov    [rsi], dl
    dec    rsi
    test   rax, rax
    jnz    .loop
    test   rdi, rdi
    jz     .nosign
    mov    byte [rsi], '-'
    dec    rsi
.nosign:
    inc    rsi
    lea    rdx, [rel _t_ibuf + 22]
    sub    rdx, rsi
    mov    rcx, rsi
    call   _t_print_str
    add    rsp, 40
    pop    rsi
    pop    rdi
    pop    rbx
    pop    rbp
    ret

