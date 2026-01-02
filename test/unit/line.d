#line 100
enum FirstLine = __LINE__;

unittest line {
	assert(FirstLine == 100);

	#line 200
	assert(__LINE__ == 200);
	assert(__LINE__ == 201);

	#line // Comment...
		300
	assert(__LINE__ == 300);
	assert(__LINE__ == 301);

	#line __LINE__
	assert(__LINE__ == 303);
	assert(__LINE__ == 304);
}
