{ pkgs }:
{
  pname,
  version,
  src,
  pnpmDepsHash,
  main,
  meta,
  buildCommand ? "build",
  installExtra ? "",
}:
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  inherit pname version src;

  pnpmDeps = pkgs.fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pkgs.pnpm;
    fetcherVersion = 3;
    hash = pnpmDepsHash;
  };

  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.nodejs_24
    pkgs.pnpm
    pkgs.pnpmConfigHook
  ];

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    pnpm run ${buildCommand}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install_root="$out/lib/${pname}"
    mkdir -p "$install_root" "$out/bin"
    cp -R package.json node_modules dist "$install_root/"
    ${installExtra}
    makeWrapper ${pkgs.nodejs_24}/bin/node "$out/bin/${pname}" \
      --add-flags "$install_root/${main}"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    export HOME="$TMPDIR/check-home"
    mkdir -p "$HOME"
    "$out/bin/${pname}" --version
  '';

  strictDeps = true;
  inherit meta;
})
