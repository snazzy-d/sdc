module d.rt.eh;

import d.rt.dwarf;
import d.rt.unwind;

private enum ExceptionRegno = 0;
private enum SelectorRegno = 1;

private auto getExceptionClass() {
	ulong ec;
	
	auto s = "SDC\0D2\0\0";
	for(uint i = 0; i < s.length; i++) {
		ec = ec << 8 | s[i];
	}
	
	return ec;
}

enum ExceptionClass = getExceptionClass();

private Throwable inFlight;
private _Unwind_Exception ue;

void __sd_eh_delete(_Unwind_Reason_Code reason, _Unwind_Exception* exceptionObject) {
	inFlight = null;
}

/**
 * Throws a exception.
 */
extern(C) void __sd_eh_throw(Throwable t) {
	if(inFlight !is null) {
		// TODO: chain
	}
	
	inFlight = t;
	
	ue.exception_class = ExceptionClass;
	ue.exception_cleanup = &__sd_eh_delete;
	
	auto f = _Unwind_RaiseException(&ue);
	
	/+
	import core.stdc.stdlib, core.stdc.stdio;
	+/
	printf("FAILED TO RAISE EXCEPTION %i\n".ptr, f);
	exit(-1);
}

extern(C) _Unwind_Reason_Code __sd_eh_personality(
	int ver,
	_Unwind_Action actions,
	ulong exceptionClass,
	_Unwind_Exception* exceptionObject,
	_Unwind_Context* ctx,
) {
	if (ver != 1) {
		return _Unwind_Reason_Code.FATAL_PHASE1_ERROR;
	}
	
	ubyte* p = cast(ubyte*) _Unwind_GetLanguageSpecificData(ctx);
	if (p is null) {
		return _Unwind_Reason_Code.CONTINUE_UNWIND;
	}
	
	// XXX: GCC mention:
	// Shortcut for phase 2 found handler for domestic exception.
	// Consider adding this when it is understood :D
	
	// get the instruction pointer
    // will be used to find the right entry in the callsite_table
    // -1 because it will point past the last instruction
    auto ip = _Unwind_GetIP(ctx) - 1;
	// printf("ip:%p\n".ptr, ip);
	
	auto headers = parseLsdHeader(p, ctx);
	/+
	printf("start:\t%p\n".ptr, headers.start);
	printf("lpStart:\t%p\n".ptr, headers.lpStart);
	printf("typeTable:\t%p\n".ptr, headers.typeTable);
	printf("actionTable:\t%p\n".ptr, headers.actionTable);
	+/
	_Unwind_Ptr landingPad = null;
	const(ubyte)* actionPtr = null;
	
	while (p < headers.actionTable) {
		auto start  = read_encoded(p, ctx, headers.callSiteEncoding);
		auto len    = read_encoded(p, ctx, headers.callSiteEncoding);
		auto lp     = read_encoded(p, ctx, headers.callSiteEncoding);
		auto action = read_uleb128(p);
		
		// printf("start: %ld\tlen: %ld\tlp: %ld\n".ptr, start, len, lp);
		
		// The table is sorted, so if we've passed the ip, stop.
		if (ip < headers.start + start) {
			return _Unwind_Reason_Code.CONTINUE_UNWIND;
		}
		
		// We found something !
		if (ip < headers.start + start + len) {
			if (lp) {
				landingPad = headers.lpStart + lp;
			}
			
			if (action) {
				actionPtr = headers.actionTable + action - 1;
			}
			
			break;
		}
	}
	
	if (landingPad is null) {
		return _Unwind_Reason_Code.CONTINUE_UNWIND;
	}
	
	// We have landing pad, but no action. This is a cleanup.
	if (actionPtr is null) {
		return setupCleanup(ctx, actions, landingPad, exceptionObject);
	}
	
	// We do not catch foreign exceptions and if we have to force unwind.
	bool doCatch = (exceptionClass == ExceptionClass) && !(actions & _Unwind_Action.FORCE_UNWIND);
	
	ptrdiff_t nextOffset = -1;
	while(nextOffset) {
		auto switchval = read_sleb128(actionPtr);
		auto prev = actionPtr;
		nextOffset = read_sleb128(actionPtr);
		
		if (switchval < 0) {
			printf("FILTER NOT SUPPORTED\n".ptr);
			exit(-1);
		}
		
		if (switchval == 0) {
			// XXX: Ensure that nextOffset is 0 as cleanup must come last.
			return setupCleanup(ctx, actions, landingPad, exceptionObject);
		}
		
		p = headers.typeTable - switchval * headers.typeEncoding.getSize();
		auto tmp = read_encoded(p, ctx, headers.typeEncoding);
		auto candidate = *(cast(ClassInfo*) &tmp);

		// Null is a special case that always catches.		
		if (candidate !is null && !doCatch) {
			continue;
		}
		
		// XXX: We don't need to recompute all downcast every time.
		if (__sd_class_downcast(inFlight, candidate) !is null) {
			return setupCatch(ctx, actions, switchval, landingPad, exceptionObject);
		}
		
		actionPtr = prev + nextOffset;
	}
	
	// No action found.
	return _Unwind_Reason_Code.CONTINUE_UNWIND;
}

private _Unwind_Reason_Code setupCatch(_Unwind_Context* ctx, _Unwind_Action actions, ptrdiff_t switchval, _Unwind_Ptr landingPad, _Unwind_Exception* exceptionObject) {
	if (actions & _Unwind_Action.SEARCH_PHASE) {
		return _Unwind_Reason_Code.HANDLER_FOUND;
	}
	
	if (actions & _Unwind_Action.CLEANUP_PHASE) {
		_Unwind_SetGR(ctx, ExceptionRegno, *(cast(_Unwind_Word*) &exceptionObject));
		_Unwind_SetGR(ctx, SelectorRegno, switchval);
		_Unwind_SetIP(ctx, landingPad);
		
		return _Unwind_Reason_Code.INSTALL_CONTEXT;
    }
	
    return _Unwind_Reason_Code.FATAL_PHASE2_ERROR;
}

_Unwind_Reason_Code setupCleanup(_Unwind_Context* ctx, _Unwind_Action actions, _Unwind_Ptr landingPad, _Unwind_Exception* exceptionObject) {
	// if we're merely in search phase, continue
	if (actions & _Unwind_Action.SEARCH_PHASE) {
		return _Unwind_Reason_Code.CONTINUE_UNWIND;
	}
	
	_Unwind_SetGR(ctx, ExceptionRegno, *(cast(_Unwind_Word*) &exceptionObject));
	_Unwind_SetGR(ctx, SelectorRegno, 0);
	_Unwind_SetIP(ctx, landingPad);
	
	return _Unwind_Reason_Code.INSTALL_CONTEXT;
}

