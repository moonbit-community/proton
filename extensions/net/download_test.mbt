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
async test "download handles empty chunked unknown-length and gzip responses" {
  let root = @fs.tmpdir(prefix="proton-net-download-")
  defer @fs.rmdir(root, recursive=true)
  // gzip representation of 'hello', generated independently of the HTTP client.
  let gzip = b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x02\x03\xcb\x48\xcd\xc9\xc9\x07\x00\x86\xa6\x10\x36\x05\x00\x00\x00"
  let cases = [
    ("Content-Length: 0\r\n", b"", b"", Some(0L)),
    (
      "Transfer-Encoding: chunked\r\n",
      b"2\r\nhe\r\n3\r\nllo\r\n0\r\n\r\n",
      b"hello",
      None,
    ),
    ("Connection: close\r\n", b"hello", b"hello", None),
    ("Content-Encoding: gzip\r\nContent-Length: 25\r\n", gzip, b"hello", None),
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
  let destination = root + "/file"
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
  with_download_server(
    connection => {
      ignore(connection.read_until("\r\n\r\n"))
      connection.write("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
    },
    url => {
      try @net.download(url, root + "/missing/file") catch {
        @net.FileFailed(..) => ()
        error => raise error
      } noraise {
        _ => fail("missing parent was accepted")
      }
    },
  )
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
