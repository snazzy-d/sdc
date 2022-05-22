module d.gc.finddivisor;

/**
 * This module is only an utility in order to find the
 * mul and shift value required to find an small item index
 * in a run from its offset without using division.
 *
 * index = (offset * mul) >> (binShift + shift)
 */
void main() {
	foreach (d; 5 .. 8) {
		Outer: foreach (uint shift; 0 .. 32) {
			auto m = (1 << shift) / d;
			while (((d * m) >> shift) == 0) {
				m++;
			}

			foreach (uint i; 0 .. 7 * 4096) {
				auto d0 = (i * m) >> shift;
				auto d1 = i / d;
				if (d0 != d1) {
					continue Outer;
				}
			}

			import core.stdc.stdio;
			printf("For d = %d\tmul: %d\tshift: %d\n", d, m, shift);
		}
	}
}
