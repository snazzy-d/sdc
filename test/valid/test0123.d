//T has-passed:yes
//T compiles:yes
//T retval:0

#line __LINE__
# line 12 /* With a comment */
#line // This is a comment
  34
#	line 56 __FILE__
#line 78 "foo.d"
#line 90 "multi
line.d"

int main() {
	return 0;
}
