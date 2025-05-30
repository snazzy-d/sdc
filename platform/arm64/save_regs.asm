.global ___sd_gc_push_registers

.section __TEXT,__text

___sd_gc_push_registers:
; Standard call ABI. x29 is the frame pointer and x30 the link register.
	sub     sp, sp, #96
	stp     x29, x30, [sp, #80]
	add     x29, sp, #80
; Registers x19-28 are callee saved.
	stp     x19, x20, [sp, #0]
	stp     x21, x22, [sp, #16]
	stp     x23, x24, [sp, #32]
	stp     x25, x26, [sp, #48]
	stp     x27, x28, [sp, #64]
; This method is passed a delegate. x0 contains the context as a first argument
; and x1, the second argument is the function pointer. x0 do not need any special
; threatement as it is also the first argument when calling the delegate.
	blr x1
; Restore the frame pointer and link register and return.
	ldp     x29, x30, [sp, #80]
	add     sp, sp, #96
	ret
