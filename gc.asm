default rel

struc	heap_obj
	heap_obj_type: resb 1
endstruc

struc    string_matrix
	 			resb 1 ; matrix_type
         string_matrix_data:    ; contiguous data
endstruc

struc    fixed_matrix
	 			resb 1 ; matrix_type
         fixed_matrix_rows:     resd 1 ; 64 bytes
         fixed_matrix_cols:     resd 1 ;
         fixed_matrix_data:     ; contiguous data
endstruc

struc    moved_heap_obj
	 			resb 1 ; matrix_type
         moved_heap_obj_newptr: ; new ptr
endstruc

struc    pair
	 			resb 1 ; matrix_type
         pair_first: 		resq 1; ptr
         pair_second: 		resq 1; ptr
         pair_object_size:		; empty
endstruc

%define TYPE_FIXED_MATRIX 0
%define TYPE_STRING_MATRIX 1
%define TYPE_PAIR 2
%define TYPE_MOVED 3

section .data

; fixed_matrix_size:	dd $ - fixed_matrix

cursor_msg:		db "Heap Offset %d", 10, 0
type_fixed_matrix_msg:	db "[FIXED_MATRIX]", 10, 0
rows_msg:		db ":rows=%d", 10, 0
cols_msg:		db ":cols=%d", 10, 0
type_moved_object_msg:	db "[MOVED_OBJECT]", 10, 0
newptr_msg:		db ":newptr=%d", 10, 0
type_pair_msg:	        db "[PAIR]", 10, 0
pairptr_msg:		db ":pairptr=%d", 10, 0
collect_msg:		db "....collecting.....", 10, 0
error_msg:		db "ERROR, didn't expect byte %d", 10, 0

flipper:	db 0
gcsec1ptr:	dq gcsec1
gcsec2ptr:	dq gcsec2

section .bss

gcsec1:		resq 10000
gcsec2:		resq 10000
overflow:	; empty. Just address the overflow point

section .text

global start
extern malloc
extern _printf
extern _exit
extern _memcpy

; code at last yaaay!

start:
	push rbp
	mov rbp, rsp
	sub rsp, 24 ; align stack & reserve

	mov rdi, 10
	mov rsi, 8
	call alloc_fixed_matrix

	mov rdi, 12
	mov rsi, 16
	call alloc_fixed_matrix
	mov [rsp+8], rax

	mov rdi, 6
	mov rsi, 4
	call alloc_fixed_matrix
	mov [rsp+16], rax

	mov rdi, [rsp+8]
	mov rsi, [rsp+16]
	call alloc_pair
	mov [rsp+24], rax
	mov rdi, rax
	mov rsi, [rsp+8]
	call alloc_pair
	mov [rsp], rax

	call print_heap

	mov rdi, [rsp]
	call collect

	call print_heap

	mov rdi, 12
	mov rsi, 16
	call alloc_fixed_matrix
	mov [rsp+16], rax

	call print_heap

	mov rdi, [rsp+16]
	call collect

	call print_heap

	add rsp, 24

	mov rax, 0x2000001
	xor rdi, rdi
	syscall

print_heap:
	push r13
	push r14
	sub rsp, 8
	call get_heap_ptr
	mov r13, rax
	call get_heap_cursor
	mov r14, rax
print_heap_next:
	mov rdi, cursor_msg
	mov rsi, r13
	call _printf
	cmp byte [r13], TYPE_FIXED_MATRIX
	je print_fixed_matrix
	cmp byte [r13], TYPE_MOVED
	je print_moved_object
	cmp byte [r13], TYPE_PAIR
	je print_pair
	jne print_heap_error
print_fixed_matrix:
	mov rdi, type_fixed_matrix_msg
	call _printf
	mov rdi, rows_msg
	xor rsi, rsi
	mov esi, dword [ r13 + fixed_matrix_rows ]
	call _printf
	mov rdi, cols_msg
	xor rsi, rsi
	mov esi, dword [ r13 + fixed_matrix_cols ]
	call _printf
	mov rdi, r13
	call sizeof_fixed_matrix
	add r13, rax
	jmp print_heap_continue
print_moved_object:
	mov rdi, type_moved_object_msg
	call _printf
	mov rdi, newptr_msg
	mov rsi, [r13 + moved_heap_obj_newptr]
	call _printf
	mov r13, r14
	jmp print_heap_continue
print_pair:
	mov rdi, type_pair_msg
	call _printf
	mov rdi, pairptr_msg
	mov rsi, [r13 + pair_first]
	call _printf
	mov rdi, pairptr_msg
	mov rsi, [r13 + pair_second]
	call _printf
	add r13, pair_object_size
	jmp print_heap_continue
print_heap_continue:
	cmp r13, r14
	jl print_heap_next
	add rsp, 8
	pop r13
	pop r14
	ret
print_heap_error:
	mov rdi, error_msg
	xor rax, rax
	mov al, [r13]
	mov rsi, rax
	call _printf
	add rsp, 8
	pop r13
	pop r14
	ret

collect:
	push rdi
	mov rdi, collect_msg
	call _printf
	pop rdi
	sub rsp, 8 ; stack alignment
	call collect_step
	add rsp, 8
	jmp heap_flip
collect_step:
	sub rsp, 24 ; 2 vars, aligned
	mov [rsp+8], rdi ; save original ptr
	cmp byte [rdi], TYPE_FIXED_MATRIX
	je collect_fixed_matrix
	cmp byte [rdi], TYPE_PAIR
	je collect_pair
	cmp byte [rdi], TYPE_MOVED
	je collect_moved_object
	jne print_heap_error ; I guess this is a more general error...
collect_fixed_matrix:
	call sizeof_fixed_matrix
	mov [rsp+16], rax ; save size
	mov rdx, rax
	call get_opposing_heap_cursor
	mov rsi, [rsp+8] ; original ptr
	mov rdi, rax
	call _memcpy
	mov rdi, [rsp+16] ; size
	call opposing_heap_reserve
	jmp collect_mark_moved
collect_moved_object:
	; nothing to do but return the new pointer
	mov rax, [rdi+moved_heap_obj_newptr]
	add rsp, 24
	ret
collect_pair:
	mov rdx, pair_object_size
	call get_opposing_heap_cursor
	mov rsi, [rsp+8] ; original ptr
	mov rdi, rax
	call _memcpy
	mov rdi, pair_object_size
	call opposing_heap_reserve
	mov rdi, [rsp+8] ; original ptr
	mov byte [rdi], TYPE_MOVED
	mov [rdi + moved_heap_obj_newptr], rax
	mov [rsp+8], rax ; back up new ptr
	; now copy the items in the pair
	mov rdi, [rax + pair_first] ; collect from here
	call collect_step
	mov rdi, [rsp+8] ; bring up new ptr
	mov [rdi + pair_first], rax ; move moved pair ptr
	mov rdi, [rdi + pair_second] ; collect from here
	call collect_step
	mov rdi, [rsp+8] ; bring up new ptr
	mov [rdi + pair_second], rax ; move moved pair ptr
	mov rax, rdi ; still return new ptr for the pair
	add rsp, 24
	ret
collect_mark_moved:
	mov rdi, [rsp+8] ; original ptr
	mov byte [rdi], TYPE_MOVED
	mov [rdi + moved_heap_obj_newptr], rax
	add rsp, 24
	ret

sizeof_fixed_matrix:
	mov rax, 20
	xor rsi, rsi
	mov esi, dword [ rdi + fixed_matrix_rows ]
	xor rcx, rcx
	mov ecx, dword [ rdi + fixed_matrix_cols ]
	imul rcx, rsi
	imul rcx, 8
	add rax, rcx
	ret

alloc_fixed_matrix:
	push rdi
	push rsi
	imul rdi, rsi ; calc sizeof in rdi
	lea rdi, [rdi*8+20]
	call heap_reserve ; reserve it & get addr
	pop rsi
	pop rdi
	mov byte [rax], TYPE_FIXED_MATRIX
	mov [rax + fixed_matrix_rows], edi
	mov [rax + fixed_matrix_cols], esi
	ret

alloc_pair:
	push rdi
	push rsi
	mov rdi, pair_object_size
	call heap_reserve ; reserve it & get addr
	pop rsi
	pop rdi
	mov byte [rax], TYPE_PAIR
	mov [rax + pair_first], rdi
	mov [rax + pair_second], rsi
	ret

alloc_string_matrix:
	mov rdi, 20
	call heap_reserve
	mov byte [rax], 0 ; null byte
	ret

get_heap_cursor:
	call get_heap_cursor_ptr
	mov rax, [rax]
	ret

get_heap_cursor_ptr:
	cmp byte [flipper], 0
	jne get_heap_cursor_ptr_use_gcsec2
	mov rax, gcsec1ptr
	ret
get_heap_cursor_ptr_use_gcsec2:
	mov rax, gcsec2ptr
	ret

get_opposing_heap_cursor:
	call get_opposing_heap_cursor_ptr
	mov rax, [rax]
	ret

get_opposing_heap_cursor_ptr:
	cmp byte [flipper], 1
	jne get_opposing_heap_cursor_ptr_use_gcsec2
	mov rax, gcsec1ptr
	ret
get_opposing_heap_cursor_ptr_use_gcsec2:
	mov rax, gcsec2ptr
	ret

get_heap_ptr:
	cmp byte [flipper], 0
	jne get_heap_ptr_use_gcsec2
	mov rax, gcsec1
	ret
get_heap_ptr_use_gcsec2:
	mov rax, gcsec2
	ret

heap_flip:
	call get_heap_ptr
	mov rdi, rax
	call get_heap_cursor_ptr
	mov [rax], rdi
	mov rax, 0
	mov al, [flipper]
	xor al, 0x01
	mov [flipper], al
	ret

heap_reserve:
	push rdi
	call get_heap_cursor_ptr
	pop rdi
	mov rcx, rax
	mov rax, [rax]
	add rdi, rax
	mov [rcx], rdi
	ret

opposing_heap_reserve:
	push rdi
	call get_opposing_heap_cursor_ptr
	pop rdi
	mov rcx, rax
	mov rax, [rax]
	add rdi, rax
	mov [rcx], rdi
	ret
