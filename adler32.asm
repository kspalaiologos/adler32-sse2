
; A fast (~13GiB/s) Adler32-derivative checksum program as a 1015 byte ELF file.
; Written for the purposes of being included in Alpha64.
; I decided to release this particular part of Alpha64 to the general public,
; as it is my own contribution to an existing idea that has been already widely
; researched before me.                            ~ Kamila Szewczyk, Apr 2022

format ELF64 executable
use64

entry _start

; Compute x / 0xFFF1. Consider K = (2 ^ N) / 0xFFF1, for some value of N.
; Now, to compute X / 0xFFF1 is to compute X * K, and shift it N positions to the right.
; Finally, compute `x - trunc(edx = x / 0xFFF1) * 0xFFF1`, yielding the desired remainder.
; K = 0x80078071 used throughout the program has been devised from N=47, since
; N=32+M, where M is the smallest integer where:
;   0xFFF1 <= (2^(32 + M) mod 0xFFF1) + 2^M, or alternatively
;   0xFFF1 <= 0xFFF1 * floor(2^(M+32) / 0xFFF1) + 2^M + 2^(M+32).
macro mod0xFFF1 K,N,src,reg {
    mov e#reg, src
    imul r#reg, K
    shr r#reg, N
    imul e#reg, e#reg, 0xFFF1
    sub src, e#reg
}

; Compute the adler32 checksum.
; Input:
; - EDI => initial checksum value.
; - RCX => input buffer
; - RDX => input size
adler32:
    ; eax = high(edi), esi = low(edi)
    mov eax, edi
    shr eax, 16
    movzx esi, di
    ; load the pointer to the end of the data
    lea r10, [rcx + rdx]
    ; the data needs to be processed byte-wise until desired alignment is reached.
    ; if the input size is 0, terminate the algorithm as there is nothing to checksum.
    ; The value of the initial checksum value will be glued back together and returned.
    test rdx, rdx
    je .terminate
    ; Check if the lowest two bits of the input pointer are aligned to 16 bytes.
    test cl, 15
    jne .unaligned
.aligned:
    ; If we have reached this point, the data is aligned so we can process it using vector operations.
    ; Compute the new end taking on the account the possibility that some of the data might have been processed already
    ; and it will be processed afterwards. end -= (end - p) & 0x1F to adjust for the amount of bytes per iteration (32)
    mov rdx, r10
    mov r8, r10
    sub rdx, rcx
    and edx, 31
    sub r8, rdx
    ; Not even one iteration of the vectorised algorithm is guaranteed. If the data isn't large enough to be processed
    ; in a chunk (less than 32 bytes), skip to the bytewise checksumming part.
    cmp rcx, r8
    je .process_remaining
    ; Load a few constants that will be used throughout the algorithm to save a few CPU cycles during the loop.
    ; The value of K for the mod0xFFF1 macro.
    mov r9d, 0x80078071
    ; The initial vector values.
    pxor xmm1, xmm1
    movdqu xmm8, [.V32]
    movdqu xmm7, [.V24]
    movdqu xmm6, [.V16]
    movdqu xmm5, [.V8]
.chunk_loop:
    ; Compute the chunk size. It's either the smaller of two values - the amount of data to process in total, or 4096 (chunk * 8).
    mov rdx, r8
    sub rdx, rcx
    mov edi, 4096
    cmp rdx, rdi
    cmova rdx, rdi
    ; Clear the vector registers.
    ; XMM0 => sum of bytes
    ; XMM13 => sum of low bytes
    ; XMM4, XMM11, XMM10, XMM9 => 16-bit counters for byte sums. Each accumulates a
    ; number and the dot product will need to be computed to add the resulting
    ; high bytes
    pxor xmm0, xmm0
    pxor xmm13, xmm13

    pxor xmm4, xmm4
    pxor xmm11, xmm11
    pxor xmm10, xmm10
    pxor xmm9, xmm9
    ; Subtract chunk size modulo the amount of bytes per iteration (32).
    mov rdi, rdx
    mov rdx, rcx
    and rdi, 0xFFFFFFFFFFFFFFE0
    ; Define the end of the chunk as the input pointer + chunk size.
    add rcx, rdi
    ; high += low * chunk_size
    imul edi, esi
    add edi, eax
.inner_chunk_loop:
    ; Accumulate previous counters to current counters and load a new batch
    ; of data using aligned moves.
    movdqa xmm3, [rdx]
    movdqa xmm2, [rdx + 16]
    paddd xmm13, xmm0
    ; Use `PSADBW` to add the bytes horizontally with 8 bytes per sum.
    ; Add the sums to XMM0.
    movdqa xmm12, xmm3
    psadbw xmm12, xmm1
    paddd xmm12, xmm0

    movdqa xmm0, xmm2
    psadbw xmm0, xmm1
    paddd xmm0, xmm12
    ; Accumulate the data into the additional counters too.
    ; Unpack high and low parts and add them to the respective counter vector.
    movdqa xmm12, xmm3
    punpckhbw xmm3, xmm1
    punpcklbw xmm12, xmm1
    paddw xmm11, xmm3
    paddw xmm4, xmm12
    
    movdqa xmm3, xmm2
    punpckhbw xmm2, xmm1
    punpcklbw xmm3, xmm1
    paddw xmm9, xmm2
    paddw xmm10, xmm3
    ; Loop until the end of the chunk has been reached.
    add rdx, 32
    cmp rcx, rdx
    jne .inner_chunk_loop
    ; Finish calculating the XMM13 and XMM0 counter. Update the values of high and low (respectively) checksum elements.
    pshufd xmm3, xmm0, 0x31
    paddd xmm0, xmm3
    pshufd xmm3, xmm0, 0x2
    paddd xmm0, xmm3
    movd eax, xmm0
    add esi, eax
    mod0xFFF1 r9, 47, esi, ax

    pslld xmm13, 5
    movdqa xmm2, xmm4
    pmaddwd xmm2, xmm8
    paddd xmm2, xmm13
    pmaddwd xmm11, xmm7
    paddd xmm2, xmm11
    pmaddwd xmm10, xmm6
    paddd xmm2, xmm10
    pmaddwd xmm9, xmm5
    paddd xmm2, xmm9

    pshufd xmm0, xmm2, 0x31
    paddd xmm0, xmm2
    pshufd xmm2, xmm0, 0x2
    paddd xmm0, xmm2
    movd eax, xmm0
    add eax, edi
    mod0xFFF1 r9, 47, eax, dx

    ; Loop while there is data left.
    cmp r8, rcx
    jne .chunk_loop
.process_remaining:
    ; Check if the input pointer has reached the end already.
    cmp r10, rcx
    je .terminate
.process_bytewise:
    ; The contents of this loop are mirrored in the bytewise checksumming part to get a chunk of aligned data.
    movzx edx, BYTE [rcx]
    inc rcx
    add esi, edx
    add eax, esi
    cmp r10, rcx
    jne .process_bytewise
    ; The process of computing the remainder of the high and low parts by 0xFFF1. Explanation below.
    mov edi, 0x80078071
    mod0xFFF1 rdi, 47, esi, dx
    mod0xFFF1 rdi, 47, eax, dx
.terminate:
    ; Glue together eax and esi (respectively higher and lower bits of the resulting checksum) and yield the result.
    sal eax, 16
    or eax, esi
    ret
.recheck_alignment:
    ; Check lowest two bits of the input pointer to determine whether it's aligned to 16 bits.
    test cl, 15
    je .now_aligned
.unaligned:
    ; Process unaligned data. Perform byte-wise checksumming until alignment is reached.
    ; low += *input++.
    movzx edx, BYTE [rcx]
    inc rcx
    add esi, edx
    ; high += low
    add eax, esi
    cmp r10, rcx
    jne .recheck_alignment
.now_aligned:
    ; Compute the remainder of the high and low parts of the checksum when dividing by 0xFFF1.
    mov edi, 0x80078071
    mod0xFFF1 rdi, 47, esi, dx
    mod0xFFF1 rdi, 47, eax, dx
    ; The data is aligned now.
    jmp .aligned

.V32: dw 32, 31, 30, 29, 28, 27, 26, 25
.V24: dw 24, 23, 22, 21, 20, 19, 18, 17
.V16: dw 16, 15, 14, 13, 12, 11, 10,  9
.V8:  dw  8,  7,  6,  5,  4,  3,  2,  1

; stat structure buffer.
sb:     times 144 db 0

; System interface on x64 Linux works as follows:
; eax - syscall_number
; Parameters:
; 1st  2nd  3rd  4th  5th  6th
; rdi  rsi  rdx  r10  r8   r9

; The system call numbers (eax values) used by the driver code.
open equ 2
mmap equ 9
fstat equ 5
exit equ 60
write equ 1

; The entry point to test the checksum algorithm.
; The application takes a single CLI argument with the file to checksum.
_start:
    ; Section 3.4.1 of the ABI document (Initial Stack and Register State) contains figure 3.9,
    ; which is a table describing initial stack layout. According to the the layout, the top of the stack
    ; is the argument count, followed by pointers to argument strings. As I am not interested in the argument
    ; count and the first argument, I pop them off. The remaining element is the file name and it's saved in
    ; rdi, which will be used for a syscall soon.
    pop rdi
    pop rdi
    pop rdi
    ; open($rdi, O_RDWR); O_RDWR = open = 2
    mov eax, open
    mov esi, eax
    syscall
    ; Preserve the file descriptor over the fstat call.
    push rax
    ; fstat($eax, sb) to query the file size
    mov esi, sb
    mov rdi, rax
    mov eax, fstat
    syscall
    ; mmap(0, *(uint64_t *) sb + 48, PROT_READ = 1, MAP_SHARED = 1, fd, 0)
    ; Note: Offset 48 into the stat structure is the file size, but since FASM does not supply
    ;       POSIX headers, I had to perform this calculation myself. Check `man 2 lstat`.
    pop r8
    xor r9d, r9d
    xor edi, edi
    mov eax, mmap
    mov edx, 1
    mov r10d, edx
    mov rsi, [sb + 48]
    syscall
    ; Compute the adler32 checksum.
    mov rdx, rsi
    mov rcx, rax
    xor eax, eax
    mov edi, 1
    call adler32
    ; Stringify the checksum to decimal.
    ; XXX: This code could be modified to display the checksum in hexadecimal or as-is, as binary data.
    ; Reserve a 16 byte buffer on the stack.
    mov rbp, rsp
    sub rbp, 16
    mov edi, 10
    mov esi, eax
    mov rcx, 14
.stringify_loop:
    ; Load the input number to eax.
    mov eax, esi
    xor edx, edx
    ; eax = eax / edi
    ; edx = eax % edi
    div edi
    ; Add 48 (ASCII 0) to turn the remainder into a digit.
    add edx, 48
    ; Store the digit in the output buffer.
    mov BYTE [rbp + rcx], dl
    ; Preserve the previous value and replace it with the new one.
    mov edx, esi
    mov esi, eax
    ; Preserve the counter and decrement it.
    mov rax, rcx
    dec rcx
    ; Loop if the previous value is > 9 (=> if there are more digits left).
    cmp edx, 9
    ja .stringify_loop
    ; Otherwise: print the value.
    ; write(0, buf + rax, 16 - rax)
    lea rsi, [rbp + rax]
    xor edi, edi
    mov edx, 16
    sub edx, eax
    mov eax, write
    syscall
    ; Quit the program. `ret` obviously won't work.
    mov eax, exit
    syscall
