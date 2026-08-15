#!/usr/bin/env python3
from pathlib import Path
import subprocess, tempfile, sys
ROOT=Path(__file__).resolve().parents[1]
TOOL=ROOT/'tools/harden-https-defaults.py'

def main():
    with tempfile.TemporaryDirectory(prefix='ourfw-https-hardening-') as td:
        trunk=Path(td)/'padavan-ng/trunk'
        cert=trunk/'user/httpd/https-cert.sh'
        ui=trunk/'user/www/n56u_ribbon_fixed/Advanced_Services_Content.asp'
        cert.parent.mkdir(parents=True); ui.parent.mkdir(parents=True)
        cert.write_text('#!/bin/sh\nRSA_BITS=1024\nCERT_DAYS=365\n')
        ui.write_text('<select id="https_gen_rb">\n'
                      '                                                    <option value="1024">RSA 1024 (*)</option>\n'
                      '                                                    <option value="2048">RSA 2048</option>\n'
                      '                                                    <option value="prime256v1">EC P-256</option>\n</select>\n')
        for _ in range(2):
            subprocess.run([sys.executable,str(TOOL),str(trunk.parent)],check=True)
        c=cert.read_text(); u=ui.read_text()
        assert 'RSA_BITS=2048' in c and 'RSA_BITS=1024' not in c
        assert 'value="2048" selected="selected">RSA 2048 (*)' in u
        assert '<option value="1024">RSA 1024</option>' in u
        assert u.count('selected="selected"') == 1
        print('HTTPS HARDENING MOCK: OK')
if __name__=='__main__': main()
