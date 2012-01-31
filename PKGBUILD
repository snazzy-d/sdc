pkgname=sdc-git
pkgver=20120131
pkgrel=1
pkgdesc="sdc, the stupid D compiler"
arch=('i686' 'x86_64')
license=('GPL')
depends=('llvm>=3.0' 'dmd')
makedepends=('git')
provides=('sdc')
conflicts=('sdc')

_gitroot="https://github.com/bhelyer/SDC.git"
_gitname="SDC"

build() {
  cd "$srcdir"
  msg "Connecting to GIT server...."

  if [ -d $_gitname ] ; then
    cd $_gitname && git pull origin
    msg "The local files are updated."
  else
    git clone $_gitroot $_gitname
  fi

  msg "GIT checkout done or server timeout"
  msg "Starting make..."

  cd "$srcdir/$_gitname"

  if [ ! -e llvm ] ; then
    ln -s /usr/lib/llvm .
  fi

  if [ `uname -m` == "i686" ] ; then
    make ARCHFLAG=-m32
  else
    make ARCHFLAG=-m64
  fi

  mkdir -p "$pkgdir/usr/bin"
  cp -r bin/sdc "$pkgdir/usr/bin/sdc"
}
