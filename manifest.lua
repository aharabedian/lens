-- manifest.lua - every file the updater installs: { path in the repo, path under /home }.
-- tests/test_layout.lua checks that every file in src/ and lib/ is listed, so a new module only needs a line here.
-- Programs go to bin/, modules to lib/ at the same path.
return {
  { "lib/lens/codec.lua", "lib/lens/codec.lua" },
  { "lib/lens/metrics.lua", "lib/lens/metrics.lua" },
}
