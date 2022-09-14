import foo;
import foo.bar;
import foo.bar : buzz;
import foo.bar : buzz = qux;
import foo.bar : symbol1;
import foo.bar : symbol1, symbol2;
import foo.bar.buzz : symbol1, symbol2,
                      symbol3;
import foo.bar : symbol1, symbol2,
                 symbol3, symbol4;
import foo.bar
	: symbol1, symbol2, symbol3,
	  symbol4, symbol5;
import foo.bar
	: symbol1, symbol2, symbol3,
	  symbol4, symbol5, symbol6;
import foo.bar
	: symbol1, symbol2, symbol3,
	  symbol4, symbol5, symbol6,
	  symbol7;
import foo.bar
	: symbol1, symbol2, symbol3,
	  symbol4, symbol5, symbol6,
	  symbol7, symbol8;
import foo.bar
	: symbol1, symbol2, symbol3,
	  symbol4, symbol5, symbol6,
	  symbol7, symbol8, symbol9;
public import foo.bar : symbol1,
                        symbol2;
static import foo.bar : symbol1,
                        symbol2;
import foo.bar : foo = bar, fizz = buzz;
import foo.bar : foo = bar, fizz = buzz,
                 symbol1;
import foo.bar : foo = bar, fizz = buzz,
                 symbol1, symbol2;
import foo.bar
	: foo = bar, fizz = buzz, symbol1,
	  symbol2, symbol3;
import foo.bar
	: foo = bar, fizz = buzz, symbol1,
	  symbol2, symbol3, symbol4;
import foo.bar
	: foo = bar,
	  fizz = buzz,
	  symbol1,
	  symbol2,
	  symbol3,
	  symbol4,
	  symbol5;
import foo.bar
	: foo = bar,
	  fizz = buzz,
	  symbol1,
	  symbol2,
	  symbol3,
	  symbol4,
	  symbol5,
	  symbol6;
