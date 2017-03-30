//T compiles:yes
//T has-passed:yes
//T retval:0
// Test various control flow terminations

bool condition;

int main() {
	noflow();
	
	assert(ifflow0() == 1);
	assert(ifflow1() == 1);
	assert(ifflow2() == 0);
	
	assert(loopflow() == 1);
	
	assert(tryflow0() == 0);
	assert(tryflow1() == 0);
	assert(tryflow2() == 1);
	
	assert(switchflow0() == 0);
	assert(switchflow1() == 0);
	
	assert(gotoflow0() == 0);
	assert(gotoflow1() == 0);
	
	return 0;
}

void noflow() {}

uint ifflow0() {
	if (condition) {
		return 0;
	} else {
		return 1;
	}
}

uint ifflow1() {
	if (condition) {
		return 0;
	}
	
	return 1;
}

uint ifflow2() {
	if (condition) {
	} else {
		return 0;
	}
	
	return 1;
}

uint loopflow() {
	while(condition) {
		return 0;
	}
	
	do {
		return 1;
	} while(condition);
	
	// FIXME: instruction lowerer lost the capability
	// to see this is unreachable.
	return 2;
}

uint tryflow0() {
	try {
		return 0;
	} catch(Exception e) {
		return 1;
	}
}

uint tryflow1() {
	try {
		return 0;
	} catch(Exception e) {}
	
	return 1;
}

uint tryflow2() {
	try {
	} catch(Exception e) {
		return 0;
	}
	
	return 1;
}

uint switchflow0() {
	switch(cast(uint) condition) {
		case 0:
			return 0;
		
		case 1:
			return 1;
		
		default:
			return 2;
	}
}

uint switchflow1() {
	switch(cast(uint) condition) {
		case 0:
			break;
		
		 case 1:
			return 1;
		
		 default:
			break;
	}
	
	return 0;
}

uint gotoflow0() {
	goto Next;
	Next: goto End;
	End: return 0;
}

uint gotoflow1() {
	goto Next;
	End: return 0;
	Next: goto End;
}
