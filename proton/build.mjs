#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  cefApiVersion,
  runtimeLayoutVersion,
  runtimeRequirements,
} from "./cef_requirements.generated.mjs";

const moduleRoot = path.dirname(fileURLToPath(import.meta.url));
const ffiRoot = path.join(moduleRoot, "internal", "native", "ffi");
const macosDeploymentTarget = "12.0";

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

function runtimePlatformId() {
  return `${process.platform}-${process.arch}`;
}

function runtimeStoreRoot(env) {
  const configured = envValue(env, "PROTON_RUNTIME_STORE").trim();
  if (configured.length > 0) {
    if (!path.isAbsolute(configured)) {
      throw new Error(`PROTON_RUNTIME_STORE must be an absolute path: ${configured}`);
    }
    return path.resolve(configured);
  }
  const home = envValue(env, process.platform === "win32" ? "USERPROFILE" : "HOME").trim()
    || envValue(env, process.platform === "win32" ? "HOME" : "USERPROFILE").trim();
  if (home.length === 0) {
    throw new Error("Cannot resolve the Proton runtime store because no home directory is available");
  }
  return path.resolve(home, ".proton", "store");
}

function cefSdkRoot(env) {
  const platform = runtimePlatformId();
  const requirement = runtimeRequirements[platform];
  if (!requirement?.supported) {
    throw new Error(`The Proton CEF backend is not supported for ${platform}`);
  }
  const id = `cef-${requirement.sha256}-layout-${runtimeLayoutVersion}`;
  return path.join(runtimeStoreRoot(env), platform, id, "sdk");
}

function pkgConfig(args) {
  const result = spawnSync("pkg-config", args, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || `pkg-config ${args.join(" ")} failed`);
  }
  return result.stdout.trim();
}

function platformConfig(cefRoot) {
  const commonStubFlags = appendFlags(
    `-DCEF_API_VERSION=${cefApiVersion}`,
    `-I${quote(path.join(ffiRoot, "include"))}`,
    `-I${quote(cefRoot)}`,
  );
  if (process.platform === "darwin") {
    const deploymentFlag = `-mmacosx-version-min=${macosDeploymentTarget}`;
    return {
      deploymentTargetFlags: deploymentFlag,
      stubFlags: appendFlags(deploymentFlag, commonStubFlags),
      macObjcFlags: appendFlags(
        deploymentFlag,
        "-ObjC -fblocks",
        commonStubFlags,
      ),
      loaderFlags: appendFlags(
        deploymentFlag,
        "-ObjC++ -std=c++17 -DWRAPPING_CEF_SHARED=1",
        `-I${quote(cefRoot)}`,
      ),
      linkFlags: [
        deploymentFlag,
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
      deploymentTargetFlags: "",
      stubFlags: commonStubFlags,
      macObjcFlags: "",
      loaderFlags: "",
      linkFlags: [
        quote(path.join(cefRoot, "Release", "libcef.lib")),
        "user32.lib shell32.lib shlwapi.lib ole32.lib uuid.lib comctl32.lib",
        "dwmapi.lib shcore.lib gdi32.lib advapi32.lib",
      ].join(" "),
    };
  }

  if (process.platform === "linux") {
    const cflags = pkgConfig(["--cflags", "gtk+-3.0", "x11"]);
    const libs = pkgConfig(["--libs", "gtk+-3.0", "x11"]);
    const releaseDir = path.join(cefRoot, "Release");
    return {
      deploymentTargetFlags: "",
      stubFlags: appendFlags("-DOS_LINUX=1 -DCEF_X11=1", commonStubFlags, cflags),
      macObjcFlags: "",
      loaderFlags: "",
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
  // A source checkout runs workspace prebuilds before it can build the setup
  // executable that creates the first store installation. Only that bootstrap
  // build has no Proton native link target.
  if (envValue(env, "PROTON_CEF_SETUP_BOOTSTRAP") === "1") {
    return { vars: {}, link_configs: [] };
  }
  const cefRoot = cefSdkRoot(env);
  const config = platformConfig(cefRoot);
  return {
    vars: {
      PROTON_DEPLOYMENT_TARGET_CC_FLAGS: config.deploymentTargetFlags,
      PROTON_NATIVE_STUB_CC_FLAGS: config.stubFlags,
      PROTON_MAC_OBJC_STUB_CC_FLAGS: config.macObjcFlags,
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
