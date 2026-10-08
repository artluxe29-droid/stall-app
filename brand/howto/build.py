import json,re,sys
I=json.load(open('icons.json'));I['search']='<circle cx="11" cy="11" r="7"/><path d="m20 20-3.6-3.6"/>'
open('icons.js','w').write('window.ICONS='+json.dumps(I)+';')
svg=lambda k,s=18:f'<svg viewBox="0 0 24 24" width="{s}" height="{s}" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">{I[k]}</svg>'
C={'book':('#EEF8C8','#4E6106'),'headphones':('#DDEBFF','#2563EB'),'shirt':('#FCE4F1','#DB2777'),'bowl':('#DCF7E6','#16A34A'),'laptop':('#EDE4FF','#7C3AED')}
grid=''.join(f'<div class="card"><div class="t" style="background:{C[k][0]};color:{C[k][1]}">{svg(k,26)}</div><b>{t}</b><span>{p}</span></div>' for k,t,p in [('book','Engineering Maths (Stroud)','₦6,500'),('headphones','Wireless earbuds','₦14,000'),('bowl','Jollof & chicken','₦2,500'),('shirt','Vintage denim jacket','₦9,000')])
res=''.join(f'<div class="row"><div class="t" style="background:{C["book"][0]};color:{C["book"][1]}">{svg("book",22)}</div><div><b>{t}</b><span>{p}</span><small>{s}</small></div></div>' for t,p,s in [('Casio fx-991ES Plus calculator','₦8,500','Ada Okafor · Hall B · ✓ Verified'),('Scientific calculator (used)','₦5,000','Tunde B. · Hall D'),('Calculator + maths set','₦9,800','Campus Books · Shop 4')])
tabs=''.join(f'<span class="{"on" if i==0 else ""}">{svg(k,14)}{l}</span>' for i,(k,l) in enumerate([('home','Home'),('store','Stores'),('bag','Sell'),('list','Orders'),('id','Account')]))
code=''.join(f'<span>{c}</span>' for c in 'STALL-7K2Q9M')
awn=''.join('<i></i>' for _ in range(8))
for ep in sys.argv[1:]:
  h=open(ep+'.html').read()
  for k,v in {'%GRID%':grid,'%RES%':res,'%TABS%':tabs,'%CODE%':code,'%AWN%':awn,'%DOMAIN%':'stall.com.ng'}.items():h=h.replace(k,v)
  h=re.sub(r'\$\{(\w+?)(\d*)\}',lambda m:svg(m.group(1),int(m.group(2) or 14)),h)
  open(ep+'.built.html','w').write(h)
