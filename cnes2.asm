; ============================================================================
; SugarRush Assembler v2.0 - Heavy Duty NES Compiler
; 120MB RAM Architecture | 600 Files Support | .candy Project Files
; A-Z Candy Themed Internal Memory Pools & Variables
; ============================================================================
format PE console
entry _start

; ============================================================================
; Windows API Constants
; ============================================================================
STD_OUTPUT_HANDLE     = -11
STD_ERROR_HANDLE      = -12
GENERIC_READ          = 0x80000000
GENERIC_WRITE         = 0x40000000
OPEN_EXISTING         = 3
CREATE_ALWAYS         = 2
FILE_ATTRIBUTE_NORMAL = 0x80
MEM_COMMIT            = 0x1000
MEM_RESERVE           = 0x2000
PAGE_READWRITE        = 0x04
MEM_RELEASE           = 0x8000
INVALID_HANDLE_VALUE  = -1

; ============================================================================
; Assembler Constants (120MB Architecture)
; ============================================================================
MEM_TOTAL             = 125829120   ; 120 MB total
POOL_SOURCE_SIZE      = 20971520    ; 20 MB
POOL_OUTPUT_SIZE      = 16777216    ; 16 MB
POOL_SYMS_SIZE        = 64000000    ; 64 MB
POOL_HASH_SIZE        = 8388608     ; 8 MB
POOL_STR_SIZE         = 10485760    ; 10 MB
POOL_MISC_SIZE        = 5242880     ; 5 MB

MAX_SYMBOLS           = 1000000
SYM_ENTRY_SIZE        = 64          ; 48 name + 4 val + 4 flags + 4 next + 4 pad
HASH_TABLE_SIZE       = 2097152     ; 2M entries
HASH_MASK             = 2097151

MAX_FILES             = 600
FILE_ENTRY_SIZE       = 268         ; 256 name + 4 offset + 4 len + 4 base
MAX_LINE              = 2048
MAX_INCLUDES          = 64
SYMBOL_NAME_LEN       = 48

SYM_DEFINED           = 1
SYM_LABEL             = 2
SYM_CONSTANT          = 4
SYM_MACRO             = 8

AM_IMPLIED            = 0
AM_ACCUMULATOR        = 1
AM_IMMEDIATE          = 2
AM_ZEROPAGE           = 3
AM_ZEROPAGE_X         = 4
AM_ZEROPAGE_Y         = 5
AM_ABSOLUTE           = 6
AM_ABSOLUTE_X         = 7
AM_ABSOLUTE_Y         = 8
AM_INDIRECT           = 9
AM_INDIRECT_X         = 10
AM_INDIRECT_Y         = 11
AM_RELATIVE           = 12

; ============================================================================
; Data Section
; ============================================================================
section '.data' data readable writeable

; --- UI Messages (English) ---
msg_banner      db 'SugarRush Assembler v2.0 - Heavy Duty NES Compiler',13,10
                db '120MB RAM | 600 Files | A-Z Candy Architecture',13,10,0
msg_usage       db 'Usage: SugarRush project.candy  or  SugarRush file.asm',13,10,0
msg_reading     db 'Reading project: ',0
msg_pass1       db 'Pass 1: Analyzing symbols...',13,10,0
msg_pass2       db 'Pass 2: Generating code...',13,10,0
msg_writing     db 'Writing ROM: ',0
msg_done        db 'Compilation successful!',13,10,0
msg_symbols     db ' symbols defined',13,10,0
msg_bytes       db ' bytes of PRG-ROM generated',13,10,0
msg_err_open    db 'Error: Cannot open: ',0
msg_err_mem     db 'Error: Out of memory (VirtualAlloc 120MB failed)',13,10,0
msg_err_write   db 'Error: Cannot write output file',13,10,0
msg_newline     db 13,10,0

; --- A-Z Candy Themed Variables ---
input_filename  db 260 dup(0)
output_filename db 260 dup(0)
base_path       db 260 dup(0)

mem_base        dd 0
Apple_Pool      dd 0        ; A - Apple (Source Pool)
Bonbon_Pool     dd 0        ; B - Bonbon (Output Pool)
Caramel_Pool    dd 0        ; C - Caramel (Symbol Pool)
Donut_Pool      dd 0        ; D - Donut (Hash Pool)
Eclair_Pool     dd 0        ; E - Eclair (String Pool)
Fudge_Pool      dd 0        ; F - Fudge (Misc Pool)

Gummy_Table     rb MAX_FILES * FILE_ENTRY_SIZE ; G - Gummy (File Table)
num_files       dd 0

IceCream_Stack  rb 64       ; I - IceCream (If Stack)
if_sp           dd 0

Jawbreaker_Stack_Pos rd 32  ; J - Jawbreaker (Rept Stack Pos)
Jawbreaker_Stack_Line rd 32 ; J - Jawbreaker (Rept Stack Line)
Jawbreaker_Stack_Cnt rd 32  ; J - Jawbreaker (Rept Stack Count)
rept_sp         dd 0

KitKat_Buf      db MAX_LINE dup(0) ; K - KitKat (Token Buffer)
Lollipop_Buf    db MAX_LINE dup(0) ; L - Lollipop (Line Buffer)
Marshmallow_Buf db MAX_LINE dup(0) ; M - Marshmallow (Operand Buffer)
Nougat_Buf      db 260 dup(0)      ; N - Nougat (Path Buffer)

Oreo_Handle     dd 0        ; O - Oreo (Stdout Handle)
Peppermint_Handle dd 0      ; P - Peppermint (Stderr Handle)
Quince_Handle   dd 0        ; Q - Quince (File Handle)
RockCandy_Bytes dd 0        ; R - RockCandy (Bytes Read/Written)

Snickers_PC     dd 0        ; S - Snickers (Program Counter)
Taffy_Org       dd 0x8000   ; T - Taffy (Origin)
Uno_Bar_Pos     dd 0        ; U - U-No Bar (Output Position)
Vanilla_Pos     dd 0        ; V - Vanilla (Source Position)
Waffle_Len      dd 0        ; W - Waffle (Source Length)
Xylitol_Line    dd 0        ; X - Xylitol (Line Number)
York_Syms       dd 0        ; Y - York (Symbol Count)
Zagnut_Errs     dd 0        ; Z - Zagnut (Error Count)

has_errors      dd 0
current_pass    dd 0

ines_prg        dd 1
ines_chr        dd 0
ines_mirror     dd 0
ines_mapper     dd 0
ines_battery    dd 0

current_bank    dd 0
rs_address      dd 0

expr_value      dd 0

; 6502 Opcode Table
align 4
opcode_table:
op_adc  db 'ADC',0,  0xFF,0xFF,0x69,0x65,0x75,0xFF,0x6D,0x7D,0x79,0xFF,0x61,0x71,0xFF, 0,0,0
op_and  db 'AND',0,  0xFF,0xFF,0x29,0x25,0x35,0xFF,0x2D,0x3D,0x39,0xFF,0x21,0x31,0xFF, 0,0,0
op_asl  db 'ASL',0,  0xFF,0x0A,0xFF,0x06,0x16,0xFF,0x0E,0x1E,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_bcc  db 'BCC',0,  0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x90, 0,0,0
op_bcs  db 'BCS',0,  0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xB0, 0,0,0
op_beq  db 'BEQ',0,  0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xF0, 0,0,0
op_bit  db 'BIT',0,  0xFF,0xFF,0xFF,0x24,0xFF,0xFF,0x2C,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_bmi  db 'BMI',0,  0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x30, 0,0,0
op_bne  db 'BNE',0,  0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xD0, 0,0,0
op_bpl  db 'BPL',0,  0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x10, 0,0,0
op_brk  db 'BRK',0,  0x00,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_bvc  db 'BVC',0,  0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x50, 0,0,0
op_bvs  db 'BVS',0,  0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x70, 0,0,0
op_clc  db 'CLC',0,  0x18,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_cld  db 'CLD',0,  0xD8,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_cli  db 'CLI',0,  0x58,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_clv  db 'CLV',0,  0xB8,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_cmp  db 'CMP',0,  0xFF,0xFF,0xC9,0xC5,0xD5,0xFF,0xCD,0xDD,0xD9,0xFF,0xC1,0xD1,0xFF, 0,0,0
op_cpx  db 'CPX',0,  0xFF,0xFF,0xE0,0xE4,0xFF,0xFF,0xEC,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_cpy  db 'CPY',0,  0xFF,0xFF,0xC0,0xC4,0xFF,0xFF,0xCC,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_dec  db 'DEC',0,  0xFF,0xFF,0xFF,0xC6,0xD6,0xFF,0xCE,0xDE,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_dex  db 'DEX',0,  0xCA,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_dey  db 'DEY',0,  0x88,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_eor  db 'EOR',0,  0xFF,0xFF,0x49,0x45,0x55,0xFF,0x4D,0x5D,0x59,0xFF,0x41,0x51,0xFF, 0,0,0
op_inc  db 'INC',0,  0xFF,0xFF,0xFF,0xE6,0xF6,0xFF,0xEE,0xFE,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_inx  db 'INX',0,  0xE8,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_iny  db 'INY',0,  0xC8,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_jmp  db 'JMP',0,  0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x4C,0xFF,0xFF,0x6C,0xFF,0xFF,0xFF, 0,0,0
op_jsr  db 'JSR',0,  0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x20,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_lda  db 'LDA',0,  0xFF,0xFF,0xA9,0xA5,0xB5,0xFF,0xAD,0xBD,0xB9,0xFF,0xA1,0xB1,0xFF, 0,0,0
op_ldx  db 'LDX',0,  0xFF,0xFF,0xA2,0xA6,0xFF,0xB6,0xAE,0xFF,0xBE,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_ldy  db 'LDY',0,  0xFF,0xFF,0xA0,0xA4,0xB4,0xFF,0xAC,0xBC,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_lsr  db 'LSR',0,  0xFF,0x4A,0xFF,0x46,0x56,0xFF,0x4E,0x5E,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_nop  db 'NOP',0,  0xEA,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_ora  db 'ORA',0,  0xFF,0xFF,0x09,0x05,0x15,0xFF,0x0D,0x1D,0x19,0xFF,0x01,0x11,0xFF, 0,0,0
op_pha  db 'PHA',0,  0x48,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_php  db 'PHP',0,  0x08,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_pla  db 'PLA',0,  0x68,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_plp  db 'PLP',0,  0x28,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_rol  db 'ROL',0,  0xFF,0x2A,0xFF,0x26,0x36,0xFF,0x2E,0x3E,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_ror  db 'ROR',0,  0xFF,0x6A,0xFF,0x66,0x76,0xFF,0x6E,0x7E,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_rti  db 'RTI',0,  0x40,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_rts  db 'RTS',0,  0x60,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_sbc  db 'SBC',0,  0xFF,0xFF,0xE9,0xE5,0xF5,0xFF,0xED,0xFD,0xF9,0xFF,0xE1,0xF1,0xFF, 0,0,0
op_sec  db 'SEC',0,  0x38,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_sed  db 'SED',0,  0xF8,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_sei  db 'SEI',0,  0x78,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_sta  db 'STA',0,  0xFF,0xFF,0xFF,0x85,0x95,0xFF,0x8D,0x9D,0x99,0xFF,0x81,0x91,0xFF, 0,0,0
op_stx  db 'STX',0,  0xFF,0xFF,0xFF,0x86,0xFF,0x96,0x8E,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_sty  db 'STY',0,  0xFF,0xFF,0xFF,0x84,0x94,0xFF,0x8C,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_tax  db 'TAX',0,  0xAA,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_tay  db 'TAY',0,  0xA8,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_tsx  db 'TSX',0,  0xBA,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_txa  db 'TXA',0,  0x8A,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_txs  db 'TXS',0,  0x9A,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
op_tya  db 'TYA',0,  0x98,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0,0,0
opcode_table_end:
NUM_OPCODES = (opcode_table_end - opcode_table) / 20

instr_sizes db 1,  1,  2,  2,  2,  2,  3,  3,   3,   3,  2,   2,   2
num_buf     db 16 dup(0)

; ============================================================================
; Code Section
; ============================================================================
section '.text' code readable executable

_start:
        push    STD_OUTPUT_HANDLE
        call    [GetStdHandle]
        mov     [Oreo_Handle], eax
        push    STD_ERROR_HANDLE
        call    [GetStdHandle]
        mov     [Peppermint_Handle], eax

        push    msg_banner
        call    print_string

        call    [GetCommandLineA]
        mov     esi, eax
        call    skip_arg
        call    skip_spaces
        cmp     byte [esi], 0
        je      .show_usage

        lea     edi, [input_filename]
        call    copy_arg

        call    alloc_memory
        test    eax, eax
        jz      .mem_error

        lea     esi, [input_filename]
        lea     edi, [output_filename]
        call    make_output_name

        lea     esi, [input_filename]
        call    check_extension_candy
        test    eax, eax
        jnz     .is_project

        push    input_filename
        call    load_source_file
        test    eax, eax
        jz      .open_error
        jmp     .start_pass1

.is_project:
        push    msg_reading
        call    print_string
        push    input_filename
        call    print_string
        push    msg_newline
        call    print_string

        push    input_filename
        call    parse_project_file
        test    eax, eax
        jz      .open_error

.start_pass1:
        push    msg_pass1
        call    print_string
        mov     dword [current_pass], 1
        call    assemble_pass
        cmp     dword [has_errors], 0
        jne     .had_errors

        push    dword [York_Syms]
        call    print_number
        push    msg_symbols
        call    print_string

        push    msg_pass2
        call    print_string
        mov     dword [current_pass], 2
        mov     dword [Uno_Bar_Pos], 0
        call    assemble_pass
        cmp     dword [has_errors], 0
        jne     .had_errors

        push    dword [Uno_Bar_Pos]
        call    print_number
        push    msg_bytes
        call    print_string

        push    msg_writing
        call    print_string
        push    output_filename
        call    print_string
        push    msg_newline
        call    print_string

        call    write_nes_file
        test    eax, eax
        jz      .write_error

        push    msg_done
        call    print_string
        push    0
        call    [ExitProcess]

.show_usage:
        push    msg_usage
        call    print_string
        push    1
        call    [ExitProcess]
.mem_error:
        push    msg_err_mem
        call    print_string_err
        push    1
        call    [ExitProcess]
.open_error:
        push    msg_err_open
        call    print_string_err
        push    input_filename
        call    print_string_err
        push    msg_newline
        call    print_string_err
        push    1
        call    [ExitProcess]
.write_error:
        push    msg_err_write
        call    print_string_err
        push    1
        call    [ExitProcess]
.had_errors:
        push    msg_newline
        call    print_string_err
        push    1
        call    [ExitProcess]

alloc_memory:
        push    PAGE_READWRITE
        push    MEM_COMMIT or MEM_RESERVE
        push    MEM_TOTAL
        push    0
        call    [VirtualAlloc]
        test    eax, eax
        jz      .fail
        mov     [mem_base], eax

        mov     ebx, eax
        mov     [Apple_Pool], ebx
        add     ebx, POOL_SOURCE_SIZE
        mov     [Bonbon_Pool], ebx
        add     ebx, POOL_OUTPUT_SIZE
        mov     [Caramel_Pool], ebx
        add     ebx, POOL_SYMS_SIZE
        mov     [Donut_Pool], ebx
        add     ebx, POOL_HASH_SIZE
        mov     [Eclair_Pool], ebx
        add     ebx, POOL_STR_SIZE
        mov     [Fudge_Pool], ebx
        
        xor     eax, eax
        inc     eax
        ret
.fail:
        xor     eax, eax
        ret

check_extension_candy:
        push    esi
        xor     ecx, ecx
.find_dot:
        lodsb
        test    al, al
        jz      .no_ext
        cmp     al, '.'
        jne     .find_dot
        lea     ecx, [esi-1]
        jmp     .find_dot
.no_ext:
        test    ecx, ecx
        jz      .ret_false
        mov     esi, ecx
        lodsb
        or      al, 0x20
        cmp     al, 'c'
        jne     .ret_false
        lodsb
        or      al, 0x20
        cmp     al, 'a'
        jne     .ret_false
        lodsb
        or      al, 0x20
        cmp     al, 'n'
        jne     .ret_false
        lodsb
        or      al, 0x20
        cmp     al, 'd'
        jne     .ret_false
        lodsb
        or      al, 0x20
        cmp     al, 'y'
        jne     .ret_false
        pop     esi
        mov     eax, 1
        ret
.ret_false:
        pop     esi
        xor     eax, eax
        ret

parse_project_file:
        push    ebp
        mov     ebp, esp
        push    ebx
        push    edi

        push    0
        lea     eax, [Nougat_Buf]
        push    eax
        push    260
        push    dword [ebp+8]
        call    [GetFullPathNameA]

        lea     esi, [Nougat_Buf]
        xor     ecx, ecx
.find_last_slash:
        lodsb
        test    al, al
        jz      .done_slash
        cmp     al, '\'
        je      .is_slash
        cmp     al, '/'
        je      .is_slash
        inc     ecx
        jmp     .find_last_slash
.is_slash:
        mov     edx, esi
        dec     edx
        jmp     .find_last_slash
.done_slash:
        test    edx, edx
        jz      .no_dir
        mov     byte [edx+1], 0
.no_dir:
        lea     esi, [Nougat_Buf]
        lea     edi, [base_path]
.copy_base:
        lodsb
        stosb
        test    al, al
        jnz     .copy_base

        push    0
        push    FILE_ATTRIBUTE_NORMAL
        push    OPEN_EXISTING
        push    0
        push    0
        push    GENERIC_READ
        push    dword [ebp+8]
        call    [CreateFileA]
        cmp     eax, INVALID_HANDLE_VALUE
        je      .fail

        mov     ebx, eax
        mov     edi, [Fudge_Pool]
        push    0
        push    RockCandy_Bytes
        push    POOL_MISC_SIZE
        push    edi
        push    ebx
        call    [ReadFile]
        push    ebx
        call    [CloseHandle]

        mov     ecx, [RockCandy_Bytes]
        mov     byte [edi+ecx], 0
        mov     esi, edi

.parse_loop:
        call    .skip_ws
        cmp     byte [esi], 0
        je      .done
        cmp     byte [esi], ';'
        je      .skip_line
        cmp     word [esi], '//'
        je      .skip_line

        lea     edi, [KitKat_Buf]
        xor     ecx, ecx
.read_key:
        mov     al, [esi]
        cmp     al, '='
        je      .got_key
        cmp     al, ' '
        je      .got_key
        cmp     al, 9
        je      .got_key
        cmp     al, 13
        je      .got_key
        cmp     al, 10
        je      .got_key
        test    al, al
        jz      .got_key
        stosb
        inc     esi
        inc     ecx
        jmp     .read_key
.got_key:
        mov     byte [edi], 0
        call    .skip_ws
        cmp     byte [esi], '='
        jne     .skip_line
        inc     esi
        call    .skip_ws

        lea     edi, [Marshmallow_Buf]
        xor     ecx, ecx
.read_val:
        mov     al, [esi]
        cmp     al, 13
        je      .got_val
        cmp     al, 10
        je      .got_val
        cmp     al, ';'
        je      .got_val
        test    al, al
        jz      .got_val
        stosb
        inc     esi
        inc     ecx
        jmp     .read_val
.got_val:
        mov     byte [edi], 0

        lea     eax, [KitKat_Buf]
        cmp     dword [eax], 'file'
        je      .load_file
        jmp     .check_config

.load_file:
        lea     esi, [base_path]
        lea     edi, [Nougat_Buf]
.copy_base2:
        lodsb
        stosb
        test    al, al
        jnz     .copy_base2
        dec     edi
        lea     esi, [Marshmallow_Buf]
.copy_file:
        lodsb
        stosb
        test    al, al
        jnz     .copy_file
        
        push    Nougat_Buf
        call    load_source_file
        jmp     .next_line

.check_config:
        cmp     dword [eax], 'ines'
        jne     .next_line
        cmp     dword [eax+4], 'prg' + (0 shl 24)
        je      .set_prg
        cmp     dword [eax+4], 'chr' + (0 shl 24)
        je      .set_chr
        cmp     dword [eax+4], 'mir' + (0 shl 24)
        je      .set_mir
        cmp     dword [eax+4], 'map' + (0 shl 24)
        je      .set_map
        jmp     .next_line

.set_prg:
        lea     esi, [Marshmallow_Buf]
        call    eval_expression
        mov     [ines_prg], eax
        jmp     .next_line
.set_chr:
        lea     esi, [Marshmallow_Buf]
        call    eval_expression
        mov     [ines_chr], eax
        jmp     .next_line
.set_mir:
        lea     esi, [Marshmallow_Buf]
        call    eval_expression
        mov     [ines_mirror], eax
        jmp     .next_line
.set_map:
        lea     esi, [Marshmallow_Buf]
        call    eval_expression
        mov     [ines_mapper], eax

.next_line:
        cmp     byte [esi], 13
        jne     .nl2
        inc     esi
.nl2:
        cmp     byte [esi], 10
        jne     .nl3
        inc     esi
.nl3:
        jmp     .parse_loop

.skip_line:
        lodsb
        test    al, al
        jz      .done
        cmp     al, 10
        jne     .skip_line
        jmp     .parse_loop

.skip_ws:
        cmp     byte [esi], ' '
        je      .sw1
        cmp     byte [esi], 9
        je      .sw1
        ret
.sw1:
        inc     esi
        jmp     .skip_ws

.done:
        mov     eax, 1
        pop     edi
        pop     ebx
        pop     ebp
        ret     4
.fail:
        xor     eax, eax
        pop     edi
        pop     ebx
        pop     ebp
        ret     4

load_source_file:
        push    ebp
        mov     ebp, esp
        push    ebx
        push    edi

        push    0
        push    FILE_ATTRIBUTE_NORMAL
        push    OPEN_EXISTING
        push    0
        push    0
        push    GENERIC_READ
        push    dword [ebp+8]
        call    [CreateFileA]
        cmp     eax, INVALID_HANDLE_VALUE
        je      .fail

        mov     ebx, eax
        push    0
        push    ebx
        call    [GetFileSize]
        mov     ecx, eax

        mov     edx, [Waffle_Len]
        add     edx, ecx
        add     edx, 2
        cmp     edx, POOL_SOURCE_SIZE
        ja      .close_fail

        mov     edi, [Apple_Pool]
        add     edi, [Waffle_Len]
        push    0
        push    RockCandy_Bytes
        push    ecx
        push    edi
        push    ebx
        call    [ReadFile]

        mov     eax, [num_files]
        cmp     eax, MAX_FILES
        jge     .close_fail
        
        mov     edi, eax
        imul    edi, FILE_ENTRY_SIZE
        add     edi, Gummy_Table
        
        push    edi
        mov     esi, [ebp+8]
        xor     ecx, ecx
.copy_name:
        lodsb
        stosb
        inc     ecx
        test    al, al
        jnz     .copy_name
        pop     edi
        
        mov     eax, [Waffle_Len]
        mov     [edi+256], eax
        mov     eax, [RockCandy_Bytes]
        mov     [edi+260], eax
        mov     dword [edi+264], 0
        
        inc     dword [num_files]
        
        ; FIXED: Avoid memory-to-memory addition
        mov     eax, [RockCandy_Bytes]
        add     [Waffle_Len], eax
        
        mov     edi, [Apple_Pool]
        add     edi, [Waffle_Len]
        mov     byte [edi], 13
        mov     byte [edi+1], 10
        add     dword [Waffle_Len], 2

        push    ebx
        call    [CloseHandle]
        mov     eax, 1
        pop     edi
        pop     ebx
        pop     ebp
        ret     4

.close_fail:
        push    ebx
        call    [CloseHandle]
.fail:
        xor     eax, eax
        pop     edi
        pop     ebx
        pop     ebp
        ret     4

assemble_pass:
        pushad
        mov     eax, [Taffy_Org]
        mov     [Snickers_PC], eax
        mov     dword [Vanilla_Pos], 0
        mov     dword [Xylitol_Line], 0
        mov     dword [Zagnut_Errs], 0
        mov     dword [has_errors], 0
        mov     dword [rept_sp], 0
        mov     dword [if_sp], 0

        cmp     dword [current_pass], 2
        jne     .pass1_init
        mov     dword [Snickers_PC], 0x8000
        mov     dword [Taffy_Org], 0x8000
        jmp     .main_loop
.pass1_init:
        mov     dword [York_Syms], 0
        mov     edi, [Donut_Pool]
        mov     ecx, HASH_TABLE_SIZE
        xor     eax, eax
        rep     stosd

.main_loop:
        mov     eax, [Vanilla_Pos]
        cmp     eax, [Waffle_Len]
        jge     .pass_done

        call    read_line
        inc     dword [Xylitol_Line]
        
        mov     eax, [if_sp]
        test    eax, eax
        jz      .process
        dec     eax
        movzx   eax, byte [IceCream_Stack + eax]
        test    eax, eax
        jnz     .process
        
        lea     esi, [Lollipop_Buf]
        call    skip_ws
        cmp     byte [esi], '.'
        jne     .main_loop
        inc     esi
        lea     edi, [KitKat_Buf]
        xor     ecx, ecx
.read_dir:
        mov     al, [esi+ecx]
        call    is_ident_char
        jnc     .check_dir
        mov     [edi+ecx], al
        inc     ecx
        jmp     .read_dir
.check_dir:
        mov     byte [edi+ecx], 0
        lea     eax, [KitKat_Buf]
        cmp     dword [eax], 'if' + (0 shl 16)
        je      .inc_if
        cmp     dword [eax], 'else'
        je      .toggle_if
        cmp     dword [eax], 'endi'
        je      .dec_if
        jmp     .main_loop
.inc_if:
        mov     eax, [if_sp]
        mov     byte [IceCream_Stack + eax], 0
        inc     dword [if_sp]
        jmp     .main_loop
.toggle_if:
        mov     eax, [if_sp]
        dec     eax
        movzx   eax, byte [IceCream_Stack + eax]
        xor     eax, 1
        mov     edx, [if_sp]
        dec     edx
        mov     [IceCream_Stack + edx], al
        jmp     .main_loop
.dec_if:
        dec     dword [if_sp]
        jmp     .main_loop

.process:
        lea     esi, [Lollipop_Buf]
        call    process_line
        jmp     .main_loop

.pass_done:
        popad
        ret

read_line:
        push    esi
        push    edi
        push    ecx
        mov     esi, [Apple_Pool]
        add     esi, [Vanilla_Pos]
        lea     edi, [Lollipop_Buf]
        xor     ecx, ecx
.read_char:
        mov     eax, [Vanilla_Pos]
        add     eax, ecx
        cmp     eax, [Waffle_Len]
        jge     .end_of_source
        mov     al, [esi+ecx]
        cmp     al, 13
        je      .found_eol
        cmp     al, 10
        je      .found_eol
        cmp     ecx, MAX_LINE-2
        jge     .found_eol
        mov     [edi+ecx], al
        inc     ecx
        jmp     .read_char
.found_eol:
        mov     byte [edi+ecx], 0
        add     ecx, [Vanilla_Pos]
.skip_eol:
        cmp     ecx, [Waffle_Len]
        jge     .done
        mov     esi, [Apple_Pool]
        mov     al, [esi+ecx]
        cmp     al, 13
        je      .skip_one
        cmp     al, 10
        je      .skip_one
        jmp     .done
.skip_one:
        inc     ecx
        jmp     .skip_eol
.done:
        mov     [Vanilla_Pos], ecx
        pop     ecx
        pop     edi
        pop     esi
        ret
.end_of_source:
        mov     byte [edi+ecx], 0
        add     ecx, [Vanilla_Pos]
        mov     [Vanilla_Pos], ecx
        pop     ecx
        pop     edi
        pop     esi
        ret

process_line:
        pushad
        call    skip_ws
        cmp     byte [esi], 0
        je      .line_done
        cmp     byte [esi], ';'
        je      .line_done
        cmp     word [esi], '//'
        je      .line_done

        push    esi
        call    check_label
        pop     esi
        test    eax, eax
        jz      .no_label
        call    handle_label
        call    skip_ws
        cmp     byte [esi], 0
        je      .line_done
        cmp     byte [esi], ';'
        je      .line_done
.no_label:
        cmp     byte [esi], '.'
        je      .is_directive
        push    esi
        call    check_assignment
        pop     esi
        test    eax, eax
        jnz     .line_done
        call    handle_instruction
        jmp     .line_done
.is_directive:
        call    handle_directive
.line_done:
        popad
        ret

skip_ws:
        cmp     byte [esi], ' '
        je      .sw1
        cmp     byte [esi], 9
        je      .sw1
        ret
.sw1:
        inc     esi
        jmp     skip_ws

check_label:
        push    esi
        mov     al, [esi]
        call    is_ident_start
        jnc     .cl_no
.cl_scan:
        inc     esi
        mov     al, [esi]
        cmp     al, ':'
        je      .cl_yes
        call    is_ident_char
        jc      .cl_scan
.cl_no:
        pop     esi
        xor     eax, eax
        ret
.cl_yes:
        pop     esi
        mov     eax, 1
        ret

is_ident_start:
        cmp     al, '_'
        je      .iis_yes
        cmp     al, '@'
        je      .iis_yes
        call    is_alpha
        ret
.iis_yes:
        stc
        ret

is_ident_char:
        call    is_ident_start
        jc      .iic_yes
        call    is_digit
        ret
.iic_yes:
        stc
        ret

is_alpha:
        cmp     al, 'A'
        jb      .ia_no
        cmp     al, 'Z'
        jbe     .ia_yes
        cmp     al, 'a'
        jb      .ia_no
        cmp     al, 'z'
        jbe     .ia_yes
.ia_no:
        clc
        ret
.ia_yes:
        stc
        ret

is_digit:
        cmp     al, '0'
        jb      .id_no
        cmp     al, '9'
        jbe     .id_yes
.id_no:
        clc
        ret
.id_yes:
        stc
        ret

handle_label:
        push    edi
        lea     edi, [KitKat_Buf]
        xor     ecx, ecx
.hl_copy:
        mov     al, [esi]
        cmp     al, ':'
        je      .hl_end
        call    is_ident_char
        jnc     .hl_end
        cmp     ecx, SYMBOL_NAME_LEN-1
        jge     .hl_end
        cmp     al, 'a'
        jb      .hl_store
        cmp     al, 'z'
        ja      .hl_store
        sub     al, 32
.hl_store:
        mov     [edi+ecx], al
        inc     ecx
        inc     esi
        jmp     .hl_copy
.hl_end:
        mov     byte [edi+ecx], 0
        cmp     byte [esi], ':'
        jne     .hl_no_colon
        inc     esi
.hl_no_colon:
        pop     edi
        cmp     dword [current_pass], 1
        jne     .hl_skip_add
        mov     edx, [Snickers_PC]
        mov     ecx, SYM_DEFINED or SYM_LABEL
        lea     esi, [KitKat_Buf]
        call    add_symbol
.hl_skip_add:
        ret

check_assignment:
        push    ebx
        push    edi
        push    esi
        mov     al, [esi]
        call    is_ident_start
        jnc     .ca_no
        lea     edi, [KitKat_Buf]
        xor     ecx, ecx
.ca_ident:
        mov     al, [esi+ecx]
        call    is_ident_char
        jnc     .ca_ident_done
        cmp     al, 'a'
        jb      .ca_store
        cmp     al, 'z'
        ja      .ca_store
        sub     al, 32
.ca_store:
        mov     [edi+ecx], al
        inc     ecx
        jmp     .ca_ident
.ca_ident_done:
        mov     byte [edi+ecx], 0
        add     esi, ecx
        call    skip_ws
        cmp     byte [esi], '='
        je      .ca_found
        push    esi
        mov     al, [esi]
        or      al, 0x20
        cmp     al, 'e'
        jne     .ca_not_equ
        mov     al, [esi+1]
        or      al, 0x20
        cmp     al, 'q'
        jne     .ca_not_equ
        mov     al, [esi+2]
        or      al, 0x20
        cmp     al, 'u'
        jne     .ca_not_equ
        mov     al, [esi+3]
        cmp     al, ' '
        je      .ca_equ_found
        cmp     al, 9
        je      .ca_equ_found
.ca_not_equ:
        pop     esi
        jmp     .ca_no
.ca_equ_found:
        pop     esi
        add     esi, 3
        jmp     .ca_eval
.ca_found:
        inc     esi
.ca_eval:
        call    skip_ws
        call    eval_expression
        cmp     dword [current_pass], 1
        jne     .ca_done
        mov     edx, eax
        mov     ecx, SYM_DEFINED or SYM_CONSTANT
        lea     esi, [KitKat_Buf]
        call    add_symbol
.ca_done:
        pop     esi
        pop     edi
        pop     ebx
        mov     eax, 1
        ret
.ca_no:
        pop     esi
        pop     edi
        pop     ebx
        xor     eax, eax
        ret

handle_directive:
        inc     esi
        push    edi
        lea     edi, [KitKat_Buf]
        xor     ecx, ecx
.hd_copy:
        mov     al, [esi+ecx]
        call    is_ident_char
        jnc     .hd_copy_done
        cmp     al, 'A'
        jb      .hd_store
        cmp     al, 'Z'
        ja      .hd_store
        or      al, 0x20
.hd_store:
        mov     [edi+ecx], al
        inc     ecx
        jmp     .hd_copy
.hd_copy_done:
        mov     byte [edi+ecx], 0
        add     esi, ecx
        pop     edi
        call    skip_ws
        lea     eax, [KitKat_Buf]
        cmp     dword [eax], 'org' + (0 shl 24)
        je      .dir_org
        cmp     word [eax], 'db'
        je      .dir_db
        cmp     dword [eax], 'byte'
        je      .dir_db
        cmp     word [eax], 'dw'
        je      .dir_dw
        cmp     dword [eax], 'word'
        je      .dir_dw
        cmp     dword [eax], 'ines'
        jne     .not_ines
        cmp     dword [eax+4], 'prg' + (0 shl 24)
        je      .dir_inesprg
        cmp     dword [eax+4], 'chr' + (0 shl 24)
        je      .dir_ineschr
        cmp     dword [eax+4], 'mir' + (0 shl 24)
        je      .dir_inesmir
        cmp     dword [eax+4], 'map' + (0 shl 24)
        je      .dir_inesmap
.not_ines:
        cmp     dword [eax], 'bank'
        je      .dir_bank
        cmp     dword [eax], 'rsse'
        je      .dir_rsset
        cmp     word [eax], 'rs'
        je      .dir_rs
        cmp     word [eax], 'ds'
        je      .dir_ds
        cmp     dword [eax], 'alig'
        je      .dir_align
        cmp     dword [eax], 'rept'
        je      .dir_rept
        cmp     dword [eax], 'endr'
        je      .dir_endr
        cmp     word [eax], 'if' + (0 shl 16)
        je      .dir_if
        cmp     dword [eax], 'else'
        je      .dir_else
        cmp     dword [eax], 'endi'
        je      .dir_endif
        ret

.dir_org:
        call    eval_expression
        mov     [Snickers_PC], eax
        mov     [Taffy_Org], eax
        ret

.dir_db:
.db_loop:
        call    skip_ws
        cmp     byte [esi], 0
        je      .db_done
        cmp     byte [esi], ';'
        je      .db_done
        cmp     byte [esi], '"'
        je      .db_string
        call    eval_expression
        cmp     dword [current_pass], 2
        jne     .db_skip_emit
        call    emit_byte_al
.db_skip_emit:
        inc     dword [Snickers_PC]
        call    skip_ws
        cmp     byte [esi], ','
        jne     .db_done
        inc     esi
        jmp     .db_loop
.db_done:
        ret
.db_string:
        inc     esi
.dbs_loop:
        mov     al, [esi]
        cmp     al, '"'
        je      .dbs_end
        cmp     al, 0
        je      .dbs_end
        cmp     dword [current_pass], 2
        jne     .dbs_skip
        call    emit_byte_al
.dbs_skip:
        inc     dword [Snickers_PC]
        inc     esi
        jmp     .dbs_loop
.dbs_end:
        cmp     byte [esi], '"'
        jne     .db_comma_check
        inc     esi
.db_comma_check:
        call    skip_ws
        cmp     byte [esi], ','
        jne     .db_done
        inc     esi
        jmp     .db_loop

.dir_dw:
.dw_loop:
        call    skip_ws
        cmp     byte [esi], 0
        je      .dw_done
        cmp     byte [esi], ';'
        je      .dw_done
        call    eval_expression
        cmp     dword [current_pass], 2
        jne     .dw_skip
        call    emit_byte_al
        mov     al, ah
        call    emit_byte_al
.dw_skip:
        add     dword [Snickers_PC], 2
        call    skip_ws
        cmp     byte [esi], ','
        jne     .dw_done
        inc     esi
        jmp     .dw_loop
.dw_done:
        ret

.dir_inesprg:
        call    eval_expression
        mov     [ines_prg], eax
        ret

.dir_ineschr:
        call    eval_expression
        mov     [ines_chr], eax
        ret

.dir_inesmir:
        call    eval_expression
        mov     [ines_mirror], eax
        ret

.dir_inesmap:
        call    eval_expression
        mov     [ines_mapper], eax
        ret

.dir_bank:
        call    eval_expression
        mov     [current_bank], eax
        ret

.dir_rsset:
        call    eval_expression
        mov     [rs_address], eax
        ret

.dir_rs:
        call    eval_expression
        add     [rs_address], eax
        ret


.dir_if:
        call    eval_expression
        test    eax, eax
        jz      .if_false
        mov     eax, [if_sp]
        mov     byte [IceCream_Stack + eax], 1
        inc     dword [if_sp]
        ret
.if_false:
        mov     eax, [if_sp]
        mov     byte [IceCream_Stack + eax], 0
        inc     dword [if_sp]
        ret
.dir_else:
        mov     eax, [if_sp]
        dec     eax
        movzx   eax, byte [IceCream_Stack + eax]
        xor     eax, 1
        mov     edx, [if_sp]
        dec     edx
        mov     [IceCream_Stack + edx], al
        ret
.dir_endif:
        dec     dword [if_sp]
        ret
.dir_rept:
        call    eval_expression
        mov     ebx, eax
        mov     eax, [rept_sp]
        cmp     eax, 32
        jge     .rept_full
        mov     ecx, [Vanilla_Pos]
        mov     edx, [Xylitol_Line]
        mov     [Jawbreaker_Stack_Pos + eax*4], ecx
        mov     [Jawbreaker_Stack_Line + eax*4], edx
        mov     [Jawbreaker_Stack_Cnt + eax*4], ebx
        inc     dword [rept_sp]
.rept_full:
        ret
.dir_endr:
        mov     eax, [rept_sp]
        test    eax, eax
        jz      .endr_err
        dec     eax
        mov     [rept_sp], eax
        mov     ebx, [Jawbreaker_Stack_Cnt + eax*4]
        dec     ebx
        mov     [Jawbreaker_Stack_Cnt + eax*4], ebx
        test    ebx, ebx
        jz      .endr_done
        mov     ecx, [Jawbreaker_Stack_Pos + eax*4]
        mov     [Vanilla_Pos], ecx
        mov     edx, [Jawbreaker_Stack_Line + eax*4]
        mov     [Xylitol_Line], edx
        inc     dword [rept_sp]
.endr_done:
.endr_err:
        ret

.dir_ds:
        call    eval_expression
        mov     ecx, eax
        cmp     dword [current_pass], 2
        jne     .ds_skip
.ds_emit:
        test    ecx, ecx
        jz      .ds_skip
        xor     al, al
        call    emit_byte_al
        dec     ecx
        inc     dword [Snickers_PC]
        jmp     .ds_emit
.ds_skip:
        cmp     dword [current_pass], 1
        jne     .ds_done2
        add     [Snickers_PC], ecx
.ds_done2:
        ret

.dir_align:
        call    eval_expression
        test    eax, eax
        jz      .al_done
        mov     ecx, eax
        mov     eax, [Snickers_PC]
        xor     edx, edx
        div     ecx
        test    edx, edx
        jz      .al_done
        sub     ecx, edx
        cmp     dword [current_pass], 2
        jne     .al_skip
.al_emit:
        test    ecx, ecx
        jz      .al_done
        xor     al, al
        call    emit_byte_al
        dec     ecx
        inc     dword [Snickers_PC]
        jmp     .al_emit
.al_skip:
        add     [Snickers_PC], ecx
.al_done:
        ret

handle_instruction:
        push    edi
        lea     edi, [KitKat_Buf]
        xor     ecx, ecx
.hi_copy:
        mov     al, [esi+ecx]
        call    is_alpha
        jnc     .hi_copy_done
        cmp     al, 'a'
        jb      .hi_cs
        cmp     al, 'z'
        ja      .hi_cs
        sub     al, 32
.hi_cs:
        mov     [edi+ecx], al
        inc     ecx
        cmp     ecx, 3
        jb      .hi_copy
.hi_copy_done:
        mov     byte [edi+ecx], 0
        add     esi, ecx
        pop     edi
        cmp     ecx, 3
        jne     .hi_error
        call    find_opcode
        test    eax, eax
        jz      .hi_error
        mov     ebx, eax
        call    skip_ws
        call    parse_addressing_mode
        mov     cl, [ebx+4+eax]
        cmp     cl, 0xFF
        je      .hi_addr_error
        movzx   edx, byte [instr_sizes+eax]
        cmp     dword [current_pass], 1
        jne     .hi_emit
        add     [Snickers_PC], edx
        ret
.hi_emit:
        mov     al, cl
        call    emit_byte_al
        inc     dword [Snickers_PC]
        cmp     edx, 1
        je      .hi_done
        mov     eax, [expr_value]
        cmp     edx, 2
        je      .hi_one_byte
        push    eax
        call    emit_byte_al
        inc     dword [Snickers_PC]
        pop     eax
        shr     eax, 8
        call    emit_byte_al
        inc     dword [Snickers_PC]
        jmp     .hi_done
.hi_one_byte:
        call    emit_byte_al
        inc     dword [Snickers_PC]
.hi_done:
        ret
.hi_error:
.hi_addr_error:
        add     dword [Snickers_PC], 1
        ret

find_opcode:
        push    ecx
        push    edx
        lea     edx, [opcode_table]
        mov     ecx, NUM_OPCODES
.fo_loop:
        mov     al, [KitKat_Buf]
        cmp     al, [edx]
        jne     .fo_next
        mov     al, [KitKat_Buf+1]
        cmp     al, [edx+1]
        jne     .fo_next
        mov     al, [KitKat_Buf+2]
        cmp     al, [edx+2]
        jne     .fo_next
        mov     eax, edx
        pop     edx
        pop     ecx
        ret
.fo_next:
        add     edx, 20
        dec     ecx
        jnz     .fo_loop
        xor     eax, eax
        pop     edx
        pop     ecx
        ret

parse_addressing_mode:
        push    ebx
        push    ecx
        cmp     byte [esi], 0
        je      .pam_implied
        cmp     byte [esi], ';'
        je      .pam_implied
        cmp     word [esi], '//'
        je      .pam_implied
        cmp     byte [KitKat_Buf], 'B'
        jne     .pam_not_branch
        lea     eax, [KitKat_Buf]
        cmp     word [eax+1], 'CC'
        je      .pam_relative
        cmp     word [eax+1], 'CS'
        je      .pam_relative
        cmp     word [eax+1], 'EQ'
        je      .pam_relative
        cmp     word [eax+1], 'MI'
        je      .pam_relative
        cmp     word [eax+1], 'NE'
        je      .pam_relative
        cmp     word [eax+1], 'PL'
        je      .pam_relative
        cmp     word [eax+1], 'VC'
        je      .pam_relative
        cmp     word [eax+1], 'VS'
        je      .pam_relative
.pam_not_branch:
        cmp     byte [esi], '#'
        je      .pam_immediate
        cmp     byte [esi], '('
        je      .pam_indirect
        mov     al, [esi]
        or      al, 0x20
        cmp     al, 'a'
        jne     .pam_not_acc
        mov     al, [esi+1]
        cmp     al, 0
        je      .pam_accumulator
        cmp     al, ' '
        je      .pam_accumulator
        cmp     al, 9
        je      .pam_accumulator
        cmp     al, ';'
        je      .pam_accumulator
.pam_not_acc:
        call    eval_expression
        mov     [expr_value], eax
        call    skip_ws
        cmp     byte [esi], ','
        jne     .pam_no_index
        inc     esi
        call    skip_ws
        mov     al, [esi]
        or      al, 0x20
        cmp     al, 'x'
        je      .pam_indexed_x
        cmp     al, 'y'
        je      .pam_indexed_y
        jmp     .pam_no_index
.pam_indexed_x:
        inc     esi
        mov     eax, [expr_value]
        cmp     eax, 0xFF
        ja      .pam_abs_x
        mov     eax, AM_ZEROPAGE_X
        jmp     .pam_done
.pam_abs_x:
        mov     eax, AM_ABSOLUTE_X
        jmp     .pam_done
.pam_indexed_y:
        inc     esi
        mov     eax, [expr_value]
        cmp     eax, 0xFF
        ja      .pam_abs_y
        mov     eax, AM_ZEROPAGE_Y
        jmp     .pam_done
.pam_abs_y:
        mov     eax, AM_ABSOLUTE_Y
        jmp     .pam_done
.pam_no_index:
        mov     eax, [expr_value]
        cmp     eax, 0xFF
        ja      .pam_absolute
        cmp     byte [KitKat_Buf], 'J'
        je      .pam_absolute
        mov     eax, AM_ZEROPAGE
        jmp     .pam_done
.pam_absolute:
        mov     eax, AM_ABSOLUTE
        jmp     .pam_done
.pam_implied:
        mov     eax, AM_IMPLIED
        jmp     .pam_done
.pam_accumulator:
        mov     eax, AM_ACCUMULATOR
        jmp     .pam_done
.pam_immediate:
        inc     esi
        call    eval_expression
        mov     [expr_value], eax
        mov     eax, AM_IMMEDIATE
        jmp     .pam_done
.pam_relative:
        call    eval_expression
        cmp     dword [current_pass], 2
        jne     .pam_rel_pass1
        mov     ecx, [Snickers_PC]
        add     ecx, 2
        sub     eax, ecx
        cmp     eax, -128
        jl      .pam_rel_range_err
        cmp     eax, 127
        jg      .pam_rel_range_err
        and     eax, 0xFF
        mov     [expr_value], eax
        jmp     .pam_rel_ok
.pam_rel_range_err:
        xor     eax, eax
        mov     [expr_value], eax
.pam_rel_ok:
        mov     eax, AM_RELATIVE
        jmp     .pam_done
.pam_rel_pass1:
        mov     dword [expr_value], 0
        mov     eax, AM_RELATIVE
        jmp     .pam_done
.pam_indirect:
        inc     esi
        call    skip_ws
        call    eval_expression
        mov     [expr_value], eax
        call    skip_ws
        cmp     byte [esi], ','
        je      .pam_ind_x_check
        cmp     byte [esi], ')'
        jne     .pam_ind_err
        inc     esi
        call    skip_ws
        cmp     byte [esi], ','
        jne     .pam_ind_plain
        inc     esi
        call    skip_ws
        mov     al, [esi]
        or      al, 0x20
        cmp     al, 'y'
        jne     .pam_ind_err
        inc     esi
        mov     eax, AM_INDIRECT_Y
        jmp     .pam_done
.pam_ind_plain:
        mov     eax, AM_INDIRECT
        jmp     .pam_done
.pam_ind_x_check:
        inc     esi
        call    skip_ws
        mov     al, [esi]
        or      al, 0x20
        cmp     al, 'x'
        jne     .pam_ind_err
        inc     esi
        call    skip_ws
        cmp     byte [esi], ')'
        jne     .pam_ind_err
        inc     esi
        mov     eax, AM_INDIRECT_X
        jmp     .pam_done
.pam_ind_err:
        mov     eax, AM_IMPLIED
.pam_done:
        pop     ecx
        pop     ebx
        ret

eval_expression:
        call    eval_expr_xor
        mov     ebx, eax
.ee_loop:
        call    skip_ws
        cmp     byte [esi], '|'
        jne     .ee_done
        inc     esi
        push    ebx
        call    eval_expr_xor
        pop     ebx
        or      ebx, eax
        jmp     .ee_loop
.ee_done:
        mov     eax, ebx
        ret

eval_expr_xor:
        call    eval_expr_and
        mov     ebx, eax
.ex_loop:
        call    skip_ws
        cmp     byte [esi], '^'
        jne     .ex_done
        inc     esi
        push    ebx
        call    eval_expr_and
        pop     ebx
        xor     ebx, eax
        jmp     .ex_loop
.ex_done:
        mov     eax, ebx
        ret

eval_expr_and:
        call    eval_term
        mov     ebx, eax
.ea_loop:
        call    skip_ws
        cmp     byte [esi], '&'
        jne     .ea_done
        inc     esi
        push    ebx
        call    eval_term
        pop     ebx
        and     ebx, eax
        jmp     .ea_loop
.ea_done:
        mov     eax, ebx
        ret

eval_term:
        call    eval_factor
        mov     ebx, eax
.et_loop:
        call    skip_ws
        cmp     byte [esi], '+'
        je      .et_add
        cmp     byte [esi], '-'
        je      .et_sub
        cmp     byte [esi], '*'
        je      .et_mul
        cmp     byte [esi], '/'
        je      .et_div
        cmp     byte [esi], '%'
        je      .et_mod
        cmp     word [esi], '<<'
        je      .et_shl
        cmp     word [esi], '>>'
        je      .et_shr
        mov     eax, ebx
        ret
.et_add:
        inc     esi
        push    ebx
        call    eval_factor
        pop     ebx
        add     ebx, eax
        jmp     .et_loop
.et_sub:
        inc     esi
        push    ebx
        call    eval_factor
        pop     ebx
        sub     ebx, eax
        jmp     .et_loop
.et_mul:
        inc     esi
        push    ebx
        call    eval_factor
        pop     ebx
        imul    eax, ebx
        mov     ebx, eax
        jmp     .et_loop
.et_div:
        inc     esi
        push    ebx
        call    eval_factor
        pop     ebx
        test    eax, eax
        jz      .et_div0
        xchg    eax, ebx
        xor     edx, edx
        div     ebx
        mov     ebx, eax
        jmp     .et_loop
.et_div0:
        mov     ebx, 0
        jmp     .et_loop
.et_mod:
        inc     esi
        push    ebx
        call    eval_factor
        pop     ebx
        test    eax, eax
        jz      .et_div0
        xchg    eax, ebx
        xor     edx, edx
        div     ebx
        mov     ebx, edx
        jmp     .et_loop
.et_shl:
        add     esi, 2
        push    ebx
        call    eval_factor
        pop     ebx
        mov     ecx, eax
        shl     ebx, cl
        jmp     .et_loop
.et_shr:
        add     esi, 2
        push    ebx
        call    eval_factor
        pop     ebx
        mov     ecx, eax
        shr     ebx, cl
        jmp     .et_loop

eval_factor:
        call    skip_ws
        cmp     byte [esi], '<'
        je      .ef_lo
        cmp     byte [esi], '>'
        je      .ef_hi
        cmp     byte [esi], '~'
        je      .ef_not
        cmp     byte [esi], '-'
        je      .ef_neg
        cmp     byte [esi], '$'
        je      .ef_hex
        cmp     byte [esi], '%'
        je      .ef_bin
        cmp     byte [esi], '0'
        jb      .ef_not_num
        cmp     byte [esi], '9'
        jbe     .ef_dec
.ef_not_num:
        cmp     byte [esi], 0x27
        je      .ef_char
        cmp     byte [esi], '('
        je      .ef_paren
        cmp     byte [esi], '*'
        je      .ef_pc
        mov     al, [esi]
        call    is_ident_start
        jnc     .ef_zero
        jmp     .ef_symbol
.ef_zero:
        xor     eax, eax
        ret
.ef_lo:
        inc     esi
        call    eval_factor
        and     eax, 0xFF
        ret
.ef_hi:
        inc     esi
        call    eval_factor
        shr     eax, 8
        and     eax, 0xFF
        ret
.ef_not:
        inc     esi
        call    eval_factor
        not     eax
        ret
.ef_neg:
        inc     esi
        call    eval_factor
        neg     eax
        ret
.ef_hex:
        inc     esi
        xor     eax, eax
.ef_hex_loop:
        mov     cl, [esi]
        cmp     cl, '0'
        jb      .ef_hex_done
        cmp     cl, '9'
        jbe     .ef_hex_digit
        or      cl, 0x20
        cmp     cl, 'a'
        jb      .ef_hex_done
        cmp     cl, 'f'
        ja      .ef_hex_done
        sub     cl, 'a' - 10
        jmp     .ef_hex_add
.ef_hex_digit:
        sub     cl, '0'
.ef_hex_add:
        shl     eax, 4
        movzx   ecx, cl
        or      eax, ecx
        inc     esi
        jmp     .ef_hex_loop
.ef_hex_done:
        ret
.ef_bin:
        inc     esi
        xor     eax, eax
.ef_bin_loop:
        cmp     byte [esi], '0'
        je      .ef_bin_0
        cmp     byte [esi], '1'
        je      .ef_bin_1
        ret
.ef_bin_0:
        shl     eax, 1
        inc     esi
        jmp     .ef_bin_loop
.ef_bin_1:
        shl     eax, 1
        or      eax, 1
        inc     esi
        jmp     .ef_bin_loop
.ef_dec:
        xor     eax, eax
.ef_dec_loop:
        mov     cl, [esi]
        cmp     cl, '0'
        jb      .ef_dec_done
        cmp     cl, '9'
        ja      .ef_dec_done
        sub     cl, '0'
        imul    eax, 10
        movzx   ecx, cl
        add     eax, ecx
        inc     esi
        jmp     .ef_dec_loop
.ef_dec_done:
        ret
.ef_char:
        inc     esi
        movzx   eax, byte [esi]
        inc     esi
        cmp     byte [esi], 0x27
        jne     .ef_char_done
        inc     esi
.ef_char_done:
        ret
.ef_paren:
        inc     esi
        call    eval_expression
        cmp     byte [esi], ')'
        jne     .ef_paren_done
        inc     esi
.ef_paren_done:
        ret
.ef_pc:
        inc     esi
        mov     eax, [Snickers_PC]
        ret
.ef_symbol:
        push    edi
        lea     edi, [KitKat_Buf]
        xor     ecx, ecx
.ef_sym_copy:
        mov     al, [esi]
        call    is_ident_char
        jnc     .ef_sym_done2
        cmp     al, 'a'
        jb      .ef_sym_store
        cmp     al, 'z'
        ja      .ef_sym_store
        sub     al, 32
.ef_sym_store:
        cmp     ecx, SYMBOL_NAME_LEN-1
        jge     .ef_sym_done2
        mov     [edi+ecx], al
        inc     ecx
        inc     esi
        jmp     .ef_sym_copy
.ef_sym_done2:
        mov     byte [edi+ecx], 0
        pop     edi
        lea     esi, [KitKat_Buf]
        call    find_symbol
        ret

hash_string:
        push    ecx
        push    edx
        xor     edx, edx
        mov     ebx, 5381
.hash_loop:
        movzx   eax, byte [esi]
        test    al, al
        jz      .hash_done
        cmp     al, 'A'
        jb      .no_up
        cmp     al, 'Z'
        ja      .no_up
        add     al, 32
.no_up:
        lea     ebx, [ebx*4 + ebx]
        add     ebx, eax
        inc     esi
        jmp     .hash_loop
.hash_done:
        and     ebx, HASH_MASK
        mov     eax, ebx
        pop     edx
        pop     ecx
        ret

find_symbol:
        push    esi
        call    hash_string
        pop     esi
        mov     ebx, [Donut_Pool]
        mov     ecx, [ebx + eax*4]
        test    ecx, ecx
        jz      .not_found
.loop:
        dec     ecx
        push    eax
        mov     eax, ecx
        mov     ebx, SYM_ENTRY_SIZE
        mul     ebx
        add     eax, [Caramel_Pool]
        mov     edi, eax
        pop     eax
        push    esi
        push    edi
        call    str_equal
        pop     edi
        pop     esi
        test    eax, eax
        jnz     .found
               mov     ebx, [Caramel_Pool]
        mov     eax, ecx
        imul    eax, SYM_ENTRY_SIZE
        mov     ecx, [ebx + eax + 56]
        test    ecx, ecx
        jnz     .loop
.not_found:
        xor     eax, eax
        ret
.found:
        mov     eax, [edi + 48]
        ret

add_symbol:
        push    esi
        call    hash_string
        pop     esi
        mov     ebx, [Donut_Pool]
        mov     edi, [ebx + eax*4]
        mov     ebx, [York_Syms]
        cmp     ebx, MAX_SYMBOLS
        jge     .full
        push    eax
        mov     eax, ebx
        mov     ecx, SYM_ENTRY_SIZE
        mul     ecx
        add     eax, [Caramel_Pool]
        mov     ebp, eax
        pop    eax
        push    esi
        mov     edi, ebp
        mov     ecx, 48
.copy_name:
        mov     al, [esi]
        test    al, al
        jz      .pad_name
        cmp     al, 'a'
        jb      .store
        cmp     al, 'z'
        ja      .store
        sub     al, 32
.store:
        stosb
        inc     esi
        dec     ecx
        jnz     .copy_name
.pad_name:
        xor     al, al
        rep     stosb
        pop     esi
        mov     [ebp + 48], edx
        mov     [ebp + 52], ecx
        mov     ebx, [Donut_Pool]
        mov     eax, [ebx + eax*4]
        mov     [ebp + 56], eax
        inc     dword [York_Syms]
        
        ; FIXED: Avoid memory-to-memory move
        mov     ecx, [York_Syms]
        mov     [ebx + eax*4], ecx
.full:
        ret

str_equal:
        push    esi
        push    edi
.se_loop:
        mov     al, [esi]
        mov     cl, [edi]
        cmp     al, 'a'
        jb      .se_n1
        cmp     al, 'z'
        ja      .se_n1
        sub     al, 32
.se_n1:
        cmp     cl, 'a'
        jb      .se_n2
        cmp     cl, 'z'
        ja      .se_n2
        sub     cl, 32
.se_n2:
        cmp     al, cl
        jne     .se_ne
        test    al, al
        jz      .se_eq
        inc     esi
        inc     edi
        jmp     .se_loop
.se_ne:
        xor     eax, eax
        pop     edi
        pop     esi
        ret
.se_eq:
        mov     eax, 1
        pop     edi
        pop     esi
        ret

emit_byte_al:
        push    edx
        mov     edx, [Bonbon_Pool]
        add     edx, [Uno_Bar_Pos]
        mov     [edx], al
        inc     dword [Uno_Bar_Pos]
        pop     edx
        ret

write_nes_file:
        push    ebx
        push    ecx
        push    edx
        push    0
        push    FILE_ATTRIBUTE_NORMAL
        push    CREATE_ALWAYS
        push    0
        push    0
        push    GENERIC_WRITE
        push    output_filename
        call    [CreateFileA]
        cmp     eax, INVALID_HANDLE_VALUE
        je      .wf_fail
        mov     ebx, eax
        sub     esp, 16
        mov     edi, esp
        mov     byte [edi], 'N'
        mov     byte [edi+1], 'E'
        mov     byte [edi+2], 'S'
        mov     byte [edi+3], 0x1A
        mov     eax, [ines_prg]
        mov     [edi+4], al
        mov     eax, [ines_chr]
        mov     [edi+5], al
        mov     eax, [ines_mirror]
        and     eax, 1
        mov     ecx, [ines_mapper]
        shl     ecx, 4
        and     ecx, 0xF0
        or      eax, ecx
        mov     [edi+6], al
        mov     eax, [ines_mapper]
        and     eax, 0xF0
        mov     [edi+7], al
        xor     eax, eax
        mov     [edi+8], eax
        mov     [edi+12], eax
        push    0
        push    RockCandy_Bytes
        push    16
        push    edi
        push    ebx
        call    [WriteFile]
        add     esp, 16
        mov     ecx, [ines_prg]
        shl     ecx, 14
        mov     edx, [Uno_Bar_Pos]
        cmp     edx, ecx
        jbe     .wf_write_prg
        mov     edx, ecx
.wf_write_prg:
        push    ecx
        push    0
        push    RockCandy_Bytes
        push    edx
        push    dword [Bonbon_Pool]
        push    ebx
        call    [WriteFile]
        pop     ecx
        mov     edx, [Uno_Bar_Pos]
        cmp     edx, ecx
        jge     .wf_close
        sub     ecx, edx
        mov     edi, [Bonbon_Pool]
        add     edi, [Uno_Bar_Pos]
        push    ecx
        mov     al, 0xFF
        rep     stosb
        pop     ecx
        push    0
        push    RockCandy_Bytes
        push    ecx
        mov     eax, [Bonbon_Pool]
        add     eax, [Uno_Bar_Pos]
        push    eax
        push    ebx
        call    [WriteFile]
.wf_close:
        push    ebx
        call    [CloseHandle]
        mov     eax, 1
        pop     edx
        pop     ecx
        pop     ebx
        ret
.wf_fail:
        xor     eax, eax
        pop     edx
        pop     ecx
        pop     ebx
        ret

print_string:
        push    ebp
        mov     ebp, esp
        push    esi
        push    ecx
        mov     esi, [ebp+8]
        xor     ecx, ecx
.ps_len:
        cmp     byte [esi+ecx], 0
        je      .ps_write
        inc     ecx
        jmp     .ps_len
.ps_write:
        push    0
        push    RockCandy_Bytes
        push    ecx
        push    esi
        push    dword [Oreo_Handle]
        call    [WriteFile]
        pop     ecx
        pop     esi
        pop     ebp
        ret     4

print_string_err:
        push    ebp
        mov     ebp, esp
        push    esi
        push    ecx
        mov     esi, [ebp+8]
        xor     ecx, ecx
.pse_len:
        cmp     byte [esi+ecx], 0
        je      .pse_write
        inc     ecx
        jmp     .pse_len
.pse_write:
        push    0
        push    RockCandy_Bytes
        push    ecx
        push    esi
        push    dword [Peppermint_Handle]
        call    [WriteFile]
        pop     ecx
        pop     esi
        pop     ebp
        ret     4

print_number:
        push    ebp
        mov     ebp, esp
        push    eax
        push    ecx
        push    edx
        mov     eax, [ebp+8]
        lea     ecx, [num_buf+15]
        mov     byte [ecx], 0
        dec     ecx
        test    eax, eax
        jnz     .pn_loop
        mov     byte [ecx], '0'
        dec     ecx
        jmp     .pn_print
.pn_loop:
        test    eax, eax
        jz      .pn_print
        xor     edx, edx
        push    ebx
        mov     ebx, 10
        div     ebx
        pop     ebx
        add     dl, '0'
        mov     [ecx], dl
        dec     ecx
        jmp     .pn_loop
.pn_print:
        inc     ecx
        push    ecx
        call    print_string
        pop     edx
        pop     ecx
        pop     eax
        pop     ebp
        ret     4

skip_arg:
        cmp     byte [esi], '"'
        je      .quoted
.unquoted:
        lodsb
        cmp     al, 0
        je      .done
        cmp     al, ' '
        je      .done
        cmp     al, 9
        je      .done
        jmp     .unquoted
.quoted:
        inc     esi
.q_loop:
        lodsb
        cmp     al, 0
        je      .done
        cmp     al, '"'
        je      .done
        jmp     .q_loop
.done:
        ret

skip_spaces:
        cmp     byte [esi], ' '
        je      .skip
        cmp     byte [esi], 9
        je      .skip
        ret
.skip:
        inc     esi
        jmp     skip_spaces

copy_arg:
        cmp     byte [esi], '"'
        je      .quoted
.unquoted:
        lodsb
        cmp     al, 0
        je      .done
        cmp     al, ' '
        je      .done
        cmp     al, 9
        je      .done
        stosb
        jmp     .unquoted
.quoted:
        inc     esi
.q_loop:
        lodsb
        cmp     al, 0
        je      .done
        cmp     al, '"'
        je      .done
        stosb
        jmp     .q_loop
.done:
        mov     byte [edi], 0
        ret

make_output_name:
        push    edi
        xor     ecx, ecx
.copy:
        lodsb
        stosb
        cmp     al, '.'
        jne     .not_dot
        lea     ecx, [edi-1]
.not_dot:
        cmp     al, 0
        jne     .copy
        test    ecx, ecx
        jz      .append
        mov     edi, ecx
.append:
        mov     byte [edi], '.'
        mov     byte [edi+1], 'n'
        mov     byte [edi+2], 'e'
        mov     byte [edi+3], 's'
        mov     byte [edi+4], 0
        pop     edi
        ret

section '.idata' import data readable writeable
        dd 0,0,0,RVA kernel32_name,RVA kernel32_table
        dd 0,0,0,0,0

kernel32_name db 'KERNEL32.DLL',0

kernel32_table:
        GetStdHandle    dd RVA _GetStdHandle
        GetCommandLineA dd RVA _GetCommandLineA
        CreateFileA     dd RVA _CreateFileA
        ReadFile        dd RVA _ReadFile
        WriteFile       dd RVA _WriteFile
        CloseHandle     dd RVA _CloseHandle
        GetFileSize     dd RVA _GetFileSize
        VirtualAlloc    dd RVA _VirtualAlloc
        ExitProcess     dd RVA _ExitProcess
        GetFullPathNameA dd RVA _GetFullPathNameA
        dd 0

        _GetStdHandle    dw 0
                         db 'GetStdHandle',0
        _GetCommandLineA dw 0
                         db 'GetCommandLineA',0
        _CreateFileA     dw 0
                         db 'CreateFileA',0
        _ReadFile        dw 0
                         db 'ReadFile',0
        _WriteFile       dw 0
                         db 'WriteFile',0
        _CloseHandle     dw 0
                         db 'CloseHandle',0
        _GetFileSize     dw 0
                         db 'GetFileSize',0
        _VirtualAlloc    dw 0
                         db 'VirtualAlloc',0
        _ExitProcess     dw 0
                         db 'ExitProcess',0
        _GetFullPathNameA dw 0
                         db 'GetFullPathNameA',0