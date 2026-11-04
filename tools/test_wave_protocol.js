'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const protocolPath = path.join(__dirname, '../web/js/wave_protocol.js');
const protocol = fs.existsSync(protocolPath) ? require(protocolPath) : {};
function chunks(id=7, flags=1) {
  return [0,120,240,360,480].map(offset => {
    const p=Buffer.alloc(12+2*Math.min(120,512-offset));
    p[0]=1;p[1]=flags;p.writeUInt16LE(id,2);p.writeUInt16LE(512,4);p.writeUInt16LE(offset,6);p.writeUInt32LE(46875,8);
    for(let i=0;i<(p.length-12)/2;i++)p.writeInt16LE([-32768,-1,0,32767][(offset+i)%4],12+2*i);
    return p;
  });
}
function frame(type,p) {const b=Buffer.concat([Buffer.from([type,p.length]),p]);return Buffer.concat([Buffer.from([170,85]),b,Buffer.from([protocol.crc8(b)])]);}
function browser(file, extra={}) {
  const ctx={console,Uint8Array,ArrayBuffer,DataView,Date,Promise,setInterval:()=>1,clearInterval:()=>{},navigator:{serial:{}},document:{getElementById:()=>null},location:{protocol:'http:',search:'?auto=0'},...extra};
  ctx.window=ctx;ctx.addEventListener=()=>{};ctx.WaveProtocol=protocol;
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../web/js',file),'utf8'),ctx);return ctx;
}
test('assembler API exists',()=>assert.equal(typeof protocol.Assembler,'function'));
test('signed complete capture, wrap and reset',()=>{
  const a=new protocol.Assembler();
  for(const id of [65535,0]) {const ps=chunks(id);for(const p of ps.slice(0,4))assert.equal(a.push(p),null);const w=a.push(ps[4]);assert.equal(w.captureId,id);assert.equal(w.sampleRate,46875);assert.equal(w.triggered,true);assert.deepEqual(w.samples.slice(0,4),[-32768,-1,0,32767]);assert.equal(w.samples.length,512);}
  a.push(chunks()[0]);a.reset();for(const p of chunks().slice(1))assert.equal(a.push(p),null);
});
test('missing, duplicate, out of order and mismatched chunks invalidate; offset zero recovers',()=>{
  for(const order of [[0,2,3,4],[0,1,1,2,3,4],[0,2,1,3,4]]) {const a=new protocol.Assembler(),ps=chunks();for(const n of order)assert.equal(a.push(ps[n]),null);let w;for(const p of ps)w=a.push(p);assert.equal(w.samples.length,512);}
  for(const change of [p=>p[2]++,p=>p[1]=0,p=>p[0]=2,p=>p[4]=1,p=>p[8]=0,p=>p[1]=2,p=>p[6]=121]) {const a=new protocol.Assembler(),ps=chunks();a.push(ps[0]);change(ps[1]);for(const p of ps.slice(1))assert.equal(a.push(p),null);}
  for(const p of [Buffer.alloc(0),chunks()[0].subarray(0,251),Buffer.alloc(254)])assert.equal(new protocol.Assembler().push(p),null);
});
test('outer framing accepts arbitrary fragmentation and invalidates a capture on CRC error',()=>{
  const a=new protocol.Assembler(),waves=[],types=[];
  const d=new protocol.FrameDecoder((t,p)=>{types.push(t);if(t===16){const w=a.push(p);if(w)waves.push(w);}},()=>a.reset());
  const ps=chunks(),bad=frame(1,Buffer.alloc(15));bad[bad.length-1]^=1;
  const data=Buffer.concat([Buffer.from([1,170]),frame(16,ps[0]),bad,...ps.slice(1).map(p=>frame(16,p)),...chunks(0).map(p=>frame(16,p)),frame(1,Buffer.alloc(15))]);
  for(let n=0;n<data.length;n+=7)d.push(data.subarray(n,n+7));
  assert.equal(waves.length,1);assert.equal(waves[0].captureId,0);assert.equal(types.filter(t=>t===1).length,1);
});
test('Web Serial preserves status callbacks and separates complete wave callbacks',async()=>{
  const reads=[];let pending;
  const port={open:async()=>{},close:async()=>{},writable:{getWriter:()=>({write:async()=>{},releaseLock(){}})},readable:{getReader:()=>({read:()=>reads.length?Promise.resolve({value:reads.shift(),done:false}):new Promise(r=>pending=r),cancel:async()=>{if(pending)pending({done:true});},releaseLock(){}})}};
  const ctx=browser('serial.js',{navigator:{serial:{requestPort:async()=>port}}});let statuses=[],waves=[],connections=[];
  assert.equal(typeof ctx.Serial.onWave,'function');ctx.Serial.onFrame(s=>statuses.push(s));ctx.Serial.onWave(w=>waves.push(w));ctx.Serial.onConnection(v=>connections.push(v));
  reads.push(Buffer.concat([frame(1,Buffer.from([1,2,60,61,0,0,3,2,254,255,127,1,0,0,128])),...chunks().map(p=>frame(16,p))]));
  await ctx.Serial.connect();await new Promise(r=>setImmediate(r));
  assert.equal(statuses.length,1);assert.equal(statuses[0].bend,-2);assert.equal(statuses[0].clip,2147483649);assert.equal(waves.length,1);await ctx.Serial.disconnect();assert.deepEqual(connections,[true,false]);
});
test('bridge named wave event validates data and reconnect ignores obsolete stream callbacks',()=>{
  const streams=[];class EventSource {constructor(){this.events={};streams.push(this);}addEventListener(n,fn){this.events[n]=fn;}close(){}}
  const ctx=browser('bridge_serial.js',{EventSource});let waves=[],statuses=[];
  assert.equal(typeof ctx.Serial.onWave,'function');ctx.Serial.onWave(w=>waves.push(w));ctx.Serial.onFrame(s=>statuses.push(s));ctx.Serial.connect();let es=streams[0];es.onopen();
  const wave={captureId:3,sampleRate:46875,triggered:true,samples:Array(512).fill(-1)};
  es.events.wave({data:JSON.stringify(wave)});es.events.wave({data:JSON.stringify({...wave,samples:[0]})});es.onmessage({data:'{"notes":[60]}'});
  assert.equal(waves.length,1);assert.equal(statuses.length,1);ctx.Serial.disconnect();ctx.Serial.connect();streams[1].onopen();es.events.wave({data:JSON.stringify(wave)});assert.equal(waves.length,1);ctx.Serial.disconnect();
});
module.exports={chunks};

test('optional physical UART fixture decodes through public frame decoder',t=>{
 const fixture=path.join(__dirname,'../sim/waveform_uart.hex');if(!fs.existsSync(fixture)){t.skip('physical UART fixture not generated yet');return;}
 const waves=[],a=new protocol.Assembler(),decoder=new protocol.FrameDecoder((type,p)=>{if(type===16){const w=a.push(p);if(w)waves.push(w);}},()=>a.reset());
 const bytes=Buffer.from(fs.readFileSync(fixture,'utf8').trim().split(/\s+/).map(v=>parseInt(v,16)));
 for(let n=0;n<bytes.length;n+=17)decoder.push(bytes.subarray(n,n+17));
 assert.deepEqual(waves.map(w=>w.captureId),[0,1]);const pattern=[0,32767,-32768,-1,1,-21931,1234,-1234];for(const w of waves){assert.equal(w.sampleRate,46875);assert.equal(w.triggered,true);assert.deepEqual(w.samples,Array.from({length:512},(_,i)=>pattern[i%8]));}
});
