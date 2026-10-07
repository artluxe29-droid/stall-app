# python3 voice.py ep  → reads ep.script.json [{cap,say}], speaks each line, times the episode around the speech,
# adds a soft music bed under it, and writes ep.times.js (for the animation) and ep.wav (for the video).
import sys,json,numpy as np,soundfile as sf
from kokoro_onnx import Kokoro
ep=sys.argv[1];V=sys.argv[2] if len(sys.argv)>2 else 'af_heart';SP=float(sys.argv[3]) if len(sys.argv)>3 else .94
S=json.load(open(ep+'.script.json'));k=Kokoro('kokoro.onnx','voices.bin');SR=24000
clips=[];times=[];t=.9
for i,b in enumerate(S):
  a,sr=k.create(b['say'],voice=V,speed=SP,lang='en-us');a=a/ (np.abs(a).max()+1e-9)*.85;clips.append(a);d=len(a)/SR
  times.append([round(t,3),round(d,3)]);t+=d+(1.6 if i==0 else b.get('after',.75))
OUT=round(t+.2,3);DUR=round(OUT+4.6,3);N=int(DUR*SR)
voice=np.zeros(N,dtype=np.float32)
for (st,d),a in zip(times,clips):i=int(st*SR);voice[i:i+len(a)]+=a[:N-i]
# calm pad: slow major-seventh chords, sine partials, soft attack and release
n=np.arange(N)/SR;pad=np.zeros(N)
CH=[[261.63,329.63,392.0,493.88],[220.0,261.63,329.63,392.0],[174.61,220.0,261.63,329.63],[196.0,246.94,293.66,392.0]]
L=4.0
for j in range(int(DUR/L)+1):
  s0=j*L;env=np.clip((n-s0)/1.2,0,1)*np.clip((s0+L+1.2-n)/1.6,0,1)
  m=env>0
  for f in CH[j%4]:
    for h,g in [(1,1),(2,.18),(.5,.35)]:pad[m]+=g*env[m]*np.sin(2*np.pi*f*h*n[m])
pad/=np.abs(pad).max()+1e-9
duck=np.ones(N);
for st,d in times:duck[int(st*SR):int((st+d)*SR)]=.55
duck=np.convolve(duck,np.ones(4800)/4800,mode='same')
fade=np.clip(n/1.5,0,1)*np.clip((DUR-n)/2.5,0,1)
mix=voice+pad*.075*duck*fade
mix/=max(1,np.abs(mix).max()/.95)
sf.write(ep+'.wav',mix.astype(np.float32),SR)
open(ep+'.times.js','w').write('window.TIMES='+json.dumps(times)+';window.OUT='+str(OUT)+';window.DURATION='+str(DUR)+';window.SCRIPT='+json.dumps(S)+';')
print(ep,'beats',len(times),'duration',DUR)
