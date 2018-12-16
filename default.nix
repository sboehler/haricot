{ mkDerivation, base, bifunctors, bytestring, containers, Decimal
, exceptions, filepath, groups, hpack, lens, megaparsec, mtl
, optparse-applicative, pretty-simple, prettyprinter, regex-pcre
, scientific, stdenv, tasty, tasty-golden, tasty-hunit
, tasty-quickcheck, tasty-smallcheck, text, time
}:
mkDerivation {
  pname = "beans";
  version = "0.0.2.0";
  src = ./.;
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    base bifunctors bytestring containers Decimal exceptions filepath
    groups lens megaparsec mtl prettyprinter regex-pcre scientific text
    time
  ];
  libraryToolDepends = [ hpack ];
  executableHaskellDepends = [
    base megaparsec optparse-applicative text time
  ];
  testHaskellDepends = [
    base bytestring filepath megaparsec mtl pretty-simple prettyprinter
    regex-pcre tasty tasty-golden tasty-hunit tasty-quickcheck
    tasty-smallcheck text time
  ];
  preConfigure = "hpack";
  homepage = "https://github.com/sboehler/beans#readme";
  description = "A plain text accounting tool";
  license = stdenv.lib.licenses.bsd3;
}
