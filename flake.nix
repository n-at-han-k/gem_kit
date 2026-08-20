{
  description = "gem_kit — a deprecation DSL and the release toolchain that enforces it";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Gemfile.lock pins the gems and gemset.nix says where nix fetches each
        # one. Regenerate the latter with `bundix -l` after touching either.
        #
        # No `gemspec` in the Gemfile, so no gemspec has to be smuggled into the
        # store alongside it: the dependencies are named outright, which is also
        # the only sane answer when two gemspecs share one bundle.
        gems = pkgs.bundlerEnv {
          name = "gem-kit-gems";
          ruby = pkgs.ruby_3_4;
          gemfile = ./Gemfile;
          lockfile = ./Gemfile.lock;
          gemset = ./gemset.nix;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = with pkgs; [
            bundix
            gems
            gems.wrappedRuby
            libyaml
            openssl
            trufflehog
          ];

          shellHook = ''
            # A pre-commit hook runs with a minimal environment, and Ruby then
            # defaults to US-ASCII — which turns every em dash in these sources
            # into "invalid byte sequence" the moment a file is read.
            export LANG="''${LANG:-C.UTF-8}"
            export LC_ALL="''${LC_ALL:-$LANG}"

            # Neither gem is in the bundle — they are the repository — so put
            # this lib/ on the load path and let `require "gem_kit"` and
            # `require "gem_kit/release"` find the working tree.
            export RUBYLIB="$PWD/lib''${RUBYLIB:+:$RUBYLIB}"

            if [ ! -f .git/hooks/pre-commit ]; then
              bundle exec lefthook install
            fi
          '';
        };
      }
    );
}
