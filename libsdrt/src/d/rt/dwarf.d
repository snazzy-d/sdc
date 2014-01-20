module d.rt.dwarf;

import d.rt.unwind;

alias uintptr_t = size_t;

enum Format {
	Absptr  = 0x00,
	Uleb128 = 0x01,
	Udata2  = 0x02, // unsigned 2-byte
	Udata4  = 0x03,
	Udata8  = 0x04,
	Sleb128 = 0x09,
	Sdata2  = 0x0a,
	Sdata4  = 0x0b,
	Sdata8  = 0x0c,
}

enum Base {
	Absptr  = 0x00,
	Pcrel   = 0x10, // relative to program counter
	Textrel = 0x20, // relative to .text
	Datarel = 0x30, // relative to .got or .eh_frame_hdr
	Funcrel = 0x40, // relative to beginning of function
	Aligned = 0x50, // is an aligned void*
}

struct Encoding {
	private ubyte encoding;
	
	enum Omit = 0xff;
	enum Indirect = 0x80;
	
	this(ubyte encoding) {
		this.encoding = encoding;
	}
	
	Format getFormat() {
		return cast(Format) (encoding & 0x0f);
	}
	
	Base getBase() {
		return cast(Base) (encoding & 0x70);
	}
	
	bool isIndirect() {
		return !!(encoding & Indirect);
	}
	
	bool isOmit() {
		return encoding == Omit;
	}
	
	uint getSize() {
		if (isOmit()) {
			return 0;
		}
		
		switch(encoding & 0x07) {
			case Format.Absptr:
				return size_t.sizeof;
			
			case Format.Udata2:
				return 2;
			
			case Format.Udata4:
				return 4;
			
			case Format.Udata8:
				return 8;
			
			default:
				assert(0);
		}
	}
}

uintptr_t read_uleb128(ref const(ubyte)* p) {
	uintptr_t result = 0;
	uint shift = 0;
	ubyte b;
	
	do {
		b = *p++;
		result |= (cast(uintptr_t) (b & 0x7f) << shift);
		shift += 7;
	} while(b & 0x80);
	
	return result;
}

ptrdiff_t read_sleb128(ref const(ubyte)* p) {
	uint shift = 0;
	ubyte b;
	ptrdiff_t result = 0;
	
	do {
		b = *p++;
		result |= (cast(long) (b & 0x7f) << shift);
		shift += 7;
	} while(b & 0x80);
	
	// Sign-extend if the value is negative.
	if(shift < 8 * result.sizeof && (b & 0x40) != 0) {
		result |= -(1L << shift);
	}
	
	return result;
}

ubyte read_ubyte(ref const(ubyte)* p) {
	return *p++;
}

uintptr_t read_encoded(ref const(ubyte)* p, _Unwind_Context* ctx, Encoding encoding) {
	// TODO: Implement cast from pointer to integral.
	auto pcrel = *(cast(uintptr_t*) &p);
	
	uintptr_t result;
	
	switch (encoding.getFormat()) {
		case Format.Uleb128:
			result = read_uleb128(p);
			break;
		
		case Format.Sleb128:
			result = read_sleb128(p);
			break;
		
		case Format.Absptr:
			result = *(cast(uintptr_t*)p);
			p += uintptr_t.sizeof;
			break;
		
		case Format.Udata2:
			result = *(cast(ushort*)p);
			p += ushort.sizeof;
			break;
		
		case Format.Udata4:
			result = *(cast(uint*)p);
			p += uint.sizeof;
			break;
		
		case Format.Udata8:
			result = cast(uintptr_t)*(cast(ulong*)p);
			p += ulong.sizeof;
			break;
		
		case Format.Sdata2:
			result = cast(uintptr_t)*(cast(short*)p);
			p += short.sizeof;
			break;
		
		case Format.Sdata4:
			result = cast(uintptr_t)*(cast(int*)p);
			p += int.sizeof;
			break;
		
		case Format.Sdata8:
			result = cast(uintptr_t)*(cast(long*)p);
			p += long.sizeof;
			break;
		
		default:
			printf("FORMAT NOT SUPPORTED %d\n".ptr, encoding.getFormat());
			exit(-1);
	}
	
	switch(encoding.getBase()) {
		case Base.Absptr:
		case Base.Aligned:
			break;
		
		case Base.Pcrel:
			result += pcrel;
		
		case Base.Textrel:
			auto txt = _Unwind_GetTextRelBase(ctx);
			result += *(cast(uintptr_t*) &txt);
			break;
		
		case Base.Datarel:
			auto data = _Unwind_GetDataRelBase(ctx);
			result += *(cast(uintptr_t*) &data);
			break;
		
		case Base.Funcrel:
			auto region = _Unwind_GetRegionStart(ctx);
			result += *(cast(uintptr_t*) &region);
			break;
		
		default:
			printf("BASE NOT SUPPORTED %d\n".ptr, encoding.getBase());
			exit(-1);
	}
	
	if (encoding.isIndirect()) {
		// result = *(_Unwind_Internal_Ptr *) result;
	}
	
	return result;
}

struct LsdHeaderInfo {
	_Unwind_Ptr start;
	_Unwind_Ptr lpStart;
	
	Encoding callSiteEncoding;
	Encoding typeEncoding;
	
	const(ubyte)* typeTable;
	const(ubyte)* actionTable;
}

auto parseLsdHeader(ref const(ubyte)* p, _Unwind_Context* ctx) {
	LsdHeaderInfo infos;
	
	// infos.start = ctx ? _Unwind_GetRegionStart(ctx) : null;
	if (ctx !is null) {
		infos.start = _Unwind_GetRegionStart(ctx);
	}
	
	auto encoding = Encoding(*p++);
	/+
	info.lpStart = encoding.isOmit()
		? infos.start
		: read_encoded_value(p, ctx, encoding);
	+/
	if (encoding.isOmit()) {
		infos.lpStart = infos.start;
	} else {
		auto encoded = read_encoded(p, ctx, encoding);
		infos.lpStart = *(cast(void**) &encoded);
	}
	
	infos.typeEncoding = Encoding(*p++);
	if (!infos.typeEncoding.isOmit()) {
		auto tmp = read_uleb128(p);
		infos.typeTable = p + tmp;
	}
	
	infos.callSiteEncoding = Encoding(*p++);
	auto tmp = read_uleb128(p);
	infos.actionTable = p + tmp;
	
	return infos;
}

