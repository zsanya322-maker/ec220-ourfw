#!/usr/bin/env python3
"""Verify the *final* EC220 Padavan image without external binwalk/unsquashfs.

Padavan uses SquashFS v4/XZ.  This parser is intentionally small and read-only;
it walks the image produced by our pinned build and verifies that CORE/BUILTINS
and the immutable OURFW rescue payload actually survived image creation.
"""
from __future__ import annotations
import argparse, bz2, hashlib, io, lzma, posixpath, struct, sys, tarfile
from pathlib import Path

SB_FMT = '<IIIIIHHHHHHQQQQQQQQ'
MAGIC = 0x73717368
META_UNCOMP = 1 << 15
DATA_UNCOMP = 1 << 24
DATA_MASK = 0x00FFFFFF
INVALID_FRAG = 0xFFFFFFFF

class Squash:
    def __init__(self, image: bytes):
        self.image=image
        self.base=image.find(b'hsqs')
        if self.base < 0: raise ValueError('SquashFS magic not found')
        v=struct.unpack_from(SB_FMT,image,self.base)
        if v[0] != MAGIC or v[9] != 4: raise ValueError('not SquashFS v4')
        self.inodes=v[1]; self.block_size=v[3]; self.fragments=v[4]; self.comp=v[5]
        self.root_ref=v[11]; self.bytes_used=v[12]
        self.id_table=v[13]; self.xattr_table=v[14]; self.inode_table=v[15]
        self.dir_table=v[16]; self.frag_table=v[17]; self.lookup=v[18]
        self.fs=image[self.base:self.base+self.bytes_used]
        self.meta_cache={}
        self.frag_entries=self._load_fragments()
        self.paths={}
        self._walk(self.root_ref,'')

    def _decomp(self,payload:bytes)->bytes:
        if self.comp == 4: return lzma.decompress(payload,format=lzma.FORMAT_XZ)
        raise ValueError(f'unsupported SquashFS compression id {self.comp}')

    def meta(self,rel:int):
        if rel in self.meta_cache: return self.meta_cache[rel]
        hdr=struct.unpack_from('<H',self.fs,rel)[0]; size=hdr & 0x7fff
        raw=self.fs[rel+2:rel+2+size]
        dec=raw if hdr & META_UNCOMP else self._decomp(raw)
        out=(dec,rel+2+size); self.meta_cache[rel]=out; return out

    def meta_stream(self,table:int,block:int,offset:int,n:int)->bytes:
        out=bytearray(); rel=table+block
        while len(out)<n:
            dec,nxt=self.meta(rel)
            if offset >= len(dec): offset-=len(dec); rel=nxt; continue
            take=min(n-len(out),len(dec)-offset); out+=dec[offset:offset+take]
            if len(out)>=n: break
            rel=nxt; offset=0
        return bytes(out)

    def inode_base(self,ref:int):
        block,off=ref>>16,ref&0xffff
        b=self.meta_stream(self.inode_table,block,off,16)
        typ,mode,uid,gid,mtime,ino=struct.unpack('<HHHHII',b)
        return typ,mode,uid,gid,mtime,ino,block,off

    def inode(self,ref:int):
        typ,mode,uid,gid,mtime,ino,block,off=self.inode_base(ref)
        raw=self.meta_stream(self.inode_table,block,off,256)
        d={'type':typ,'mode':mode,'ino':ino,'ref':ref,'kind':'other'}; p=16
        if typ==1:
            start,nlink,size,doff,parent=struct.unpack_from('<IIHHI',raw,p)
            d.update(kind='dir',start_block=start,file_size=size,offset=doff)
        elif typ==8:
            nlink,size,start,parent,icount,doff,xattr=struct.unpack_from('<IIIIHHI',raw,p)
            d.update(kind='dir',start_block=start,file_size=size,offset=doff)
        elif typ==2:
            start,frag,foff,size=struct.unpack_from('<IIII',raw,p)
            nb=size//self.block_size if frag!=INVALID_FRAG else (size+self.block_size-1)//self.block_size
            bs=self.meta_stream(self.inode_table,block,off+p+16,nb*4) if nb else b''
            d.update(kind='file',start_block=start,fragment=frag,offset=foff,file_size=size,
                     block_sizes=list(struct.unpack('<'+'I'*nb,bs)) if nb else [])
        elif typ==9:
            start,size,sparse,nlink,frag,foff,xattr=struct.unpack_from('<QQQIIII',raw,p)
            nb=size//self.block_size if frag!=INVALID_FRAG else (size+self.block_size-1)//self.block_size
            bs=self.meta_stream(self.inode_table,block,off+p+40,nb*4) if nb else b''
            d.update(kind='file',start_block=start,fragment=frag,offset=foff,file_size=size,
                     block_sizes=list(struct.unpack('<'+'I'*nb,bs)) if nb else [])
        elif typ in (3,10):
            nlink,size=struct.unpack_from('<II',raw,p)
            target=self.meta_stream(self.inode_table,block,off+p+8,size).decode('utf-8','replace')
            d.update(kind='symlink',target=target,file_size=size)
        return d

    def dir_entries(self,ino):
        raw=self.meta_stream(self.dir_table,ino['start_block'],ino['offset'],ino['file_size'])
        p=0; out=[]
        while p+12<=len(raw):
            count,start,baseino=struct.unpack_from('<III',raw,p); p+=12
            if count>4096: break
            for _ in range(count+1):
                if p+8>len(raw): return out
                entoff,inooff,typ,size=struct.unpack_from('<HhHH',raw,p); p+=8
                n=size+1
                if p+n>len(raw): return out
                name=raw[p:p+n].decode('utf-8','replace'); p+=n
                out.append((name,(start<<16)|entoff))
            if p>=len(raw)-3: break
        return out

    def _walk(self,ref:int,path:str):
        ino=self.inode(ref); here=path or '/'; self.paths[here]=ino
        if ino['kind']=='dir':
            for name,child in self.dir_entries(ino):
                self._walk(child,(path.rstrip('/')+'/'+name) if path else '/'+name)

    def _load_fragments(self):
        if not self.fragments: return []
        per=8192//16; indexes=(self.fragments+per-1)//per; buf=bytearray()
        for i in range(indexes):
            ptr=struct.unpack_from('<Q',self.fs,self.frag_table+i*8)[0]
            dec,_=self.meta(ptr); buf+=dec
        return [struct.unpack_from('<QII',buf,i*16) for i in range(self.fragments)]

    def _data_block(self,start:int,flag:int):
        if flag==0: return b'\0'*self.block_size,0
        n=flag & DATA_MASK; raw=self.fs[start:start+n]
        return (raw if flag & DATA_UNCOMP else self._decomp(raw)),n

    def read(self,path:str)->bytes:
        ino=self.paths[path]
        if ino['kind']=='symlink': return ino['target'].encode()
        if ino['kind']!='file': raise ValueError(f'{path} is not file')
        out=bytearray(); pos=ino['start_block']
        for flag in ino['block_sizes']:
            dec,n=self._data_block(pos,flag); out+=dec; pos+=n
        if ino['fragment']!=INVALID_FRAG:
            start,flag,_=self.frag_entries[ino['fragment']]; dec,_=self._data_block(start,flag)
            remain=ino['file_size']-len(out); out+=dec[ino['offset']:ino['offset']+remain]
        return bytes(out[:ino['file_size']])

    def exists_inside(self,path:str)->bool:
        ino=self.paths.get(path)
        if not ino: return False
        if ino['kind']!='symlink': return True
        target=ino['target']
        if target.startswith('/'):
            resolved=posixpath.normpath(target)
        else:
            resolved=posixpath.normpath(posixpath.join(posixpath.dirname(path),target))
        return resolved in self.paths


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('image'); ap.add_argument('report',nargs='?',default='IMAGE-VERIFY.txt'); a=ap.parse_args()
    image=Path(a.image); report=Path(a.report); data=image.read_bytes(); sq=Squash(data)
    errs=[]
    def need(cond,msg):
        if not cond: errs.append(msg)
    required=['/usr/bin/ourfw-loader.sh','/usr/share/ourfw/defaults.tar.bz2','/www/ourfw/index.asp','/www/ourfw/assets/ourfw.js','/www/ourfw/assets/ourfw.css','/usr/sbin/httpd','/usr/sbin/dropbear','/usr/sbin/wg','/usr/sbin/awg','/usr/sbin/openvpn','/usr/libexec/sftp-server','/usr/bin/openssl','/usr/bin/https-cert.sh','/usr/bin/nfqws','/usr/bin/zapret.sh','/usr/bin/sha256sum','/bin/base64','/usr/bin/autostart.sh']
    for p in required: need(sq.exists_inside(p),f'missing/broken {p}')
    need(any(sq.exists_inside(p) for p in ['/usr/bin/curl','/usr/sbin/curl','/bin/curl']), 'missing curl binary')
    need(any(p.startswith('/lib/libssl.so') for p in sq.paths), 'missing libssl')
    need(any(p.startswith('/lib/libcrypto.so') for p in sq.paths), 'missing libcrypto')
    for mod in ['wireguard.ko','amneziawg.ko','nfnetlink_queue.ko','xt_NFQUEUE.ko','ip6table_mangle.ko','zram.ko']:
        need(any(p.endswith('/'+mod) for p in sq.paths),f'missing kernel module {mod}')
    if '/usr/sbin/httpd' in sq.paths:
        httpd=sq.read('/usr/sbin/httpd')
        need(b'ourfw_api.cgi' in httpd,'compiled httpd lacks OURFW API')
        need(b'file-chunk' in httpd and b'/tmp/ourfw-csrf.token' in httpd and b'/etc/storage/ourfw/runtime/ourfw-api.sh' in httpd,'compiled httpd lacks v0.5 bounded/CSRF bridge')
    if '/usr/bin/autostart.sh' in sq.paths: need(b'ourfw-loader.sh' in sq.read('/usr/bin/autostart.sh'),'autostart lacks OURFW loader')
    if '/usr/share/ourfw/defaults.tar.bz2' in sq.paths:
        try:
            arc=sq.read('/usr/share/ourfw/defaults.tar.bz2')
            with tarfile.open(fileobj=io.BytesIO(arc),mode='r:bz2') as tf: names=set(tf.getnames())
            for n in ['./runtime/ourfwctl.sh','./runtime/ourfw-api.sh','./runtime/ourfw-transfer.sh','./runtime/ourfw-backup.sh','./runtime/ourfw-ui.sh','./modules/smart-routing/apply.sh','./modules/vpn/apply.sh','./modules/vpn/failover.sh','./modules/adblock/apply.sh','./modules/adblock/update.sh','./modules/zram/apply.sh','./modules/watchdog/event.sh','./www/index.asp','./www/assets/ourfw.js','./www/assets/ourfw.css']:
                need(n in names,f'defaults missing {n}')
        except Exception as e: errs.append(f'defaults archive unreadable: {e}')
    if '/www/ourfw/index.asp' in sq.paths:
        ui=sq.read('/www/ourfw/index.asp')
        js=sq.read('/www/ourfw/assets/ourfw.js') if '/www/ourfw/assets/ourfw.js' in sq.paths else b''
        surface=ui+b'\n'+js
        for token in [b'Backup Center',b'vpn-profile',b'openvpn-profile',b'AdBlock Lite',b'ZRAM',b'component-package',b'diagnostics-export',b'section-commit']:
            need(token in surface,f'fallback WebUI surface missing token {token!r}')

    lines=[f'IMAGE={image.name}',f'SHA256={hashlib.sha256(data).hexdigest()}',f'IMAGE_BYTES={len(data)}',f'SQUASHFS_OFFSET={sq.base}',f'SQUASHFS_BYTES={sq.bytes_used}',f'PATHS={len(sq.paths)}']
    if errs:
        lines.insert(0,'IMAGE_VERIFY=FAILED'); lines += ['ERROR='+e for e in errs]
        report.write_text('\n'.join(lines)+'\n'); print(report.read_text(),end='',file=sys.stderr); return 50
    lines.insert(0,'IMAGE_VERIFY=OK'); report.write_text('\n'.join(lines)+'\n'); print(report.read_text(),end=''); return 0

if __name__=='__main__': raise SystemExit(main())
