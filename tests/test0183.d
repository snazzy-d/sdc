//T compiles:yes
//T has-passed:yes
//T retval:42

int main() {
	int a = mixin("-12");
	mixin("int b;");
	mixin("b") = mixin("42");
	assert(a == -12);

	assert(mixin("22 + 31") == 53);
	assert(mixin("22") * mixin("2") == mixin("44"));
	
	switch(mixin("b")) {
		case mixin("1") :
			return 12;
		case mixin("42") :
			break;
		default :
			assert(0);
	}

	mixin("switch(a){default : break;}");

	uint ctr;
	foreach(c; mixin("\"test\"")) {
		ctr++;
	}
	assert(ctr == 4);

	mixin("return mixin(\"42\");");
}

