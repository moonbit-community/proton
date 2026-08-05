#!/usr/bin/env node

import { mkdirSync, readFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";

const threshold = Number.parseFloat(process.argv[2] ?? "90");
if (!Number.isFinite(threshold) || threshold < 0 || threshold > 100) {
  console.error("usage: node tools/check_non_generated_coverage.mjs [0..100]");
  process.exit(2);
}

const output = join("_build", "non_generated_coverage.json");
mkdirSync(dirname(output), { recursive: true });

const moonCommand = process.platform === "win32" ? "moon.exe" : "moon";
const coverage = spawnSync(
  moonCommand,
  ["coverage", "analyze", "--", "-f", "coveralls", "-o", output],
  { stdio: "inherit" },
);
if (coverage.status !== 0) {
  process.exit(coverage.status ?? 1);
}

const rawReport = readFileSync(output, "utf8");
let report;
try {
  report = JSON.parse(rawReport);
} catch (error) {
  // moon_cove_report currently emits unescaped Windows path separators in
  // Coveralls JSON. The report does not include source text, so escaping all
  // backslashes is a narrow compatibility fix for those path strings.
  report = JSON.parse(rawReport.replace(/\\/g, "\\\\"));
}
rmSync(output, { force: true });

const isExcludedFromLibraryCoverage = name =>
  /(^|[\\/])protocol[\\/]typed[\\/]typed_generated_/.test(name) ||
  /(^|[\\/])protocol[\\/]manifest_generated\.mbt$/.test(name) ||
  /(^|[\\/])examples[\\/]/.test(name);

let covered = 0;
let total = 0;
const files = [];

for (const file of report.source_files ?? []) {
  if (!file.name.endsWith(".mbt") || isExcludedFromLibraryCoverage(file.name)) {
    continue;
  }
  let fileCovered = 0;
  let fileTotal = 0;
  for (const value of file.coverage ?? []) {
    if (value === null) {
      continue;
    }
    fileTotal += 1;
    if (value > 0) {
      fileCovered += 1;
    }
  }
  if (fileTotal > 0) {
    covered += fileCovered;
    total += fileTotal;
    files.push({ name: file.name, covered: fileCovered, total: fileTotal });
  }
}

const percent = total === 0 ? 100 : (covered * 100) / total;
console.log(
  `non-generated library coverage: ${covered}/${total} = ${percent.toFixed(2)}%`,
);
for (const file of files.sort((a, b) => a.name.localeCompare(b.name))) {
  const filePercent = (file.covered * 100) / file.total;
  console.log(
    `  ${file.name}: ${file.covered}/${file.total} = ${filePercent.toFixed(2)}%`,
  );
}

if (percent + Number.EPSILON < threshold) {
  console.error(
    `coverage ${percent.toFixed(2)}% is below required ${threshold.toFixed(2)}%`,
  );
  process.exit(1);
}
