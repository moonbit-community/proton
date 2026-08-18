#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const moduleRoot = path.dirname(fileURLToPath(import.meta.url));
const ffiRoot = path.join(moduleRoot, "internal", "native", "ffi");

function readPayloadEnv() {
  const raw = fs.readFileSync(0, "utf8").trim();
  return raw.length === 0 ? {} : JSON.parse(raw).env ?? {};
}

function envValue(env, name) {
  return env[name] ?? process.env[name] ?? "";
}

function quote(value) {
  return `"${value.replace(/\\/g, "/")}"`;
}

function appendFlags(...parts) {
  return parts.filter(part => part.length > 0).join(" ");
}

function findRuntimeManifest(start) {
  for (let current = path.resolve(start); ; current = path.dirname(current)) {
    const manifest = path.join(current, ".proton", "runtime.json");
    if (fs.existsSync(manifest)) {
      return manifest;
    }
    const parent = path.dirname(current);
    if (parent === current) {
      throw new Error(
        "Proton CEF runtime is not configured; run `proton_cli cef setup` in the project",
      );
    }
  }
}

function activeCefRoot() {
  const manifestPath = findRuntimeManifest(process.cwd());
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const expectedPlatform = `${process.platform}-${process.arch}`;
  if (manifest.platform !== expectedPlatform) {
    throw new Error(
      `Proton runtime platform is ${manifest.platform}; expected ${expectedPlatform}`,
    );
  }
  if (typeof manifest.cef !== "string" || !path.isAbsolute(manifest.cef)) {
    throw new Error(`Invalid CEF path in ${manifestPath}`);
  }
  if (!fs.existsSync(manifest.cef)) {
    throw new Error(`CEF SDK does not exist: ${manifest.cef}`);
  }
  return manifest.cef;
}

function pkgConfig(args) {
  const result = spawnSync("pkg-config", args, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || `pkg-config ${args.join(" ")} failed`);
  }
  return result.stdout.trim();
}

function platformConfig(cefRoot, env) {
  const commonStubFlags = appendFlags(
    "-DCEF_API_VERSION=14700",
    `-include ${quote(path.join(ffiRoot, "src", "proton_allocator.h"))}`,
    `-I${quote(path.join(ffiRoot, "include"))}`,
    `-I${quote(cefRoot)}`,
  );
  const requestedCc = envValue(env, "MOON_CC").trim();

  if (process.platform === "darwin") {
    return {
      stubCc: requestedCc || "clang",
      stubFlags: appendFlags("-fblocks", commonStubFlags),
      loaderCc: requestedCc || "clang++",
      loaderFlags: appendFlags(
        "-std=c++17 -DWRAPPING_CEF_SHARED=1",
        `-I${quote(cefRoot)}`,
      ),
      linkFlags: [
        "-framework Cocoa",
        "-framework AppKit",
        "-framework Foundation",
        "-framework UserNotifications",
        "-framework CoreFoundation",
        "-framework Security",
        "-lc++",
      ].join(" "),
    };
  }

  if (process.platform === "win32") {
    return {
      stubCc: requestedCc || "clang",
      stubFlags: commonStubFlags,
      loaderCc: requestedCc || "clang++",
      loaderFlags: "-std=c++17",
      linkFlags: [
        quote(path.join(cefRoot, "Release", "libcef.lib")),
        "user32.lib shell32.lib shlwapi.lib ole32.lib comctl32.lib",
        "dwmapi.lib shcore.lib gdi32.lib advapi32.lib",
      ].join(" "),
    };
  }

  if (process.platform === "linux") {
    const cflags = pkgConfig(["--cflags", "gtk+-3.0", "x11"]);
    const libs = pkgConfig(["--libs", "gtk+-3.0", "x11"]);
    const releaseDir = path.join(cefRoot, "Release");
    return {
      stubCc: requestedCc || "cc",
      stubFlags: appendFlags("-DOS_LINUX=1 -DCEF_X11=1", commonStubFlags, cflags),
      loaderCc: envValue(env, "CXX").trim() || "c++",
      loaderFlags: "-std=c++17",
      linkFlags: appendFlags(
        `-L${quote(releaseDir)} -lcef -Wl,-rpath,${quote(releaseDir)}`,
        libs,
        "-ldl -lpthread -lm",
      ),
    };
  }

  throw new Error(`Unsupported Proton platform: ${process.platform}`);
}

export function createNativeLinkConfig(env = readPayloadEnv()) {
  const cefRoot = activeCefRoot();
  const config = platformConfig(cefRoot, env);
  return {
    vars: {
      PROTON_NATIVE_STUB_CC: config.stubCc,
      PROTON_NATIVE_STUB_CC_FLAGS: config.stubFlags,
      PROTON_CEF_LOADER_CC: config.loaderCc,
      PROTON_CEF_LOADER_CC_FLAGS: config.loaderFlags,
    },
    link_configs: [
      {
        package: "moonbit-community/proton/internal/native/ffi",
        link_flags: config.linkFlags,
      },
    ],
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.stdout.write(JSON.stringify(createNativeLinkConfig()));
}
