module d.gc.rbtest;

import d.gc.rbtree;

struct Stuff {
	Node!Stuff node;
	ulong value;
}

ptrdiff_t stuffCmp(Stuff* lhs, Stuff* rhs) {
	return (lhs.value == rhs.value)
		? (cast(ptrdiff_t) lhs) - (cast(ptrdiff_t) rhs)
		: (lhs.value - rhs.value);
}

enum Items = 174762;
Stuff[32][Items]* nodes;

Stuff* get_node(ulong tree, ulong node) {
	assert(node < 174762 && tree < 32);
	return &nodes[0][node][tree];
}

void main() {
	// 128 Mb to ramble through.
	nodes = cast(Stuff[32][Items]*) malloc(128 * 1024 * 1024);
	
	ulong prand = 365307287;
	
	foreach (i; 0 .. Items) {
		foreach (t; 0 .. 32) {
			prand = prand_next(prand);
			get_node(t, i).value = prand;
		}
	}
	
	RBTree!(Stuff, stuffCmp)[32] trees;
	
	foreach (i; 0 .. Items) {
		foreach (t; 0 .. 32) {
			trees[t].insert(get_node(t, i));
			// rb_print_tree(trees[t]);
		}
	}
	
	foreach (i; 0 .. Items) {
		foreach (t; 0 .. 32) {
			trees[t].remove(get_node(t, i));
			// rb_print_tree(trees[t]);
		}
	}
}

ulong prand_next(ulong prev) {
	return (prev * 31415821 + 1) % 100_000_000;
}

private:
extern(C) void* malloc(size_t);
