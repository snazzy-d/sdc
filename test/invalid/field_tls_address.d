//T error: field_tls_address.d:7:10:
//T error: Thread local tls has no address at compile time.

int tls;

struct S {
	int* p = &tls;
}
