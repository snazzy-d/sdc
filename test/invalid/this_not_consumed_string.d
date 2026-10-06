//T error: this_not_consumed_string.d:5:1:
//T error: nope can't be resolved in type immutable(char)[].

void main() {
	"hi".nope;
}
