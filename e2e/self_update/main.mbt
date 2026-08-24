///|
/// An application that updates itself, used to run the whole chain for real.
///
/// It has two roles. Revision 1 launched with `PROTON_E2E_ROLE=update` checks a
/// channel, downloads, installs and relaunches. `open` inherits that environment
/// when starting revision 2, so the installed revision disambiguates the new
/// process: it records the successful launch and cleans the retained bundle.
/// That second role is the only evidence the relaunch worked, because by then
/// nothing is watching.
async fn main {
  if @env.get_env_var("PROTON_E2E_ROLE") == Some("update") &&
    @updater.current_revision() == 1UL {
    run_update() catch {
      error => {
        println("failed: \{error}")
        panic()
      }
    }
  } else {
    let bundle = running_bundle()
    let version = @mbfs.read_file_to_string(
      "\{bundle}/Contents/Resources/version",
    )
    report_launch(bundle, version)
    @updater.cleanup_previous() catch {
      error => report_launch(bundle, "cleanup failed: " + error.message())
    }
  }
}

///|
/// Returns the bundle this process is running from.
///
/// Derived from argv[0] rather than an environment variable, because that is
/// the only thing a relaunched process is given.
fn running_bundle() -> String {
  parent(parent(parent(@env.args()[0])))
}

///|
/// Records that this build started, beside the bundle it started from.
fn report_launch(bundle : String, version : String) -> Unit raise {
  let log = "\{parent(bundle)}/relaunched.txt"
  let previous = @mbfs.read_file_to_string(log) catch { _ => "" }
  @mbfs.write_string_to_file(log, "\{previous}started \{version}\n")
}

///|
async fn run_update() -> Unit {
  let endpoint = require_env("PROTON_E2E_ENDPOINT")
  let root = require_env("PROTON_E2E_ROOT")
  let base = require_env("PROTON_E2E_BASE")
  let key = require_env("PROTON_E2E_KEY")
  // The running version is read from the bundle, not from the environment.
  // That is what an application would do, and it is what stops a check on
  // launch from offering the same release forever: after the update, this is
  // the new version.
  let bundle = running_bundle()
  let text = @mbfs.read_file_to_string("\{bundle}/Contents/Resources/version")
  let current_revision = @updater.current_revision()
  report_launch(bundle, text)
  println("running \{text}")
  let channel = @updater.UpdateChannel::new(
    endpoint,
    [key],
    "darwin-arm64",
    current_revision,
  )
  // The network is the one piece this harness supplies itself. Every URL is
  // still an https URL, because the manifest schema refuses anything else;
  // only the transport is replaced, so what is exercised below is the real
  // ordering of checks and not a relaxed version of it.
  let fetch : @updater.Fetch = fn(url) raise @updater.UpdateError {
    guard url.has_prefix(base) else {
      raise @updater.FetchFailed(url~, detail="not served by this harness")
    }
    let name = url[base.length():].to_owned()
    @mbfs.read_file_to_bytes("\{root}/\{name}") catch {
      error =>
        raise @updater.FetchFailed(url~, detail=@debug.render(Repr(error)))
    }
  }
  let artifact_fetch : @updater.ArtifactFetch = async fn(
    url,
    _expected_size,
    consume,
  ) -> Unit raise @updater.UpdateError {
    guard url.has_prefix(base) else {
      raise @updater.FetchFailed(url~, detail="not served by this harness")
    }
    let name = url[base.length():].to_owned()
    let file = @async_fs.open("\{root}/\{name}", mode=ReadOnly) catch {
      error =>
        raise @updater.FetchFailed(url~, detail=@debug.render(Repr(error)))
    }
    defer file.close()
    let buffer = FixedArray::make(1024 * 1024, b'\x00')
    for ;; {
      let read = file.read(buffer) catch {
        error =>
          raise @updater.FetchFailed(url~, detail=@debug.render(Repr(error)))
      }
      if read <= 0 {
        break
      }
      consume(buffer.unsafe_reinterpret_as_bytes()[:read].to_owned())
    }
  }
  let bound = @updater.oldest_accepted(30)
  println("checking against \{bound.to_text()}")
  match channel.check(fetch, bound) {
    UpToDate => println("up to date")
    Available(update) => {
      println("offered \{update.version()}")
      ignore(channel.download_and_install(artifact_fetch, update))
      println("installed")
      @updater.relaunch()
      println("relaunched")
    }
  }
}

///|
fn require_env(name : String) -> String raise {
  match @env.get_env_var(name) {
    Some(value) => value
    None => fail("\{name} is not set")
  }
}

///|
fn parent(path : String) -> String {
  let native_path : @mbpath.Path = path
  native_path.dirname().to_string()
}
