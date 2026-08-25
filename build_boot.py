#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build SP523FC S001014 boots from the TRUE FULL stock boot (extracted from the
official update_nowaveform.img at 0x4df226, 65,226,752 bytes).

KEY FIX: the stock boot has a post-ramdisk section (second section 0x32000 +
DTBs, ~321KB) that ALL previous repacks dropped. The header still declares
second_size=0x32000, so the device reads that region; without the real data
the kernel gets no working device tree and hangs before display init.
This build PRESERVES the post-ramdisk section verbatim, shifted to the
page-aligned position after the (possibly larger) new ramdisk.

MODE:
  'magisk' -> Magisk root using the PROVEN-WORKING community payloads (SP101FU
              V3zOF reference) + USB=adb,mtp in prop.default
  'noadb'  -> no magisk, only prop.default USB=adb,mtp (diagnostic)
  'noop'   -> byte-identical stock ramdisk content, only recompressed
              (isolates the recompression variable)
"""
import gzip, hashlib, struct, sys, zlib

SRC_TRUE = 'boot_SP523FC_S001014_original.img'  # true full stock boot (from package, includes second/DTB section)
SRC_REF = r'F:\项目\水墨屏备份\boot_SP101FU_USR_S001345_241216_magisk_patched-28102_V3zOF.img'

MODE = sys.argv[1] if len(sys.argv) > 1 else 'magisk'
assert MODE in ('magisk', 'noadb', 'noop')
OUT = {'magisk': 'boot_SP523FC_S001014_magisk_root_adbmtp.img',
       'noadb': 'boot_SP523FC_S001014_adbmtp_nomagisk.img',
       'noop': 'boot_SP523FC_S001014_noop.img'}[MODE]


def stock_gzip(data, level=6):
    """gzip identical in header to the factory boot: FLG=0 MTIME=0 XFL=0 OS=3"""
    co = zlib.compressobj(level, zlib.DEFLATED, -15)
    body = co.compress(data) + co.flush()
    hdr = bytes([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03])
    trailer = struct.pack('<I', zlib.crc32(data) & 0xffffffff) + \
              struct.pack('<I', len(data) & 0xffffffff)
    return hdr + body + trailer


def read_boot(path):
    d = open(path, 'rb').read()
    page = struct.unpack('<I', d[36:40])[0]
    ks = struct.unpack('<I', d[8:12])[0]
    rs = struct.unpack('<I', d[16:20])[0]
    r_off = (1 + (ks + page - 1) // page) * page
    return d, page, ks, rs, r_off


def read_cpio(dec):
    entries = []
    i = 0
    while i + 110 <= len(dec):
        if dec[i:i+6] != b'070701':
            break
        hdr = dec[i:i+110]
        def H(o): return int(hdr[o:o+8], 16)
        ns = H(94); fs = H(54)
        name = dec[i+110:i+110+ns].rstrip(b'\0').decode('utf-8', 'replace')
        bo = (i + 110 + ns + 3) & ~3
        entries.append(dict(
            name=name, ino=H(0), mode=H(14), uid=H(22), gid=H(30), nlink=H(38),
            mtime=H(46), devmajor=H(62), devminor=H(70), rdevmajor=H(78),
            rdevminor=H(86), check=H(102), data=dec[bo:bo+fs]))
        if name == 'TRAILER!!!':
            break
        i = (bo + fs + 3) & ~3
    return entries


def write_cpio(entries):
    out = bytearray()
    def push(name, mode, uid, gid, nlink, mtime, data, ino=0):
        nonlocal out
        nb = name.encode('utf-8') + b'\0'
        hdr = b'070701'
        for v in (ino, mode, uid, gid, nlink, mtime, len(data),
                  0, 0, 0, 0, len(nb), 0):
            hdr += ('%08x' % v).encode('ascii')
        assert len(hdr) == 110
        out += hdr
        out += nb
        while len(out) % 4:
            out += b'\0'
        out += data
        while len(out) % 4:
            out += b'\0'
    for e in entries:
        push(e['name'], e['mode'], e['uid'], e['gid'], e['nlink'], e['mtime'],
             e['data'], e['ino'])
    push('TRAILER!!!', 0, 0, 0, 1, 0, b'')
    return bytes(out)


def compute_boot_id(img):
    """Compute the RK uboot boot-image SHA1 id (common/image-android.c).

    Hash = SHA1 of, in order:
      kernel_data + kernel_size(u32 LE)
      ramdisk_data + ramdisk_size(u32 LE)
      second_data + second_size(u32 LE)
      recovery_dtbo_data(0 bytes) + recovery_dtbo_size(u32 LE)
      dtb_data + dtb_size(u32 LE)
    Kernel data starts at pgsz (header page skipped); each data block is the
    EXACT size field value (not page-aligned); size fields appended after data.
    NOTE: header field recovery_dtbo_offset is u64, so dtb_size lives at
    offset 1648 (0x670), dtb_addr at 1652 (u64).
    """
    def u32(o): return struct.unpack('<I', img[o:o+4])[0]
    ks, rs, ss, pgsz = u32(8), u32(16), u32(24), u32(36)
    rdbo = u32(1632)
    dsz = u32(1648)
    def AL(v, a): return (v + a - 1) // a * a
    r_off = pgsz + AL(ks, pgsz)
    s_off = r_off + AL(rs, pgsz)
    d_off = s_off + AL(ss, pgsz) + AL(rdbo, pgsz)
    h = hashlib.sha1()
    h.update(img[pgsz:pgsz + ks]); h.update(struct.pack('<I', ks))
    h.update(img[r_off:r_off + rs]); h.update(struct.pack('<I', rs))
    h.update(img[s_off:s_off + ss]); h.update(struct.pack('<I', ss))
    h.update(b''); h.update(struct.pack('<I', rdbo))
    h.update(img[d_off:d_off + dsz]); h.update(struct.pack('<I', dsz))
    return h.digest()


def main():
    base, page, oks, ors, or_off = read_boot(SRC_TRUE)
    print('base true stock: %d bytes, kernel 0x800-0x%x, ramdisk 0x%x-0x%x' % (
        len(base), or_off, or_off, or_off + ors))

    # stock post-ramdisk section: from page-aligned position after stock ramdisk
    post_off = (or_off + ors + page - 1) // page * page
    post = base[post_off:]
    print('preserving post-ramdisk section: %d bytes @0x%x (second_size=0x%x)' % (
        len(post), post_off, struct.unpack('<I', base[24:28])[0]))

    orig_entries = read_cpio(gzip.decompress(base[or_off:or_off+ors]))

    if MODE == 'noop':
        # byte-identical stock content, only recompressed
        new_entries = orig_entries[:]
        mag = None
    else:
        new_entries = []
        mag = None
        for e in orig_entries:
            if e['name'] == 'init' and MODE == 'magisk':
                rd, rpage, rks, rrs, rr_off = read_boot(SRC_REF)
                ref = {x['name']: x for x in read_cpio(gzip.decompress(rd[rr_off:rr_off+rrs]))}
                for n in ('init', 'overlay.d/sbin/magisk.xz', 'overlay.d/sbin/stub.xz',
                          'overlay.d/sbin/init-ld.xz', '.backup/.magisk', '.backup/.rmlist'):
                    assert n in ref, 'reference missing %s' % n
                maginit = dict(ref['init'])
                mg, stub, ld = ref['overlay.d/sbin/magisk.xz'], ref['overlay.d/sbin/stub.xz'], ref['overlay.d/sbin/init-ld.xz']
                rmlist, magcfg = ref['.backup/.rmlist'], dict(ref['.backup/.magisk'])
                cfg = magcfg['data'].decode('utf-8', 'replace')
                cfg_lines = [l for l in cfg.splitlines() if not l.startswith('SHA1=')]
                cfg_lines.append('SHA1=%s' % hashlib.sha1(base).hexdigest())
                magcfg['data'] = ('\n'.join(cfg_lines) + '\n').encode('utf-8')
                mag = dict(maginit=maginit, mg=mg, stub=stub, ld=ld, rmlist=rmlist,
                           magcfg=magcfg, cfg_lines=cfg_lines)

                new_entries.append(maginit)
                for n, ent in [('overlay.d', dict(mode=0o40750, data=b'')),
                               ('overlay.d/sbin', dict(mode=0o40750, data=b'')),
                               ('overlay.d/sbin/init-ld.xz', ld),
                               ('overlay.d/sbin/magisk.xz', mg),
                               ('overlay.d/sbin/stub.xz', stub),
                               ('.backup', dict(mode=0o40000, data=b'')),
                               ('.backup/.magisk', magcfg),
                               ('.backup/.rmlist', rmlist),
                               ('.backup/init', dict(mode=0o120750, data=b'/system/bin/init'))]:
                    e2 = dict(ent)
                    e2['name'] = n
                    e2['uid'] = e2['gid'] = 0
                    e2['nlink'] = 1
                    e2['mtime'] = 0
                    e2['ino'] = 117899520
                    e2.setdefault('devmajor', 0); e2.setdefault('devminor', 0)
                    e2.setdefault('rdevmajor', 0); e2.setdefault('rdevminor', 0)
                    e2.setdefault('check', 0)
                    new_entries.append(e2)
            elif e['name'] == 'TRAILER!!!':
                continue
            else:
                new_entries.append(e)

        # USB composite adb+mtp in prop.default
        for e in new_entries:
            if e['name'] == 'prop.default':
                pd = e['data'].decode('utf-8', 'replace')
                # Force USB=adb. This build's system init.rc has NO
                # "on property:persist.adb.tcp.port=* -> start adbd" trigger, and the
                # USB HAL only honours charging/MTP, so adbd ONLY starts when
                # sys.usb.config=adb fires the existing init trigger. Setting
                # sys.usb.config=adb in prop.default starts adbd + adb gadget at
                # first-stage boot; persist.sys.usb.config=adb keeps the framework
                # from switching back to MTP (REQUIRES /data erase, else the old
                # persisted "none" wins). adbd itself also binds TCP:5555 (persist.
                # adb.tcp.port) as a fallback while it is running.
                pd = pd.replace('persist.sys.usb.config=none', 'persist.sys.usb.config=adb')
                pd += '\nsys.usb.config=adb\n'
                if 'persist.adb.tcp.port' not in pd:
                    pd += '\npersist.adb.tcp.port=5555\n'
                e['data'] = pd.encode('utf-8')
                break

    cpio = write_cpio(new_entries)
    gz = stock_gzip(cpio, 6)

    # assemble: header + kernel + new ramdisk + post-ramdisk section
    hdr = bytearray(base[:0x800])
    struct.pack_into('<I', hdr, 16, len(gz))
    out = bytearray(bytes(hdr) + base[0x800:or_off] + gz)
    while len(out) % page:
        out += b'\0'
    out += post
    while len(out) % page:
        out += b'\0'

    # RK uboot SHA1-verifies the boot image against the header id field
    # (image-android.c: "Hash from header" / "Hash real" / "ANDROID: Hash OK").
    # A modified ramdisk changes the hash, so the id MUST be recomputed for
    # the new content (stock id would fail the check -> no boot).
    img = bytes(out)
    boot_id = compute_boot_id(img)
    out[0x240:0x254] = boot_id
    out[0x254:0x260] = b'\0' * 12
    print('  boot id: %s' % boot_id.hex())

    open(OUT, 'wb').write(bytes(out))
    print('wrote %s (%d bytes = 0x%x)' % (OUT, len(out), len(out)))
    print('  ramdisk gz %d bytes, post-ramdisk %d bytes preserved' % (len(gz), len(post)))
    if mag:
        print('  magisk payloads from reference (proven boot):')
        print('    magiskinit %d, magisk.xz %d, stub %d, init-ld %d' % (
            len(mag['maginit']['data']), len(mag['mg']['data']),
            len(mag['stub']['data']), len(mag['ld']['data'])))
        print('    .backup/.magisk: %s' % ' | '.join(mag['cfg_lines']))


if __name__ == '__main__':
    main()
