module d.gc.valuetracker;

struct ValueTracker(T) {
private:
	T value;
	T threshold;

	import d.sync.mutex;
	Mutex mutex;
public:
	this(T initialValue, T threshold) {
		this.value = initialValue;
		this.threshold = threshold;
	}

	bool above() shared {
		mutex.lock();
		scope(exit) mutex.unlock();
		return (cast(ValueTracker*) &this).aboveImpl();
	}

	bool below() shared {
		mutex.lock();
		scope(exit) mutex.unlock();
		return (cast(ValueTracker*) &this).belowImpl();
	}
	
	void setThreshold(T th) shared {
		mutex.lock();
		scope(exit) mutex.unlock();
		(cast(ValueTracker*) &this).setThresholdImpl(threshold);
	}

	void setRelativeThreshold(T multNum, T multDen, T min = 0) shared {
		mutex.lock();
		scope(exit) mutex.unlock();
		(cast(ValueTracker*) &this).setRelativeThresholdImpl(multNum, multDen, min);
	}

	void addValue(T val) shared {
		mutex.lock();
		scope(exit) mutex.unlock();
		(cast(ValueTracker*) &this).addValueImpl(val);
	}

	void setValue(T val) shared {
		mutex.lock();
		scope(exit) mutex.unlock();
		(cast(ValueTracker*) &this).setValueImpl(val);
	}
private:
	bool aboveImpl() {
		return value >= threshold;
	}

	bool belowImpl() {
		return value <= threshold;
	}

	void setThresholdImpl(T th) {
		threshold = th;
	}

	void setRelativeThresholdImpl(T multNum, T multDen, T min) {
		import d.gc.util;
		threshold = max(threshold * multNum / multDen, min);
	}

	void addValueImpl(T val) {
		value += val;
	}

	void setValueImpl(T val) {
		value = val;
	}
}
