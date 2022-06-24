{ lib, stdenv, dmd, nasm, llvmPackages, dflags ? null}:
stdenv.mkDerivation
{   name="sdc";
    src= lib.cleanSource ./.;
    nativeBuildInputs = [dmd llvmPackages.bintools];

    preBuild= let
        dflagsDecl = if dflags == null then "" else "DFLAGS=\"${dflags}\"";
    in
    ''
        makeFlagsArray+=(NATIVE_DMD_IMPORTS="-I${dmd}/include/dmd" ${dflagsDecl})
    '';
    buildInputs = [nasm llvmPackages.libllvm];


    installPhase =
    ''
        mkdir $out
        cp -r bin $out/bin
        cp -r lib $out/lib
        rm sdlib/*.mak
        mkdir $out/include
        cp -r sdlib $out/include/sdc
        dd >$out/bin/sdc.conf << EOF
        {
            "includePath": ["$out/include/sdc", "."],
            "libPath": ["$out/lib"],
        }
        EOF
    '';
}
