module d.gc.ring;

struct Node(N, string NodeName = "rnode") {
private:
	alias Link = .Link!(N, NodeName);

	Link prev;
	Link next;
}

struct Ring(N, string NodeName = "rnode") {
private:
	alias Link = .Link!(N, NodeName);
	alias Node = .Node!(N, NodeName);

	Link root;

	static ref Node nodeData(N* n) {
		return .nodeData!NodeName(n);
	}

public:
	@property
	bool empty() {
		return root.isNull();
	}

	void clear() {
		root = Link(null);
	}

	@property
	N* first() {
		return root.node;
	}

	@property
	N* last() {
		return empty ? null : root.prev.node;
	}

	void insert(N* n) {
		auto ln = Link(n);

		if (empty) {
			ln.prev = ln;
			ln.next = ln;
			root = ln;
			return;
		}

		auto prev = root.prev;
		auto next = root;

		ln.prev = prev;
		ln.next = next;

		next.prev = ln;
		prev.next = ln;

		root = ln;
	}

	void remove(N* n) {
		assert(!empty);

		if (root.node is n) {
			if (root.next.node is n) {
				root = Link(null);
				return;
			}

			root = root.next;
		}

		auto ln = Link(n);

		auto prev = ln.prev;
		auto next = ln.next;

		prev.next = next;
		next.prev = prev;
	}
}

private:

ref Node!(N, NodeName) nodeData(string NodeName, N)(N* n) {
	mixin("return n." ~ NodeName ~ ";");
}

struct Link(N, string NodeName) {
	alias Node = .Node!(N, NodeName);

	N* _node;

	this(N* n) {
		_node = n;
	}

	@property
	N* node() {
		return _node;
	}

	// FIXME: Use is operator overload.
	bool isNull() {
		return node is null;
	}

	@property
	ref Node nodeData() {
		return .nodeData!NodeName(node);
	}

	@property
	ref Link prev() {
		return nodeData.prev;
	}

	@property
	ref Link next() {
		return nodeData.next;
	}
}

unittest ring {
	struct Stuff {
		ulong value;
		Node!Stuff rnode;
	}

	Stuff[128] stuffs;
	foreach (i; 0 .. stuffs.length) {
		stuffs[i].value = i;
	}

	alias Link = .Link!(Stuff, "rnode");
	Ring!Stuff ring;

	assert(ring.first is null);
	assert(ring.last is null);

	foreach (i; 0 .. stuffs.length) {
		auto n = &stuffs[i];
		ring.insert(n);

		assert(ring.first is n);
		assert(ring.last is &stuffs[0]);
	}

	// Remove the first element.
	ring.remove(&stuffs[127]);
	assert(ring.first is &stuffs[126]);
	assert(ring.last is &stuffs[0]);

	// Remove the last element.
	ring.remove(&stuffs[0]);
	assert(ring.first is &stuffs[126]);
	assert(ring.last is &stuffs[1]);

	// Remove most of the elements.
	foreach (i; 1 .. 63) {
		auto first = &stuffs[127 - i];
		auto last = &stuffs[i];

		assert(ring.first is first);
		assert(ring.last is last);

		ring.remove(first);
		ring.remove(last);
	}

	// Empty the ring by removing the two last elements.
	auto a = &stuffs[64];
	auto b = &stuffs[63];
	assert(ring.first is a);
	assert(ring.last is b);

	ring.remove(b);
	assert(ring.first is a);
	assert(ring.last is a);

	ring.remove(a);
	assert(ring.first is null);
	assert(ring.last is null);
}
