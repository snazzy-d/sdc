//T compiles:yes
//T retval:0
//T has-passed:yes
// Tests nested switch

int main() {
	int x = 10;
	switch (x) {
		case 1:
			switch (x) {
				default:
					break;
			}

			break;

		case 2:
			switch (x) {
				default:
					break;

				case 1:
					switch (x) {
						default:
							break;
					}

					break;
			}

			break;

		default:
			break;
	}

	return 0;
}
