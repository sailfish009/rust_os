; RUSTOS LOADER
; STAGE 1

%include "src/asm_routines/constants.asm"

; Kernel elf executable initial load point
%define loadpoint 0xA000

; Page tables
; These constants MUST match the ones in plan.md
; If a constant defined here doesn't exists in that file, then it's also fine
%define page_table_section_start 0x00020000
%define page_table_p4 0x00020000
%define page_table_p3 0x00021000
%define page_table_p2 0x00022000
%define page_table_section_end 0x00023000


[BITS 32]
[ORG 0x7e00]

protected_mode:
    ; load all the other segments with 32 bit data segments
    mov eax, 0x10
    mov ds, eax
    mov es, eax
    mov fs, eax
    mov gs, eax
    mov ss, eax
    ; set up stack
    mov esp, 0x7c00 ; stack grows downwards

    ; SCREEN: top left: "00"
    mov dword [0xb8000], 0x2f302f30

    call enable_A20
    call check_long_mode
    call set_up_SSE


    ; SCREEN: top left: "01"
    mov dword [0xb8000], 0x2f312f30


    ; paging
    call set_up_page_tables
    call enable_paging

    ; SCREEN: top left: "02"
    mov dword [0xb8000], 0x2f322f30


    ; parse elf header
    ; http://wiki.osdev.org/ELF#Tables
    ;
    ; Because we are working in protected mode, we assume some values to fit in 32 bits.
    ; Of course we test thay they are, but this code gives error if they aren't
    ; It's not good practice, but... here we go :]
    ;
    ; elf error messages begin with "E"
    mov al, 'E'

    ; magic number 0x7f+'ELF'
    ; if not elf show error message "E!"
    mov ah, '!'
    cmp dword [loadpoint + 0], 0x464c457f
    jne error

    ; bitness and instrucion set (must be 64, so values must be 2 and 0x3e) (error code: "EB")
    mov ah, 'B'
    cmp byte [loadpoint + 4], 0x2
    jne error
    cmp word [loadpoint + 18], 0x3e
    jne error

    ; endianess (must be little endian, so value must be 1) (error code: "EE")
    mov ah, 'E'
    cmp byte [loadpoint + 5], 0x1
    jne error

    ; elf version (must be 2) (error code: "EV")
    ; mov ah, 'V'
    ; cmp byte [loadpoint + 0x0006], 0x2
    ; jne error ; this fails. ignored currently. I can't remember why it wasn't here originally
    ; ^ FIXME

    ; Now lets trust it's actually real and valid elf file

    ; kernel entry position must be 0x_00000000_00100000, 1MiB
    ; (error code : "EP")
    mov ah, 'P'
    cmp dword [loadpoint + 24], 0x00100000
    jne error
    cmp dword [loadpoint + 28], 0x00000000
    jne error

    ; load point is correct, great. print green OK
    mov dword [0xb8000 + 80*24], 0x2f4b2f4f


    ; Parse program headers and relocate sections
    ; http://wiki.osdev.org/ELF#Program_header
    ; (error code : "EH")
    mov ah, 'H'

    ; We know that program header size is 56 (=0x38) bytes
    ; still, lets check it:
    cmp word [loadpoint + 54], 0x38
    jne error


    ; get "Program header table position", check that it is max 32bits
    mov ebx, dword [loadpoint + 32]
    cmp dword [loadpoint + 36], 0
    jne error
    add ebx, loadpoint ; now ebx points to first program header

    ; get length of program header table
    mov ecx, 0
    mov cx, [loadpoint + 56]

    mov ah, '_'
    ; loop through headers
.loop_headers:
    ; First, lets check that this sector should be loaded

    cmp dword [ebx], 1 ; load: this is important
    jne .next   ; if not important: continue

    ; load: clear p_memsz bytes at p_vaddr to 0, then copy p_filesz bytes from p_offset to p_vaddr
    push ecx

    ; lets ignore some (probably important) stuff here
    ; Again, because we are working in protected mode, we assume some values to fit in 32 bits.

    mov ah, 'A'

    ; esi = p_offset
    mov esi, [ebx + 8]
    cmp dword [ebx + 12], 0
    jne error
    add esi, loadpoint  ; now points to begin of buffer we must copy

    mov ah, 'B'

    ; edi = p_vaddr
    mov edi, [ebx + 16]
    cmp dword [ebx + 20], 0
    jne error

    mov ah, 'C'

    ; ecx = p_memsz
    mov ecx, [ebx + 40]
    cmp dword [ebx + 44], 0
    jne error

    ; <1> clear p_memsz bytes at p_vaddr to 0
    push edi
.loop_clear:
    mov byte [edi], 0
    inc edi
    loop .loop_clear
    pop edi
    ; </1>

    mov ah, 'D'

    ; ecx = p_filesz
    mov ecx, [ebx + 32]
    cmp dword [ebx + 36], 0
    jne error

    ; <2> copy p_filesz bytes from p_offset to p_vaddr
    ; uses: esi, edi, ecx
    rep movsb   ; https://en.wikibooks.org/wiki/X86_Assembly/Data_Transfer#Move_String
    ; </2>

    pop ecx

    ; next entry
    loop .loop_headers

    ; no next entry, done
    jmp .over

.next:
    add ebx, 0x38   ; skip entry (0x38 is entry size)
    loop .loop_headers

    mov ah, '-'

    ; ELF relocation done
.over:
    ; going to byte bytes mode (8*8 = 2**6 = 64 bits = Long mode)

    ; relocate GDT
    mov esi, tmp_gdt64  ; from
    mov edi, gdt        ; to
    mov ecx, 8*3+12     ; size (no pointer)
    rep movsb           ; copy

    ; load GDT
    lgdt [gdt + 8*3]

    ; Now we are in IA32e (compatibility) submode
    ; jump into kernel entry (relocated to 0x00010000)
    ; and enable real 64 bit mode
    jmp 0x08:0x00100000



; http://wiki.osdev.org/A20_Line
; Using only "Fast A20" gate
; Might be a bit unreliable, but it is small :]
enable_A20:
    in al, 0x92
    test al, 2
    jnz .done
    or al, 2
    and al, 0xFE
    out 0x92, al
.done:
    ret


; Check for SSE and enable it.
; http://os.phil-opp.com/set-up-rust.html#enabling-sse
; http://wiki.osdev.org/SSE
set_up_SSE:
    ; check for SSE
    mov eax, 0x1
    cpuid
    test edx, 1<<25
    jz .SSE_missing

    ; enable SSE
    mov eax, cr0
    and ax, 0xFFFB      ; clear coprocessor emulation CR0.EM
    or ax, 0x2          ; set coprocessor monitoring  CR0.MP
    mov cr0, eax
    mov eax, cr4
    or ax, 3 << 9       ; set CR4.OSFXSR and CR4.OSXMMEXCPT at the same time
    mov cr4, eax

    ret
.SSE_missing:
    ; error: no SSE: "!S"
    mov al, '!'
    mov ah, 'S'
    jmp error

; http://wiki.osdev.org/Setting_Up_Long_Mode#x86_or_x86-64
; Just assumes that cpuid is available (processor is released after 1993)
check_long_mode:
    mov eax, 0x80000000    ; Set the A-register to 0x80000000.
    cpuid                  ; CPU identification.
    cmp eax, 0x80000001    ; Compare the A-register with 0x80000001.
    jb .no_long_mode       ; It is less, there is no long mode.
    mov eax, 0x80000001    ; Set the A-register to 0x80000001.
    cpuid                  ; CPU identification.
    test edx, 1 << 29      ; Test if the LM-bit is set in the D-register.
    jz .no_long_mode       ; They aren't, there is no long mode.
    ret
.no_long_mode:
    ; error: no long mode: "!L"
    mov al, '!'
    mov ah, 'L'
    jmp error


; Prints `ERR: ` and the given 2-character error code to screen (TL) and hangs.
; args: ax=(al,ah)=error_code (2 characters)
error:
    mov dword [0xb8000], 0x4f524f45
    mov dword [0xb8004], 0x4f3a4f52
    mov dword [0xb8008], 0x4f204f20
    mov dword [0xb800a], 0x4f204f20
    mov byte  [0xb800a], al
    mov byte  [0xb800c], ah
    hlt


; set up paging
; http://os.phil-opp.com/entering-longmode.html#set-up-identity-paging
; http://wiki.osdev.org/Paging
; http://pages.cs.wisc.edu/~remzi/OSTEP/vm-paging.pdf
; Identity map first 1GiB (0x200000 * 0x200) ???
; using 2MiB pages
set_up_page_tables:
    ; map first P4 entry to P3 table
    mov eax, page_table_p3
    or eax, 0b11 ; present & writable
    mov [page_table_p4], eax

    ; map first P3 entry to P2 table
    mov eax, page_table_p2
    or eax, 0b11 ; present & writable
    mov [page_table_p3], eax

    ; map each P2 entry to a huge 2MiB page
    mov ecx, 0         ; counter

.map_page_table_p2_loop:
    ; map ecx-th P2 entry to a huge page that starts at address 2MiB*ecx
    mov eax, 0x200000                   ; 2MiB
    mul ecx                             ; page[ecx] start address
    or eax, 0b10000011                  ; present & writable & huge
    mov [page_table_p2 + ecx * 8], eax  ; map entry

    inc ecx
    cmp ecx, 0x200                  ; is the whole P2 table is mapped?
    jne .map_page_table_p2_loop     ; next entry

    ; recursively map the last the last page in p4
    ; http://os.phil-opp.com/modifying-page-tables.html#implementation
    mov eax, page_table_p4
    or eax, 0b11 ; present + writable
    mov [page_table_p4 + 511 * 8], eax

    ; done
    ret

; enable_paging
; http://os.phil-opp.com/entering-longmode.html#enable-paging
; http://wiki.osdev.org/Paging#Enabling
enable_paging:
    ; load P4 to cr3 register (cpu uses this to access the P4 table)
    mov eax, page_table_p4
    mov cr3, eax

    ; enable PAE-flag in cr4 (Physical Address Extension)
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    ; set the long mode bit in the EFER MSR (model specific register)
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr

    ; enable paging in the cr0 register
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax

    ret

; constant data

; GDT (Global Descriptor Table)
tmp_gdt64:
    dq 0 ; zero entry
    dq (1<<44) | (1<<47) | (1<<41) | (1<<43) | (1<<53) ; code segment
    dq (1<<44) | (1<<47) | (1<<41) ; data segment
.pointer:   ; GDTR
    dw 8*3      ; size
    dq gdt      ; POINTER

times (0x400-($-$$)) db 0 ; fill two sectors
