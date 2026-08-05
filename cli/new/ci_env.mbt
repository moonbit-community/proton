///|
/// CI environment detection for `proton_cli new`.
///
/// Adapted from the MIT-licensed `justjavac/ci` package
/// (https://github.com/justjavac/moonbit-ci). The scaffold only needs the
/// boolean "are we in CI" answer, which the upstream package derives purely
/// from provider environment variables plus the generic `CI` variable; its
/// git metadata fallback does not influence that boolean and is not ported.

///|
/// Environment variables set by known CI providers.
let ci_provider_env_vars : Array[String] = [
  "APPVEYOR", "bamboo_agentId", "BITBUCKET_BUILD_NUMBER", "BITRISE_IO", "BUDDY_WORKSPACE_ID",
  "BUILDKITE", "CIRCLECI", "CIRRUS_CI", "CODEBUILD_BUILD_ID", "CF_BUILD_ID", "DRONE",
  "GITHUB_ACTION", "GITLAB_CI", "JENKINS_URL", "SAILCI", "SEMAPHORE", "SHIPPABLE",
  "TRAVIS", "BUILD_BUILDURI", "WERCKER_MAIN_PIPELINE_STARTED",
]

///|
/// Return whether the current process appears to be running in CI.
fn is_ci() -> Bool {
  for name in ci_provider_env_vars {
    if env_var_is_set(name) {
      return true
    }
  }
  env_var_is_set("CI")
}

///|
/// Return whether an environment variable is present.
fn env_var_is_set(name : String) -> Bool {
  @env.get_env_var(name) is Some(_)
}
