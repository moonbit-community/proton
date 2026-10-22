///|
async fn with_download_server(
  serve : async (@socket.Tcp) -> Unit,
  run : async (String) -> Unit,
) -> Unit {
  @async.with_timeout(10000, () => {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    @async.with_task_group(group => {
      let sender = group.spawn(() => {
        let (connection, _) = server.accept()
        defer connection.close()
        serve(connection)
      })
      run("http://\{server.addr}/file")
      sender.wait()
    })
  })
}

///|
async test "download streams authenticated binary content and reports written bytes" {
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  let destination = root + "/下载.bin"
  let content = Bytes::make(2 * 1024 * 1024, b'\xff')
  let progress : Array[@net.DownloadProgress] = []
  with_download_server(
    connection => {
      let request = connection.read_until("\r\n\r\n").unwrap()
      assert_true(request.contains("Authorization: Bearer test-token\r\n"))
      assert_true(request.contains("Accept-Encoding: identity\r\n"))
      assert_true(request.has_prefix("GET /file?q=1 HTTP/1.1\r\n"))
      connection.write(
        "HTTP/1.1 200 OK\r\nContent-Length: \{content.length()}\r\n\r\n",
      )
      connection.write(content)
    },
    url => {
      @net.download(
        url + "?q=1#fragment",
        destination,
        headers={ "Authorization": "Bearer test-token" },
        on_progress=p => progress.push(p),
      )
    },
  )
  assert_eq(@fs.read_file(destination).binary(), content)
  assert_eq(progress[0].received_bytes, 0L)
  assert_eq(
    progress.last().unwrap().received_bytes,
    content.length().to_int64(),
  )
  for p in progress {
    assert_eq(p.total_bytes, Some(content.length().to_int64()))
  }
  assert_eq(@fs.readdir(root), ["下载.bin"])
}

///|
async test "download handles empty chunked and unknown-length identity responses" {
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  let cases = [
    ("Content-Length: 0\r\n", b"", b"", Some(0L)),
    (
      "Transfer-Encoding: chunked\r\n",
      b"2\r\nhe\r\n3\r\nllo\r\n0\r\n\r\n",
      b"hello",
      None,
    ),
    ("Connection: close\r\n", b"hello", b"hello", None),
    (
      "Content-Encoding: identity\r\nContent-Length: 5\r\n",
      b"hello",
      b"hello",
      Some(5L),
    ),
  ]
  for index, (headers, body, expected, total) in cases {
    let progress : Array[@net.DownloadProgress] = []
    let destination = root + "/\{index}"
    with_download_server(
      connection => {
        ignore(connection.read_until("\r\n\r\n"))
        connection.write("HTTP/1.1 200 OK\r\n\{headers}\r\n")
        connection.write(body)
      },
      url => @net.download(url, destination, on_progress=p => progress.push(p)),
    )
    assert_eq(@fs.read_file(destination).binary(), expected)
    assert_eq(
      progress.last().unwrap().received_bytes,
      expected.length().to_int64(),
    )
    assert_eq(progress.last().unwrap().total_bytes, total)
  }
}

///|
async test "HTTP failures redirects and partial responses preserve existing files" {
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  let destination = root + "/file"
  @fs.write_file(destination, "old")
  for status in [401, 403, 404, 302, 206] {
    with_download_server(
      connection => {
        ignore(connection.read_until("\r\n\r\n"))
        connection.write(
          "HTTP/1.1 \{status} Rejected\r\nContent-Length: 0\r\nLocation: /other\r\n\r\n",
        )
      },
      url => {
        try @net.download(url, destination, overwrite=true) catch {
          @net.HttpStatus(status=actual) => assert_eq(actual, status)
          error => raise error
        } noraise {
          _ => fail("expected HTTP failure")
        }
      },
    )
    assert_eq(@fs.read_file(destination).text(), "old")
    assert_eq(@fs.readdir(root), ["file"])
  }
}

///|
async test "truncated downloads clean up without replacing the old file" {
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  let destination = root + "/file"
  @fs.write_file(destination, "old")
  with_download_server(
    connection => {
      ignore(connection.read_until("\r\n\r\n"))
      connection.write("HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\npartial")
    },
    url => {
      try @net.download(url, destination, overwrite=true) catch {
        @net.NetworkFailed(..) => ()
        error => raise error
      } noraise {
        _ => fail("expected truncated response failure")
      }
    },
  )
  assert_eq(@fs.read_file(destination).text(), "old")
  assert_eq(@fs.readdir(root), ["file"])
}

///|
async test "overwrite is explicit and failed file submission cleans up" {
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  // Error paths preserve the caller's spelling, including redundant components.
  let destination = root + "/./file"
  @fs.write_file(destination, "old")
  for overwrite in [false, true] {
    with_download_server(
      connection => {
        ignore(connection.read_until("\r\n\r\n"))
        connection.write("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nnew")
      },
      url => {
        if overwrite {
          @net.download(url, destination, overwrite=true)
        } else {
          try @net.download(url, destination) catch {
            @net.DestinationExists(path~) => assert_eq(path, destination)
            error => raise error
          } noraise {
            _ => fail("existing file was overwritten")
          }
        }
      },
    )
    assert_eq(
      @fs.read_file(destination).text(),
      if overwrite {
        "new"
      } else {
        "old"
      },
    )
    assert_eq(@fs.readdir(root), ["file"])
  }
  let invalid_parents = ["/missing/file", "/file/other"]
  if @async.platform is (MacOS | Linux) {
    invalid_parents.push("/missing/../file")
    invalid_parents.push("/file/../other")
  }
  for suffix in invalid_parents {
    let destination = root + suffix
    try @net.download("http://127.0.0.1:1/file", destination) catch {
      @net.FileFailed(detail~) => assert_true(detail.contains(destination))
      error => raise error
    } noraise {
      _ => fail("invalid parent was accepted")
    }
  }
}

///|
async test "cancellation closes a stalled response and removes its temporary file" {
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  let destination = root + "/file"
  @fs.write_file(destination, "old")
  let ready : @async.Queue[Unit] = @async.Queue(kind=Unbounded)
  let peer_closed = Ref(false)
  with_download_server(
    connection => {
      ignore(connection.read_until("\r\n\r\n"))
      connection.write("HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\npartial")
      assert_eq(connection.read_some(), None)
      peer_closed.val = true
    },
    url => {
      @async.with_task_group(group => {
        let reader = group.spawn(allow_failure=true, () => {
          @net.download(url, destination, overwrite=true, on_progress=_ => {
            ignore(try! ready.try_put(()))
          })
        })
        ready.get()
        // Wait for actual file IO, while the server deliberately withholds EOF.
        let files = @fs.readdir(root)
        let temporary = files.filter(name => name.has_suffix(".part"))[0]
        while @fs.file_size(root + "/" + temporary) == 0L {
          @async.pause()
        }
        reader.cancel()
        try reader.wait() catch {
          @async.WaitedTaskAlreadyCancelled => ()
          error => raise error
        } noraise {
          _ => fail("download did not cancel")
        }
      })
    },
  )
  assert_true(peer_closed.val)
  assert_eq(@fs.read_file(destination).text(), "old")
  assert_eq(@fs.readdir(root), ["file"])
}

///|
async test "concurrent downloads cannot both claim the same destination" {
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  let destination = root + "/file"
  @async.with_timeout(10000, () => {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let ready : @async.Queue[Unit] = @async.Queue(kind=Unbounded)
    let release : @async.Queue[Unit] = @async.Queue(kind=Unbounded)
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        for content in ["one", "two"] {
          let (connection, _) = server.accept()
          group.spawn_bg(() => {
            defer connection.close()
            ignore(connection.read_until("\r\n\r\n"))
            connection.write("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\n")
            release.get()
            connection.write(content)
          })
        }
      })
      let tasks = Array::makei(2, _ => {
        group.spawn(() => {
          try
            @net.download("http://\{server.addr}/file", destination, on_progress=p => {
              if p.received_bytes == 0L {
                ignore(try! ready.try_put(()))
              }
            })
          catch {
            @net.DestinationExists(..) => false
            error => raise error
          } noraise {
            _ => true
          }
        })
      })
      ready.get()
      ready.get()
      assert_false(@fs.exists(destination))
      release.put(())
      release.put(())
      assert_true(tasks[0].wait() != tasks[1].wait())
    })
  })
  let content = @fs.read_file(destination).text()
  assert_true(content == "one" || content == "two")
  assert_eq(@fs.readdir(root), ["file"])
}

///|
async test "cancellation at the final progress notification does not submit the file" {
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  let destination = root + "/file"
  @fs.write_file(destination, "old")
  with_download_server(
    connection => {
      ignore(connection.read_until("\r\n\r\n"))
      connection.write("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nnew")
    },
    url => {
      @async.with_task_group(group => {
        let task : Ref[@async.Task[Unit]?] = Ref(None)
        let reader = group.spawn(allow_failure=true, () => {
          @net.download(url, destination, overwrite=true, on_progress=p => {
            if p.received_bytes == 3L {
              task.val.unwrap().cancel()
            }
          })
        })
        task.val = Some(reader)
        try reader.wait() catch {
          @async.WaitedTaskAlreadyCancelled => ()
          error => raise error
        } noraise {
          _ => fail("cancelled download was submitted")
        }
      })
    },
  )
  assert_eq(@fs.read_file(destination).text(), "old")
  assert_eq(@fs.readdir(root), ["file"])
}

///|
async test "download rejects invalid requests before creating files" {
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  for
    (url, headers) in [
      ("file:///tmp/input", {}),
      ("https:///file", {}),
      ("http://127.0.0.1/file", { "rAnGe": "bytes=0-1" }),
    ] {
    try @net.download(url, root + "/file", headers~) catch {
      @net.InvalidRequest(..) => ()
      error => raise error
    } noraise {
      _ => fail("invalid request was accepted")
    }
  }
  let invalid_destinations = [
    "",
    ".",
    "..",
    root + "/",
    root + "/.",
    root + "/..",
  ]
  if @async.platform is Windows {
    invalid_destinations.push(root + "\\")
    invalid_destinations.push("C:")
    invalid_destinations.push("C:\\")
  }
  for destination in invalid_destinations {
    try @net.download("http://127.0.0.1:1/file", destination) catch {
      @net.InvalidRequest(..) => ()
      error => raise error
    } noraise {
      _ => fail("directory path was accepted as a file name")
    }
  }
  assert_eq(@fs.readdir(root), [])
}

///|
async test "relative destination paths are resolved before file submission" {
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  let destination = @path.Path(root + "/relative.bin")
    .relative(base=@path.Path(".").resolve())
    .to_string()
  with_download_server(
    connection => {
      ignore(connection.read_until("\r\n\r\n"))
      connection.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
    },
    url => @net.download(url, destination),
  )
  assert_eq(@fs.read_file(root + "/relative.bin").text(), "ok")
  assert_eq(@fs.readdir(root), ["relative.bin"])
}

///|
async test "encoded responses are rejected instead of saving gzip bytes" {
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  let destination = root + "/file"
  @fs.write_file(destination, "old")
  // async#672: even a valid gzip stream can bypass decoding with close framing.
  let gzip = b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x02\x03\xcb\x48\xcd\xc9\xc9\x07\x00\x86\xa6\x10\x36\x05\x00\x00\x00"
  for
    (framing, body) in [
      ("Connection: close\r\n", gzip),
      ("Content-Length: 25\r\n", gzip),
      ("Transfer-Encoding: chunked\r\n", b"19\r\n" + gzip + b"\r\n0\r\n\r\n"),
    ] {
    for explicit_encoding in [false, true] {
      let progress_called = Ref(false)
      with_download_server(
        connection => {
          let request = connection.read_until("\r\n\r\n").unwrap()
          assert_true(
            request.contains(
              if explicit_encoding {
                "Accept-Encoding: gzip\r\n"
              } else {
                "Accept-Encoding: identity\r\n"
              },
            ),
          )
          connection.write(
            @utf8.encode(
              "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\n\{framing}\r\n",
            ) +
            body,
          )
        },
        url => {
          try
            @net.download(
              url,
              destination,
              overwrite=true,
              headers=if explicit_encoding {
                { "Accept-Encoding": "gzip" }
              } else {
                {}
              },
              on_progress=_ => progress_called.val = true,
            )
          catch {
            @net.NetworkFailed(detail~) =>
              assert_true(detail.contains("identity encoding"))
            error => raise error
          } noraise {
            _ => fail("encoded bytes were accepted as a complete download")
          }
        },
      )
      assert_false(progress_called.val)
      assert_eq(@fs.read_file(destination).text(), "old")
      assert_eq(@fs.readdir(root), ["file"])
    }
  }
}

///|
async test "download preserves symlink parent traversal for existing and new files" {
  guard @async.platform is (MacOS | Linux) else { return }
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  @fs.mkdir(root + "/local")
  @fs.mkdir(root + "/other/child", recursive=true)
  @fs.symlink(target="../other/child", root + "/local/link")
  for relative in [false, true] {
    let base = if relative {
      @path.Path(root).relative(base=@path.Path(".").resolve()).to_string()
    } else {
      root
    }
    for overwrite in [false, true] {
      let name = "file-\{relative}-\{overwrite}"
      let destination = base + "/local/link/../" + name
      let intended = root + "/other/" + name
      let unrelated = root + "/local/" + name
      @fs.write_file(unrelated, "unrelated")
      if overwrite {
        @fs.write_file(intended, "old")
      }
      with_download_server(
        connection => {
          ignore(connection.read_until("\r\n\r\n"))
          connection.write("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nnew")
        },
        url => @net.download(url, destination, overwrite~),
      )
      assert_eq(@fs.read_file(intended).text(), "new")
      assert_eq(@fs.read_file(unrelated).text(), "unrelated")
    }
  }
  assert_false(
    @fs.readdir(root + "/other").any(name => {
      name.has_prefix(".proton-download-")
    }),
  )
  assert_false(
    @fs.readdir(root + "/local").any(name => {
      name.has_prefix(".proton-download-")
    }),
  )
}

///|
async test "download replaces a final symlink without changing its target" {
  guard @async.platform is (MacOS | Linux) else { return }
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(root + "/target", "original")
  @fs.symlink(target="target", root + "/link")
  for overwrite in [false, true] {
    with_download_server(
      connection => {
        ignore(connection.read_until("\r\n\r\n"))
        connection.write("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nnew")
      },
      url => {
        try @net.download(url, root + "/link", overwrite~) catch {
          @net.DestinationExists(path~) => {
            assert_false(overwrite)
            assert_eq(path, root + "/link")
          }
          error => raise error
        } noraise {
          _ => assert_true(overwrite)
        }
      },
    )
    assert_eq(@fs.read_file(root + "/target").text(), "original")
  }
  assert_eq(@fs.read_file(root + "/link").text(), "new")
  assert_eq(@fs.readdir(root, sort=true), ["link", "target"])
}

///|
async test "download resolves directory links including Windows junctions" {
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  @fs.mkdir(root + "/parent")
  @fs.symlink(target=root + "/parent", root + "/alias")
  with_download_server(
    connection => {
      ignore(connection.read_until("\r\n\r\n"))
      connection.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
    },
    url => @net.download(url, root + "/alias/file"),
  )
  assert_eq(@fs.read_file(root + "/parent/file").text(), "ok")
  assert_eq(@fs.readdir(root + "/parent"), ["file"])
}

///|
async test "download does not require permission to list the parent directory" {
  guard @async.platform is (MacOS | Linux) else { return }
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  @fs.chmod(root, 0o300)
  defer @fs.chmod(root, 0o700)
  with_download_server(
    connection => {
      ignore(connection.read_until("\r\n\r\n"))
      connection.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
    },
    url => @net.download(url, root + "/file"),
  )
  assert_eq(@fs.read_file(root + "/file").text(), "ok")
}

///|
async test "download preserves Windows extended paths with trailing dots" {
  guard @async.platform is Windows else { return }
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  let absolute = @path.Path(root).resolve().to_string()
  let extended = if absolute.has_prefix("\\\\?\\") {
    absolute
  } else if absolute.has_prefix("\\\\") {
    "\\\\?\\UNC\\" + absolute[2:].to_owned()
  } else {
    "\\\\?\\" + absolute
  }
  let parent = extended + "\\folder."
  @fs.mkdir(parent)
  // Keep backslashes: async's recursive rmdir joins children with '/'.
  defer {
    for name in @fs.readdir(parent) {
      @fs.remove(parent + "\\" + name)
    }
    @fs.rmdir(parent)
  }
  for ordinary_exists in [false, true] {
    let ordinary = absolute + "\\folder"
    if ordinary_exists {
      @fs.mkdir(ordinary)
      @fs.write_file(ordinary + "\\report", "unrelated")
    }
    let destination = parent + "\\report"
    with_download_server(
      connection => {
        ignore(connection.read_until("\r\n\r\n"))
        connection.write("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nnew")
      },
      url => @net.download(url, destination, overwrite=ordinary_exists),
    )
    assert_eq(@fs.read_file(destination).text(), "new")
    assert_eq(@fs.readdir(parent), ["report"])
    if ordinary_exists {
      assert_eq(@fs.read_file(ordinary + "\\report").text(), "unrelated")
      assert_eq(@fs.readdir(ordinary), ["report"])
    } else {
      assert_eq(@fs.readdir(root), ["folder."])
    }
  }
}
