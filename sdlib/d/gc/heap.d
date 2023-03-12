module d.gc.heap;

/**
 * This is a Pairing Heap similar to jemalloc's.
 * See: https://github.com/jemalloc/jemalloc/blob/dev/include/jemalloc/internal/ph.h
 *
 * A Pairing Heap implementation.
 *
 * "The Pairing Heap: A New Form of Self-Adjusting Heap"
 * https://www.cs.cmu.edu/~sleator/papers/pairing-heaps.pdf
 *
 * With auxiliary twopass list, described in a follow on paper.
 *
 * "Pairing Heaps: Experiments and Analysis"
 * http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.106.2988&rep=rep1&type=pdf
 *
 *******************************************************************************
 *
 * We include a non-obvious optimization:
 * - First, we introduce a new pop-and-link operation; pop the two most
 *   recently-inserted items off the aux-list, link them, and push the resulting
 *   heap.
 * - We maintain a count of the number of insertions since the last time we
 *   merged the aux-list (i.e. via first() or remove_first()).  After N inserts,
 *   we do ffs(N) pop-and-link operations.
 *
 * One way to think of this is that we're progressively building up a tree in
 * the aux-list, rather than a linked-list (think of the series of merges that
 * will be performed as the aux-count grows).
 *
 * There's a couple reasons we benefit from this:
 * - Ordinarily, after N insertions, the aux-list is of size N.  With our
 *   strategy, it's of size O(log(N)).  So we decrease the worst-case time of
 *   first() calls, and reduce the average cost of remove_min calls.  Since
 *   these almost always occur while holding a lock, we practically reduce the
 *   frequency of unusually long hold times.
 * - This moves the bulk of the work of merging the aux-list onto the threads
 *   that are inserting into the heap.  In some common scenarios, insertions
 *   happen in bulk, from a single thread (think tcache flushing; we potentially
 *   move many slabs from slabs_full to slabs_nonfull).  All the nodes in this
 *   case are in the inserting threads cache, and linking them is very cheap
 *   (cache misses dominate linking cost).  Without this optimization, linking
 *   happens on the next call to remove_first.  Since that remove_first call
 *   likely happens on a different thread (or at least, after the cache has
 *   gotten cold if done on the same thread), deferring linking trades cheap
 *   link operations now for expensive ones later.
 *
 * The ffs trick keeps amortized insert cost at constant time.  Similar
 * strategies based on periodically sorting the list after a batch of operations
 * perform worse than this in practice, even with various fancy tricks; they
 * all took amortized complexity of an insert from O(1) to O(log(n)).
 */

struct Node(N, string NodeName = "phnode") {
private:
	alias Link = .Link!(N, NodeName);

	Link prev;
	Link next;
	Link child;
}

// TODO: when supported add default to use opCmp for compare.
struct Heap(N, alias compare, string NodeName = "phnode") {
private:
	alias Link = .Link!(N, NodeName);
	alias Node = .Node!(N, NodeName);

	Link root;
	size_t auxcount;

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
		auxcount = 0;
	}

	N* pop() {
		if (empty) {
			return null;
		}

		mergeAux();

		auto ret = root.node;
		root = mergeChildren(root);
		return ret;
	}

	void insert(N* n) {
		// Let's make sure the node is clean.
		auto ln = Link(n);
		ln.prev = Link(null);
		ln.next = Link(null);
		ln.child = Link(null);

		/**
		 * Treat the root as an aux list during insertion, and lazily merge
		 * during extract(). For elements that are inserted, then removed
		 * via remove() before the aux list is ever processed, this makes
		 * insert/remove constant-time, whereas eager merging would make
		 * insert O(log n).
		 */
		if (empty) {
			root = ln;
			return;
		}

		/**
		 * As a special case, check to see if we can replace the root.
		 * This is practically common in some important cases, and lets
		 * us defer some insertions (hopefully, until the point where
		 * some of the items in the aux list have been removed, savings
		 * us from linking them at all).
		 */
		if (compare(n, root.node) <= 0) {
			ln.child = root;
			root.prev = ln;
			root = ln;
			auxcount = 0;
			return;
		}

		auto aux = root.next;
		if (!aux.isNull()) {
			aux.prev = ln;
		}

		root.next = ln;
		ln.prev = root;
		ln.next = aux;

		auxcount++;
		if (auxcount < 2) {
			return;
		}

		import sdc.intrinsics;
		uint nmerge = countTrailingZeros(auxcount);
		bool done = false;
		for (uint i = 0; i < nmerge && !done; i++) {
			done = tryAuxMergePair();
		}
	}

	void remove(N* n) {
		auto ln = Link(n);
		if (root.node is n) {
			if (ln.child.isNull()) {
				root = ln.next;
				return;
			}

			mergeAux();
			if (root.node is n) {
				root = mergeChildren(ln);
				return;
			}
		}

		auto prev = ln.prev;
		auto next = ln.next;

		auto replace = mergeChildren(ln);
		if (!replace.isNull()) {
			replace.next = next;
			if (!next.isNull()) {
				next.prev = replace;
			}

			next = replace;
		}

		if (!next.isNull()) {
			next.prev = prev;
		}

		assert(!prev.isNull());
		if (prev.child.node is n) {
			prev.child = next;
		} else {
			prev.next = next;
		}
	}

	@property
	N* any() {
		if (root.isNull()) {
			return null;
		}

		auto aux = root.next;
		return aux.isNull() ? root.node : aux.node;
	}

private:
	void mergeAux() {
		auxcount = 0;

		auto n = root.next;
		if (n.isNull()) {
			return;
		}

		root.prev = Link(null);
		root.next = Link(null);
		n.prev = Link(null);

		n = mergeSiblings(n);
		assert(n.next.isNull());
		root = merge(root, n);
	}

	bool tryAuxMergePair() {
		assert(!root.isNull(), "root is null!");

		auto n0 = root.next;
		if (n0.isNull()) {
			return true;
		}

		auto n1 = n0.next;
		if (n1.isNull()) {
			return true;
		}

		auto n2 = n1.next;

		n0.next = Link(null);
		n0.prev = Link(null);
		n1.next = Link(null);
		n1.prev = Link(null);

		n0 = merge(n0, n1);
		root.next = n0;
		n0.prev = root;

		n0.next = n2;
		if (n2.isNull()) {
			return true;
		}

		n2.prev = n0;
		return false;
	}

	static Link merge(Link n0, Link n1) {
		if (n0.isNull()) {
			return n1;
		}

		if (n1.isNull()) {
			return n0;
		}

		assert(n0.node !is n1.node);
		auto cmp = compare(n0.node, n1.node) <= 0;
		auto x0 = cmp ? n0 : n1;
		auto x1 = cmp ? n1 : n0;

		auto x0child = x0.child;
		x1.next = x0child;
		x0.child = x1;
		x1.prev = x0;

		if (!x0child.isNull()) {
			x0child.prev = x1;
		}

		return x0;
	}

	static Link mergeChildren(Link n) {
		auto child = n.child;
		if (child.isNull()) {
			return Link(null);
		}

		return mergeSiblings(child);
	}

	static Link mergeSiblings(Link n) {
		auto n0 = n;
		auto n1 = n.next;
		if (n1.isNull()) {
			return n0;
		}

		/**
		 * We merge the sibling in two passes.
		 * 1. We merge every pair of siblings, 2 by 2.
		 * 2. Then we merge the first two siblings again
		 *    and again until only one remains.
		 *
		 * The first pass ensures that we divide by 2 the size
		 * of the list of siblings before doign a regular merge,
		 * which prevents pathological cases where the full list
		 * of sibling is lowered down to the next level again and
		 * again.
		 */
		auto nrest = n1.next;
		if (!nrest.isNull()) {
			nrest.prev = Link(null);
		}

		n0.prev = Link(null);
		n0.next = Link(null);
		n1.prev = Link(null);
		n1.next = Link(null);

		auto head = merge(n0, n1);
		auto tail = head;

		while (!nrest.isNull()) {
			n0 = nrest;
			n1 = n0.next;
			if (n1.isNull()) {
				tail.next = n0;
				tail = n0;
				break;
			}

			nrest = n1.next;
			if (!nrest.isNull()) {
				nrest.prev = Link(null);
			}

			n0.prev = Link(null);
			n0.next = Link(null);
			n1.prev = Link(null);
			n1.next = Link(null);

			n0 = merge(n0, n1);
			tail.next = n0;
			tail = n0;
		}

		n0 = head;
		n1 = n0.next;
		if (n1.isNull()) {
			return n0;
		}

		while (true) {
			head = n1.next;
			assert(n0.prev.isNull());
			n0.next = Link(null);
			assert(n1.prev.isNull());
			n1.next = Link(null);

			n0 = merge(n0, n1);
			if (head.isNull()) {
				break;
			}

			tail.next = n0;
			tail = n0;
			n0 = head;
			n1 = n0.next;
		}

		return n0;
	}

	void dump() {
		// ph_print_tree!NodeName(root.node);
	}
}

private:
//+
void ph_print_tree(string NodeName, N)(N* root) {
	Debug!(N, NodeName).print_tree(root, 0);
}

template Debug(N, string NodeName) {
	alias Link = .Link!(N, NodeName);
	alias Node = .Node!(N, NodeName);

	static ref Node nodeData(N* n) {
		return .nodeData!NodeName(n);
	}

	void print_tree(Link n, uint depth) {
		print_tree(n.node, depth);
	}

	void print_tree(N* n, uint depth) {
		if (n is null) {
			return;
		}

		foreach (i; 0 .. depth) {
			import core.stdc.stdio;
			printf("\t");
		}

		import core.stdc.stdio;
		printf("%p %d\tprev: %p\n", n, n.value, nodeData(n).prev);

		print_tree(nodeData(n).child, depth + 1);
		print_tree(nodeData(n).next, depth);
	}
}

// +/

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

	@property
	ref Link child() {
		return nodeData.child;
	}
}

unittest heap {
	struct Stuff {
		ulong value;
		Node!Stuff phnode;
	}

	static ptrdiff_t stuffCmp(Stuff* lhs, Stuff* rhs) {
		auto l = cast(size_t) lhs;
		auto r = cast(size_t) rhs;

		return (lhs.value == rhs.value)
			? (l > r) - (l < r)
			: (lhs.value - rhs.value);
	}

	Stuff[128] stuffs;
	foreach (i; 0 .. stuffs.length) {
		stuffs[i].value = i;
	}

	alias Link = .Link!(Stuff, "phnode");
	Heap!(Stuff, stuffCmp) heap;

	size_t computeAuxLength() {
		auto n = heap.root;
		size_t len = 0;
		while (!n.isNull()) {
			n = n.next;
			len++;
		}

		return len - 1;
	}

	void checkIntegrity() {
		void check(Link n, Link prev, Link parent) {
			if (n.isNull()) {
				return;
			}

			assert(parent.isNull() || stuffCmp(parent.node, n.node) < 0);

			// /!\ The root's prev is not maintained.
			assert(prev.isNull() || n.prev.node is prev.node);
			check(n.next, n, parent);
			check(n.child, n, n);
		}

		check(heap.root, Link(null), Link(null));
	}

	void checkHeap() {
		foreach (i; 0 .. stuffs.length) {
			auto n = &stuffs[i];
			assert(heap.pop() is n);
			checkIntegrity();
		}

		assert(heap.empty);
	}

	// Inserting in reverse order creates a linked list.
	for (size_t i = stuffs.length; i-- > 0;) {
		auto n = &stuffs[i];
		heap.insert(n);

		assert(heap.auxcount == 0);
		assert(heap.root.node is n);
		checkIntegrity();
	}

	checkHeap();

	// Inserting in order creates a linked list.
	foreach (i; 0 .. stuffs.length) {
		auto n = &stuffs[i];
		heap.insert(n);
		checkIntegrity();

		import sdc.intrinsics;
		assert(computeAuxLength() == popCount(i));
	}

	checkHeap();

	// This test a possibly pathological case.
	// We insert the smallest element first, but then
	// insert all the other elements in reverse order.
	heap.insert(&stuffs[0]);

	for (size_t i = stuffs.length; i-- > 1;) {
		auto n = &stuffs[i];
		heap.insert(n);
		checkIntegrity();
	}

	checkHeap();

	// Check we know how to remove nodes properly.
	foreach (i; 0 .. stuffs.length) {
		auto n = &stuffs[i];
		heap.insert(n);
		checkIntegrity();

		import d.gc.util;
		if (isPow2(i)) {
			heap.remove(n);
			checkIntegrity();
			heap.insert(n);
			checkIntegrity();
		}
	}

	// Removing the root when it doesn't have child is special cased.
	assert(heap.root.node.value == 0);
	assert(heap.root.child.isNull());
	heap.remove(&stuffs[0]);
	checkIntegrity();
	heap.insert(&stuffs[0]);
	checkIntegrity();

	// Now the root has child, we want to check that codepath as well.
	assert(heap.root.node.value == 0);
	assert(!heap.root.child.isNull());
	heap.remove(&stuffs[0]);
	checkIntegrity();
	heap.insert(&stuffs[0]);
	checkIntegrity();

	// Remove half the nodes.
	foreach (i; 0 .. stuffs.length / 2) {
		heap.remove(&stuffs[2 * i + 1]);
		checkIntegrity();
	}

	foreach (i; 0 .. stuffs.length / 2) {
		auto n = &stuffs[2 * i];
		assert(heap.pop() is n);
		checkIntegrity();
	}

	assert(heap.empty);
}
