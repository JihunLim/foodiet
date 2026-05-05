// Foodiet iOS UI Kit — Screens
// Core screens composed from Components.jsx atoms

const {useState: _useState, useEffect: _useEffect} = React;

// ─────────────────────────────────────────────────────────────
// HOME — 오늘의 식단 요약
// ─────────────────────────────────────────────────────────────
function HomeScreen({onOpenCamera, onOpenMeal}) {
  return (
    <div style={{padding:'0 16px 24px', fontFamily:FONT}}>
      {/* Greeting */}
      <div style={{display:'flex', alignItems:'center', gap:12, padding:'8px 4px 18px'}}>
        <div style={{flex:1}}>
          <div style={{fontSize:13, color:C.fg2, fontWeight:500}}>4월 18일 목요일 · 봄</div>
          <div style={{fontSize:26, fontWeight:700, color:C.fg, letterSpacing:-0.02, marginTop:2}}>
            안녕, 지은아 👋
          </div>
        </div>
        <div style={{width:44, height:44, borderRadius:999, background:C.coralSoft, display:'flex', alignItems:'center', justifyContent:'center'}}>
          <Icon name="bell" size={20} color={C.coralDark}/>
        </div>
      </div>

      {/* Calorie summary hero */}
      <Card elevated style={{padding:20, background:'linear-gradient(135deg, #FFF4EC 0%, #FFE8CF 45%, #E6F2D3 100%)', border:'none'}}>
        <div style={{display:'flex', alignItems:'center', gap:18}}>
          <Ring value={85} size={118} stroke={12} tone="coral" label={
            <div style={{textAlign:'center'}}>
              <div style={{fontSize:24, fontWeight:700, color:C.coralDark, lineHeight:1}}>1,280</div>
              <div style={{fontSize:11, color:C.fg2, marginTop:2}}>/ 1,500 kcal</div>
            </div>
          }/>
          <div style={{flex:1}}>
            <div style={{fontSize:13, color:C.fg2, fontWeight:500}}>오늘의 섭취</div>
            <div style={{fontSize:16, color:C.fg1, fontWeight:700, marginTop:4, lineHeight:1.4}}>
              목표까지<br/><span style={{color:C.coralDark}}>220 kcal</span> 남았어!
            </div>
          </div>
        </div>
        <div style={{display:'grid', gridTemplateColumns:'1fr 1fr 1fr', gap:10, marginTop:16}}>
          {[
            {k:'탄수', v:168, m:220, c:C.butter},
            {k:'단백질', v:72, m:90, c:C.leaf},
            {k:'지방', v:38, m:50, c:C.coral},
          ].map(m => (
            <div key={m.k} style={{background:'rgba(255,255,255,0.7)', borderRadius:12, padding:10}}>
              <div style={{fontSize:11, color:C.fg2, fontWeight:700}}>{m.k}</div>
              <div style={{fontSize:17, color:C.fg, fontWeight:700, margin:'2px 0 6px'}}>{m.v}<span style={{fontSize:11, color:C.fgMuted}}>/{m.m}g</span></div>
              <div style={{height:4, borderRadius:99, background:'rgba(230,221,207,0.6)', overflow:'hidden'}}>
                <div style={{width:`${(m.v/m.m)*100}%`, height:'100%', background:m.c, borderRadius:99}}/>
              </div>
            </div>
          ))}
        </div>
      </Card>

      {/* Foodie coach */}
      <div style={{marginTop:14}}>
        <FoodieBubble>
          단백질이 조금 부족해 보여! 저녁엔 <b>두부</b>나 <b>닭가슴살</b> 어때? 🐓
        </FoodieBubble>
      </div>

      {/* Today's meals */}
      <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'24px 4px 10px'}}>
        <div style={{fontSize:18, fontWeight:700, color:C.fg, letterSpacing:-0.01}}>오늘의 식단</div>
        <div style={{fontSize:12, color:C.fgMuted, fontWeight:700}}>3끼 기록 완료</div>
      </div>

      <div style={{display:'flex', flexDirection:'column', gap:10}}>
        <MealRow type="아침" time="8:30" title="그릭요거트 + 블루베리" kcal={280} img={C.butter} onClick={onOpenMeal}/>
        <MealRow type="점심" time="12:40" title="봄나물 비빔밥" kcal={520} img={C.coral} onClick={onOpenMeal} hl/>
        <MealRow type="간식" time="15:20" title="딸기 5알" kcal={48} img={C.berry} onClick={onOpenMeal}/>
        <MealEmptyRow type="저녁" onClick={onOpenCamera}/>
      </div>

      {/* Recipe recommendation */}
      <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'24px 4px 10px'}}>
        <div style={{fontSize:18, fontWeight:700, color:C.fg, letterSpacing:-0.01}}>봄 레시피 추천 🌸</div>
        <div style={{fontSize:12, color:C.coralDark, fontWeight:700}}>더보기</div>
      </div>
      <div style={{display:'flex', gap:10, overflowX:'auto', margin:'0 -16px', padding:'0 16px'}}>
        <RecipeCard name="쑥 두부 된장국" kcal={180} tag="봄나물" bg={C.leafSoft} illust="../../assets/illust-namul.svg"/>
        <RecipeCard name="딸기 리코타 토스트" kcal={240} tag="브런치" bg={'#FFE4D1'} illust="../../assets/illust-strawberry.svg"/>
        <RecipeCard name="봄채소 샐러드" kcal={190} tag="가볍게" bg={'#FFF0D6'} illust="../../assets/illust-salad.svg"/>
      </div>
    </div>
  );
}

function MealRow({type, time, title, kcal, img, onClick, hl}) {
  return (
    <Card onClick={onClick} elevated={hl} style={{padding:12, display:'flex', alignItems:'center', gap:12}}>
      <div style={{width:52, height:52, borderRadius:14, background:img, opacity:0.9, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>
        <Icon name="camera" size={22} color="#fff" strokeWidth={2.2}/>
      </div>
      <div style={{flex:1, minWidth:0}}>
        <MealChip type={type} time={time}/>
        <div style={{fontSize:15, fontWeight:700, color:C.fg1, marginTop:4, overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap'}}>{title}</div>
      </div>
      <div style={{textAlign:'right'}}>
        <div style={{fontSize:18, fontWeight:700, color:C.coralDark, fontFeatureSettings:"'tnum' 1"}}>{kcal}</div>
        <div style={{fontSize:10, color:C.fgMuted}}>kcal</div>
      </div>
    </Card>
  );
}

function MealEmptyRow({type, onClick}) {
  return (
    <div onClick={onClick} style={{
      padding:14, borderRadius:18, border:`1.5px dashed ${C.border}`,
      display:'flex', alignItems:'center', gap:12, cursor:'pointer',
      background:'rgba(251,246,239,0.4)',
    }}>
      <div style={{width:52, height:52, borderRadius:14, background:C.coralSoft, display:'flex', alignItems:'center', justifyContent:'center'}}>
        <Icon name="plus" size={24} color={C.coralDark}/>
      </div>
      <div>
        <MealChip type={type}/>
        <div style={{fontSize:14, color:C.fg2, marginTop:4, fontWeight:500}}>사진으로 기록하기</div>
      </div>
    </div>
  );
}

function RecipeCard({name, kcal, tag, bg, illust}) {
  return (
    <div style={{minWidth:170, background:'#fff', borderRadius:16, border:`1px solid ${C.hairline}`, overflow:'hidden', flexShrink:0}}>
      <div style={{height:96, background:bg, display:'flex', alignItems:'center', justifyContent:'center'}}>
        <img src={illust} width="70" alt=""/>
      </div>
      <div style={{padding:12}}>
        <Chip tone="leaf" size="sm">{tag}</Chip>
        <div style={{fontSize:14, fontWeight:700, color:C.fg1, marginTop:6, lineHeight:1.3, letterSpacing:-0.01}}>{name}</div>
        <div style={{fontSize:11, color:C.fgMuted, marginTop:4}}><span style={{color:C.coralDark, fontWeight:700}}>{kcal}</span> kcal</div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// CAMERA — 음식 사진 촬영/분석
// ─────────────────────────────────────────────────────────────
function CameraScreen({onClose, onAnalyzed}) {
  const [phase, setPhase] = _useState('shoot'); // shoot | analyzing | result
  _useEffect(() => {
    if (phase === 'analyzing') {
      const t = setTimeout(() => setPhase('result'), 1600);
      return () => clearTimeout(t);
    }
  }, [phase]);

  return (
    <div style={{position:'absolute', inset:0, background:'#1a1612', display:'flex', flexDirection:'column', fontFamily:FONT}}>
      {/* Top bar */}
      <div style={{padding:'60px 20px 16px', display:'flex', justifyContent:'space-between', alignItems:'center'}}>
        <button onClick={onClose} style={{width:40, height:40, borderRadius:999, background:'rgba(255,255,255,0.15)', border:'none', color:'#fff', display:'flex', alignItems:'center', justifyContent:'center'}}>
          <Icon name="close" size={20} color="#fff"/>
        </button>
        <div style={{display:'inline-flex', gap:6, background:'rgba(0,0,0,0.35)', padding:'6px 14px', borderRadius:999, color:'#fff', fontSize:12, fontWeight:700, letterSpacing:0.02}}>
          <Icon name="sparkle" size={14} color="#FFB38A"/>
          AI 자동 분석
        </div>
        <div style={{width:40}}/>
      </div>

      {/* Viewfinder */}
      <div style={{flex:1, position:'relative', margin:'0 16px', borderRadius:28, overflow:'hidden',
        background: phase==='shoot'
          ? 'radial-gradient(circle at 30% 40%, #5a3b22 0%, #2a1d12 100%)'
          : 'linear-gradient(180deg, #3a2818 0%, #1a1108 100%)'}}>

        {/* fake viewfinder content — a plated dish */}
        <div style={{position:'absolute', inset:0, display:'flex', alignItems:'center', justifyContent:'center'}}>
          <div style={{width:220, height:220, borderRadius:999, background:'#FBF6EF', boxShadow:'0 20px 60px rgba(0,0,0,0.3), inset 0 4px 12px rgba(0,0,0,0.08)', display:'flex', alignItems:'center', justifyContent:'center'}}>
            <img src="../../assets/illust-salad.svg" width="160" alt=""/>
          </div>
        </div>

        {/* corner brackets */}
        {phase === 'shoot' && (
          <>
            {[{t:24,l:24,d:'tl'},{t:24,r:24,d:'tr'},{b:24,l:24,d:'bl'},{b:24,r:24,d:'br'}].map((p,i)=>(
              <div key={i} style={{position:'absolute', top:p.t, left:p.l, right:p.r, bottom:p.b,
                width:32, height:32,
                borderTop:p.d[0]==='t'?'3px solid rgba(255,255,255,0.9)':'none',
                borderBottom:p.d[0]==='b'?'3px solid rgba(255,255,255,0.9)':'none',
                borderLeft:p.d[1]==='l'?'3px solid rgba(255,255,255,0.9)':'none',
                borderRight:p.d[1]==='r'?'3px solid rgba(255,255,255,0.9)':'none',
                borderTopLeftRadius:p.d==='tl'?12:0, borderTopRightRadius:p.d==='tr'?12:0,
                borderBottomLeftRadius:p.d==='bl'?12:0, borderBottomRightRadius:p.d==='br'?12:0,
              }}/>
            ))}
            <div style={{position:'absolute', bottom:20, left:0, right:0, textAlign:'center', color:'rgba(255,255,255,0.85)', fontSize:13, fontWeight:500, letterSpacing:-0.01}}>
              접시가 화면 중앙에 오도록 해줘
            </div>
          </>
        )}

        {phase === 'analyzing' && (
          <div style={{position:'absolute', inset:0, background:'rgba(26,17,8,0.55)', backdropFilter:'blur(2px)', display:'flex', alignItems:'center', justifyContent:'center', flexDirection:'column', gap:18}}>
            <div style={{width:60, height:60, border:'3px solid rgba(255,255,255,0.2)', borderTop:'3px solid #FF8A5B', borderRadius:999, animation:'spin 1s linear infinite'}}/>
            <div style={{color:'#fff', fontSize:15, fontWeight:700}}>음식을 알아보는 중...</div>
            <div style={{color:'rgba(255,255,255,0.7)', fontSize:12}}>봄나물, 밥, 고추장 감지됨</div>
          </div>
        )}

        {phase === 'result' && (
          <div style={{position:'absolute', bottom:16, left:16, right:16, background:'#fff', borderRadius:20, padding:16, boxShadow:'0 10px 30px rgba(0,0,0,0.2)'}}>
            <div style={{display:'flex', alignItems:'center', gap:6, marginBottom:8}}>
              <Icon name="sparkle" size={14} color={C.coralDark}/>
              <div style={{fontSize:11, fontWeight:700, color:C.coralDark, letterSpacing:0.02}}>분석 완료 · 12:40</div>
              <MealChip type="점심"/>
            </div>
            <div style={{fontSize:18, fontWeight:700, color:C.fg, letterSpacing:-0.01}}>봄나물 비빔밥</div>
            <div style={{display:'flex', alignItems:'center', gap:8, marginTop:6}}>
              <div style={{fontSize:22, fontWeight:700, color:C.coralDark, fontFeatureSettings:"'tnum' 1"}}>520</div>
              <div style={{fontSize:12, color:C.fg2}}>kcal · 탄수 78g · 단백 18g · 지방 12g</div>
            </div>
            <div style={{display:'flex', gap:8, marginTop:12}}>
              <Button variant="ghost" style={{flex:1}}>수정</Button>
              <Button variant="primary" style={{flex:2}} onClick={onAnalyzed}>기록하기</Button>
            </div>
          </div>
        )}
      </div>

      {/* Shutter */}
      {phase === 'shoot' && (
        <div style={{padding:'30px 20px 44px', display:'flex', justifyContent:'space-between', alignItems:'center'}}>
          <div style={{width:52, height:52, borderRadius:14, background:'rgba(255,255,255,0.15)', display:'flex', alignItems:'center', justifyContent:'center'}}>
            <div style={{width:28, height:28, borderRadius:6, background:'linear-gradient(135deg,#FFB38A,#FF8A5B)'}}/>
          </div>
          <button onClick={() => setPhase('analyzing')} style={{width:76, height:76, borderRadius:999, background:'#fff', border:'5px solid rgba(255,255,255,0.3)', padding:0, cursor:'pointer', boxShadow:'0 0 0 3px #fff inset'}}>
            <div style={{width:'100%', height:'100%', borderRadius:999, background:'#fff'}}/>
          </button>
          <div style={{width:52, height:52, borderRadius:999, background:'rgba(255,255,255,0.15)', display:'flex', alignItems:'center', justifyContent:'center', color:'#fff', fontSize:11, fontWeight:700}}>
            갤러리
          </div>
        </div>
      )}

      <style>{'@keyframes spin{to{transform:rotate(360deg)}}'}</style>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// WEIGHT — 몸무게 추적 그래프
// ─────────────────────────────────────────────────────────────
function WeightScreen() {
  const data = [64.2, 63.8, 63.5, 63.9, 63.2, 62.8, 62.4];
  const goal = 58.0;
  const min = 57, max = 65;
  const w = 340, h = 160;
  const points = data.map((v,i) => {
    const x = (i / (data.length-1)) * (w-40) + 20;
    const y = h - ((v - min)/(max-min)) * (h-30) - 10;
    return {x, y, v};
  });
  const path = points.map((p,i) => (i===0?'M':'L') + p.x + ',' + p.y).join(' ');
  const area = path + ` L${points[points.length-1].x},${h} L${points[0].x},${h} Z`;

  return (
    <div style={{padding:'0 16px 24px', fontFamily:FONT}}>
      <div style={{padding:'8px 4px 20px'}}>
        <div style={{fontSize:13, color:C.fg2, fontWeight:500}}>몸무게 추적</div>
        <div style={{fontSize:28, fontWeight:700, color:C.fg, letterSpacing:-0.02, marginTop:2}}>
          목표까지 <span style={{color:C.coralDark}}>4.4kg</span>
        </div>
      </div>

      <Card elevated style={{padding:20}}>
        <div style={{display:'flex', alignItems:'baseline', gap:16, marginBottom:12}}>
          <div>
            <div style={{fontSize:11, color:C.fgMuted, fontWeight:700, letterSpacing:0.02}}>현재</div>
            <div style={{fontSize:36, fontWeight:700, color:C.coralDark, lineHeight:1, fontFeatureSettings:"'tnum' 1"}}>62.4<span style={{fontSize:18, color:C.fg2, marginLeft:4}}>kg</span></div>
          </div>
          <div style={{flex:1}}/>
          <Chip tone="leaf">↓ 1.8kg (7일)</Chip>
        </div>

        <svg width={w} height={h} style={{display:'block', margin:'0 auto'}} viewBox={`0 0 ${w} ${h}`}>
          <defs>
            <linearGradient id="areaG" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#FF8A5B" stopOpacity="0.3"/>
              <stop offset="100%" stopColor="#FF8A5B" stopOpacity="0"/>
            </linearGradient>
          </defs>
          {/* goal line */}
          <line x1="20" x2={w-20} y1={h-((goal-min)/(max-min))*(h-30)-10} y2={h-((goal-min)/(max-min))*(h-30)-10} stroke={C.leaf} strokeWidth="1.5" strokeDasharray="4 4"/>
          <text x={w-24} y={h-((goal-min)/(max-min))*(h-30)-14} textAnchor="end" fontSize="10" fill={C.leafDark} fontWeight="700" fontFamily={FONT}>목표 58.0</text>
          <path d={area} fill="url(#areaG)"/>
          <path d={path} fill="none" stroke="#FF8A5B" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"/>
          {points.map((p,i) => (
            <g key={i}>
              <circle cx={p.x} cy={p.y} r={i===points.length-1?6:3.5} fill="#fff" stroke="#FF8A5B" strokeWidth="2.5"/>
              {i===points.length-1 && (
                <g transform={`translate(${p.x-26}, ${p.y-32})`}>
                  <rect width="52" height="22" rx="11" fill="#3E3A31"/>
                  <text x="26" y="15" textAnchor="middle" fill="#fff" fontSize="11" fontWeight="700" fontFamily={FONT}>62.4</text>
                </g>
              )}
            </g>
          ))}
        </svg>
        <div style={{display:'flex', justifyContent:'space-between', padding:'6px 20px 0', fontSize:10, color:C.fgMuted, fontWeight:700}}>
          {['월','화','수','목','금','토','일'].map(d => <span key={d}>{d}</span>)}
        </div>
      </Card>

      {/* Goal card */}
      <div style={{marginTop:12, background:'linear-gradient(140deg, #B5DB94 0%, #7FB77E 100%)', borderRadius:18, padding:18, color:'#fff'}}>
        <div style={{fontSize:11, fontWeight:700, opacity:0.85, letterSpacing:0.02}}>목표</div>
        <div style={{fontSize:28, fontWeight:700, marginTop:2, letterSpacing:-0.02}}>58.0 kg</div>
        <ProgressBar value={28} max={100} tone="leaf"/>
        <div style={{fontSize:12, marginTop:8, opacity:0.9}}>2.6kg 감량 완료 · 약 6주 예상</div>
      </div>

      {/* log CTA */}
      <div style={{marginTop:14}}>
        <Button variant="primary" style={{width:'100%', padding:16, fontSize:16}} icon={<Icon name="scale" size={18} color="#fff" strokeWidth={2.4}/>}>
          오늘 몸무게 기록하기
        </Button>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// FRIDGE AI — 냉장고 → 요리 추천
// ─────────────────────────────────────────────────────────────
function FridgeScreen() {
  return (
    <div style={{padding:'0 16px 24px', fontFamily:FONT}}>
      <div style={{padding:'8px 4px 18px'}}>
        <div style={{display:'inline-flex', gap:6, alignItems:'center', marginBottom:4}}>
          <Icon name="sparkle" size={14} color={C.coralDark}/>
          <span style={{fontSize:12, color:C.coralDark, fontWeight:700, letterSpacing:0.02}}>AI 레시피</span>
        </div>
        <div style={{fontSize:26, fontWeight:700, color:C.fg, letterSpacing:-0.02, lineHeight:1.25}}>
          냉장고 속 재료로<br/>뭐 만들어볼까?
        </div>
      </div>

      {/* Fridge photo + detected ingredients */}
      <Card elevated style={{padding:0, overflow:'hidden'}}>
        <div style={{height:160, background:'linear-gradient(140deg, #E0F1CE 0%, #FFF4EC 100%)', position:'relative', display:'flex', alignItems:'center', justifyContent:'center'}}>
          <img src="../../assets/illust-namul.svg" width="90" style={{position:'absolute', top:30, left:40}} alt=""/>
          <img src="../../assets/illust-strawberry.svg" width="60" style={{position:'absolute', top:50, right:60}} alt=""/>
          <img src="../../assets/illust-rice-bowl.svg" width="90" style={{position:'absolute', bottom:20, left:'50%', transform:'translateX(-50%)'}} alt=""/>
          <div style={{position:'absolute', top:12, right:12, background:'rgba(62,58,49,0.8)', color:'#fff', fontSize:10, fontWeight:700, padding:'4px 10px', borderRadius:999, letterSpacing:0.04}}>
            2분 전 촬영
          </div>
        </div>
        <div style={{padding:14}}>
          <div style={{fontSize:12, color:C.fg2, fontWeight:700, marginBottom:8}}>감지된 재료 · 8개</div>
          <div style={{display:'flex', gap:6, flexWrap:'wrap'}}>
            {['봄나물','두부','달걀','딸기','된장','쌀','당근','양파'].map(i => (
              <Chip key={i} tone="neutral" size="sm">{i}</Chip>
            ))}
          </div>
        </div>
      </Card>

      {/* Recipe cards */}
      <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'22px 4px 10px'}}>
        <div style={{fontSize:18, fontWeight:700, color:C.fg, letterSpacing:-0.01}}>너한테 맞는 3가지 🌸</div>
      </div>

      <div style={{display:'flex', flexDirection:'column', gap:10}}>
        {[
          {name:'쑥 두부 된장찌개', kcal:220, min:25, tag:'봄나물', img:'../../assets/illust-namul.svg', bg:C.leafSoft, match:96},
          {name:'봄나물 비빔밥', kcal:420, min:20, tag:'한끼식사', img:'../../assets/illust-rice-bowl.svg', bg:'#FFE4D1', match:88},
          {name:'딸기 요거트볼', kcal:180, min:5, tag:'간식', img:'../../assets/illust-strawberry.svg', bg:'#FFF0D6', match:82},
        ].map(r => (
          <Card key={r.name} style={{padding:12, display:'flex', alignItems:'center', gap:12}}>
            <div style={{width:72, height:72, borderRadius:14, background:r.bg, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>
              <img src={r.img} width="56" alt=""/>
            </div>
            <div style={{flex:1, minWidth:0}}>
              <div style={{display:'flex', alignItems:'center', gap:6}}>
                <Chip tone="leaf" size="sm">✓ {r.match}% 매칭</Chip>
              </div>
              <div style={{fontSize:16, fontWeight:700, color:C.fg1, marginTop:4, letterSpacing:-0.01}}>{r.name}</div>
              <div style={{fontSize:11, color:C.fgMuted, marginTop:3}}>
                <span style={{color:C.coralDark, fontWeight:700}}>{r.kcal}</span> kcal · {r.min}분
              </div>
            </div>
            <Icon name="chevronR" size={18} color={C.fgMuted}/>
          </Card>
        ))}
      </div>

      <div style={{marginTop:14}}>
        <Button variant="soft" style={{width:'100%'}} icon={<Icon name="camera" size={18} color={C.coralDark} strokeWidth={2.4}/>}>
          냉장고 다시 찍기
        </Button>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// ONBOARDING — 목표 설정
// ─────────────────────────────────────────────────────────────
function OnboardingScreen({onDone}) {
  const [goal, setGoal] = _useState('diet');
  return (
    <div style={{padding:'8px 20px 24px', fontFamily:FONT, display:'flex', flexDirection:'column', height:'100%'}}>
      <div style={{display:'flex', gap:6, padding:'4px 0 24px'}}>
        {[1,1,1,0].map((a,i) => (
          <div key={i} style={{flex:1, height:4, borderRadius:99, background: a ? C.coral : C.border}}/>
        ))}
      </div>

      <div style={{display:'flex', justifyContent:'center', margin:'8px 0 16px'}}>
        <img src="../../assets/mascot-foodie.svg" width="110" alt=""/>
      </div>

      <div style={{fontSize:24, fontWeight:700, color:C.fg, lineHeight:1.3, letterSpacing:-0.02, textAlign:'center'}}>
        어떤 목표로 시작할까?
      </div>
      <div style={{fontSize:13.5, color:C.fg2, textAlign:'center', marginTop:6, lineHeight:1.5}}>
        언제든 바꿀 수 있으니까 편하게 골라봐
      </div>

      <div style={{display:'flex', flexDirection:'column', gap:10, marginTop:24}}>
        {[
          {k:'diet', icon:'🌱', title:'다이어트', sub:'건강하게 체중 감량'},
          {k:'maintain', icon:'⚖️', title:'체중 유지', sub:'지금 이대로 균형있게'},
          {k:'bulk', icon:'💪', title:'근육 증가', sub:'운동 + 단백질 중심'},
          {k:'habit', icon:'📖', title:'식단 기록만', sub:'가볍게 시작하기'},
        ].map(o => (
          <div key={o.k} onClick={() => setGoal(o.k)} style={{
            padding:16, borderRadius:16, border:`1.8px solid ${goal===o.k ? C.coral : C.border}`,
            background: goal===o.k ? C.coralSoft : '#fff',
            display:'flex', alignItems:'center', gap:14, cursor:'pointer',
            transition:'all .15s',
          }}>
            <div style={{width:44, height:44, borderRadius:12, background:goal===o.k ? '#fff' : C.coralSoft, display:'flex', alignItems:'center', justifyContent:'center', fontSize:22}}>{o.icon}</div>
            <div style={{flex:1}}>
              <div style={{fontSize:16, fontWeight:700, color:C.fg, letterSpacing:-0.01}}>{o.title}</div>
              <div style={{fontSize:12, color:C.fg2, marginTop:2}}>{o.sub}</div>
            </div>
            <div style={{width:22, height:22, borderRadius:999, border:`2px solid ${goal===o.k ? C.coral : C.border}`, background:goal===o.k?C.coral:'transparent', display:'flex', alignItems:'center', justifyContent:'center'}}>
              {goal===o.k && <Icon name="check" size={14} color="#fff"/>}
            </div>
          </div>
        ))}
      </div>

      <div style={{flex:1}}/>
      <Button variant="primary" style={{width:'100%', padding:16, fontSize:16, marginTop:20}} onClick={onDone}>
        다음
      </Button>
    </div>
  );
}

Object.assign(window, {HomeScreen, CameraScreen, WeightScreen, FridgeScreen, OnboardingScreen});
