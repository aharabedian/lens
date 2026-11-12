-- manifest.lua - every file lens-update installs: { path in the repo, path under /home }.
-- tests/test_layout.lua checks that every file in src/ and lib/ is listed, so a new module only needs a line here.
-- Programs go to bin/, modules to lib/ at the same path.
return {
  { "src/lens-discover.lua", "bin/lens-discover.lua" },
  { "src/lens-hub.lua", "bin/lens-hub.lua" },
  { "src/lens-update.lua", "bin/lens-update.lua" },
  { "lib/lens/codec.lua", "lib/lens/codec.lua" },
  { "lib/lens/discover.lua", "lib/lens/discover.lua" },
  { "lib/lens/gui.lua", "lib/lens/gui.lua" },
  { "lib/lens/hub/alerts.lua", "lib/lens/hub/alerts.lua" },
  { "lib/lens/hub/app.lua", "lib/lens/hub/app.lua" },
  { "lib/lens/hub/config.lua", "lib/lens/hub/config.lua" },
  { "lib/lens/hub/core.lua", "lib/lens/hub/core.lua" },
  { "lib/lens/hub/dashboard.lua", "lib/lens/hub/dashboard.lua" },
  { "lib/lens/hub/query.lua", "lib/lens/hub/query.lua" },
  { "lib/lens/hub/rules.lua", "lib/lens/hub/rules.lua" },
  { "lib/lens/hub/store.lua", "lib/lens/hub/store.lua" },
  { "lib/lens/metrics.lua", "lib/lens/metrics.lua" },
  { "lib/lens/version.lua", "lib/lens/version.lua" },
  { "config/lens-hub.example.cfg", "lens-hub.example.cfg" },
}
