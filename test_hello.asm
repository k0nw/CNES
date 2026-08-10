; ============================================================================
; test_hello.asm - ROM de prueba para CNES
; Muestra un fondo azul en la NES
; ============================================================================

; --- Configuracion iNES ---
.inesprg 1          ; 1 banco de PRG-ROM (16KB)
.ineschr 1          ; 1 banco de CHR-ROM (8KB)
.inesmir 1          ; Mirroring vertical
.inesmap 0          ; Mapper 0 (NROM)

; --- Variables en RAM (direcciones fijas) ---
vblank_flag     = $0000
frame_counter   = $0001

; --- Constantes del PPU ---
PPU_CTRL    = $2000
PPU_MASK    = $2001
PPU_STATUS  = $2002
PPU_SCROLL  = $2005
PPU_ADDR    = $2006
PPU_DATA    = $2007

; === Codigo PRG-ROM ===
.org $C000

; ============================================================================
; RESET - Punto de entrada principal
; ============================================================================
RESET:
    SEI                 ; Deshabilitar interrupciones
    CLD                 ; Limpiar modo decimal (no usado en NES)
    LDX #$40
    STX $4017           ; Deshabilitar frame IRQ del APU
    LDX #$FF
    TXS                 ; Inicializar stack pointer
    INX                 ; X = 0
    STX PPU_CTRL        ; Deshabilitar NMI
    STX PPU_MASK        ; Deshabilitar renderizado
    STX $4010           ; Deshabilitar IRQ del DMC

; Esperar primer vblank
wait_vblank1:
    BIT PPU_STATUS
    BPL wait_vblank1

; Limpiar RAM
    LDA #$00
    LDX #$00
clear_ram:
    STA $0000,X
    STA $0100,X
    STA $0200,X
    STA $0300,X
    STA $0400,X
    STA $0500,X
    STA $0600,X
    STA $0700,X
    INX
    BNE clear_ram

; Esperar segundo vblank
wait_vblank2:
    BIT PPU_STATUS
    BPL wait_vblank2

; ==============================
; Configurar paleta de colores
; ==============================
    LDA PPU_STATUS      ; Reset del latch de direccion
    LDA #$3F
    STA PPU_ADDR        ; Direccion alta de la paleta
    LDA #$00
    STA PPU_ADDR        ; Direccion baja de la paleta

    ; Fondo: azul oscuro
    LDA #$02            ; Azul oscuro
    STA PPU_DATA
    LDA #$12            ; Azul medio
    STA PPU_DATA
    LDA #$22            ; Azul claro
    STA PPU_DATA
    LDA #$32            ; Azul palido
    STA PPU_DATA

    ; Segunda sub-paleta
    LDA #$02
    STA PPU_DATA
    LDA #$14
    STA PPU_DATA
    LDA #$24
    STA PPU_DATA
    LDA #$34
    STA PPU_DATA

    ; Tercera sub-paleta
    LDA #$02
    STA PPU_DATA
    LDA #$16
    STA PPU_DATA
    LDA #$26
    STA PPU_DATA
    LDA #$36
    STA PPU_DATA

    ; Cuarta sub-paleta
    LDA #$02
    STA PPU_DATA
    LDA #$18
    STA PPU_DATA
    LDA #$28
    STA PPU_DATA
    LDA #$38
    STA PPU_DATA

; ==============================
; Limpiar nametable
; ==============================
    LDA PPU_STATUS
    LDA #$20
    STA PPU_ADDR
    LDA #$00
    STA PPU_ADDR

    LDA #$00            ; Tile vacio
    LDX #$00
    LDY #$04            ; 4 paginas de 256 = 1024 bytes
clear_nametable:
    STA PPU_DATA
    INX
    BNE clear_nametable
    DEY
    BNE clear_nametable

; ==============================
; Activar renderizado
; ==============================
    LDA #%10010000      ; Activar NMI, usar pattern table 1 para fondo
    STA PPU_CTRL
    LDA #%00011110      ; Mostrar sprites y fondo
    STA PPU_MASK

; Reset del scroll
    LDA #$00
    STA PPU_SCROLL
    STA PPU_SCROLL

; ============================================================================
; Loop principal - esperar NMI infinitamente
; ============================================================================
main_loop:
    LDA vblank_flag
    BEQ main_loop

    LDA #$00
    STA vblank_flag

    ; Aqui iria la logica del juego
    INC frame_counter

    JMP main_loop

; ============================================================================
; NMI - Interrupcion de vblank
; ============================================================================
NMI:
    PHA                 ; Guardar registros
    TXA
    PHA
    TYA
    PHA

    ; Senalar que hubo vblank
    LDA #$01
    STA vblank_flag

    ; Reset del scroll
    LDA #$00
    STA PPU_SCROLL
    STA PPU_SCROLL

    PLA                 ; Restaurar registros
    TAY
    PLA
    TAX
    PLA
    RTI

; ============================================================================
; IRQ - No usado
; ============================================================================
IRQ:
    RTI

; ============================================================================
; Vectores de interrupcion (deben estar en $FFFA-$FFFF)
; ============================================================================
.org $FFFA
    .dw NMI             ; Vector NMI ($FFFA)
    .dw RESET           ; Vector RESET ($FFFC)
    .dw IRQ             ; Vector IRQ ($FFFE)

; ============================================================================
; Banco CHR-ROM (8KB de tiles - vacio por ahora)
; ============================================================================
.org $0000
    .ds 8192            ; 8KB de tiles vacios