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
