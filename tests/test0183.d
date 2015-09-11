// TEST method inheritance with one base interface
// COMPILES: yes


interface mybase {
  void methodI();
  int methodI2();
}

class mychild : mybase{
      void methodI(){}
      int methodI2(){return 0;}
      void methodC(){}
}
void main() {
    mychild c = new mychild();
}
