(function() {
  const rootName = __ROOT_NAME_JS__;
  const extensionName = __EXTENSION_NAME_JS__;
  function normalizeOptions(value) {
    return value && typeof value === 'object' && !Array.isArray(value)
      ? value
      : Object.create(null);
  }
  function readPayload(path, options) {
    const normalized =
      typeof options === 'string' ? { encoding: options } : normalizeOptions(options);
    const payload = { path: path };
    if (typeof normalized.encoding === 'string') {
      payload.encoding = normalized.encoding;
    }
    return payload;
  }
  function writePayload(path, content, options) {
    const normalized =
      typeof options === 'string' ? { encoding: options } : normalizeOptions(options);
    const payload = { path: path, content: content };
    if (typeof normalized.encoding === 'string') {
      payload.encoding = normalized.encoding;
    }
    if (typeof normalized.flush === 'boolean') {
      payload.flush = normalized.flush;
    }
    return payload;
  }
  function statPayload(path, options) {
    const normalized = normalizeOptions(options);
    const payload = { path: path };
    if (typeof normalized.throwIfNoEntry === 'boolean') {
      payload.throw_if_no_entry = normalized.throwIfNoEntry;
    }
    return payload;
  }
  function readdirPayload(path, options) {
    const normalized = normalizeOptions(options);
    const payload = { path: path };
    if (typeof normalized.recursive === 'boolean') {
      payload.recursive = normalized.recursive;
    }
    return payload;
  }
  function mkdirPayload(path, options) {
    const normalized = normalizeOptions(options);
    const payload = { path: path };
    if (typeof normalized.recursive === 'boolean') {
      payload.recursive = normalized.recursive;
    }
    return payload;
  }
  function rmPayload(path, options) {
    const normalized = normalizeOptions(options);
    const payload = { path: path };
    if (typeof normalized.recursive === 'boolean') {
      payload.recursive = normalized.recursive;
    }
    if (typeof normalized.force === 'boolean') {
      payload.force = normalized.force;
    }
    return payload;
  }
  function openFilePayload(path, options) {
    if (typeof options === 'string') {
      return { path: path, flags: options };
    }
    const normalized = normalizeOptions(options);
    const payload = { path: path };
    if (typeof normalized.flags === 'string') {
      payload.flags = normalized.flags;
    }
    if (typeof normalized.read === 'boolean') {
      payload.read = normalized.read;
    }
    if (typeof normalized.write === 'boolean') {
      payload.write = normalized.write;
    }
    if (typeof normalized.append === 'boolean') {
      payload.append = normalized.append;
    }
    if (typeof normalized.create === 'boolean') {
      payload.create = normalized.create;
    }
    if (typeof normalized.truncate === 'boolean') {
      payload.truncate = normalized.truncate;
    }
    if (typeof normalized.createNew === 'boolean') {
      payload.create_new = normalized.createNew;
    }
    return payload;
  }
  function copyFilePayload(src, dest, options) {
    const payload = { src: src, dest: dest };
    if (typeof options === 'boolean') {
      payload.overwrite = options;
      return payload;
    }
    const normalized = normalizeOptions(options);
    if (typeof normalized.overwrite === 'boolean') {
      payload.overwrite = normalized.overwrite;
    }
    return payload;
  }
  function truncatePayload(path, options) {
    if (typeof options === 'number') {
      return { path: path, len: options };
    }
    const normalized = normalizeOptions(options);
    const payload = { path: path };
    if (typeof normalized.len === 'number') {
      payload.len = normalized.len;
    }
    return payload;
  }
  function normalizeAdditionalData(value) {
    if (typeof value === 'string') {
      try {
        return JSON.parse(value);
      } catch {
        return Object.create(null);
      }
    }
    return value && typeof value === 'object' ? value : Object.create(null);
  }
  function releaseSharedBuffer(buffer) {
    if (buffer && window.chrome?.webview?.releaseBuffer) {
      window.chrome.webview.releaseBuffer(buffer);
    }
  }
  function toUint8Array(content) {
    if (content instanceof Uint8Array) {
      return content;
    }
    if (
      content instanceof ArrayBuffer ||
      (typeof SharedArrayBuffer === 'function' && content instanceof SharedArrayBuffer)
    ) {
      return new Uint8Array(content);
    }
    if (ArrayBuffer.isView(content)) {
      return new Uint8Array(content.buffer, content.byteOffset, content.byteLength);
    }
    if (typeof content === 'string') {
      return new TextEncoder().encode(content);
    }
    throw new TypeError('MoonBit fs.writeFileBuffer expects Uint8Array, ArrayBuffer, SharedArrayBuffer, typed array, or string');
  }
  function ridPayload(rid, extra) {
    if (typeof rid !== 'number') {
      throw new TypeError('MoonBit fs rid APIs expect a numeric rid');
    }
    const payload = extra ? Object.assign({}, extra) : Object.create(null);
    payload.rid = rid;
    return payload;
  }
  const root = window[rootName];
  if (!root || typeof root !== 'object' || typeof root['@@ensureExtension'] !== 'function') {
    return;
  }
  const current = root[extensionName];
  if (current && current['@@nodeStyleFs'] === true) {
    return;
  }
  const extensionApi = root['@@ensureExtension'](extensionName);
  const api = Object.create(null);
  let sharedSequence = 0;
  let sharedBufferQueue = Promise.resolve();
  let sharedBufferListenerInstalled = false;
  const pendingSharedBuffers = new Map();
  Object.defineProperty(api, '@@nodeStyleFs', { value: true });
  Object.defineProperty(api, 'name', { value: extensionName, enumerable: true });
  api.invoke = function(apiName, payload) {
    return extensionApi.invoke(apiName, payload);
  };
  api.on = function(eventName, listener) {
    return extensionApi.on(eventName, listener);
  };
  function ensureSharedBufferListener() {
    if (sharedBufferListenerInstalled) {
      return true;
    }
    if (!window.chrome?.webview?.addEventListener) {
      return false;
    }
    window.chrome.webview.addEventListener('sharedbufferreceived', function(event) {
      const data = normalizeAdditionalData(event.additionalData);
      if (
        data.kind !== 'lepus-fs-read-buffer' &&
        data.kind !== 'lepus-fs-write-buffer'
      ) {
        return;
      }
      const sequence = Number(data.sequence);
      const pending = pendingSharedBuffers.get(sequence);
      if (!pending || pending.kind !== data.kind) {
        return;
      }
      pendingSharedBuffers.delete(sequence);
      try {
        const buffer = event.getBuffer();
        const size = Number(data.size);
        const capacity = Number(data.capacity || buffer.byteLength);
        if (buffer.byteLength < size || buffer.byteLength !== capacity) {
          releaseSharedBuffer(buffer);
          pending.reject(
            new Error(
              'fs SharedArrayBuffer size mismatch for #' +
                sequence +
                ': size=' +
                size +
                ', capacity=' +
                capacity +
                ', buffer=' +
                buffer.byteLength,
            ),
          );
          return;
        }
        pending.resolve({ buffer: buffer, size: size, capacity: capacity });
      } catch (error) {
        pending.reject(error);
      }
    });
    sharedBufferListenerInstalled = true;
    return true;
  }
  function waitForSharedBuffer(kind, sequence) {
    if (!ensureSharedBufferListener()) {
      return Promise.reject(
        new Error('fs SharedArrayBuffer transfer requires WebView2 sharedbufferreceived events'),
      );
    }
    return new Promise(function(resolve, reject) {
      const timeout = window.setTimeout(function() {
        pendingSharedBuffers.delete(sequence);
        reject(new Error('Timed out waiting for fs SharedArrayBuffer #' + sequence));
      }, 5000);
      pendingSharedBuffers.set(sequence, {
        kind: kind,
        resolve: function(value) {
          window.clearTimeout(timeout);
          resolve(value);
        },
        reject: function(error) {
          window.clearTimeout(timeout);
          reject(error);
        },
      });
    });
  }
  function enqueueSharedBufferTask(callback) {
    const next = sharedBufferQueue.then(callback, callback);
    sharedBufferQueue = next.catch(function() {});
    return next;
  }
  function nextSharedSequence() {
    sharedSequence += 1;
    if (sharedSequence > 0x3fffffff) {
      sharedSequence = 1;
    }
    return sharedSequence;
  }
  api.sharedBufferSupport = function() {
    return extensionApi.sharedBufferSupport({});
  };
  api.readFileBuffer = function(path) {
    return enqueueSharedBufferTask(async function() {
      const sequence = nextSharedSequence();
      const wait = waitForSharedBuffer('lepus-fs-read-buffer', sequence);
      let received = null;
      try {
        const [reply, nextReceived] = await Promise.all([
          extensionApi.readFileBuffer({ path: path, sequence: sequence }),
          wait,
        ]);
        received = nextReceived;
        const source = new Uint8Array(received.buffer, 0, reply.bytes_read);
        const content = new Uint8Array(reply.bytes_read);
        content.set(source);
        return {
          path: reply.path,
          content: content,
          bytes_read: reply.bytes_read,
          capacity: received.capacity,
        };
      } finally {
        if (received) {
          releaseSharedBuffer(received.buffer);
        } else {
          pendingSharedBuffers.delete(sequence);
        }
      }
    });
  };
  api.writeFileBuffer = function(path, content, options) {
    return enqueueSharedBufferTask(async function() {
      const bytes = toUint8Array(content);
      const sequence = nextSharedSequence();
      const normalized = normalizeOptions(options);
      const wait = waitForSharedBuffer('lepus-fs-write-buffer', sequence);
      let received = null;
      try {
        const [, nextReceived] = await Promise.all([
          extensionApi.writeFileBufferPrepare({
            path: path,
            sequence: sequence,
            size: bytes.byteLength,
            flush: typeof normalized.flush === 'boolean' ? normalized.flush : undefined,
          }),
          wait,
        ]);
        received = nextReceived;
        new Uint8Array(received.buffer, 0, bytes.byteLength).set(bytes);
        return await extensionApi.writeFileBufferCommit({
          sequence: sequence,
          size: bytes.byteLength,
        });
      } finally {
        if (received) {
          releaseSharedBuffer(received.buffer);
        } else {
          pendingSharedBuffers.delete(sequence);
        }
      }
    });
  };
  api.readFile = function(path, options) {
    return extensionApi.readFile(readPayload(path, options));
  };
  api.readTextFile = function(path, options) {
    return extensionApi.readTextFile(readPayload(path, options));
  };
  api.writeFile = function(path, content, options) {
    return extensionApi.writeFile(writePayload(path, content, options));
  };
  api.writeTextFile = function(path, content, options) {
    return extensionApi.writeTextFile(writePayload(path, content, options));
  };
  api.appendFile = function(path, content, options) {
    return extensionApi.appendFile(writePayload(path, content, options));
  };
  api.stat = function(path, options) {
    return extensionApi.stat(statPayload(path, options));
  };
  api.readdir = function(path, options) {
    return extensionApi.readdir(readdirPayload(path, options));
  };
  api.mkdir = function(path, options) {
    return extensionApi.mkdir(mkdirPayload(path, options));
  };
  api.unlink = function(path) {
    return extensionApi.unlink({ path: path });
  };
  api.rm = function(path, options) {
    return extensionApi.rm(rmPayload(path, options));
  };
  api.rename = function(oldPath, newPath) {
    return extensionApi.rename({ old_path: oldPath, new_path: newPath });
  };
  api.copyFile = function(src, dest, options) {
    return extensionApi.copyFile(copyFilePayload(src, dest, options));
  };
  api.realpath = function(path) {
    return extensionApi.realpath({ path: path });
  };
  api.truncate = function(path, options) {
    return extensionApi.truncate(truncatePayload(path, options));
  };
  api.size = function(path) {
    return extensionApi.size({ path: path });
  };
  api.open = function(path, mode) {
    return extensionApi.open({ path: path, mode: typeof mode === 'string' ? mode : 'r' });
  };
  api.openFile = function(path, options) {
    return extensionApi.openFile(openFilePayload(path, options));
  };
  api.read = function(rid, size) {
    return extensionApi.read(ridPayload(rid, { size: size }));
  };
  api.write = function(rid, content) {
    return extensionApi.write(ridPayload(rid, { content: content }));
  };
  api.seek = function(rid, offset, whence) {
    return extensionApi.seek(
      ridPayload(rid, {
        offset: offset,
        whence: typeof whence === 'string' ? whence : 'set',
      }),
    );
  };
  api.fstat = function(rid) {
    return extensionApi.fstat(ridPayload(rid));
  };
  api.flush = function(rid) {
    return extensionApi.flush(ridPayload(rid));
  };
  api.close = function(rid) {
    return extensionApi.close(ridPayload(rid));
  };
  api.exists = function(path) {
    return extensionApi.exists({ path: path });
  };
  root[extensionName] = api;
})();
