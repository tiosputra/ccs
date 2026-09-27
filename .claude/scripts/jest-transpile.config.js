// jest-transpile.config.js - a repo's own jest.config.js, with ts-jest in transpile-only mode.
//
// Used from inside a space checkout, by the tdd-workflow skill's Step 0 matrix:
//
//   cd spaces/<task>/<repo> && npx jest --config ../../../.claude/scripts/jest-transpile.config.js ...
//
// By default ts-jest typechecks every file it compiles, in every worker, on every cold cache -
// and a new space always starts cold, because jest keys its cache by absolute path. The
// verify step already runs `npx tsc --noEmit` over the same files, so that typecheck is
// paid twice. This overlay keeps everything else from the repo's config and only turns
// that per-worker typecheck off. Measured on backend 2026-09-25, cold cache, 2 workers:
// one heavy test file 15.7s -> 2.6s, full suite 696.8s -> 36.6s, identical results.
// See the tdd-workflow skill, "Why transpile-only", for why the default is that slow.
//
// Nothing here edits the repo: the repo's jest.config.js is read, never written. A type
// error is no longer a test failure under this config - it is a `tsc --noEmit` failure,
// which is why the matrix pairs the two.
const fs = require('fs');
const path = require('path');

const repo = process.cwd();
const own = path.join(repo, 'jest.config.js');
if (!fs.existsSync(own)) {
  throw new Error(`jest-transpile.config.js: no jest.config.js in ${repo} - cd into the repo checkout first`);
}
const base = require(own);

module.exports = {
  ...base,
  rootDir: repo,
  // The repo's config prints every test name; the verify step only reads the summary.
  verbose: false,
  transform: {
    ...base.transform,
    '^.+\\.ts$': ['ts-jest', { tsconfig: { isolatedModules: true } }],
  },
};
