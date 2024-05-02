module sdc.intrinsics;

bool expect(bool v, bool e) {
	return v;
}

bool likely(T)(T val) {
	return expect(cast(bool) val, true);
}

bool unlikely(T)(T val) {
	return expect(cast(bool) val, false);
}

void* alloca(size_t size);

ubyte popCount(ubyte n);
ushort popCount(ushort n);
uint popCount(uint n);
ulong popCount(ulong n);

ubyte countLeadingZeros(ubyte n);
ushort countLeadingZeros(ushort n);
uint countLeadingZeros(uint n);
ulong countLeadingZeros(ulong n);

ubyte countTrailingZeros(ubyte n);
ushort countTrailingZeros(ushort n);
uint countTrailingZeros(uint n);
ulong countTrailingZeros(ulong n);

ushort bswap(ushort n);
uint bswap(uint n);
ulong bswap(ulong n);

ubyte fetchAdd(ubyte* ptr, ubyte value);
ushort fetchAdd(ushort* ptr, ushort value);
uint fetchAdd(uint* ptr, uint value);
ulong fetchAdd(ulong* ptr, ulong value);

ubyte fetchSub(ubyte* ptr, ubyte value);
ushort fetchSub(ushort* ptr, ushort value);
uint fetchSub(uint* ptr, uint value);
ulong fetchSub(ulong* ptr, ulong value);

ubyte fetchAnd(ubyte* ptr, ubyte value);
ushort fetchAnd(ushort* ptr, ushort value);
uint fetchAnd(uint* ptr, uint value);
ulong fetchAnd(ulong* ptr, ulong value);

ubyte fetchOr(ubyte* ptr, ubyte value);
ushort fetchOr(ushort* ptr, ushort value);
uint fetchOr(uint* ptr, uint value);
ulong fetchOr(ulong* ptr, ulong value);

ubyte fetchXor(ubyte* ptr, ubyte value);
ushort fetchXor(ushort* ptr, ushort value);
uint fetchXor(uint* ptr, uint value);
ulong fetchXor(ulong* ptr, ulong value);

struct CompareAndSwapResult(T) {
	T value;
	bool success;
}

CompareAndSwapResult!ubyte cas(ubyte* ptr, ubyte old, ubyte val);
CompareAndSwapResult!ushort cas(ushort* ptr, ushort old, ushort val);
CompareAndSwapResult!uint cas(uint* ptr, uint old, uint val);
CompareAndSwapResult!ulong cas(ulong* ptr, ulong old, ulong val);

CompareAndSwapResult!ubyte casWeak(ubyte* ptr, ubyte old, ubyte val);
CompareAndSwapResult!ushort casWeak(ushort* ptr, ushort old, ushort val);
CompareAndSwapResult!uint casWeak(uint* ptr, uint old, uint val);
CompareAndSwapResult!ulong casWeak(ulong* ptr, ulong old, ulong val);

ulong readCycleCounter();
void* readFramePointer();
