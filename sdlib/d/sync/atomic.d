module d.sync.atomic;

import sdc.intrinsics;

// Work around limitation in SDC's symbol resolution.
private alias ifetchAdd = fetchAdd;
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
	T load(MemoryOrder order = MemoryOrder.SeqCst) shared {
		return value;
	}

	void store(T value, MemoryOrder order = MemoryOrder.SeqCst) shared {
		this.value = value;
	}

	T fetchAdd(T increment, MemoryOrder order = MemoryOrder.SeqCst) shared {
		return ifetchAdd(&value, increment);
	}

	bool cas(ref T expected, T desired,
	         MemoryOrder order = MemoryOrder.SeqCst) shared {
		auto cr = icas(&value, expected, desired);
		expected = cr.value;
		return cr.success;
	}

	bool casWeak(ref T expected, T desired,
	             MemoryOrder order = MemoryOrder.SeqCst) shared {
		auto cr = icasWeak(&value, expected, desired);
		expected = cr.value;
		return cr.success;
	}
}
