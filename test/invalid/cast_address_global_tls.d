//T error: cast_address_global_tls.d:4:16:
//T error: Thread local g has no address at compile time.
int g;
const(int)* p = &cast(const(int)) g;
