Tpl!(Type1, Type2, Type3, Type4, Type5)
	foo(Tpl!(Type1, Type2,
	         Type3, Type4, Type5) bar,
	    Tpl!(Type1, Type2, Type3,
	         Type4, Type5) buzz) {}
