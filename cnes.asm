; ============================================================================
; CNES - Compilador NES Super Ligero
; Un ensamblador de 6502 escrito en x86 FASM para generar ROMs .nes
; Uso: cnes archivo.asm  ->  genera archivo.nes
;
; Caracteristicas:
;   - Ensamblador de dos pasadas (resuelve referencias adelantadas)
;   - Todas las 56 instrucciones oficiales del 6502
;   - Todos los modos de direccionamiento
;   - Directivas iNES (.inesprg, .ineschr, .inesmir, .inesmap)
;   - .org, .db/.byte, .dw/.word, .include, .incbin
;   - .define, equ, =  para constantes
;   - .bank, .rsset, .rs, .ds, .ascii, .align
;   - Expresiones con +, -, *, /, <, > (byte bajo/alto)
;   - Etiquetas con :
;   - Comentarios con ; o //
;   - Hexadecimal $xx, binario %xxxxxxxx, decimal
;   - Case insensitive en mnemonicos
;   - Mensajes de error con numero de linea
; ============================================================================

format PE console
entry _start

; ============================================================================
; Constantes de Windows API
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
; Constantes del ensamblador
; ============================================================================
MAX_SOURCE     = 1048576    ; 1 MB maximo de fuente
MAX_OUTPUT     = 524288     ; 512 KB maximo de salida
MAX_SYMBOLS    = 8192       ; Maximo de simbolos
MAX_LINE       = 1024       ; Longitud maxima de linea
MAX_INCLUDES   = 32         ; Profundidad maxima de includes
MAX_PATH_LEN   = 260
SYMBOL_NAME_LEN = 64        ; Longitud maxima nombre de simbolo
SYMBOL_ENTRY_SIZE = 72      ; 64 nombre + 4 valor + 4 flags

; Flags de simbolo
SYM_DEFINED    = 1
SYM_LABEL      = 2
SYM_CONSTANT   = 4

; Modos de direccionamiento
AM_IMPLIED     = 0
AM_ACCUMULATOR = 1
AM_IMMEDIATE   = 2
AM_ZEROPAGE    = 3
AM_ZEROPAGE_X  = 4
AM_ZEROPAGE_Y  = 5
AM_ABSOLUTE    = 6
AM_ABSOLUTE_X  = 7
AM_ABSOLUTE_Y  = 8
AM_INDIRECT    = 9
AM_INDIRECT_X  = 10
AM_INDIRECT_Y  = 11
AM_RELATIVE    = 12

; ============================================================================
; Seccion de datos
; ============================================================================
section '.data' data readable writeable

; --- Mensajes ---
msg_banner      db 'CNES v1.0 - Compilador NES Super Ligero',13,10
                db '6502 Assembler -> iNES ROM',13,10,0
msg_usage       db 'Uso: cnes archivo.asm',13,10,0
msg_reading     db 'Leyendo: ',0
msg_newline     db 13,10,0
msg_pass1       db 'Pasada 1: Analizando simbolos...',13,10,0
msg_pass2       db 'Pasada 2: Generando codigo...',13,10,0
msg_writing     db 'Escribiendo: ',0
msg_done        db 'Compilacion exitosa!',13,10,0
msg_symbols     db ' simbolos definidos',13,10,0
msg_bytes       db ' bytes de PRG-ROM generados',13,10,0
msg_err_open    db 'Error: No se puede abrir el archivo: ',0
msg_err_read    db 'Error: No se puede leer el archivo',13,10,0
msg_err_write   db 'Error: No se puede escribir el archivo de salida',13,10,0
msg_err_mem     db 'Error: No hay memoria suficiente',13,10,0
msg_err_syntax  db 'Error de sintaxis en linea ',0
msg_err_undef   db 'Error: Simbolo no definido: ',0
msg_err_redef   db 'Error: Simbolo redefinido: ',0
msg_err_range   db 'Error: Valor fuera de rango en linea ',0
msg_err_branch  db 'Error: Salto fuera de rango en linea ',0
msg_err_opcode  db 'Error: Instruccion invalida en linea ',0
msg_err_addr    db 'Error: Modo de direccionamiento invalido en linea ',0
msg_err_include db 'Error: No se puede incluir archivo: ',0
msg_at_line     db ' en linea ',0
msg_colon       db ': ',0

; --- Variables del ensamblador ---
input_filename  db MAX_PATH_LEN dup(0)
output_filename db MAX_PATH_LEN dup(0)
current_file    db MAX_PATH_LEN dup(0)

; Punteros a buffers (asignados con VirtualAlloc)
source_buf      dd 0        ; Buffer del codigo fuente
output_buf      dd 0        ; Buffer de salida (ROM)
symbol_table    dd 0        ; Tabla de simbolos
line_buf        db MAX_LINE dup(0)  ; Buffer de linea actual
token_buf       db MAX_LINE dup(0)  ; Buffer de token actual
operand_buf     db MAX_LINE dup(0)  ; Buffer de operando

; Estado del ensamblador
current_pass    dd 0        ; Pasada actual (1 o 2)
current_pc      dd 0        ; Program Counter actual (direccion 6502)
current_org     dd 0x8000   ; Origen actual
output_pos      dd 0        ; Posicion en el buffer de salida
source_pos      dd 0        ; Posicion en el buffer fuente
source_len      dd 0        ; Longitud del fuente
line_number     dd 0        ; Numero de linea actual
num_symbols     dd 0        ; Cantidad de simbolos
error_count     dd 0        ; Cantidad de errores
has_errors      dd 0        ; Flag de errores

; Configuracion iNES
ines_prg        dd 1        ; Bancos de PRG-ROM (16KB cada uno)
ines_chr        dd 0        ; Bancos de CHR-ROM (8KB cada uno)
ines_mirror     dd 0        ; Mirroring (0=H, 1=V)
ines_mapper     dd 0        ; Numero de mapper
ines_battery    dd 0        ; Battery-backed RAM

; Variables de banco
current_bank    dd 0        ; Banco actual
bank_offsets    dd 16 dup(0) ; Offsets de cada banco en la salida

; Variables para .rsset / .rs
rs_address      dd 0        ; Direccion actual de RS

; Handles de Windows
stdout_handle   dd 0
stderr_handle   dd 0
file_handle     dd 0
bytes_rw        dd 0        ; Bytes leidos/escritos
file_size       dd 0

; Expresion temporal
expr_value      dd 0
expr_hibyte     dd 0        ; Flag para operador >
expr_lobyte     dd 0        ; Flag para operador <

; ============================================================================
; Tabla de opcodes del 6502
; Formato: nombre (3 bytes), opcode por modo de direccionamiento
; Indices: IMP,ACC,IMM,ZP,ZPX,ZPY,ABS,ABSX,ABSY,IND,INDX,INDY,REL
; 0xFF = modo no soportado
; ============================================================================
align 4
opcode_table:
; Cada entrada: 3 bytes nombre + 1 pad + 13 bytes opcodes + 3 pad = 20 bytes
;               NAME  pad IMP  ACC  IMM  ZP   ZPX  ZPY  ABS  ABSX ABSY IND  INDX INDY REL  pad pad pad
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

; Tamano de la instruccion segun modo de direccionamiento
; IMP ACC IMM ZP  ZPX ZPY ABS ABSX ABSY IND INDX INDY REL
instr_sizes db 1,  1,  2,  2,  2,  2,  3,  3,   3,   3,  2,   2,   2

; Buffer para conversion de numeros a texto
num_buf     db 16 dup(0)

; ============================================================================
; Seccion de codigo
; ============================================================================
section '.text' code readable executable

; ============================================================================
; Punto de entrada
; ============================================================================
_start:
        ; Obtener handles de consola
        push    STD_OUTPUT_HANDLE
        call    [GetStdHandle]
        mov     [stdout_handle], eax

        push    STD_ERROR_HANDLE
        call    [GetStdHandle]
        mov     [stderr_handle], eax

        ; Mostrar banner
        push    msg_banner
        call    print_string

        ; Obtener linea de comandos
        call    [GetCommandLineA]
        mov     esi, eax

        ; Saltar el nombre del programa
        call    skip_arg
        ; Saltar espacios
        call    skip_spaces
        ; Verificar que hay argumento
        cmp     byte [esi], 0
        je      .show_usage

        ; Copiar nombre del archivo de entrada
        lea     edi, [input_filename]
        call    copy_arg

        ; Generar nombre de salida (.nes)
        lea     esi, [input_filename]
        lea     edi, [output_filename]
        call    make_output_name

        ; Asignar memoria para buffers
        call    alloc_buffers
        test    eax, eax
        jz      .mem_error

        ; Leer el archivo fuente
        push    msg_reading
        call    print_string
        push    input_filename
        call    print_string
        push    msg_newline
        call    print_string

        lea     eax, [input_filename]
        push    eax
        call    read_source_file
        test    eax, eax
        jz      .open_error

        ; ===== PASADA 1 =====
        push    msg_pass1
        call    print_string

        mov     dword [current_pass], 1
        call    assemble_pass

        ; Verificar errores en pasada 1
        cmp     dword [has_errors], 0
        jne     .had_errors

        ; Mostrar cantidad de simbolos
        push    dword [num_symbols]
        call    print_number
        push    msg_symbols
        call    print_string

        ; ===== PASADA 2 =====
        push    msg_pass2
        call    print_string

        mov     dword [current_pass], 2
        ; Resetear estado para pasada 2
        mov     dword [output_pos], 0
        call    assemble_pass

        ; Verificar errores en pasada 2
        cmp     dword [has_errors], 0
        jne     .had_errors

        ; Mostrar bytes generados
        push    dword [output_pos]
        call    print_number
        push    msg_bytes
        call    print_string

        ; Escribir archivo de salida
        push    msg_writing
        call    print_string
        push    output_filename
        call    print_string
        push    msg_newline
        call    print_string

        call    write_nes_file
        test    eax, eax
        jz      .write_error

        ; Exito!
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
        call    print_string
        push    1
        call    [ExitProcess]

.open_error:
        push    msg_err_open
        call    print_string
        push    input_filename
        call    print_string
        push    msg_newline
        call    print_string
        push    1
        call    [ExitProcess]

.write_error:
        push    msg_err_write
        call    print_string
        push    1
        call    [ExitProcess]

.had_errors:
        push    dword [error_count]
        call    print_number
        push    msg_err_syntax
        call    print_string_err
        push    msg_newline
        call    print_string_err
        push    1
        call    [ExitProcess]

; ============================================================================
; skip_arg - Salta un argumento en la linea de comandos
; Entrada: ESI = puntero a la cadena
; Salida:  ESI = despues del argumento
; ============================================================================
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
        inc     esi             ; saltar comilla inicial
.q_loop:
        lodsb
        cmp     al, 0
        je      .done
        cmp     al, '"'
        je      .done
        jmp     .q_loop
.done:
        ret

; ============================================================================
; skip_spaces - Salta espacios y tabs
; ============================================================================
skip_spaces:
        cmp     byte [esi], ' '
        je      .skip
        cmp     byte [esi], 9
        je      .skip
        ret
.skip:
        inc     esi
        jmp     skip_spaces

; ============================================================================
; copy_arg - Copia un argumento a EDI
; ============================================================================
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

; ============================================================================
; make_output_name - Cambia la extension a .nes
; Entrada: ESI = nombre original, EDI = destino
; ============================================================================
make_output_name:
        push    edi
        xor     ecx, ecx       ; posicion del ultimo '.'
.copy:
        lodsb
        stosb
        cmp     al, '.'
        jne     .not_dot
        lea     ecx, [edi-1]   ; recordar posicion del punto
.not_dot:
        cmp     al, 0
        jne     .copy
        ; Si encontramos un punto, reemplazar la extension
        test    ecx, ecx
        jz      .append
        mov     edi, ecx
.append:
        mov     dword [edi], '.nes'  ; Nota: little endian
        mov     byte [edi], '.'
        mov     byte [edi+1], 'n'
        mov     byte [edi+2], 'e'
        mov     byte [edi+3], 's'
        mov     byte [edi+4], 0
        pop     edi
        ret

; ============================================================================
; alloc_buffers - Asignar memoria para los buffers
; Retorna: EAX = 1 si OK, 0 si error
; ============================================================================
alloc_buffers:
        ; Buffer de fuente (1 MB)
        push    PAGE_READWRITE
        push    MEM_COMMIT or MEM_RESERVE
        push    MAX_SOURCE
        push    0
        call    [VirtualAlloc]
        test    eax, eax
        jz      .fail
        mov     [source_buf], eax

        ; Buffer de salida (512 KB)
        push    PAGE_READWRITE
        push    MEM_COMMIT or MEM_RESERVE
        push    MAX_OUTPUT
        push    0
        call    [VirtualAlloc]
        test    eax, eax
        jz      .fail
        mov     [output_buf], eax

        ; Tabla de simbolos
        push    PAGE_READWRITE
        push    MEM_COMMIT or MEM_RESERVE
        push    MAX_SYMBOLS * SYMBOL_ENTRY_SIZE
        push    0
        call    [VirtualAlloc]
        test    eax, eax
        jz      .fail
        mov     [symbol_table], eax

        mov     eax, 1
        ret
.fail:
        xor     eax, eax
        ret

; ============================================================================
; read_source_file - Lee un archivo fuente a memoria
; Entrada: [esp+4] = puntero al nombre del archivo
; Retorna: EAX = 1 si OK, 0 si error
; ============================================================================
read_source_file:
        push    ebp
        mov     ebp, esp
        push    ebx

        ; Abrir archivo
        push    0                       ; hTemplateFile
        push    FILE_ATTRIBUTE_NORMAL   ; dwFlagsAndAttributes
        push    OPEN_EXISTING           ; dwCreationDisposition
        push    0                       ; lpSecurityAttributes
        push    0                       ; dwShareMode
        push    GENERIC_READ            ; dwDesiredAccess
        push    dword [ebp+8]           ; lpFileName
        call    [CreateFileA]
        cmp     eax, INVALID_HANDLE_VALUE
        je      .fail
        mov     ebx, eax                ; guardar handle

        ; Obtener tamano
        push    0
        push    ebx
        call    [GetFileSize]
        cmp     eax, MAX_SOURCE
        ja      .close_fail
        mov     [source_len], eax

        ; Leer archivo
        push    0                       ; lpOverlapped
        push    bytes_rw                ; lpNumberOfBytesRead
        push    dword [source_len]      ; nNumberOfBytesToRead
        push    dword [source_buf]      ; lpBuffer
        push    ebx                     ; hFile
        call    [ReadFile]
        test    eax, eax
        jz      .close_fail

        ; Cerrar archivo
        push    ebx
        call    [CloseHandle]

        mov     eax, 1
        pop     ebx
        pop     ebp
        ret     4

.close_fail:
        push    ebx
        call    [CloseHandle]
.fail:
        xor     eax, eax
        pop     ebx
        pop     ebp
        ret     4

; ============================================================================
; assemble_pass - Ejecuta una pasada del ensamblador
; ============================================================================
assemble_pass:
        pushad
        ; Resetear estado
        mov     eax, [current_org]
        mov     [current_pc], eax
        mov     dword [source_pos], 0
        mov     dword [line_number], 0
        mov     dword [error_count], 0
        mov     dword [has_errors], 0

        ; Si es pasada 2, resetear PC al org original
        cmp     dword [current_pass], 2
        jne     .pass1_init
        mov     dword [current_pc], 0x8000
        mov     dword [current_org], 0x8000
        jmp     .main_loop
.pass1_init:
        mov     dword [num_symbols], 0

.main_loop:
        ; Verificar fin del fuente
        mov     eax, [source_pos]
        cmp     eax, [source_len]
        jge     .pass_done

        ; Leer siguiente linea
        call    read_line
        inc     dword [line_number]

        ; Procesar linea
        lea     esi, [line_buf]
        call    process_line

        jmp     .main_loop

.pass_done:
        popad
        ret

; ============================================================================
; read_line - Lee una linea del buffer fuente a line_buf
; ============================================================================
read_line:
        push    esi
        push    edi
        push    ecx

        mov     esi, [source_buf]
        add     esi, [source_pos]
        lea     edi, [line_buf]
        xor     ecx, ecx               ; contador de caracteres

.read_char:
        mov     eax, [source_pos]
        add     eax, ecx
        cmp     eax, [source_len]
        jge     .end_of_source

        mov     al, [esi+ecx]
        cmp     al, 13                  ; CR
        je      .found_eol
        cmp     al, 10                  ; LF
        je      .found_eol

        ; Copiar caracter
        cmp     ecx, MAX_LINE-2
        jge     .found_eol
        mov     [edi+ecx], al
        inc     ecx
        jmp     .read_char

.found_eol:
        mov     byte [edi+ecx], 0       ; terminar string

        ; Avanzar source_pos pasando CR/LF
        add     ecx, [source_pos]
.skip_eol:
        cmp     ecx, [source_len]
        jge     .done
        mov     esi, [source_buf]
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
        mov     [source_pos], ecx
        pop     ecx
        pop     edi
        pop     esi
        ret

.end_of_source:
        mov     byte [edi+ecx], 0
        add     ecx, [source_pos]
        mov     [source_pos], ecx
        pop     ecx
        pop     edi
        pop     esi
        ret

; ============================================================================
; process_line - Procesa una linea de ensamblador
; Entrada: ESI = puntero a la linea (line_buf)
; ============================================================================
process_line:
        pushad

        ; Saltar espacios iniciales
        call    .skip_ws

        ; Linea vacia o comentario?
        cmp     byte [esi], 0
        je      .line_done
        cmp     byte [esi], ';'
        je      .line_done
        cmp     word [esi], '//'
        je      .line_done

        ; Verificar si hay una etiqueta (termina en ':' o es un identificador seguido de ':')
        push    esi
        call    .check_label
        pop     esi
        test    eax, eax
        jz      .no_label

        ; Procesar etiqueta
        call    .handle_label
        ; Continuar con el resto de la linea
        call    .skip_ws
        cmp     byte [esi], 0
        je      .line_done
        cmp     byte [esi], ';'
        je      .line_done

.no_label:
        ; Verificar si es una directiva (empieza con '.')
        cmp     byte [esi], '.'
        je      .is_directive

        ; Verificar si es NAME = VALUE o NAME equ VALUE
        push    esi
        call    .check_assignment
        pop     esi
        test    eax, eax
        jnz     .line_done      ; fue procesado como asignacion

        ; Debe ser una instruccion 6502
        call    .handle_instruction
        jmp     .line_done

.is_directive:
        call    .handle_directive
        jmp     .line_done

.line_done:
        popad
        ret

; --- Saltar espacios/tabs ---
.skip_ws:
        cmp     byte [esi], ' '
        je      .sw1
        cmp     byte [esi], 9
        je      .sw1
        ret
.sw1:
        inc     esi
        jmp     .skip_ws

; --- check_label: Verifica si hay etiqueta ---
; Retorna EAX=1 si hay etiqueta, 0 si no
.check_label:
        push    esi
        ; Un label empieza con letra o _ y termina en ':'
        mov     al, [esi]
        call    .is_ident_start
        jnc     .cl_no

.cl_scan:
        inc     esi
        mov     al, [esi]
        cmp     al, ':'
        je      .cl_yes
        call    .is_ident_char
        jc      .cl_scan
.cl_no:
        pop     esi
        xor     eax, eax
        ret
.cl_yes:
        pop     esi
        mov     eax, 1
        ret

; --- is_ident_start: AL es inicio de identificador? CF=1 si si ---
.is_ident_start:
        cmp     al, '_'
        je      .iis_yes
        cmp     al, '@'
        je      .iis_yes
        call    .is_alpha
        ret
.iis_yes:
        stc
        ret

; --- is_ident_char: AL es caracter de identificador? CF=1 si si ---
.is_ident_char:
        call    .is_ident_start
        jc      .iic_yes
        call    .is_digit
        ret
.iic_yes:
        stc
        ret

; --- is_alpha: CF=1 si AL es letra ---
.is_alpha:
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

; --- is_digit: CF=1 si AL es digito ---
.is_digit:
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

; --- handle_label: Procesa una etiqueta ---
.handle_label:
        ; Copiar nombre de la etiqueta a token_buf
        push    edi
        lea     edi, [token_buf]
        xor     ecx, ecx
.hl_copy:
        mov     al, [esi]
        cmp     al, ':'
        je      .hl_end
        call    .is_ident_char
        jnc     .hl_end
        cmp     ecx, SYMBOL_NAME_LEN-1
        jge     .hl_end
        ; Convertir a mayusculas
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
        ; Saltar el ':'
        cmp     byte [esi], ':'
        jne     .hl_no_colon
        inc     esi
.hl_no_colon:
        pop     edi

        ; Solo en pasada 1: agregar simbolo
        cmp     dword [current_pass], 1
        jne     .hl_skip_add

        push    dword [current_pc]
        push    SYM_DEFINED or SYM_LABEL
        lea     eax, [token_buf]
        push    eax
        call    add_symbol
.hl_skip_add:
        ret

; --- check_assignment: NAME = VALUE o NAME equ VALUE ---
; Retorna EAX=1 si se proceso, 0 si no
.check_assignment:
        push    ebx
        push    edi
        push    esi

        ; Primero leer un posible identificador
        mov     al, [esi]
        call    .is_ident_start
        jnc     .ca_no

        ; Copiar identificador a token_buf
        lea     edi, [token_buf]
        xor     ecx, ecx
.ca_ident:
        mov     al, [esi+ecx]
        call    .is_ident_char
        jnc     .ca_ident_done
        ; Mayusculas
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

        ; Saltar espacios
        call    .skip_ws

        ; Es '='?
        cmp     byte [esi], '='
        je      .ca_found

        ; Es 'equ' o 'EQU'?
        push    esi
        mov     al, [esi]
        or      al, 0x20       ; tolower
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
        ; Verificar que le sigue espacio o fin
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
        add     esi, 3         ; saltar 'equ'
        jmp     .ca_eval

.ca_found:
        inc     esi             ; saltar '='

.ca_eval:
        call    .skip_ws

        ; Evaluar la expresion
        call    eval_expression
        ; EAX = valor

        ; Solo en pasada 1: agregar simbolo
        cmp     dword [current_pass], 1
        jne     .ca_done

        push    eax             ; valor
        push    SYM_DEFINED or SYM_CONSTANT
        lea     ebx, [token_buf]
        push    ebx
        call    add_symbol

.ca_done:
        pop     esi             ; descartar ESI original
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

; --- handle_directive: Procesa directivas que empiezan con '.' ---
.handle_directive:
        inc     esi             ; saltar el '.'

        ; Leer nombre de directiva a token_buf
        push    edi
        lea     edi, [token_buf]
        xor     ecx, ecx
.hd_copy:
        mov     al, [esi+ecx]
        call    .is_ident_char
        jnc     .hd_copy_done
        ; tolower
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

        ; Saltar espacios despues de directiva
        call    .skip_ws

        ; Comparar con directivas conocidas
        lea     eax, [token_buf]

        ; .org
        cmp     dword [eax], 'org' + (0 shl 24)
        je      .dir_org

        ; .db / .byte
        cmp     word [eax], 'db'
        je      .dir_db
        cmp     dword [eax], 'byte'
        je      .dir_db

        ; .dw / .word
        cmp     word [eax], 'dw'
        je      .dir_dw
        cmp     dword [eax], 'word'
        je      .dir_dw

        ; .inesprg
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

        ; .include
        cmp     dword [eax], 'incl'
        je      .dir_include_check

        ; .incbin
        cmp     dword [eax], 'incb'
        je      .dir_incbin

        ; .define
        cmp     dword [eax], 'defi'
        je      .dir_define

        ; .bank
        cmp     dword [eax], 'bank'
        je      .dir_bank

        ; .rsset
        cmp     dword [eax], 'rsse'
        je      .dir_rsset

        ; .rs
        cmp     word [eax], 'rs'
        je      .dir_rs

        ; .ds
        cmp     word [eax], 'ds'
        je      .dir_ds

        ; .ascii
        cmp     dword [eax], 'asci'
        je      .dir_ascii

        ; .align
        cmp     dword [eax], 'alig'
        je      .dir_align

        ; Directiva desconocida - ignorar
        ret

; --- .org ---
.dir_org:
        call    eval_expression
        mov     [current_pc], eax
        mov     [current_org], eax
        ret

; --- .db / .byte ---
.dir_db:
.db_loop:
        call    .skip_ws
        cmp     byte [esi], 0
        je      .db_done
        cmp     byte [esi], ';'
        je      .db_done

        ; Verificar si es string entre comillas
        cmp     byte [esi], '"'
        je      .db_string

        ; Evaluar expresion
        call    eval_expression
        ; Emitir byte
        cmp     dword [current_pass], 2
        jne     .db_skip_emit
        call    emit_byte_al
.db_skip_emit:
        inc     dword [current_pc]

        ; Verificar si hay coma
        call    .skip_ws
        cmp     byte [esi], ','
        jne     .db_done
        inc     esi
        jmp     .db_loop
.db_done:
        ret

.db_string:
        inc     esi             ; saltar comilla inicial
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
        inc     dword [current_pc]
        inc     esi
        jmp     .dbs_loop
.dbs_end:
        cmp     byte [esi], '"'
        jne     .db_comma_check
        inc     esi
.db_comma_check:
        call    .skip_ws
        cmp     byte [esi], ','
        jne     .db_done
        inc     esi
        jmp     .db_loop

; --- .dw / .word ---
.dir_dw:
.dw_loop:
        call    .skip_ws
        cmp     byte [esi], 0
        je      .dw_done
        cmp     byte [esi], ';'
        je      .dw_done

        call    eval_expression
        cmp     dword [current_pass], 2
        jne     .dw_skip
        ; Little-endian: byte bajo primero
        call    emit_byte_al
        mov     al, ah
        call    emit_byte_al
.dw_skip:
        add     dword [current_pc], 2

        call    .skip_ws
        cmp     byte [esi], ','
        jne     .dw_done
        inc     esi
        jmp     .dw_loop
.dw_done:
        ret

; --- .inesprg ---
.dir_inesprg:
        call    eval_expression
        mov     [ines_prg], eax
        ret

; --- .ineschr ---
.dir_ineschr:
        call    eval_expression
        mov     [ines_chr], eax
        ret

; --- .inesmir ---
.dir_inesmir:
        call    eval_expression
        mov     [ines_mirror], eax
        ret

; --- .inesmap ---
.dir_inesmap:
        call    eval_expression
        mov     [ines_mapper], eax
        ret

; --- .include ---
.dir_include_check:
        ; Verificar que es "include" completo
        lea     eax, [token_buf]
        cmp     dword [eax+4], 'ude' + (0 shl 24)
        jne     .dir_unknown
        jmp     .dir_include

.dir_include:
        ; Obtener nombre del archivo entre comillas
        cmp     byte [esi], '"'
        jne     .dir_unknown
        inc     esi

        ; Copiar nombre a operand_buf
        push    edi
        lea     edi, [operand_buf]
        xor     ecx, ecx
.di_copy:
        mov     al, [esi]
        cmp     al, '"'
        je      .di_copy_done
        cmp     al, 0
        je      .di_copy_done
        mov     [edi+ecx], al
        inc     ecx
        inc     esi
        jmp     .di_copy
.di_copy_done:
        mov     byte [edi+ecx], 0
        pop     edi

        ; Saltar comilla final
        cmp     byte [esi], '"'
        jne     .di_do
        inc     esi
.di_do:
        ; Guardar estado actual
        push    dword [source_pos]
        push    dword [source_len]
        push    dword [line_number]

        ; Leer archivo incluido
        ; Necesitamos un buffer temporal - usamos parte libre del source_buf
        mov     eax, [source_len]
        push    eax                     ; guardar pos original

        ; Abrir archivo incluido
        push    0
        push    FILE_ATTRIBUTE_NORMAL
        push    OPEN_EXISTING
        push    0
        push    0
        push    GENERIC_READ
        lea     eax, [operand_buf]
        push    eax
        call    [CreateFileA]
        cmp     eax, INVALID_HANDLE_VALUE
        je      .di_error

        mov     ebx, eax

        ; Obtener tamano
        push    0
        push    ebx
        call    [GetFileSize]
        mov     ecx, eax               ; ecx = tamano del include

        ; Leer al final del source_buf
        pop     eax                     ; eax = posicion donde insertar
        push    eax
        push    ecx                     ; guardar tamano del include

        ; Mover el resto del fuente hacia adelante para hacer espacio
        ; En realidad, insertaremos el contenido en la posicion actual de lectura
        ; Es mas simple: leemos el include y lo procesamos inline

        ; Leer archivo al final del buffer fuente
        mov     edx, [source_buf]
        add     edx, [source_len]

        push    0                       ; lpOverlapped
        push    bytes_rw                ; lpNumberOfBytesRead
        push    ecx                     ; nNumberOfBytesToRead
        push    edx                     ; lpBuffer
        push    ebx                     ; hFile
        call    [ReadFile]

        push    ebx
        call    [CloseHandle]

        pop     ecx                     ; tamano del include
        pop     eax                     ; posicion original

        ; Ajustar para procesar el include: insertar en source
        ; Guardamos source_pos actual y lo ponemos al inicio del include
        mov     edx, [source_len]
        mov     [source_pos], edx       ; source_pos apunta al include
        add     edx, ecx
        mov     [source_len], edx       ; nuevo len incluye el include
        mov     dword [line_number], 0

        ; Procesar las lineas del include
.di_process:
        mov     eax, [source_pos]
        cmp     eax, [source_len]
        jge     .di_restore

        call    read_line
        inc     dword [line_number]
        lea     esi, [line_buf]
        call    process_line
        jmp     .di_process

.di_restore:
        ; Restaurar estado
        pop     dword [line_number]
        pop     dword [source_len]
        pop     dword [source_pos]
        ret

.di_error:
        pop     eax             ; limpiar stack
        pop     dword [line_number]
        pop     dword [source_len]
        pop     dword [source_pos]

        cmp     dword [current_pass], 2
        jne     .di_err_skip
        push    msg_err_include
        call    print_string_err
        lea     eax, [operand_buf]
        push    eax
        call    print_string_err
        push    msg_newline
        call    print_string_err
        inc     dword [error_count]
        mov     dword [has_errors], 1
.di_err_skip:
        ret

; --- .incbin ---
.dir_incbin:
        ; Similar a include pero emite bytes directos
        cmp     byte [esi], '"'
        jne     .dir_unknown
        inc     esi

        push    edi
        lea     edi, [operand_buf]
        xor     ecx, ecx
.dib_copy:
        mov     al, [esi]
        cmp     al, '"'
        je      .dib_copy_done
        cmp     al, 0
        je      .dib_copy_done
        mov     [edi+ecx], al
        inc     ecx
        inc     esi
        jmp     .dib_copy
.dib_copy_done:
        mov     byte [edi+ecx], 0
        pop     edi
        cmp     byte [esi], '"'
        jne     .dib_open
        inc     esi
.dib_open:
        ; Abrir archivo binario
        push    0
        push    FILE_ATTRIBUTE_NORMAL
        push    OPEN_EXISTING
        push    0
        push    0
        push    GENERIC_READ
        lea     eax, [operand_buf]
        push    eax
        call    [CreateFileA]
        cmp     eax, INVALID_HANDLE_VALUE
        je      .dib_error
        mov     ebx, eax

        ; Obtener tamano
        push    0
        push    ebx
        call    [GetFileSize]
        mov     ecx, eax

        cmp     dword [current_pass], 2
        jne     .dib_skip_read

        ; Leer directamente al output_buf
        mov     edx, [output_buf]
        add     edx, [output_pos]
        push    0
        push    bytes_rw
        push    ecx
        push    edx
        push    ebx
        call    [ReadFile]
        ; Ajustar output_pos
        mov     eax, [bytes_rw]
        add     [output_pos], eax

.dib_skip_read:
        add     [current_pc], ecx

        push    ebx
        call    [CloseHandle]
        ret

.dib_error:
        cmp     dword [current_pass], 2
        jne     .dib_err_skip
        push    msg_err_include
        call    print_string_err
        lea     eax, [operand_buf]
        push    eax
        call    print_string_err
        push    msg_newline
        call    print_string_err
        inc     dword [error_count]
        mov     dword [has_errors], 1
.dib_err_skip:
        ret

; --- .define NAME VALUE ---
.dir_define:
        ; Leer nombre
        push    edi
        lea     edi, [token_buf]
        xor     ecx, ecx
.dd_name:
        mov     al, [esi]
        call    .is_ident_char
        jnc     .dd_name_done
        cmp     al, 'a'
        jb      .dd_ns
        cmp     al, 'z'
        ja      .dd_ns
        sub     al, 32
.dd_ns:
        mov     [edi+ecx], al
        inc     ecx
        inc     esi
        jmp     .dd_name
.dd_name_done:
        mov     byte [edi+ecx], 0
        pop     edi

        call    .skip_ws

        ; Evaluar valor
        call    eval_expression

        cmp     dword [current_pass], 1
        jne     .dd_done
        push    eax
        push    SYM_DEFINED or SYM_CONSTANT
        lea     ebx, [token_buf]
        push    ebx
        call    add_symbol
.dd_done:
        ret

; --- .bank ---
.dir_bank:
        call    eval_expression
        mov     [current_bank], eax
        ret

; --- .rsset ---
.dir_rsset:
        call    eval_expression
        mov     [rs_address], eax
        ret

; --- .rs ---
.dir_rs:
        ; Primero verificar si hay etiqueta antes (ya procesada, le asignamos rs_address)
        ; .rs solo reserva espacio en el area de RS
        call    eval_expression
        ; EAX = cantidad de bytes a reservar
        ; El label anterior deberia apuntar a rs_address
        ; Incrementar rs_address
        add     [rs_address], eax
        ret

; --- .ds ---
.dir_ds:
        call    eval_expression
        mov     ecx, eax        ; cantidad de bytes

        ; Verificar si hay fill value
        push    ecx
        call    .skip_ws
        xor     edx, edx        ; fill = 0 por defecto
        cmp     byte [esi], ','
        jne     .ds_fill
        inc     esi
        call    .skip_ws
        call    eval_expression
        mov     edx, eax
.ds_fill:
        pop     ecx

        ; Emitir ecx bytes con valor dl
        cmp     dword [current_pass], 2
        jne     .ds_skip
.ds_emit:
        test    ecx, ecx
        jz      .ds_skip
        mov     al, dl
        call    emit_byte_al
        dec     ecx
        inc     dword [current_pc]
        jmp     .ds_emit
.ds_skip:
        ; En pasada 1, solo avanzar PC
        cmp     dword [current_pass], 1
        jne     .ds_done2
        add     [current_pc], ecx
.ds_done2:
        ret

; --- .ascii ---
.dir_ascii:
        cmp     byte [esi], '"'
        jne     .dir_unknown
        inc     esi
.da_loop:
        mov     al, [esi]
        cmp     al, '"'
        je      .da_end
        cmp     al, 0
        je      .da_end
        cmp     dword [current_pass], 2
        jne     .da_skip
        call    emit_byte_al
.da_skip:
        inc     dword [current_pc]
        inc     esi
        jmp     .da_loop
.da_end:
        cmp     byte [esi], '"'
        jne     .da_ret
        inc     esi
.da_ret:
        ret

; --- .align ---
.dir_align:
        call    eval_expression
        ; EAX = alineacion
        test    eax, eax
        jz      .al_done
        mov     ecx, eax
        mov     eax, [current_pc]
        ; Calcular padding = (align - (pc % align)) % align
        xor     edx, edx
        div     ecx             ; edx = pc % align
        test    edx, edx
        jz      .al_done
        sub     ecx, edx        ; ecx = bytes de padding

        cmp     dword [current_pass], 2
        jne     .al_skip
.al_emit:
        test    ecx, ecx
        jz      .al_done
        xor     al, al
        call    emit_byte_al
        dec     ecx
        inc     dword [current_pc]
        jmp     .al_emit
.al_skip:
        add     [current_pc], ecx
.al_done:
        ret

.dir_unknown:
        ret

; ============================================================================
; handle_instruction - Procesa una instruccion 6502
; Entrada: ESI = puntero al mnemonico
; ============================================================================
.handle_instruction:
        ; Leer mnemonico (3 caracteres)
        push    edi
        lea     edi, [token_buf]
        xor     ecx, ecx
.hi_copy:
        mov     al, [esi+ecx]
        call    .is_alpha
        jnc     .hi_copy_done
        ; toupper
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

        ; Verificar que el mnemonico tiene 3 caracteres
        cmp     ecx, 3
        jne     .hi_error

        ; Buscar en tabla de opcodes
        call    find_opcode
        ; EAX = puntero a la entrada de opcode, o 0 si no se encontro
        test    eax, eax
        jz      .hi_error
        mov     ebx, eax        ; EBX = puntero a entrada de opcode

        ; Determinar modo de direccionamiento
        call    .skip_ws
        call    parse_addressing_mode
        ; EAX = modo de direccionamiento
        ; [expr_value] = valor del operando

        ; Verificar que el modo es valido para esta instruccion
        mov     cl, [ebx+4+eax]  ; opcode para este modo
        cmp     cl, 0xFF
        je      .hi_addr_error

        ; En pasada 1: solo avanzar PC por el tamano de la instruccion
        movzx   edx, byte [instr_sizes+eax]
        cmp     dword [current_pass], 1
        jne     .hi_emit

        add     [current_pc], edx
        ret

.hi_emit:
        ; Pasada 2: emitir opcode y operandos
        mov     al, cl          ; opcode
        call    emit_byte_al
        inc     dword [current_pc]

        ; Segun el modo, emitir 0, 1 o 2 bytes adicionales
        cmp     edx, 1
        je      .hi_done        ; Sin operando (implied/accumulator)

        mov     eax, [expr_value]

        cmp     edx, 2
        je      .hi_one_byte

        ; 3 bytes: absolute
        ; Byte bajo
        push    eax
        call    emit_byte_al
        inc     dword [current_pc]
        pop     eax
        ; Byte alto
        shr     eax, 8
        call    emit_byte_al
        inc     dword [current_pc]
        jmp     .hi_done

.hi_one_byte:
        call    emit_byte_al
        inc     dword [current_pc]

.hi_done:
        ret

.hi_error:
        cmp     dword [current_pass], 2
        jne     .hi_err_skip
        push    msg_err_opcode
        call    print_string_err
        push    dword [line_number]
        call    print_number_err
        push    msg_newline
        call    print_string_err
        inc     dword [error_count]
        mov     dword [has_errors], 1
.hi_err_skip:
        ret

.hi_addr_error:
        cmp     dword [current_pass], 2
        jne     .hi_ae_skip
        push    msg_err_addr
        call    print_string_err
        push    dword [line_number]
        call    print_number_err
        push    msg_newline
        call    print_string_err
        inc     dword [error_count]
        mov     dword [has_errors], 1
.hi_ae_skip:
        ; Avanzar PC por tamano estimado
        add     dword [current_pc], 1
        ret

; ============================================================================
; find_opcode - Busca un mnemonico en la tabla de opcodes
; Usa: token_buf (3 chars uppercase)
; Retorna: EAX = puntero a entrada, o 0 si no encontrado
; ============================================================================
find_opcode:
        push    ecx
        push    edx
        lea     edx, [opcode_table]
        mov     ecx, NUM_OPCODES

.fo_loop:
        ; Comparar 3 bytes del nombre
        mov     al, [token_buf]
        cmp     al, [edx]
        jne     .fo_next
        mov     al, [token_buf+1]
        cmp     al, [edx+1]
        jne     .fo_next
        mov     al, [token_buf+2]
        cmp     al, [edx+2]
        jne     .fo_next

        ; Encontrado!
        mov     eax, edx
        pop     edx
        pop     ecx
        ret

.fo_next:
        add     edx, 20         ; siguiente entrada (20 bytes por entrada)
        dec     ecx
        jnz     .fo_loop

        ; No encontrado
        xor     eax, eax
        pop     edx
        pop     ecx
        ret

; ============================================================================
; parse_addressing_mode - Determina el modo de direccionamiento
; Entrada: ESI = puntero al operando
; Retorna: EAX = codigo de modo
;          [expr_value] = valor del operando
; ============================================================================
parse_addressing_mode:
        push    ebx
        push    ecx

        ; Verificar fin de linea (implied)
        cmp     byte [esi], 0
        je      .pam_implied
        cmp     byte [esi], ';'
        je      .pam_implied
        cmp     word [esi], '//'
        je      .pam_implied

        ; Verificar si el mnemonico es un branch (token_buf contiene el nombre)
        ; Branches: BCC,BCS,BEQ,BMI,BNE,BPL,BVC,BVS
        cmp     byte [token_buf], 'B'
        jne     .pam_not_branch
        ; Verificar si es un branch real (no BIT, BRK)
        lea     eax, [token_buf]
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

        ; #immediate
        cmp     byte [esi], '#'
        je      .pam_immediate

        ; (indirect...)
        cmp     byte [esi], '('
        je      .pam_indirect

        ; A (accumulator) - solo si es una sola 'A' o 'a'
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

        ; Debe ser absolute o zeropage (posiblemente con ,X o ,Y)
        call    eval_expression
        mov     [expr_value], eax

        ; Verificar ,X o ,Y
        call    .skip_ws_local
        cmp     byte [esi], ','
        jne     .pam_no_index

        inc     esi
        call    .skip_ws_local
        mov     al, [esi]
        or      al, 0x20
        cmp     al, 'x'
        je      .pam_indexed_x
        cmp     al, 'y'
        je      .pam_indexed_y
        jmp     .pam_no_index

.pam_indexed_x:
        inc     esi
        ; ZP,X o ABS,X?
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
        ; ZP o ABS?
        mov     eax, [expr_value]
        cmp     eax, 0xFF
        ja      .pam_absolute
        ; Podria ser ZP, pero necesitamos verificar si la instruccion soporta ZP
        ; Para JMP y JSR, siempre es absolute
        cmp     byte [token_buf], 'J'
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
        inc     esi             ; saltar '#'
        ; Verificar operador < o >
        mov     dword [expr_lobyte], 0
        mov     dword [expr_hibyte], 0
        cmp     byte [esi], '<'
        je      .pam_imm_lo
        cmp     byte [esi], '>'
        je      .pam_imm_hi
        jmp     .pam_imm_eval
.pam_imm_lo:
        inc     esi
        mov     dword [expr_lobyte], 1
        jmp     .pam_imm_eval
.pam_imm_hi:
        inc     esi
        mov     dword [expr_hibyte], 1
.pam_imm_eval:
        call    eval_expression
        ; Aplicar operadores de byte
        cmp     dword [expr_lobyte], 0
        jne     .pam_apply_lo
        cmp     dword [expr_hibyte], 0
        jne     .pam_apply_hi
        jmp     .pam_imm_store
.pam_apply_lo:
        and     eax, 0xFF
        jmp     .pam_imm_store
.pam_apply_hi:
        shr     eax, 8
        and     eax, 0xFF
.pam_imm_store:
        mov     [expr_value], eax
        mov     eax, AM_IMMEDIATE
        jmp     .pam_done

.pam_relative:
        ; Branch: evaluar destino y calcular offset relativo
        call    eval_expression
        ; Calcular offset: destino - (PC + 2)
        cmp     dword [current_pass], 2
        jne     .pam_rel_pass1
        mov     ecx, [current_pc]
        add     ecx, 2          ; PC despues de la instruccion de branch
        sub     eax, ecx
        ; Verificar rango [-128, +127]
        cmp     eax, -128
        jl      .pam_rel_range_err
        cmp     eax, 127
        jg      .pam_rel_range_err
        and     eax, 0xFF
        mov     [expr_value], eax
        jmp     .pam_rel_ok
.pam_rel_range_err:
        push    msg_err_branch
        call    print_string_err
        push    dword [line_number]
        call    print_number_err
        push    msg_newline
        call    print_string_err
        inc     dword [error_count]
        mov     dword [has_errors], 1
        xor     eax, eax
        mov     [expr_value], eax
.pam_rel_ok:
        mov     eax, AM_RELATIVE
        jmp     .pam_done

.pam_rel_pass1:
        ; En pasada 1, poner valor temporal
        mov     dword [expr_value], 0
        mov     eax, AM_RELATIVE
        jmp     .pam_done

.pam_indirect:
        inc     esi             ; saltar '('
        call    .skip_ws_local
        call    eval_expression
        mov     [expr_value], eax
        call    .skip_ws_local

        ; ($xx,X) ?
        cmp     byte [esi], ','
        je      .pam_ind_x_check

        ; ($xxxx) o ($xx),Y ?
        cmp     byte [esi], ')'
        jne     .pam_ind_err
        inc     esi

        ; Verificar ,Y despues del )
        call    .skip_ws_local
        cmp     byte [esi], ','
        jne     .pam_ind_plain
        inc     esi
        call    .skip_ws_local
        mov     al, [esi]
        or      al, 0x20
        cmp     al, 'y'
        jne     .pam_ind_err
        inc     esi
        mov     eax, AM_INDIRECT_Y
        jmp     .pam_done

.pam_ind_plain:
        ; JMP ($xxxx)
        mov     eax, AM_INDIRECT
        jmp     .pam_done

.pam_ind_x_check:
        inc     esi             ; saltar ','
        call    .skip_ws_local
        mov     al, [esi]
        or      al, 0x20
        cmp     al, 'x'
        jne     .pam_ind_err
        inc     esi
        call    .skip_ws_local
        cmp     byte [esi], ')'
        jne     .pam_ind_err
        inc     esi
        mov     eax, AM_INDIRECT_X
        jmp     .pam_done

.pam_ind_err:
        mov     eax, AM_IMPLIED  ; fallback
        jmp     .pam_done

.pam_done:
        pop     ecx
        pop     ebx
        ret

.skip_ws_local:
        cmp     byte [esi], ' '
        je      .swl1
        cmp     byte [esi], 9
        je      .swl1
        ret
.swl1:
        inc     esi
        jmp     .skip_ws_local

; ============================================================================
; eval_expression - Evalua una expresion numerica
; Entrada: ESI = puntero a la expresion
; Retorna: EAX = valor
; Modifica: ESI avanza pasando la expresion
; ============================================================================
eval_expression:
        push    ebx
        push    ecx
        push    edx

        call    .eval_term
        mov     ebx, eax

.ee_loop:
        ; Verificar operadores + y -
        cmp     byte [esi], '+'
        je      .ee_add
        cmp     byte [esi], '-'
        je      .ee_sub
        jmp     .ee_done

.ee_add:
        inc     esi
        call    .eval_term
        add     ebx, eax
        jmp     .ee_loop

.ee_sub:
        inc     esi
        call    .eval_term
        sub     ebx, eax
        jmp     .ee_loop

.ee_done:
        mov     eax, ebx
        pop     edx
        pop     ecx
        pop     ebx
        ret

; --- eval_term: termino (factor * o /) ---
.eval_term:
        call    .eval_factor
        mov     ebx, eax

.et_loop:
        cmp     byte [esi], '*'
        je      .et_mul
        cmp     byte [esi], '/'
        je      .et_div
        mov     eax, ebx
        ret

.et_mul:
        inc     esi
        push    ebx
        call    .eval_factor
        pop     ebx
        imul    eax, ebx
        mov     ebx, eax
        jmp     .et_loop

.et_div:
        inc     esi
        push    ebx
        call    .eval_factor
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

; --- eval_factor: factor (numero, simbolo, operador unario, parentesis) ---
.eval_factor:
        ; Saltar espacios
.ef_skip_ws:
        cmp     byte [esi], ' '
        je      .ef_sw
        cmp     byte [esi], 9
        je      .ef_sw
        jmp     .ef_start
.ef_sw:
        inc     esi
        jmp     .ef_skip_ws

.ef_start:
        ; Operador unario < (byte bajo)
        cmp     byte [esi], '<'
        je      .ef_lo
        ; Operador unario > (byte alto)
        cmp     byte [esi], '>'
        je      .ef_hi
        ; Negacion -
        cmp     byte [esi], '-'
        je      .ef_neg

        ; Numero hexadecimal $xx
        cmp     byte [esi], '$'
        je      .ef_hex

        ; Numero binario %
        cmp     byte [esi], '%'
        je      .ef_bin

        ; Numero decimal
        cmp     byte [esi], '0'
        jb      .ef_not_num
        cmp     byte [esi], '9'
        jbe     .ef_dec
.ef_not_num:

        ; Caracter entre comillas 'x'
        cmp     byte [esi], 0x27  ; comilla simple
        je      .ef_char

        ; Parentesis (
        cmp     byte [esi], '('
        je      .ef_paren

        ; PC actual *
        cmp     byte [esi], '*'
        je      .ef_pc

        ; Identificador (simbolo/etiqueta)
        mov     al, [esi]
        cmp     al, '_'
        je      .ef_symbol
        cmp     al, '@'
        je      .ef_symbol
        cmp     al, 'A'
        jb      .ef_zero
        cmp     al, 'Z'
        jbe     .ef_symbol
        cmp     al, 'a'
        jb      .ef_zero
        cmp     al, 'z'
        jbe     .ef_symbol

.ef_zero:
        xor     eax, eax
        ret

.ef_lo:
        inc     esi
        call    .eval_factor
        and     eax, 0xFF
        ret

.ef_hi:
        inc     esi
        call    .eval_factor
        shr     eax, 8
        and     eax, 0xFF
        ret

.ef_neg:
        inc     esi
        call    .eval_factor
        neg     eax
        ret

.ef_hex:
        inc     esi             ; saltar '$'
        xor     eax, eax
.ef_hex_loop:
        mov     cl, [esi]
        cmp     cl, '0'
        jb      .ef_hex_done
        cmp     cl, '9'
        jbe     .ef_hex_digit
        or      cl, 0x20        ; tolower
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
        inc     esi             ; saltar '%'
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
        inc     esi             ; saltar comilla
        movzx   eax, byte [esi]
        inc     esi
        cmp     byte [esi], 0x27
        jne     .ef_char_done
        inc     esi             ; saltar comilla final
.ef_char_done:
        ret

.ef_paren:
        inc     esi             ; saltar '('
        call    eval_expression
        cmp     byte [esi], ')'
        jne     .ef_paren_done
        inc     esi
.ef_paren_done:
        ret

.ef_pc:
        inc     esi
        mov     eax, [current_pc]
        ret

.ef_symbol:
        ; Leer nombre del simbolo
        push    edi
        lea     edi, [operand_buf]
        xor     ecx, ecx
.ef_sym_copy:
        mov     al, [esi]
        cmp     al, '_'
        je      .ef_sym_store
        cmp     al, '@'
        je      .ef_sym_store
        cmp     al, '0'
        jb      .ef_sym_done2
        cmp     al, '9'
        jbe     .ef_sym_store
        cmp     al, 'A'
        jb      .ef_sym_done2
        cmp     al, 'Z'
        jbe     .ef_sym_toupper
        cmp     al, 'a'
        jb      .ef_sym_done2
        cmp     al, 'z'
        ja      .ef_sym_done2
.ef_sym_toupper:
        cmp     al, 'a'
        jb      .ef_sym_store
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

        ; Buscar en tabla de simbolos
        lea     eax, [operand_buf]
        push    eax
        call    find_symbol
        ; EAX = valor, o 0 si no encontrado
        ret

; ============================================================================
; add_symbol - Agrega un simbolo a la tabla
; Entrada: [esp+4] = nombre, [esp+8] = flags, [esp+12] = valor
; ============================================================================
add_symbol:
        push    ebp
        mov     ebp, esp
        push    esi
        push    edi
        push    ecx

        ; Verificar si ya existe
        push    dword [ebp+8]    ; nombre
        call    find_symbol_ptr
        test    eax, eax
        jnz     .as_exists

        ; Verificar limite
        mov     eax, [num_symbols]
        cmp     eax, MAX_SYMBOLS
        jge     .as_full

        ; Calcular puntero a nueva entrada
        mov     edi, [symbol_table]
        imul    eax, SYMBOL_ENTRY_SIZE
        add     edi, eax

        ; Copiar nombre
        mov     esi, [ebp+8]
        xor     ecx, ecx
.as_copy:
        mov     al, [esi+ecx]
        mov     [edi+ecx], al
        test    al, al
        jz      .as_copy_done
        inc     ecx
        cmp     ecx, SYMBOL_NAME_LEN-1
        jb      .as_copy
        mov     byte [edi+ecx], 0
.as_copy_done:
        ; Guardar valor y flags
        mov     eax, [ebp+16]   ; valor
        mov     [edi+SYMBOL_NAME_LEN], eax
        mov     eax, [ebp+12]   ; flags
        mov     [edi+SYMBOL_NAME_LEN+4], eax

        inc     dword [num_symbols]

        pop     ecx
        pop     edi
        pop     esi
        pop     ebp
        ret     12

.as_exists:
        ; Actualizar valor si ya existe
        mov     ecx, [ebp+16]   ; valor
        mov     [eax+SYMBOL_NAME_LEN], ecx
        pop     ecx
        pop     edi
        pop     esi
        pop     ebp
        ret     12

.as_full:
        pop     ecx
        pop     edi
        pop     esi
        pop     ebp
        ret     12

; ============================================================================
; find_symbol - Busca un simbolo por nombre
; Entrada: [esp+4] = nombre
; Retorna: EAX = valor del simbolo, o 0 si no encontrado
; ============================================================================
find_symbol:
        push    ebp
        mov     ebp, esp
        push    ebx
        push    ecx
        push    esi
        push    edi

        mov     esi, [ebp+8]    ; nombre a buscar
        mov     edi, [symbol_table]
        mov     ecx, [num_symbols]
        test    ecx, ecx
        jz      .fs_not_found

.fs_loop:
        ; Comparar nombres
        push    ecx
        push    esi
        push    edi
        call    str_equal
        pop     edi
        pop     esi
        pop     ecx
        test    eax, eax
        jnz     .fs_found

        add     edi, SYMBOL_ENTRY_SIZE
        dec     ecx
        jnz     .fs_loop

.fs_not_found:
        ; Si estamos en pasada 2, reportar error
        cmp     dword [current_pass], 2
        jne     .fs_ret0
        ; No reportar errores para simplificar - usar 0
.fs_ret0:
        xor     eax, eax
        pop     edi
        pop     esi
        pop     ecx
        pop     ebx
        pop     ebp
        ret     4

.fs_found:
        mov     eax, [edi+SYMBOL_NAME_LEN]     ; valor
        pop     edi
        pop     esi
        pop     ecx
        pop     ebx
        pop     ebp
        ret     4

; ============================================================================
; find_symbol_ptr - Busca un simbolo y retorna puntero a su entrada
; Entrada: [esp+4] = nombre
; Retorna: EAX = puntero a entrada, o 0
; ============================================================================
find_symbol_ptr:
        push    ebp
        mov     ebp, esp
        push    ecx
        push    esi
        push    edi

        mov     esi, [ebp+8]
        mov     edi, [symbol_table]
        mov     ecx, [num_symbols]
        test    ecx, ecx
        jz      .fsp_not_found

.fsp_loop:
        push    ecx
        push    esi
        push    edi
        call    str_equal
        pop     edi
        pop     esi
        pop     ecx
        test    eax, eax
        jnz     .fsp_found

        add     edi, SYMBOL_ENTRY_SIZE
        dec     ecx
        jnz     .fsp_loop

.fsp_not_found:
        xor     eax, eax
        pop     edi
        pop     esi
        pop     ecx
        pop     ebp
        ret     4

.fsp_found:
        mov     eax, edi
        pop     edi
        pop     esi
        pop     ecx
        pop     ebp
        ret     4

; ============================================================================
; str_equal - Compara dos strings (case insensitive)
; Entrada: ESI, EDI = punteros a strings
; Retorna: EAX = 1 si iguales, 0 si no
; ============================================================================
str_equal:
        push    esi
        push    edi
.se_loop:
        mov     al, [esi]
        mov     cl, [edi]
        ; toupper ambos
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

; ============================================================================
; emit_byte_al - Emite un byte al buffer de salida
; Entrada: AL = byte a emitir
; ============================================================================
emit_byte_al:
        push    edx
        mov     edx, [output_buf]
        add     edx, [output_pos]
        mov     [edx], al
        inc     dword [output_pos]
        pop     edx
        ret

; ============================================================================
; write_nes_file - Escribe el archivo .nes con cabecera iNES
; Retorna: EAX = 1 si OK, 0 si error
; ============================================================================
write_nes_file:
        push    ebx
        push    ecx
        push    edx

        ; Crear archivo de salida
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

        ; Escribir cabecera iNES (16 bytes)
        ; Preparar cabecera en el stack
        sub     esp, 16
        mov     edi, esp

        ; Bytes 0-3: NES + 0x1A
        mov     byte [edi], 'N'
        mov     byte [edi+1], 'E'
        mov     byte [edi+2], 'S'
        mov     byte [edi+3], 0x1A

        ; Byte 4: PRG-ROM banks
        mov     eax, [ines_prg]
        mov     [edi+4], al

        ; Byte 5: CHR-ROM banks
        mov     eax, [ines_chr]
        mov     [edi+5], al

        ; Byte 6: Flags 6
        mov     eax, [ines_mirror]
        and     eax, 1
        mov     ecx, [ines_mapper]
        shl     ecx, 4
        and     ecx, 0xF0
        or      eax, ecx
        mov     ecx, [ines_battery]
        shl     ecx, 1
        and     ecx, 2
        or      eax, ecx
        mov     [edi+6], al

        ; Byte 7: Flags 7 (upper mapper nibble)
        mov     eax, [ines_mapper]
        and     eax, 0xF0
        mov     [edi+7], al

        ; Bytes 8-15: ceros
        xor     eax, eax
        mov     [edi+8], eax
        mov     [edi+12], eax

        ; Escribir cabecera
        push    0
        push    bytes_rw
        push    16
        push    edi
        push    ebx
        call    [WriteFile]

        add     esp, 16         ; restaurar stack

        ; Escribir PRG-ROM
        ; Tamano total de PRG = ines_prg * 16384
        mov     ecx, [ines_prg]
        shl     ecx, 14         ; * 16384
        ; Si output_pos < ecx, rellenar con 0xFF
        ; Escribir lo que tenemos
        mov     edx, [output_pos]
        cmp     edx, ecx
        jbe     .wf_write_prg
        mov     edx, ecx        ; no escribir mas del tamano del banco

.wf_write_prg:
        push    ecx             ; guardar tamano total
        push    0
        push    bytes_rw
        push    edx
        push    dword [output_buf]
        push    ebx
        call    [WriteFile]

        ; Si necesitamos padding
        pop     ecx
        mov     edx, [output_pos]
        cmp     edx, ecx
        jge     .wf_chr

        ; Llenar con 0xFF hasta completar el banco
        sub     ecx, edx        ; bytes faltantes
        ; Escribir ceros/FF para padding - usar parte libre del output_buf
        mov     edi, [output_buf]
        add     edi, [output_pos]
        push    ecx
        mov     al, 0xFF
        rep     stosb
        pop     ecx

        push    0
        push    bytes_rw
        push    ecx
        mov     eax, [output_buf]
        add     eax, [output_pos]
        push    eax
        push    ebx
        call    [WriteFile]

.wf_chr:
        ; Escribir CHR-ROM (si hay)
        mov     ecx, [ines_chr]
        test    ecx, ecx
        jz      .wf_close

        ; CHR = ines_chr * 8192 bytes
        shl     ecx, 13
        ; Por ahora emitir bytes cero (el usuario deberia usar .incbin)
        ; Usar area despues del PRG en output_buf
        mov     edi, [output_buf]
        mov     edx, [ines_prg]
        shl     edx, 14
        add     edi, edx

        ; Verificar si hay datos CHR en el output
        mov     eax, [output_pos]
        sub     eax, edx
        cmp     eax, 0
        jle     .wf_chr_zeros

        ; Hay datos CHR despues del PRG
        cmp     eax, ecx
        jbe     .wf_chr_write
        mov     eax, ecx
.wf_chr_write:
        push    ecx
        push    eax
        push    0
        push    bytes_rw
        push    eax
        push    edi
        push    ebx
        call    [WriteFile]
        pop     eax
        pop     ecx
        sub     ecx, eax
        jz      .wf_close
        ; Padding del CHR
        jmp     .wf_chr_pad

.wf_chr_zeros:
        ; No hay datos CHR, escribir ceros
.wf_chr_pad:
        ; Llenar buffer temporal con ceros
        push    ecx
        mov     edi, [output_buf]
        xor     al, al
        rep     stosb
        pop     ecx

        push    0
        push    bytes_rw
        push    ecx
        push    dword [output_buf]
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

; ============================================================================
; print_string - Imprime una cadena a stdout
; Entrada: [esp+4] = puntero a la cadena
; ============================================================================
print_string:
        push    ebp
        mov     ebp, esp
        push    esi
        push    ecx

        mov     esi, [ebp+8]
        ; Calcular longitud
        xor     ecx, ecx
.ps_len:
        cmp     byte [esi+ecx], 0
        je      .ps_write
        inc     ecx
        jmp     .ps_len
.ps_write:
        push    0
        push    bytes_rw
        push    ecx
        push    esi
        push    dword [stdout_handle]
        call    [WriteFile]

        pop     ecx
        pop     esi
        pop     ebp
        ret     4

; ============================================================================
; print_string_err - Imprime a stderr
; ============================================================================
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
        push    bytes_rw
        push    ecx
        push    esi
        push    dword [stderr_handle]
        call    [WriteFile]

        pop     ecx
        pop     esi
        pop     ebp
        ret     4

; ============================================================================
; print_number - Imprime un numero decimal a stdout
; Entrada: [esp+4] = numero
; ============================================================================
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

; ============================================================================
; print_number_err - Imprime un numero decimal a stderr
; ============================================================================
print_number_err:
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
        jnz     .pne_loop
        mov     byte [ecx], '0'
        dec     ecx
        jmp     .pne_print

.pne_loop:
        test    eax, eax
        jz      .pne_print
        xor     edx, edx
        push    ebx
        mov     ebx, 10
        div     ebx
        pop     ebx
        add     dl, '0'
        mov     [ecx], dl
        dec     ecx
        jmp     .pne_loop

.pne_print:
        inc     ecx
        push    ecx
        call    print_string_err

        pop     edx
        pop     ecx
        pop     eax
        pop     ebp
        ret     4

; ============================================================================
; Tabla de importaciones
; ============================================================================
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
