import struct
def lzo1x(src):
    ip=0; o=bytearray(); n=len(src)
    def cp(ref,l):
        for k in range(l): o.append(o[ref+k])
    state=0
    t=src[ip]
    if t>17:
        ip+=1; t-=17
        o+=src[ip:ip+t]; ip+=t; state=4 if t>=4 else t
    while True:
        t=src[ip]; ip+=1
        if t<16:
            if state==0:
                if t==0:
                    while src[ip]==0: t+=255; ip+=1
                    t+=15+src[ip]; ip+=1
                t+=3; o+=src[ip:ip+t]; ip+=t; state=4; continue
            elif state==4:
                ref=len(o)-1-0x800-(t>>2)-(src[ip]<<2); ip+=1; cp(ref,3); st=t&3
            else:
                ref=len(o)-1-(t>>2)-(src[ip]<<2); ip+=1; cp(ref,2); st=t&3
        elif t>=64:
            ref=len(o)-1-((t>>2)&7)-(src[ip]<<3); ip+=1; cp(ref,(t>>5)+1); st=t&3
        elif t>=32:
            l=t&31
            if l==0:
                while src[ip]==0: l+=255; ip+=1
                l+=31+src[ip]; ip+=1
            d=struct.unpack_from('<H',src,ip)[0]; ip+=2
            ref=len(o)-1-(d>>2); cp(ref,l+2); st=d&3
        else:
            l=t&7
            if l==0:
                while src[ip]==0: l+=255; ip+=1
                l+=7+src[ip]; ip+=1
            d=struct.unpack_from('<H',src,ip)[0]; ip+=2
            off=((t&8)<<11)+(d>>2)
            if off==0: return bytes(o)
            ref=len(o)-off-0x4000; cp(ref,l+2); st=d&3
        o+=src[ip:ip+st]; ip+=st; state=st if st else 0
def load(path):
    b=open(path,'rb').read(); u,c=struct.unpack('<II',b[:8]); return u,lzo1x(b[8:8+c])
if __name__=='__main__':
    import sys
    for p in sys.argv[1:]:
        try: u,o=load(p); print(p.split('/')[-1],u,len(o),'OK' if u==len(o) else 'MISMATCH',o[:48].hex())
        except Exception as e: print(p,'ERR',repr(e))
