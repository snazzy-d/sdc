global __sd_gc_push_registers

section .text
__sd_gc_push_registers:
; We could actually make things faster by not pushing the base and stack pointers
; but this is not performance critical and need to be rock solid.
; For some reason, clang seems to use rbp, but gcc rbx (?) so we will do it
; the clang way and push rbx to the stack as a parameter.
	push rbp
	mov rbp, rsp
; Not using push to make sure I not messup with stack alignement.
; Also sub + mov is usually faster than push (not that it matter much here).
	sub	rsp, 48
; Register r12 to r15 are callee saved so can have live values.
; Other registers are trash or already saved on the stack.
	mov	[rbp - 8], rbx
	mov	[rbp - 16], r12
	mov	[rbp - 24], r13
	mov	[rbp - 32], r14
	mov	[rbp - 40], r15
; This method is passed a delegate. rdi contains the context as a first argument
; and rsi, the second argument is the function pointer. rdi do not need any special
; threatement as it is also the first argument when calling the delegate.
	call rsi
; rsp and rbp are the only callee saved register we modified, no need to restore others.
	mov rsp, rbp
	pop rbp
	ret
