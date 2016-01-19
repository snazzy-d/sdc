/********************************
 * AtomicArray                  *
 * concurrenly accsesable array *
 *                              *
 * Copyright (2015) Stefan Koch * 
 ********************************/

module atomicarray;
import std.concurrency;

struct AtomicValue(T) {
	shared uint ownerTid;
	shared T value;
	alias valueType = T;
	alias value this;
}

AtomicValue!T atomicValue (T) (T t, shared int ownerTid = -1) {
	AtomicValue!T result;
	result.value = cast(shared) t;
	result.ownerTid = ownerTid + 1;
	return result;
}


struct AtomicArray(T) {
	import core.atomic;
	alias AT = AtomicValue!T;

	shared uint threadId;
	shared T[] _data;

	const (T) opIndex(size_t pos) {
		assert(pos <= _data.length);
		return cast(const) _data[pos];
	}

	bool aquire(shared uint aqId) in {
		assert(aqId != 0);
	} body {
		if (threadId == 0) {
			return (&threadId).cas(0, aqId);
		} else if (threadId == aqId) {
			return true;
		} else {
			return false;
		}
	}

	typeof(this) opBinary(string op)(AT av) {
		while(!aquire(av.ownerTid)) {
			//bla;
		}
		
		// The lock is aquired now.
		mixin(q{ _data } ~ op  ~ q{ av; });
		//release lock;
		threadId = 0;
	}

	typeof(this) opOpAssign(string op)(AT av) {
                while(!aquire(av.ownerTid)) {
                        //bla;
                }
		
                // The lock is aquired now.
                mixin(q{ _data } ~ op ~ q{= av; });
                //release lock;
                threadId = 0;
		return this;
        }

	@property size_t length() {
		while(threadId != 0) {}
		assert(threadId == 0);
		return _data.length;
			
	}	 
}

version (test_atomic) {
	void main() {
	import std.parallelism;
        import std.algorithm;
        import std.range;
		
	version (Atomic) {
        	AtomicArray!dchar aca;
	} else {	
		dchar[] ca;
	}
	foreach(tid;parallel(iota(1,9999))) {
        	foreach(i,v;parallel("Hello cruel World")) {
                	import std.stdio;
			version (Atomic) {
				aca ~= atomicValue(v, tid);
			} else {
				ca ~= v;
			}
        	}

		version(Atomic) {
			auto ca = aca._data;
		}

		if (ca != "Hello cruel World") {
			import std.stdio;
			writeln(tid, ca);
		}
		ca = [];
	}

        
}
}
