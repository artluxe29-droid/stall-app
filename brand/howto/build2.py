import json,re,sys,os
src=open('../../index.html').read()
I={k:v for k,v in re.findall(r"(\w+):'(<[^']*)'",src[src.index('const ICO='):src.index('const ico=')])}
I['search']='<circle cx="11" cy="11" r="7"/><path d="m20 20-3.6-3.6"/>';I['sun']='<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>';I['tag']='<path d="M20.6 13.4 13.4 20.6a2 2 0 0 1-2.8 0L3 13V3h10l7.6 7.6a2 2 0 0 1 0 2.8z"/><circle cx="7.5" cy="7.5" r="1.5"/>';I['user']='<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>';I['mic']='<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>'
open('icons.js','w').write('window.ICONS='+json.dumps(I)+';')
svg=lambda k,s=14:f'<svg viewBox="0 0 24 24" width="{s}" height="{s}" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">{I[k]}</svg>'
C={'all':('#26306E','#C8F03C'),'book':('#EEF8C8','#4E6106'),'headphones':('#DDEBFF','#2563EB'),'shirt':('#FCE4F1','#DB2777'),'bowl':('#DCF7E6','#16A34A'),'laptop':('#EDE4FF','#7C3AED')}
card=lambda k,t,p:f'<div class="card"><div class="t" style="background:{C[k][0]};color:{C[k][1]}">{svg(k,26)}</div><b>{t}</b><span>{p}</span></div>'
grid=''.join(card(*x) for x in [('book','Engineering Maths (Stroud)','₦6,500'),('headphones','Wireless earbuds','₦14,000'),('bowl','Jollof & chicken','₦2,500'),('shirt','Vintage denim jacket','₦9,000')])
def tabs(ids):
  o=''
  for i,(k,l) in enumerate([('home','Home'),('store','Stores'),('tag','Sell'),('list','Orders'),('user','Account')]):
    idp=' id="tb%d"'%i if ids else ''
    o+='<span class="%s"%s>%s%s</span>'%('on' if i==0 else '',idp,svg(k,14),l)
  return o
home=f'''<section id="s-home" class="s"><div class="sb"><b>9:41</b><span>●●● ▮</span></div>
 <div class="hd"><img src="wm-indigo.svg"><div class="hic"><span id="iTheme">{svg('sun',13)}</span><span id="iMsg">{svg('chat',13)}</span><span id="iBag">{svg('bag',13)}</span></div></div>
 <div class="hero"><b>Everything you need,</b><b class="l">right on campus.</b><small>From students at your school</small></div>
 <div class="cats" id="cats">{''.join(f'<div class="ct{" on" if k=="all" else ""}" id="{i}"><i style="background:{C[k][0]};color:{C[k][1]}">{svg("sparkle" if k=="all" else k,18)}</i>{l}</div>' for i,k,l in [('cA','all','All'),('cB','book','Books'),('cE','headphones','Electronics'),('cF','shirt','Fashion'),('cD','bowl','Food')])}</div>
 <div class="reach"><span id="rS" class="on">UNILAG</span><span id="rSt">Lagos</span><span id="rN">All Nigeria</span></div>
 <div class="srch" id="hSearch">{svg('search')}<span>Search items and stores</span><span class="mic" id="mic">{svg('mic',12)}<i class="wave"></i></span></div>
 <div class="grid">{card('book','Engineering Maths (Stroud)','₦6,500')}{card('headphones','Wireless earbuds','₦14,000')}</div>
 <div class="tabbar">{tabs(True)}</div></section>'''
res=''.join(f'<div class="row"><div class="t" style="background:{C["book"][0]};color:{C["book"][1]}">{svg("book",22)}</div><div><b>{t}</b><span>{p}</span><small>{s}</small></div></div>' for t,p,s in [('Casio fx-991ES Plus calculator','₦8,500','Ada Okafor · Hall B · ✓ Verified'),('Scientific calculator (used)','₦5,000','Tunde B. · Hall D'),('Calculator + maths set','₦9,800','Campus Books · Shop 4')])
META={'e1':('1','How to *create* your account','Sign up in under a minute','Your account is ready. Let\'s explore!','Next: Find your way around'),
 'e2':('2','Find your *way* around Stall','A quick tour of the app','Now you know your way around.','Next: How to buy safely'),
 'e3':('3','How to buy *safely* on Stall','Your money is held until it\'s in your hands','Your money is held until it\'s in your hands.','Next: Your Account page'),
 'e4':('4','Your *Account* page','Everything you can manage','You\'re all set up on Stall.','More how-to videos coming soon')}
for ep in sys.argv[1:]:
  n,title,sub,outro,nxt=META[ep]
  words=' '.join(f'<span class="w{" hl" if w.startswith("*") else ""}">{w.strip("*")}</span>' for w in title.split())
  h=open('shell.html').read().replace('%SCREENS%',open(ep+'.screens.html').read())
  if ep=='e1':h=h.replace('%HOME%',home.replace('class="s"','class="s" style="z-index:2"'))
  elif ep in('e2','e4'):h=h.replace('%HOME%',home.replace('class="s"','class="s on"'))
  for k,v in {'%EP%':ep,'%NUM%':n,'%TITLE%':words,'%SUB%':sub,'%OUTRO%':outro,'%NEXT%':nxt,'%GRID%':grid,'%RES%':res,'%TABS%':tabs(False),'%CODE%':''.join(f'<span>{c}</span>' for c in 'STALL-7K2Q9M'),'%AWN6%':'<i></i>'*6,'%AWN%':'<i></i>'*8,'%DOMAIN%':os.environ.get('STALL_LINK','Get the Stall app')}.items():h=h.replace(k,v)
  h=re.sub(r'\$\{(\w+?)(\d*)\}',lambda m:svg(m.group(1),int(m.group(2) or 14)),h)
  open(ep+'.built.html','w').write(h)
print('built')
