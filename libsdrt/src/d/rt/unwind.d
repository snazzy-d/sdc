module d.rt.unwind;

alias _Unwind_Ptr = void*;
alias _Unwind_Word = size_t;

extern(C):

enum _Unwind_Reason_Code {
	NO_REASON                = 0,
	FOREIGN_EXCEPTION_CAUGHT = 1,
	FATAL_PHASE2_ERROR       = 2,
	FATAL_PHASE1_ERROR       = 3,
	NORMAL_STOP              = 4,
	END_OF_STACK             = 5,
	HANDLER_FOUND            = 6,
	INSTALL_CONTEXT          = 7,
	CONTINUE_UNWIND          = 8,
}

enum _Unwind_Action {
	SEARCH_PHASE  = 1,
	CLEANUP_PHASE = 2,
	HANDLER_FRAME = 4,
	FORCE_UNWIND  = 8,
	END_OF_STACK  = 16,
}

// FIXME: Make this accept extern(C)
alias _Unwind_Exception_Cleanup_Fn = void function(_Unwind_Reason_Code, _Unwind_Exception*);

// XXX The IA-64 ABI says that this structure must be double-word aligned.
// We probably don't follow that.
struct _Unwind_Exception {
	ulong exception_class;
	_Unwind_Exception_Cleanup_Fn exception_cleanup;
	
	_Unwind_Word private_1;
	_Unwind_Word private_2;
}

struct _Unwind_Context {}

_Unwind_Reason_Code _Unwind_RaiseException(_Unwind_Exception*);
void _Unwind_Resume(_Unwind_Exception*);
void _Unwind_DeleteException (_Unwind_Exception*);

_Unwind_Ptr _Unwind_GetLanguageSpecificData(_Unwind_Context* ctx);

_Unwind_Ptr _Unwind_GetRegionStart(_Unwind_Context* ctx);
_Unwind_Ptr _Unwind_GetTextRelBase(_Unwind_Context* ctx);
_Unwind_Ptr _Unwind_GetDataRelBase(_Unwind_Context* ctx);

_Unwind_Word _Unwind_GetGR(_Unwind_Context* ctx, int i);
_Unwind_Ptr _Unwind_GetIP(_Unwind_Context  *ctx);

void _Unwind_SetGR(_Unwind_Context* ctx, int i, _Unwind_Word n);
void _Unwind_SetIP(_Unwind_Context* ctx, _Unwind_Ptr new_value);

