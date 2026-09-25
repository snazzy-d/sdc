auto off_covers_list = [
	// sdfmt off
	2,3
	// sdfmt on
];

auto off_between_elements = [1,
	// sdfmt off
	2,3
	// sdfmt on
                             ,
                             4
];

auto off_same_line =
	[1, // sdfmt off
	2,3
	// sdfmt on
	 ,
	 4];

auto off_empty = [1,
	// sdfmt off
	// sdfmt on
                  2
];

auto off_nested = [[1],
	// sdfmt off
	[2,3]
	// sdfmt on
                   ,
                   [4]
];

foo(a,
	// sdfmt off
	b,c
	// sdfmt on
    ,
    d
);

auto off_unterminated = [1,
	// sdfmt off
	2,3
];
