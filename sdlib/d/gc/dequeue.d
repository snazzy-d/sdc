module d.gc.dequeue;

template DEQueue(T, uint Entries) {
	struct DEQueue {
	private:
		uint _front = 0;
		uint _back = 0;
		uint _count = 0;
		T[Entries] _buffer;

	public:
		enum Size = Entries;

		@property
		auto buffer() {
			assert(empty, "Buffer is not empty!");

			return _buffer.ptr;
		}

		void clear() {
			_front = 0;
			_back = 0;
			_count = 0;
		}

		void pushBackAdvance(uint delta) {
			assert(empty, "Cannot pushBackAdvance: not empty!");
			assert(delta <= Entries,
			       "Cannot pushBackAdvance: delta exceeds Entries!");

			_front = 0;
			_back = delta % Entries;
			_count = delta;
		}

		void pushBack(T item) {
			assert(!full, "Cannot pushBack: full!");

			_buffer[_back] = item;
			_back = (_back + 1) % Entries;
			_count++;
		}

		T popFront() {
			assert(!empty, "Cannot popFront: empty!");

			auto item = _buffer[_front];
			_front = (_front + 1) % Entries;
			_count--;

			return item;
		}

		void pushFront(T item) {
			assert(!full, "Cannot pushFront: full!");

			_front = (_front > 0 ? _front : Entries) - 1;
			_buffer[_front] = item;
			_count++;
		}

		T popBack() {
			assert(!empty, "Cannot popBack: empty!");

			_back = (_back > 0 ? _back : Entries) - 1;
			auto item = _buffer[_back];
			_count--;

			return item;
		}

		@property
		auto length() {
			return _count;
		}

		@property
		bool empty() {
			return _count == 0;
		}

		@property
		bool full() {
			return _count == Entries;
		}
	}
}

unittest DEQueue {
	static DEQueue!(uint, 3) q;
	assert(q.empty);

	q.pushBack(1);
	q.pushBack(2);
	q.pushBack(3);
	assert(q.full);
	assert(q.popFront() == 1);
	assert(q.popFront() == 2);
	assert(q.popFront() == 3);
	assert(q.empty);

	q.pushBack(1);
	q.pushBack(2);
	q.pushBack(3);
	assert(q.full);
	assert(q.popBack() == 3);
	assert(q.popBack() == 2);
	assert(q.popBack() == 1);
	assert(q.empty);

	q.pushFront(1);
	q.pushFront(2);
	q.pushFront(3);
	assert(q.full);
	assert(q.popFront() == 3);
	assert(q.popFront() == 2);
	assert(q.popFront() == 1);
	assert(q.empty);

	q.pushFront(1);
	q.pushFront(2);
	q.pushFront(3);
	assert(q.full);
	assert(q.popBack() == 1);
	assert(q.popBack() == 2);
	assert(q.popBack() == 3);
	assert(q.empty);

	q.pushBack(1);
	q.pushFront(2);
	q.pushBack(3);
	assert(q.full);
	assert(q.popFront() == 2);
	assert(q.popBack() == 3);
	assert(q.popFront() == 1);
	assert(q.empty);

	q.pushBack(1);
	q.pushFront(2);
	q.pushBack(3);
	assert(q.full);
	assert(q.popBack() == 3);
	assert(q.popFront() == 2);
	assert(q.popBack() == 1);
	assert(q.empty);
}
