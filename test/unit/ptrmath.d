unittest math {
	void* ptr0 = null;
	auto ptr1 = ptr0 + 1;

	assert(ptr0 is null);
	assert(ptr0 is ptr1 - 1);
	assert(ptr0 + 1 is ptr1);
	assert(ptr0 + 2 is ptr1 + 1);
}

unittest types {
	void* vptr = null;
	uint* iptr = null;

	assert(vptr is cast(void*) iptr);
	assert(vptr + 4 is cast(void*) (iptr + 1));
}
