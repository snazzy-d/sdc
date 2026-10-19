module sdc.intrinsics;

bool expect(bool v, bool e);
bool likely(bool v);
bool unlikely(bool v);

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

ubyte fetchAdd(shared(ubyte)* ptr, ubyte value);
ushort fetchAdd(shared(ushort)* ptr, ushort value);
uint fetchAdd(shared(uint)* ptr, uint value);
ulong fetchAdd(shared(ulong)* ptr, ulong value);

ubyte fetchSub(shared(ubyte)* ptr, ubyte value);
ushort fetchSub(shared(ushort)* ptr, ushort value);
uint fetchSub(shared(uint)* ptr, uint value);
ulong fetchSub(shared(ulong)* ptr, ulong value);

ubyte fetchAnd(shared(ubyte)* ptr, ubyte value);
ushort fetchAnd(shared(ushort)* ptr, ushort value);
uint fetchAnd(shared(uint)* ptr, uint value);
ulong fetchAnd(shared(ulong)* ptr, ulong value);

ubyte fetchOr(shared(ubyte)* ptr, ubyte value);
ushort fetchOr(shared(ushort)* ptr, ushort value);
uint fetchOr(shared(uint)* ptr, uint value);
ulong fetchOr(shared(ulong)* ptr, ulong value);

ubyte fetchXor(shared(ubyte)* ptr, ubyte value);
ushort fetchXor(shared(ushort)* ptr, ushort value);
uint fetchXor(shared(uint)* ptr, uint value);
ulong fetchXor(shared(ulong)* ptr, ulong value);

struct CompareAndSwapResult(T) {
	T value;
	bool success;
}

CompareAndSwapResult!ubyte cas(shared(ubyte)* ptr, ubyte old, ubyte val);
CompareAndSwapResult!ushort cas(shared(ushort)* ptr, ushort old, ushort val);
CompareAndSwapResult!uint cas(shared(uint)* ptr, uint old, uint val);
CompareAndSwapResult!ulong cas(shared(ulong)* ptr, ulong old, ulong val);

CompareAndSwapResult!ubyte casWeak(shared(ubyte)* ptr, ubyte old, ubyte val);
CompareAndSwapResult!ushort casWeak(shared(ushort)* ptr, ushort old,
                                    ushort val);
CompareAndSwapResult!uint casWeak(shared(uint)* ptr, uint old, uint val);
CompareAndSwapResult!ulong casWeak(shared(ulong)* ptr, ulong old, ulong val);

ulong readCycleCounter();
void* readFramePointer();
