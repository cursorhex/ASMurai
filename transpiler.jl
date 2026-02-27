# =============================================================================
#  TinyASM v2 → x86-64 (Intel syntax, Windows) Transpiler + Assembler
#  Utilizzo: julia transpiler.jl input.tasm output.asm [--compile]
#
#  SINTASSI COMPLETA
#  ─────────────────────────────────────────────────────────────────────────
#  Assegnazioni
#    x = 42              # intero letterale
#    x = y               # copia variabile
#    x = rax             # copia da registro
#    rax = x             # copia in registro
#    rax = rbx           # registro ← registro
#    rax = 42            # registro ← immediato
#
#  Operazioni binarie  (dest può essere var o registro)
#    z = x + y           # operandi: var, registro o intero
#    rax = rax + 1
#    rax = rbx * rcx
#
#  Array
#    arr = [1, 2, 3]     # dichiarazione  (indici 0-based, elem = 8 byte)
#    x = arr[0]          # lettura con indice intero
#    x = arr[i]          # lettura con indice variabile/registro
#    arr[0] = x          # scrittura con indice intero
#    arr[i] = x          # scrittura con indice variabile/registro
#
#  Puntatori
#    ptr = &x            # ptr = indirizzo di x
#    y   = *ptr          # lettura tramite puntatore
#    *ptr = x            # scrittura tramite puntatore
#
#  Memoria raw  (base: variabile o registro)
#    x = [rax]           # lettura da indirizzo in registro
#    x = [rax + 8]       # lettura con offset byte
#    [rax] = x           # scrittura
#    [rax + 8] = x       # scrittura con offset
#
#  Output
#    echo x              # stampa valore intero (var o registro)
#    echo "testo"        # stampa stringa letterale
#
#  Controllo del flusso
#    if  left op right   # op: > < == != >= <=
#      ...
#    else
#      ...
#    end
#
#    while left op right
#      ...
#    end
#
#    label nome          # definisce un'etichetta
#    goto  nome          # salto incondizionato
#    goto  nome if left op right   # salto condizionato
#
#  Note sui registri riservati dal runtime:
#    rax, r11 — scratch per codegen (clobbered da ogni operazione)
#    rcx, rdx, r8, r9 — usati da echo e dal runtime di stampa
#    Registri "sicuri" per l'utente: rbx, rsi, rdi, r10, r12–r15
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# 1. AST
# ─────────────────────────────────────────────────────────────────────────────

abstract type ASTNode end

# dest = src   (dest/src: var, registro, o intero letterale)
struct Assign <: ASTNode
    dest::String
    src::String
end

# dest = left op right
struct BinOpAssign <: ASTNode
    dest::String
    left::String
    op::String
    right::String
end

# name = [e1, e2, ...]
struct ArrayDecl <: ASTNode
    name::String
    elements::Vector{Int}
end

# dest = arr[idx]
struct ArrayRead <: ASTNode
    dest::String
    arr::String
    idx::String    # var, registro o intero letterale
end

# arr[idx] = src
struct ArrayWrite <: ASTNode
    arr::String
    idx::String
    src::String
end

# dest = &var
struct AddrOf <: ASTNode
    dest::String
    var::String
end

# dest = *ptr
struct DerefRead <: ASTNode
    dest::String
    ptr::String    # var o registro che contiene l'indirizzo
end

# *ptr = src
struct DerefWrite <: ASTNode
    ptr::String
    src::String
end

# dest = [base + offset]   oppure  [base + offset] = src
struct MemRead <: ASTNode
    dest::String
    base::String   # var o registro
    offset::Int
end

struct MemWrite <: ASTNode
    base::String
    offset::Int
    src::String
end

# echo var/registro  |  echo "stringa"
struct EchoVar <: ASTNode
    name::String
end

struct EchoStr <: ASTNode
    text::String
end

# label / goto
struct LabelNode <: ASTNode
    name::String
end

struct GotoNode <: ASTNode
    name::String
end

struct Condition
    left::String
    op::String
    right::String
end

struct CondGoto <: ASTNode
    name::String
    cond::Condition
end

# if / while
struct IfBlock <: ASTNode
    cond::Condition
    then_body::Vector{ASTNode}
    else_body::Vector{ASTNode}
end

struct WhileBlock <: ASTNode
    cond::Condition
    body::Vector{ASTNode}
end

struct PushNode <: ASTNode
    src::String
end

struct PopNode <: ASTNode
    dest::String
end

struct InlineAsm <: ASTNode
    code::Vector{String}
end

# ─────────────────────────────────────────────────────────────────────────────
# 2. HELPERS
# ─────────────────────────────────────────────────────────────────────────────

const X86_REGS = Set([
    "rax","rbx","rcx","rdx","rsi","rdi","rsp","rbp",
    "r8","r9","r10","r11","r12","r13","r14","r15",
])

is_register(s::AbstractString)       = String(s) ∈ X86_REGS
is_integer_literal(s::AbstractString) = match(r"^-?\d+$", String(s)) !== nothing

strip_comment(line::AbstractString) = strip(split(String(line), '#')[1])

function tokenize(line::AbstractString)
    normalized = replace(String(line), r"[=\[\],]" => " ")
    return filter(!isempty, split(normalized))
end

# ─────────────────────────────────────────────────────────────────────────────
# 3. PARSER
# ─────────────────────────────────────────────────────────────────────────────

function parse_condition(s::AbstractString)
    s = String(strip(s))
    for op in (">=", "<=", "!=", "==", ">", "<")
        idx = findfirst(op, s)
        idx === nothing && continue
        left  = String(strip(s[1:first(idx)-1]))
        right = String(strip(s[last(idx)+1:end]))
        (isempty(left) || isempty(right)) && error("Condizione non valida: '$s'")
        return Condition(left, op, right)
    end
    error("Nessun operatore di confronto in: '$s'")
end

"""
    parse_line_simple(line) -> ASTNode | Nothing
Analizza tutte le istruzioni mono-riga.
"""
function parse_line_simple(line::AbstractString)
    line = String(strip_comment(line))
    isempty(line) && return nothing

    # ── echo ─────────────────────────────────────────────────────────────────
    if startswith(line, "echo ")
        rest = String(strip(line[6:end]))
        if startswith(rest, "\"")
            endswith(rest, "\"") || error("Stringa non chiusa: $line")
            # [FIX UNICODE] Usiamo 'chop' per rimuovere in sicurezza i caratteri UTF-8
            return EchoStr(String(chop(rest, head=1, tail=1)))
        else
            return EchoVar(rest)
        end
    end
    
    # ── stack (push/pop) [NUOVO] ──────────────────────────────────────────────
    if startswith(line, "push ")
        return PushNode(String(strip(line[6:end])))
    end
    if startswith(line, "pop ")
        return PopNode(String(strip(line[5:end])))
    end

    # ── label e goto ─────────────────────────────────────────────────────────
    if startswith(line, "label ") return LabelNode(String(strip(line[7:end]))) end
    if startswith(line, "goto ")
        rest = String(strip(line[6:end]))
        idx  = findfirst(" if ", rest)
        if idx !== nothing
            name = String(strip(rest[1:first(idx)-1]))
            cond = parse_condition(rest[last(idx)+1:end])
            return CondGoto(name, cond)
        else
            return GotoNode(rest)
        end
    end

    # ── *ptr = src  (deref write) ─────────────────────────────────────────────
    if startswith(line, "*")
        m = match(r"^\*(\w+)\s*=\s*(.+)$", line)
        m !== nothing || error("Sintassi puntatore non valida: $line")
        return DerefWrite(String(m[1]), String(strip(m[2])))
    end

    # ── [base + offset] = src  (raw memory write) ─────────────────────────────
    if startswith(line, "[")
        m = match(r"^\[\s*(\w+)\s*(?:\+\s*(-?\d+))?\s*\]\s*=\s*(.+)$", line)
        m !== nothing || error("Sintassi memoria non valida: $line")
        off = m[2] !== nothing ? parse(Int, m[2]) : 0
        return MemWrite(String(m[1]), off, String(strip(m[3])))
    end

    # ── arr[idx] = src  (array write) ────────────────────────────────────────
    m = match(r"^(\w+)\[([^\]]+)\]\s*=\s*(.+)$", line)
    if m !== nothing
        return ArrayWrite(String(m[1]), String(strip(m[2])), String(strip(m[3])))
    end

    # ── dest = RHS ────────────────────────────────────────────────────────────
    eq_idx = findfirst('=', line)
    eq_idx === nothing && error("Riga non riconosciuta: '$line'")

    dest = String(strip(line[1:eq_idx-1]))
    rhs  = String(strip(line[eq_idx+1:end]))

    # [FIX BUG] Distinguiamo ArrayDecl (es: [1,2,3]) da MemRead (es: [base + 8])
    if startswith(rhs, "[") && endswith(rhs, "]")
        inside = String(strip(rhs[2:end-1]))
        # Se contiene virgole o è un singolo numero isolato, è un Array
        if contains(inside, ',') || match(r"^-?\d+$", inside) !== nothing
            elems = [parse(Int, strip(String(e))) for e in split(inside, ',')]
            return ArrayDecl(dest, elems)
        else
            # Altrimenti è una lettura in memoria [base + offset] o [base]
            m_mem = match(r"^(\w+)\s*(?:\+\s*(-?\d+))?$", inside)
            m_mem !== nothing || error("Sintassi memoria non valida: $line")
            off = m_mem[2] !== nothing ? parse(Int, m_mem[2]) : 0
            return MemRead(dest, String(m_mem[1]), off)
        end
    end

    if startswith(rhs, "&") return AddrOf(dest, String(strip(rhs[2:end]))) end
    if startswith(rhs, "*") return DerefRead(dest, String(strip(rhs[2:end]))) end

    # dest = arr[idx]
    m = match(r"^(\w+)\[([^\]]+)\]$", rhs)
    if m !== nothing return ArrayRead(dest, String(m[1]), String(strip(m[2]))) end

    # dest = src  |  dest = left op right
    tokens = String.(filter(!isempty, split(rhs)))
    length(tokens) == 1 && return Assign(dest, tokens[1])

    if length(tokens) == 3
        left, op, right = tokens
        # [NUOVO] Aggiunti operatori bit a bit
        op ∈ ("+", "-", "*", "/", "&", "|", "^", "<<", ">>") || error("Operatore non supportato: '$op' in: $line")
        return BinOpAssign(dest, left, op, right)
    end

    error("Riga non riconosciuta: '$line'")
end
"""
    parse_block(lines, start_i, terminators) -> (nodes, i)
Analizza un blocco di righe finché non trova una riga terminatrice.
Gestisce annidamento di if/while.
"""
function parse_block(lines::Vector, start_i::Int, terminators::Vector{String})
    nodes = ASTNode[]
    i = start_i

    while i <= length(lines)
        line = String(strip(strip_comment(String(lines[i]))))

        line ∈ terminators && return nodes, i
        isempty(line)       && (i += 1; continue)

        if line == "asm"
            asm_lines = String[]
            i += 1
            while i <= length(lines)
                l = String(strip(String(lines[i])))
                l == "end" && break
                push!(asm_lines, l)
                i += 1
            end
            push!(nodes, InlineAsm(asm_lines))
            i += 1
            continue
        end

        if startswith(line, "if ")
            cond = parse_condition(line[4:end])
            then_body, i = parse_block(lines, i + 1, ["else", "end"])
            i > length(lines) && error("'if' senza 'end'")
            closer = String(strip(strip_comment(String(lines[i]))))
            if closer == "else"
                else_body, i = parse_block(lines, i + 1, ["end"])
                i > length(lines) && error("'else' senza 'end'")
            else
                else_body = ASTNode[]
            end
            push!(nodes, IfBlock(cond, then_body, else_body))
            i += 1
            continue
        end

        if startswith(line, "while ")
            cond = parse_condition(line[7:end])
            body, i = parse_block(lines, i + 1, ["end"])
            i > length(lines) && error("'while' senza 'end'")
            push!(nodes, WhileBlock(cond, body))
            i += 1
            continue
        end

        node = try
            parse_line_simple(line)
        catch e
            error("Errore alla riga $i: $(sprint(showerror, e))")
        end
        node !== nothing && push!(nodes, node)
        i += 1
    end

    return nodes, i
end

parse_program(src::String) = parse_block(split(src, '\n'), 1, String[])[1]

# ─────────────────────────────────────────────────────────────────────────────
# 4. TABELLA DEI SIMBOLI
# ─────────────────────────────────────────────────────────────────────────────

struct SymbolTable
    vars::Set{String}
    arrays::Dict{String, Vector{Int}}
end

function collect_symbols!(vars::Set, arrays::Dict, nodes::Vector{ASTNode})
    for n in nodes
        if n isa Assign && !is_register(n.dest)
            push!(vars, n.dest)
        elseif n isa BinOpAssign && !is_register(n.dest)
            push!(vars, n.dest)
        elseif n isa ArrayDecl
            arrays[n.name] = n.elements
        elseif n isa ArrayRead  && !is_register(n.dest); push!(vars, n.dest)
        elseif n isa DerefRead  && !is_register(n.dest); push!(vars, n.dest)
        elseif n isa MemRead    && !is_register(n.dest); push!(vars, n.dest)
        elseif n isa AddrOf     && !is_register(n.dest); push!(vars, n.dest)
        elseif n isa IfBlock
            collect_symbols!(vars, arrays, n.then_body)
            collect_symbols!(vars, arrays, n.else_body)
        elseif n isa WhileBlock
            collect_symbols!(vars, arrays, n.body)
        elseif n isa PopNode && !is_register(n.dest); push!(vars, n.dest)
        end
    end
end

function build_symbol_table(nodes::Vector{ASTNode})
    vars   = Set{String}()
    arrays = Dict{String, Vector{Int}}()
    collect_symbols!(vars, arrays, nodes)
    return SymbolTable(vars, arrays)
end

# ─────────────────────────────────────────────────────────────────────────────
# 5. STATO CODEGEN
# ─────────────────────────────────────────────────────────────────────────────

mutable struct CodegenState
    label_count::Int
    strings::Dict{String,String}
    str_count::Int
    need_print::Bool
end

CodegenState() = CodegenState(0, Dict{String,String}(), 0, false)

function new_label!(st::CodegenState, kind::String)
    lbl = "_t_$(kind)_$(st.label_count)"
    st.label_count += 1
    lbl
end

function intern_str!(st::CodegenState, text::String)
    haskey(st.strings, text) && return st.strings[text]
    lbl = "_t_s$(st.str_count)"
    st.str_count += 1
    st.strings[text] = lbl
    st.need_print = true
    lbl
end

function collect_print_needs!(st::CodegenState, nodes::Vector{ASTNode})
    for n in nodes
        if n isa EchoStr; intern_str!(st, n.text)
        elseif n isa EchoVar; st.need_print = true
        elseif n isa IfBlock
            collect_print_needs!(st, n.then_body)
            collect_print_needs!(st, n.else_body)
        elseif n isa WhileBlock
            collect_print_needs!(st, n.body)
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# 6. GENERATORE DI CODICE
# ─────────────────────────────────────────────────────────────────────────────

"""
    load_into(reg, operand) -> String
Emette l'istruzione per caricare `operand` (var/registro/letterale/array) in `reg`.
"""
function load_into(reg::String, operand::String)
    operand == reg && return ""          # no-op
    if is_register(operand)
        return "    mov    $reg, $operand"
    elseif is_integer_literal(operand)
        return "    mov    $reg, $operand"
    else
        m = match(r"^(\w+)\[([^\]]+)\]$", operand)
        if m !== nothing
            arr_name = String(m[1])
            idx = String(strip(m[2]))
            if is_integer_literal(idx)
                off = parse(Int, idx) * 8
                return "    mov    $reg, [rel $arr_name + $off]"
            else
                # [FIX CPU x64] Carica base in r8, indice in r9, poi leggi
                return "    lea    r8, [rel $arr_name]\n    mov    r9, [rel $idx]\n    mov    $reg, [r8 + r9*8]"
            end
        end
        return "    mov    $reg, [rel $operand]"
    end
end

"""
    store_from(src_reg, dest) -> String
Emette l'istruzione per memorizzare `src_reg` in `dest` (var o registro).
"""
function store_from(src_reg::String, dest::String)
    if is_register(dest)
        dest == src_reg && return ""         # no-op
        return "    mov    $dest, $src_reg"
    else
        return "    mov    [rel $dest], $src_reg"
    end
end

function push_nonempty!(lines, s::String)
    isempty(s) || push!(lines, s)
end

function emit_binop_op(op::String)
    op == "+"  && return "    add    rax, r11"
    op == "-"  && return "    sub    rax, r11"
    op == "*"  && return "    imul   rax, r11"
    op == "/"  && return "    xor    rdx, rdx\n    idiv   r11"
    op == "&"  && return "    and    rax, r11"
    op == "|"  && return "    or     rax, r11"
    op == "^"  && return "    xor    rax, r11"
    op == "<<" && return "    mov    rcx, r11\n    shl    rax, cl"
    op == ">>" && return "    mov    rcx, r11\n    sar    rax, cl"
    error("Operatore sconosciuto: '$op'")
end

# Salto condizionale POSITIVO (salta se la condizione è VERA)
const JMP_IF_TRUE = Dict(
    ">"  => "jg",  "<"  => "jl",
    "==" => "je",  "!=" => "jne",
    ">=" => "jge", "<=" => "jle",
)
# Salto condizionale NEGATO (salta se la condizione è FALSA → usato per if/while)
const JMP_IF_FALSE = Dict(
    ">"  => "jle", "<"  => "jge",
    "==" => "jne", "!=" => "je",
    ">=" => "jl",  "<=" => "jg",
)

function emit_cmp!(lines, cond::Condition)
    push_nonempty!(lines, load_into("rax", cond.left))
    push_nonempty!(lines, load_into("r11", cond.right))
    push!(lines, "    cmp    rax, r11")
end

"""
emit_nodes! — emette ricorsivamente le istruzioni assembly.
"""
function emit_nodes!(lines::Vector{String}, nodes::Vector{ASTNode}, st::CodegenState)

    for node in nodes

        push!(lines, "")   # riga vuota prima di ogni istruzione per leggibilità

        # ── dest = src ────────────────────────────────────────────────────────
        if node isa Assign
            push!(lines, "    ; $(node.dest) = $(node.src)")
            push_nonempty!(lines, load_into("rax", node.src))
            push_nonempty!(lines, store_from("rax", node.dest))

        # ── dest = left op right ──────────────────────────────────────────────
        elseif node isa BinOpAssign
            push!(lines, "    ; $(node.dest) = $(node.left) $(node.op) $(node.right)")
            push_nonempty!(lines, load_into("rax", node.left))
            push_nonempty!(lines, load_into("r11", node.right))
            push!(lines, emit_binop_op(node.op))
            push_nonempty!(lines, store_from("rax", node.dest))

        # ── arr = [1,2,3] ─────────────────────────────────────────────────────
        elseif node isa ArrayDecl
            push!(lines, "    ; '$(node.name)' definito in .data")
            push!(lines, "    lea    rax, [rel $(node.name)]")

        # ── dest = arr[idx] ───────────────────────────────────────────────────
         elseif node isa ArrayRead
            push!(lines, "    ; $(node.dest) = $(node.arr)[$(node.idx)]")
            if is_integer_literal(node.idx)
                off = parse(Int, node.idx) * 8
                push!(lines, "    mov    rax, [rel $(node.arr) + $off]")
            else
                push!(lines, "    lea    r8, [rel $(node.arr)]")
                push_nonempty!(lines, load_into("r9", node.idx))
                push!(lines, "    mov    rax, [r8 + r9*8]")
            end
            push_nonempty!(lines, store_from("rax", node.dest))

        # ── arr[idx] = src ────────────────────────────────────────────────────
        elseif node isa ArrayWrite
            push!(lines, "    ; $(node.arr)[$(node.idx)] = $(node.src)")
            push_nonempty!(lines, load_into("rax", node.src))
            if is_integer_literal(node.idx)
                off = parse(Int, node.idx) * 8
                push!(lines, "    mov    [rel $(node.arr) + $off], rax")
            else
                push!(lines, "    lea    r8, [rel $(node.arr)]")
                push_nonempty!(lines, load_into("r9", node.idx))
                push!(lines, "    mov    [r8 + r9*8], rax")
            end

        # ── ptr = &var ────────────────────────────────────────────────────────
        elseif node isa AddrOf
            push!(lines, "    ; $(node.dest) = &$(node.var)")
            push!(lines, "    lea    rax, [rel $(node.var)]")
            push_nonempty!(lines, store_from("rax", node.dest))

        # ── dest = *ptr ───────────────────────────────────────────────────────
        elseif node isa DerefRead
            push!(lines, "    ; $(node.dest) = *$(node.ptr)")
            push_nonempty!(lines, load_into("rcx", node.ptr))
            push!(lines, "    mov    rax, [rcx]")
            push_nonempty!(lines, store_from("rax", node.dest))

        # ── *ptr = src ────────────────────────────────────────────────────────
        elseif node isa DerefWrite
            push!(lines, "    ; *$(node.ptr) = $(node.src)")
            push_nonempty!(lines, load_into("rcx", node.ptr))
            push_nonempty!(lines, load_into("rax", node.src))
            push!(lines, "    mov    [rcx], rax")

        # ── dest = [base + offset] ─────────────────────────────────────────────
        elseif node isa MemRead
            off_str = node.offset == 0 ? "" : " + $(node.offset)"
            push!(lines, "    ; $(node.dest) = [$(node.base)$(off_str)]")
            push_nonempty!(lines, load_into("rcx", node.base))
            push!(lines, node.offset == 0 ?
                  "    mov    rax, [rcx]" :
                  "    mov    rax, [rcx + $(node.offset)]")
            push_nonempty!(lines, store_from("rax", node.dest))

        # ── [base + offset] = src ──────────────────────────────────────────────
        elseif node isa MemWrite
            off_str = node.offset == 0 ? "" : " + $(node.offset)"
            push!(lines, "    ; [$(node.base)$(off_str)] = $(node.src)")
            push_nonempty!(lines, load_into("rcx", node.base))
            push_nonempty!(lines, load_into("rax", node.src))
            push!(lines, node.offset == 0 ?
                  "    mov    [rcx], rax" :
                  "    mov    [rcx + $(node.offset)], rax")

        # ── echo variabile / registro ─────────────────────────────────────────
        elseif node isa EchoVar
            push!(lines, "    ; echo $(node.name)")
            # print_int si aspetta il valore in rax
            if !(is_register(node.name) && node.name == "rax")
                push_nonempty!(lines, load_into("rax", node.name))
            end
            push!(lines, "    sub    rsp, 40")
            push!(lines, "    call   _t_print_int")
            push!(lines, "    add    rsp, 40")

        # ── echo "stringa" ────────────────────────────────────────────────────
        elseif node isa EchoStr
            lbl = st.strings[node.text]
            len = length(node.text) + 1   # +1 per '\n' in .data
            push!(lines, "    ; echo \"$(node.text)\"")
            push!(lines, "    lea    rcx, [rel $lbl]")
            push!(lines, "    mov    rdx, $len")
            push!(lines, "    sub    rsp, 40")
            push!(lines, "    call   _t_print_str")
            push!(lines, "    add    rsp, 40")

        # ── label ─────────────────────────────────────────────────────────────
        elseif node isa LabelNode
            push!(lines, "$(node.name):")

        # ── goto ─────────────────────────────────────────────────────────────
        elseif node isa GotoNode
            push!(lines, "    ; goto $(node.name)")
            push!(lines, "    jmp    $(node.name)")

        # ── goto name if cond ─────────────────────────────────────────────────
        elseif node isa CondGoto
            c = node.cond
            push!(lines, "    ; goto $(node.name) if $(c.left) $(c.op) $(c.right)")
            emit_cmp!(lines, c)
            push!(lines, "    $(JMP_IF_TRUE[c.op])    $(node.name)")

        # ── if / else / end ───────────────────────────────────────────────────
        elseif node isa IfBlock
            c        = node.cond
            lbl_else = new_label!(st, "else")
            lbl_end  = new_label!(st, "endif")
            push!(lines, "    ; if $(c.left) $(c.op) $(c.right)")
            emit_cmp!(lines, c)
            push!(lines, "    $(JMP_IF_FALSE[c.op])    $lbl_else")
            emit_nodes!(lines, node.then_body, st)
            push!(lines, "    jmp    $lbl_end")
            push!(lines, "$lbl_else:")
            if !isempty(node.else_body)
                emit_nodes!(lines, node.else_body, st)
            end
            push!(lines, "$lbl_end:")

        # ── while / end ───────────────────────────────────────────────────────
        elseif node isa WhileBlock
            c       = node.cond
            lbl_top = new_label!(st, "while")
            lbl_end = new_label!(st, "endw")
            push!(lines, "$lbl_top:")
            push!(lines, "    ; while $(c.left) $(c.op) $(c.right)")
            emit_cmp!(lines, c)
            push!(lines, "    $(JMP_IF_FALSE[c.op])    $lbl_end")
            emit_nodes!(lines, node.body, st)
            push!(lines, "    jmp    $lbl_top")
            push!(lines, "$lbl_end:")

        # ── Stack push/pop [NUOVO] ────────────────────────────────────────────
        elseif node isa PushNode
            push!(lines, "    ; push $(node.src)")
            push_nonempty!(lines, load_into("rax", node.src))
            push!(lines, "    push   rax")

        elseif node isa PopNode
            push!(lines, "    ; pop $(node.dest)")
            push!(lines, "    pop    rax")
            push_nonempty!(lines, store_from("rax", node.dest))

        # ── Inline ASM [NUOVO] ────────────────────────────────────────────────
        elseif node isa InlineAsm
            push!(lines, "    ; ── inline asm ──")
            for asml in node.code
                push!(lines, "    $asml")
            end
            push!(lines, "    ; ────────────────")
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Runtime: stampa interi e stringhe via WriteConsoleA (no CRT)
# Scratch registers: rax, r11, rcx, rdx, r8, r9
# ─────────────────────────────────────────────────────────────────────────────

const RUNTIME_HELPERS = raw"""
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
"""

# ─────────────────────────────────────────────────────────────────────────────
# 7. SEZIONI ASM
# ─────────────────────────────────────────────────────────────────────────────

function emit_data_section(sym::SymbolTable, st::CodegenState)
    lines = String["section .data"]

    for name in sort(collect(sym.vars))
        push!(lines, "    $(name)    dq 0")
    end

    for (name, elems) in sort(collect(sym.arrays), by=x->x[1])
        push!(lines, "    $(name)    dq $(join(elems, ", "))")
    end

    for (text, lbl) in sort(collect(st.strings), by=x->x[2])
        push!(lines, "    $(lbl)    db  \"$(text)\", 10, 0")
    end

    if st.need_print
        push!(lines, "")
        push!(lines, "section .bss")
        push!(lines, "    _t_hout    resq 1")
        push!(lines, "    _t_nwr     resd 1")
        push!(lines, "    _t_ibuf    resb 24")
    end

    return join(lines, '\n')
end

function emit_text_section(nodes::Vector{ASTNode}, st::CodegenState)
    extern_decls = ["    extern ExitProcess"]
    if st.need_print
        push!(extern_decls, "    extern GetStdHandle")
        push!(extern_decls, "    extern WriteConsoleA")
    end

    lines = String[
        "section .text",
        "    global main",
        join(extern_decls, '\n'),
        "",
        "main:",
    ]

    if st.need_print
        push!(lines, "    sub    rsp, 40")
        push!(lines, "    call   _t_init")
        push!(lines, "    add    rsp, 40")
    end

    emit_nodes!(lines, nodes, st)

    push!(lines, "")
    push!(lines, "    ; ── ExitProcess(0) ──────────────────────────────────")
    push!(lines, "    xor    rcx, rcx")
    push!(lines, "    sub    rsp, 40")
    push!(lines, "    call   ExitProcess")

    if st.need_print
        push!(lines, "")
        push!(lines, RUNTIME_HELPERS)
    end

    return join(lines, '\n')
end

# ─────────────────────────────────────────────────────────────────────────────
# 8. PIPELINE PRINCIPALE
# ─────────────────────────────────────────────────────────────────────────────

function transpile(src::String)
    nodes  = parse_program(src)
    sym    = build_symbol_table(nodes)
    st     = CodegenState()
    collect_print_needs!(st, nodes)
    data   = emit_data_section(sym, st)
    text   = emit_text_section(nodes, st)
    header = """; Generato da TinyASM v2 Transpiler (target: Windows x64)
; nasm -f win64 output.asm -o output.obj
; link output.obj kernel32.lib /nologo /subsystem:console /entry:main /out:output.exe

"""
    return header * data * "\n\n" * text * "\n"
end

# ─────────────────────────────────────────────────────────────────────────────
# 9. TOOLCHAIN WINDOWS
# ─────────────────────────────────────────────────────────────────────────────

function check_tool(name::String)
    try success(pipeline(`where $name`, devnull)) catch; false end
end

function find_msvc_tool(name::String)
    roots    = [get(ENV, "ProgramFiles", "C:\\Program Files"),
                get(ENV, "ProgramFiles(x86)", "C:\\Program Files (x86)")]
    vs_dirs  = ["Microsoft Visual Studio\\2022", "Microsoft Visual Studio\\2019"]
    editions = ["BuildTools", "Community", "Professional", "Enterprise"]
    for root in roots, vs in vs_dirs, ed in editions
        base = joinpath(root, vs, ed, "VC\\Tools\\MSVC")
        isdir(base) || continue
        for ver in readdir(base)
            c = joinpath(base, ver, "bin", "Hostx64", "x64", name)
            isfile(c) && return c
        end
    end
    return nothing
end

function find_kernel32()
    kits = joinpath(get(ENV, "ProgramFiles(x86)", "C:\\Program Files (x86)"),
                    "Windows Kits", "10", "Lib")
    isdir(kits) || return nothing
    vers = sort(filter(v -> isdir(joinpath(kits, v, "um", "x64")), readdir(kits)), rev=true)
    isempty(vers) && return nothing
    c = joinpath(kits, vers[1], "um", "x64", "kernel32.lib")
    return isfile(c) ? c : nothing
end

function run_step(cmd::Cmd, desc::String)
    println("  ▶  $desc")
    buf  = IOBuffer()
    proc = run(pipeline(cmd, stdout=buf, stderr=buf), wait=true)
    if !success(proc)
        println(stderr, String(take!(buf)))
        error("Comando fallito: $desc")
    end
end

function compile(asm_file::String, output_exe::String)
    obj_file = replace(asm_file, r"\.(asm|s)$" => ".obj")
    exe      = endswith(output_exe, ".exe") ? output_exe : output_exe * ".exe"

    println("\n── Compilazione (Windows x64) ───────────────────────────")

    check_tool("nasm") || error("NASM non trovato.\n  https://www.nasm.us/pub/nasm/releasebuilds/")

    linker_cmd, linker_name = if check_tool("gcc")
        (["gcc"], "gcc (MinGW)")
    else
        lnk = find_msvc_tool("link.exe")
        lnk !== nothing ? ([lnk], "MSVC [$lnk]") :
            error("Nessun linker trovato (gcc o link.exe MSVC).")
    end

    println("  i  Linker: $linker_name")
    run_step(`nasm -f win64 $asm_file -o $obj_file`, "nasm  →  $obj_file")

    if linker_cmd[1] == "gcc"
        run_step(`gcc $obj_file -o $exe -nostartfiles -lkernel32`, "gcc  →  $exe")
    else
        lnk = linker_cmd[1]
        k32 = find_kernel32()
        k32_arg = k32 !== nothing ? k32 : "kernel32.lib"
        k32 !== nothing && println("  i  kernel32.lib: $k32")
        run_step(Cmd([lnk, "/nologo", "/subsystem:console", "/entry:main",
                      obj_file, k32_arg, "/out:$exe"]), "link →  $exe")
    end

    rm(obj_file, force=true)
    println("✓  Eseguibile: $exe")
    println("   Esegui con: .\\$(basename(exe))")
end

# ─────────────────────────────────────────────────────────────────────────────
# 10. ENTRYPOINT
# ─────────────────────────────────────────────────────────────────────────────

function main()
    args       = copy(ARGS)
    do_compile = "--compile" ∈ args || "-c" ∈ args
    filter!(a -> a ∉ ("--compile", "-c"), args)

    if length(args) != 2
        println(stderr, "Utilizzo: julia transpiler.jl <input.tasm> <output.asm> [--compile]")
        exit(1)
    end

    input_file, output_file = args
    isfile(input_file) || (println(stderr, "File non trovato: $input_file"); exit(1))

    asm = try
        transpile(read(input_file, String))
    catch e
        println(stderr, "Errore: $(sprint(showerror, e))")
        exit(1)
    end

    write(output_file, asm)
    println("✓  Assembly generato: $output_file")

    if do_compile
        try
            compile(output_file, replace(output_file, r"\.(asm|s)$" => ""))
        catch e
            println(stderr, "\n✗  $(sprint(showerror, e))")
            exit(1)
        end
    end
end

main()