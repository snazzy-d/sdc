unittest math {
	void* ptr0 = null;
	auto ptr1 = ptr0 + 1;

	assert(ptr0 is null);
	assert(ptr0 is ptr1 - 1);
	assert(ptr0 + 1 is ptr1);
	assert(ptr0 + 2 is ptr1 + 1);

	assert(1 + ptr0 is ptr1);
	assert(2 + ptr0 is 1 + ptr1);

	assert(ptr0 - ptr0 == 0);
	assert(ptr1 - ptr1 == 0);
	assert(ptr1 - ptr0 == 1);
	assert(ptr0 - ptr1 == -1);
}

unittest types {
	void* vptr = null;
	uint* iptr = null;

	assert(vptr is cast(void*) iptr);
	assert(vptr + 4 is cast(void*) (iptr + 1));

	auto iptr0 = iptr;
	auto iptr1 = iptr + 1;

	assert(iptr0 + 1 is iptr1);
	assert(iptr0 + 2 is iptr1 + 1);
	assert(iptr0 + 2 is 1 + iptr1);

	assert(iptr0 - iptr0 == 0);
	assert(iptr1 - iptr1 == 0);
	assert(iptr1 - iptr0 == 1);
	assert(iptr0 - iptr1 == -1);

	auto vptr0 = cast(void*) iptr0;
	auto vptr1 = cast(void*) iptr1;

	assert(vptr0 - vptr0 == 0);
	assert(vptr1 - vptr1 == 0);
	assert(vptr1 - vptr0 == 4);
	assert(vptr0 - vptr1 == -4);
}

unittest ptr_to_bool {
	auto ptr0 = null;
	assert(!ptr0);

	auto ptr1 = cast(void*) null;
	assert(!ptr1);

	auto ptr2 = cast(void*) 0x1234567890;
	assert(ptr2);

	auto ptr3 = cast(void*) 0xffffffffffff;
	assert(ptr3);

	auto ptr4 = &ptr2;
	assert(ptr4);
}

unittest ptr_to_int {
	void* ptr0 = null;
	auto iptr0 = cast(size_t) ptr0;
	assert(iptr0 == 0);

	auto ptr1 = cast(void*) -1;
	assert(ptr1 is ptr0 - 1);

	auto ptr2 = cast(void*) uint(-1);
	assert(ptr2 is cast(void*) uint.max);
}
