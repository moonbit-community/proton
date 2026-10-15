///|
async test "metadata streaming accepts the exact limit and closes oversized chunked responses early" {
  for size in [maximum_metadata_bytes, maximum_metadata_bytes + 1] {
    @async.with_timeout(5000, () => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      @async.with_task_group(group => {
        let peer_closed = Ref(false)
        let sender = group.spawn(() => {
          let (conn, _) = server.accept()
          defer conn.close()
          ignore(conn.read_request())
          conn.send_response(200, "OK")
          conn.write(Bytes::make(size, b'x'))
          conn.flush()
          if size == maximum_metadata_bytes {
            conn.end_response()
          }
          // Oversized responses deliberately never finish. Rejection must
          // close the connection without waiting for EOF from the server.
          ignore(conn.read_request()) catch {
            _ => peer_closed.val = true
          }
        })
        let url = "http://\{server.addr}"
        if size == maximum_metadata_bytes {
          assert_eq(fetch_metadata_stream(url).length(), size)
        } else {
          try ignore(fetch_metadata_stream(url)) catch {
            FetchFailed(detail~, ..) =>
              assert_true(detail.contains("byte limit"))
            error => raise error
          } noraise {
            _ => fail("oversized metadata was accepted")
          }
        }
        sender.wait()
        assert_true(peer_closed.val)
      })
    })
  }
}

///|
async test "metadata cancellation closes the streaming connection" {
  @async.with_timeout(5000, () => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    @async.with_task_group(group => {
      let started = Ref(false)
      let closed = Ref(false)
      let sender = group.spawn(() => {
        let (conn, _) = server.accept()
        defer conn.close()
        ignore(conn.read_request())
        conn.send_response(200, "OK")
        conn.write("partial metadata")
        conn.flush()
        started.val = true
        ignore(conn.read_request()) catch {
          _ => closed.val = true
        }
      })
      let reader = group.spawn(allow_failure=true, () => {
        fetch_metadata_stream("http://\{server.addr}")
      })
      while !started.val {
        @async.sleep(5)
      }
      reader.cancel()
      ignore(reader.wait()) catch {
        _ => ()
      }
      sender.wait()
      assert_true(closed.val)
    })
  })
}

///|
test "redirect resolution preserves encoded paths and supplies empty root paths" {
  let base = "https://example.com/releases/latest.json?old=1"
  for
    (location, expected) in [
      (
        "https://cdn.example.com/signed/%2E/file?token=a%2Fb#omit", "https://cdn.example.com/signed/%2E/file?token=a%2Fb",
      ),
      (
        "//cdn.example.com/signed/%2e%2E/file?token=a%2Fb", "https://cdn.example.com/signed/%2e%2E/file?token=a%2Fb",
      ),
      (
        "../signed/%2E/file?token=a%2Fb", "https://example.com/signed/%2E/file?token=a%2Fb",
      ),
      ("/signed/%2e%2e/file", "https://example.com/signed/%2e%2e/file"),
      (
        "https://cdn.example.com?token=a%2Fb", "https://cdn.example.com/?token=a%2Fb",
      ),
      ("//cdn.example.com?token=a%2Fb", "https://cdn.example.com/?token=a%2Fb"),
      ("?token=a%2Fb", "https://example.com/releases/latest.json?token=a%2Fb"),
      ("#omit", "https://example.com/releases/latest.json?old=1"),
      ("../downloads/./nested/../file", "https://example.com/downloads/file"),
      ("../downloads/..", "https://example.com/"),
      ("../../file", "https://example.com/file"),
      ("../downloads//file", "https://example.com/downloads//file"),
    ] {
    assert_eq(update_redirect_url(base, location), expected)
  }
  assert_eq(
    update_redirect_url("https://example.com/signed/%2E/latest.json", "file"),
    "https://example.com/signed/%2E/file",
  )
}
