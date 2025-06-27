module d.sync.atomic;

import sdc.intrinsics;

// Work around limitation in SDC's symbol resolution.
private alias ifetchAdd = fetchAdd;
private alias ifetchSub = fetchSub;
private alias ifetchAnd = fetchAnd;
private alias ifetchOr = fetchOr;
private alias ifetchXor = fetchXor;
private alias icas = cas;
private alias icasWeak = casWeak;

enum MemoryOrder {
	Relaxed,
	Consume,
	Acquire,
	Release,
	AcqRel,
	SeqCst,
}

/**
 * For now, this simply uses the strongest possible memory order,
 * rather than the one specified by the user.
 *
 * FIXME: Actually use the provided ordering.
 */
struct Atomic(T) {
private:
	T value;

public:
	T load()(MemoryOrder order = MemoryOrder.SeqCst) shared {
		return value;
	}

	void store()(T value, MemoryOrder order = MemoryOrder.SeqCst) shared {
		this.value = value;
	}

	T fetchAdd()(T n, MemoryOrder order = MemoryOrder.SeqCst) shared {
		return ifetchAdd(&value, n);
	}

	T fetchSub()(T n, MemoryOrder order = MemoryOrder.SeqCst) shared {
		return ifetchSub(&value, n);
	}

	T fetchAnd()(T n, MemoryOrder order = MemoryOrder.SeqCst) shared {
		return ifetchAnd(&value, n);
	}

	T fetchOr()(T n, MemoryOrder order = MemoryOrder.SeqCst) shared {
		return ifetchOr(&value, n);
	}

	T fetchXor()(T n, MemoryOrder order = MemoryOrder.SeqCst) shared {
		return ifetchXor(&value, n);
	}

	bool cas()(ref T expected, T desired,
	           MemoryOrder order = MemoryOrder.SeqCst) shared {
		auto cr = icas(&value, expected, desired);
		expected = cr.value;
		return cr.success;
	}

	bool casWeak()(ref T expected, T desired,
	               MemoryOrder order = MemoryOrder.SeqCst) shared {
		auto cr = icasWeak(&value, expected, desired);
		expected = cr.value;
		return cr.success;
	}
}
