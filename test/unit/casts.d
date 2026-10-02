unittest address_of_cast {
	int x = 2;

	{
		// Exact cast.
		auto p = &cast(int) x;
		assert(*p == 2);
	}

	{
		// Qual cast.
		auto p = &cast(const(int)) x;
		assert(*p == 2);
	}
}
