//T error: field_tls_address.d:7:10:
//T error: Cannot use this address as a constant.

int tls;

struct S {
	int* p = &tls;
}
