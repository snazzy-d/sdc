module d.gc.valuetracker;

struct ValueTracker(T) {
private:
	T _value;
	T _threshold;
public:
	this(T initialValue, T threshold) {
		this._value = initialValue;
		this._threshold = threshold;
	}

	@property
	T value() {
		return _value;
	}

	@property
	T threshold() {
		return _threshold;
	}

	@property
	bool above() {
		return _value >= _threshold;
	}

	@property
	bool below() {
		return _value <= _threshold;
	}

	void setThreshold(T th) {
		_threshold = th;
	}

	void setRelativeThreshold(T multNum, T multDen, T min = 0) {
		import d.gc.util;
		_threshold = max(_value * multNum / multDen, min);
	}

	void add(T val) {
		_value += val;
	}

	void subtract(T val) {
		_value -= val;
	}

	void set(T val) {
		_value = val;
	}
}

unittest ValueTracker {
	ValueTracker!int tracker = ValueTracker!int(5, 10);
	assert(tracker.below);
	assert(!tracker.above);

	tracker.add(4);
	assert(tracker.below);
	assert(!tracker.above);

	tracker.add(1);
	assert(tracker.below);
	assert(tracker.above);

	tracker.set(15);
	assert(!tracker.below);
	assert(tracker.above);

	tracker.setRelativeThreshold(3, 2, 10);
	assert(tracker.value == 15);
	assert(tracker.threshold == 22);
	assert(tracker.below);
	assert(!tracker.above);

	tracker.subtract(10);
	assert(tracker.value == 5);
	assert(tracker.below);
	assert(!tracker.above);

	tracker.setRelativeThreshold(3, 2, 10);
	assert(tracker.threshold == 10);
	assert(tracker.below);
	assert(!tracker.above);
}
