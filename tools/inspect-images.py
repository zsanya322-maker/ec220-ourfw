#!/usr/bin/env python3
import argparse, hashlib, pathlib, zipfile

def sha(b): return hashlib.sha256(b).hexdigest()
def signatures(b):
    out=[]
    for sig,name in [(b'hsqs','squashfs'),(bytes.fromhex('27051956'),'uImage')]:
        pos=0; hits=[]
        while True:
            i=b.find(sig,pos)
            if i<0: break
            hits.append(i); pos=i+1
            if len(hits)>=8: break
        if hits: out.append((name,hits))
    return out

def members(path):
    p=pathlib.Path(path)
    if zipfile.is_zipfile(p):
        with zipfile.ZipFile(p) as z:
            return [(n,z.read(n)) for n in z.namelist() if not n.endswith('/')]
    return [(p.name,p.read_bytes())]

def main():
    ap=argparse.ArgumentParser(description='Read-only EC220 firmware image inspector')
    ap.add_argument('files', nargs='+')
    a=ap.parse_args()
    allm=[]
    for f in a.files:
        print(f'== {f} ==')
        ms=members(f); allm.extend((f,n,b) for n,b in ms)
        for n,b in ms:
            print(f'{n}: {len(b)} bytes (0x{len(b):x}) SHA256={sha(b)}')
            print('  head32='+b[:32].hex())
            for name,hits in signatures(b): print(' ',name,', '.join(f'0x{x:x}' for x in hits))
    # Detect the known EC220 Padavan recovery relation without assuming it.
    for _,n1,b1 in allm:
        for _,n2,b2 in allm:
            if b1 is b2: continue
            if len(b2)>len(b1) and b2.endswith(b1):
                prefix=b2[:-len(b1)]
                if prefix and not any(prefix):
                    print(f'RELATION: {n2} = {len(prefix)} (0x{len(prefix):x}) zero bytes + {n1}')
if __name__=='__main__': main()
