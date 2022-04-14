void fun() {
	auto a = c ? x : y;
	auto a = condition
		? result_if_true
		: result_if_false;

	auto a = condition
		? nested_condition_1
			? nested_result_1_1
			: nested_result_1_2
		: nested_condition_2
			? nested_result_2_1
			: nested_result_2_2;

	auto a = (c
			? long_result_1
			: long_result_2)
		? (a + b)
			? long_result_3
			: long_result_4
		: (c + d)
			? long_result_5
			: long_result_6;

	auto x = a.b * c;

	auto x = cast(shared) y;
	auto x = cast(shared Foo) y;

	auto x = new class() Foo!Bar {
		void buzz() const {}
	};
}
