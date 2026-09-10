// A small, valid BMP-backed ICO with two resolutions. No image tools needed.
export function iconBytes(red) {
  const sizes = [16, 32];
  const directory = Buffer.alloc(6 + 16 * sizes.length);
  directory.writeUInt16LE(1, 2);
  directory.writeUInt16LE(sizes.length, 4);
  let offset = directory.length;
  const images = sizes.map((size, index) => {
    const bitmap = Buffer.alloc(40 + size * size * 4 + Math.ceil(size / 32) * 4 * size);
    bitmap.writeUInt32LE(40, 0);
    bitmap.writeInt32LE(size, 4);
    bitmap.writeInt32LE(size * 2, 8);
    bitmap.writeUInt16LE(1, 12);
    bitmap.writeUInt16LE(32, 14);
    bitmap.writeUInt32LE(bitmap.length - 40, 20);
    for (let pixel = 40; pixel < 40 + size * size * 4; pixel += 4) {
      bitmap[pixel + 2] = red;
      bitmap[pixel + 3] = 255;
    }
    const entry = 6 + index * 16;
    directory[entry] = size;
    directory[entry + 1] = size;
    directory.writeUInt16LE(1, entry + 4);
    directory.writeUInt16LE(32, entry + 6);
    directory.writeUInt32LE(bitmap.length, entry + 8);
    directory.writeUInt32LE(offset, entry + 12);
    offset += bitmap.length;
    return bitmap;
  });
  return Buffer.concat([directory, ...images]);
}
