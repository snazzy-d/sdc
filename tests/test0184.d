//T compiles:yes
//T has-passed:yes
//T retval:12
//Tests the Basic isExpression 

int main() {

	struct S (int kind) {
		static if (kind == 1) {
			alias t = void;
		} else {
			alias b = uint;
		}	
	}
	
	class CwOP {
		bool _opEquals(CwOP rhs) {
			return this !is rhs;
		}
	}

	struct SwoOP {int a;}
 
	int a;
	static if (is(typeof(CwOP._opEquals))) {
		a = 12;
	}
	
	assert(is(SwoOP));	
	assert(!is(typeof(SwoOP.opEquals)));

	assert(is(S!1.t)); 

	assert(!S!0.t);

	return a;
}
