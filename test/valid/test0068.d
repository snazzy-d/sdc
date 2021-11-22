//T compiles:yes
//T has-passed:yes
//T retval:6
//? desc:Various cases for comments.

int main() {
	//      return 21;

	// //   return 31;

	string a = /+ "+/ " +/ 1";
	string c = /* "*/ " */ 1";
	int d = 1 + /* 2 */ + /+ 3 +/ // 4
		+5;

	/*
	 * return 22;
	 */

	/* return 23; */

	/* /* return 32; */

	/+
	 + return 24;
	 +/

	/+ return 25; +/

	/+ /+ return 33; +/ +/

	// /* return 26; */
	// /+ return 27; */

	/* // return 28; */
	/* // return 28; */

	/*
	// return 29;
	*/

	/*
	 * /* return 34;
	 */

	/*
	 * /+ return 35;
	 */

	/+
	// return 30;
	+/

	/+
	 + /* return 36;
	 +/

	return d;
}
