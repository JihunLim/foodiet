// Foodiet iOS UI Kit — Core Components
// Brand-styled atoms & molecules used across screens

const {useState, useEffect} = React;

// ── Brand colors (mirror of colors_and_type.css)
const C = {
  bg: '#FFFDFA',
  surface: '#FBF6EF',
  coralSoft: '#FFF4EC',
  coral100: '#FFE4D1',
  coral: '#FF8A5B',
  coralDark: '#EE7042',
  leaf: '#7FB77E',
  leafSoft: '#E0F1CE',
  leafDark: '#457A44',
  berry: '#F06A7A',
  butter: '#F7D36A',
  lavender: '#8B6FB3',
  fg: '#221F1A',
  fg1: '#3E3A31',
  fg2: '#6B6454',
  fgMuted: '#958B7A',
  border: '#E6DDCF',
  hairline: '#F4EDE2',
  warn: '#F2A93B',
  danger: '#E5574E',
};

const FONT = "'Gmarket Sans', -apple-system, 'Apple SD Gothic Neo', sans-serif";

// ── Chip
function Chip({ children, tone = 'coral', size = 'md' }) {
  const tones = {
    coral: { bg: '#FFE4D1', fg: '#C9582F' },
    leaf:  { bg: '#E0F1CE', fg: '#457A44' },
    butter:{ bg: '#FFF0D6', fg: '#A67A1F' },
    lavender:{ bg: '#EDE5F5', fg: '#5E4A85' },
    neutral:{ bg: '#F4EDE2', fg: '#6B6454' },
    danger: { bg: '#FDE4E1', fg: '#C9392F' },
  };
  const t = tones[tone] || tones.coral;
  const pad = size === 'sm' ? '3px 8px' : '5px 12px';
  const fs  = size === 'sm' ? 11 : 12;
  return (
    <span style={{
      display:'inline-flex', alignItems:'center', gap:5, padding:pad, borderRadius:999,
      fontSize:fs, fontWeight:700, letterSpacing:-0.01, background:t.bg, color:t.fg, fontFamily:FONT,
    }}>{children}</span>
  );
}

// ── Button
function Button({ children, variant='primary', onClick, style={}, icon }) {
  const base = {
    fontFamily: FONT, fontWeight:700, fontSize:15, letterSpacing:-0.01,
    border:'none', cursor:'pointer', padding:'14px 20px', borderRadius:14,
    display:'inline-flex', alignItems:'center', justifyContent:'center', gap:8,
    transition:'transform .08s ease, background .15s ease',
  };
  const variants = {
    primary:{ background:C.coral, color:'#fff', boxShadow:'0 8px 22px rgba(255,138,91,0.28)' },
    secondary:{ background:C.leafSoft, color:C.leafDark },
    ghost:{ background:'transparent', color:C.fg1, border:`1.5px solid ${C.border}`, padding:'12.5px 18.5px' },
    soft: { background:C.coralSoft, color:C.coralDark },
  };
  return (
    <button style={{...base, ...variants[variant], ...style}} onClick={onClick}
      onMouseDown={(e)=>e.currentTarget.style.transform='scale(0.97)'}
      onMouseUp={(e)=>e.currentTarget.style.transform='scale(1)'}
      onMouseLeave={(e)=>e.currentTarget.style.transform='scale(1)'}>
      {icon}{children}
    </button>
  );
}

// ── Icon (Lucide-style 24x24 strokes)
function Icon({ name, size=22, color='currentColor', strokeWidth=2 }) {
  const paths = {
    home: <path d="M3 12 12 4l9 8v8a2 2 0 0 1-2 2h-4v-6h-6v6H5a2 2 0 0 1-2-2z"/>,
    camera: <g><path d="M23 19V8a2 2 0 0 0-2-2h-3.2l-1.4-2H7.6L6.2 6H3a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h18a2 2 0 0 0 2-2z"/><circle cx="12" cy="13" r="4"/></g>,
    chart: <g><path d="M3 17l5-5 4 4 8-8"/><path d="M15 8h6v6"/></g>,
    user: <g><circle cx="12" cy="8" r="4"/><path d="M4 21c1-4 4.5-6 8-6s7 2 8 6"/></g>,
    clock: <g><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></g>,
    plus: <g><path d="M12 5v14M5 12h14"/></g>,
    check: <g><circle cx="12" cy="12" r="9"/><path d="M8 12l3 3 5-6"/></g>,
    sparkle: <g><path d="M12 3l2 5 5 2-5 2-2 5-2-5-5-2 5-2z"/></g>,
    chevronR: <path d="M9 6l6 6-6 6"/>,
    chevronL: <path d="M15 6l-6 6 6 6"/>,
    close: <g><path d="M18 6L6 18M6 6l12 12"/></g>,
    flame: <path d="M12 2s4 4 4 9a4 4 0 01-8 0c0-2 1-3 1-3S8 12 8 14a4 4 0 008 0c0-5-4-12-4-12z"/>,
    heart: <path d="M12 21s-8-5-8-11a5 5 0 0 1 9-3 5 5 0 0 1 9 3c0 6-8 11-8 11z"/>,
    settings: <g><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33h0a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82v0a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></g>,
    fridge: <g><rect x="5" y="2" width="14" height="20" rx="3"/><path d="M5 10h14M9 6v2M9 14v3"/></g>,
    bell: <path d="M18 16v-5a6 6 0 10-12 0v5l-2 2h16l-2-2zM10 20a2 2 0 004 0"/>,
    arrowR: <g><path d="M5 12h14M13 6l6 6-6 6"/></g>,
    scale: <g><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M7 5v-1a2 2 0 012-2h6a2 2 0 012 2v1M8 12h8"/></g>,
  };
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color}
         strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round">
      {paths[name]}
    </svg>
  );
}

// ── Card
function Card({children, style={}, onClick, elevated=false, padding=16}) {
  return (
    <div onClick={onClick} style={{
      background:'#fff', borderRadius:18, padding,
      border:`1px solid ${C.hairline}`,
      boxShadow: elevated ? '0 6px 18px rgba(58,38,20,0.08)' : '0 2px 6px rgba(58,38,20,0.05)',
      cursor: onClick ? 'pointer' : 'default',
      ...style,
    }}>{children}</div>
  );
}

// ── Progress bar
function ProgressBar({value=0, max=100, height=10, tone='coral'}) {
  const pct = Math.min(100, (value/max)*100);
  const fill = tone === 'leaf'
    ? 'linear-gradient(140deg, #B5DB94 0%, #7FB77E 100%)'
    : 'linear-gradient(140deg, #FFB38A 0%, #FF8A5B 100%)';
  return (
    <div style={{height, borderRadius:999, background:C.border, overflow:'hidden'}}>
      <div style={{width:`${pct}%`, height:'100%', background:fill, borderRadius:999, transition:'width .4s ease'}}/>
    </div>
  );
}

// ── Ring progress
function Ring({value=0, size=110, stroke=10, tone='coral', label}) {
  const r = (size - stroke) / 2;
  const circ = 2 * Math.PI * r;
  const offset = circ - (value/100) * circ;
  const color = tone === 'leaf' ? C.leaf : C.coral;
  return (
    <div style={{position:'relative', width:size, height:size}}>
      <svg width={size} height={size}>
        <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={C.border} strokeWidth={stroke}/>
        <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={color} strokeWidth={stroke}
                strokeLinecap="round" strokeDasharray={circ} strokeDashoffset={offset}
                transform={`rotate(-90 ${size/2} ${size/2})`} style={{transition:'stroke-dashoffset .6s ease'}}/>
      </svg>
      {label && <div style={{position:'absolute', inset:0, display:'flex', flexDirection:'column',
        alignItems:'center', justifyContent:'center', fontFamily:FONT}}>{label}</div>}
    </div>
  );
}

// ── Meal type pill (used in multiple screens)
const MEAL_COLORS = {
  '아침': { bg:'#FFF0D6', fg:'#A67A1F', dot:'#F7D36A' },
  '점심': { bg:'#FFE4D1', fg:'#C9582F', dot:'#FF8A5B' },
  '저녁': { bg:'#EDE5F5', fg:'#5E4A85', dot:'#8B6FB3' },
  '간식': { bg:'#E0F1CE', fg:'#457A44', dot:'#7FB77E' },
};
function MealChip({type, time}) {
  const m = MEAL_COLORS[type] || MEAL_COLORS['점심'];
  return (
    <span style={{
      display:'inline-flex', alignItems:'center', gap:5, padding:'4px 10px', borderRadius:999,
      fontSize:11, fontWeight:700, fontFamily:FONT, background:m.bg, color:m.fg,
    }}>
      <span style={{width:6, height:6, borderRadius:99, background:m.dot}}/>
      {type}{time && ` · ${time}`}
    </span>
  );
}

// ── Tab bar
function TabBar({active='home', onChange, onFab}) {
  const tabs = [
    {key:'home', icon:'home', label:'홈'},
    {key:'log',  icon:'clock', label:'기록'},
    {key:'chart',icon:'chart', label:'추세'},
    {key:'me',   icon:'user', label:'나'},
  ];
  return (
    <div style={{
      position:'relative', padding:'8px 14px 24px',
      display:'flex', alignItems:'center', justifyContent:'space-between',
      background:'rgba(255,253,250,0.92)',
      backdropFilter:'blur(14px)', WebkitBackdropFilter:'blur(14px)',
      borderTop:`1px solid ${C.hairline}`,
    }}>
      {tabs.slice(0,2).map(t => (
        <TabItem key={t.key} {...t} active={active===t.key} onClick={()=>onChange?.(t.key)}/>
      ))}
      <button onClick={onFab} style={{
        width:60, height:60, borderRadius:999, border:'none',
        background:'linear-gradient(140deg, #FFB38A 0%, #FF8A5B 100%)',
        color:'#fff', fontSize:30, fontWeight:700,
        display:'flex', alignItems:'center', justifyContent:'center',
        boxShadow:'0 10px 24px rgba(255,138,91,0.4)', cursor:'pointer',
        marginTop:-24, fontFamily:FONT,
      }}>
        <Icon name="camera" size={26} color="#fff" strokeWidth={2.4}/>
      </button>
      {tabs.slice(2).map(t => (
        <TabItem key={t.key} {...t} active={active===t.key} onClick={()=>onChange?.(t.key)}/>
      ))}
    </div>
  );
}
function TabItem({icon, label, active, onClick}) {
  return (
    <button onClick={onClick} style={{
      display:'flex', flexDirection:'column', alignItems:'center', gap:2,
      border:'none', background:'transparent', padding:'6px 10px', borderRadius:12,
      color: active ? C.coralDark : C.fgMuted, fontFamily:FONT, fontSize:11, fontWeight:700,
      cursor:'pointer', minWidth:56,
    }}>
      <Icon name={icon} size={22} strokeWidth={active ? 2.4 : 2}/>
      {label}
    </button>
  );
}

// ── Foodie mascot bubble (AI coach)
function FoodieBubble({children, tag='푸디의 한마디', style={}}) {
  return (
    <div style={{
      display:'flex', gap:10, alignItems:'flex-start',
      background:'#fff', padding:12, borderRadius:16,
      border:`1px solid ${C.hairline}`, ...style,
    }}>
      <div style={{
        width:40, height:40, borderRadius:999,
        background:'linear-gradient(180deg, #FFF4EC 0%, #FFE4D1 100%)',
        display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0,
      }}>
        <img src="../../assets/mascot-foodie.svg" width="30" alt=""/>
      </div>
      <div style={{flex:1}}>
        <div style={{fontSize:11, fontWeight:700, color:C.coralDark, letterSpacing:0.02, marginBottom:3, fontFamily:FONT}}>
          {tag}
        </div>
        <div style={{fontSize:13.5, color:C.fg1, lineHeight:1.5, fontFamily:FONT}}>
          {children}
        </div>
      </div>
    </div>
  );
}

// Expose globally
Object.assign(window, {C, FONT, Chip, Button, Icon, Card, ProgressBar, Ring, MealChip, MEAL_COLORS, TabBar, FoodieBubble});
