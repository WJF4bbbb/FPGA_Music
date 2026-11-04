'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
function mount() {
  let now=1000,waveHandler,connectionHandler;const ready=[],timers=[],nodes={},lines=[];
  const context={setTransform(){},clearRect(){},fillRect(){},beginPath(){},moveTo(x,y){lines.push(['m',x,y]);},lineTo(x,y){lines.push(['l',x,y]);},stroke(){},fillText(){},save(){},restore(){},rect(){},clip(){}};
  function element(id) {return nodes[id] ||= {id,textContent:'',value:'1',width:0,height:0,style:{},events:{},clientWidth:320,addEventListener(n,f){this.events[n]=f;},getBoundingClientRect(){return {width:320,height:240};},getContext(){return context;},set innerHTML(html){for(const m of html.matchAll(/id="([^"]+)"/g))element(m[1]);}};}
  element('waveformPanel');
  const ctx={console,Date:{now:()=>now},Math,Number,window:null,document:{getElementById:id=>nodes[id]||null},devicePixelRatio:2,addEventListener:(n,fn)=>{if(n==='DOMContentLoaded')ready.push(fn);},setInterval:fn=>timers.push(fn),Serial:{onWave:fn=>waveHandler=fn,onConnection:fn=>connectionHandler=fn}};ctx.window=ctx;
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../web/js/waveform.js'),'utf8'),ctx);ready.forEach(fn=>fn());
  return {nodes,lines,receive:w=>waveHandler(w),connect:v=>connectionHandler(v),tick:ms=>{now+=ms;timers.forEach(fn=>fn());}};
}
test('live canvas starts waiting and draws only received signed samples with physical time axis',()=>{
  const m=mount();assert.match(m.nodes.waveformStatus.textContent,/等待/);assert.equal(m.lines.filter(l=>l[0]==='l').length<512,true);
  m.connect(true);m.lines.length=0;m.receive({captureId:9,sampleRate:46875,triggered:true,samples:Array.from({length:512},(_,i)=>i%2?-32768:32767)});
  assert.equal(m.nodes.waveformCanvas.width,640);assert.match(m.nodes.waveformMeta.textContent,/512/);assert.match(m.nodes.waveformMeta.textContent,/10\.90/);assert.match(m.nodes.waveformMeta.textContent,/46.?875/);assert.equal(m.lines.filter(l=>l[0]==='l').length>=511,true);
});
test('freeze retains plotted capture; resume shows recent capture; stale and reconnect clear freshness',()=>{
  const m=mount(),w=id=>({captureId:id,sampleRate:46875,triggered:false,samples:Array(512).fill(2000)});
  m.connect(true);m.receive(w(1));m.nodes.waveformFreeze.events.click();m.receive(w(2));assert.match(m.nodes.waveformMeta.textContent,/#1\b/);m.nodes.waveformFreeze.events.click();assert.match(m.nodes.waveformMeta.textContent,/#2\b/);
  m.nodes.waveformScale.value='2';m.nodes.waveformScale.events.change();m.tick(2000);assert.match(m.nodes.waveformStatus.textContent,/过期|陈旧/);
  m.connect(false);m.connect(true);assert.match(m.nodes.waveformStatus.textContent,/等待/);assert.doesNotMatch(m.nodes.waveformMeta.textContent,/#2\b/);
});
test('both live pages load waveform protocol before transport and preserve other panels',()=>{
  for(const page of ['index.html','bridge.html']){const html=fs.readFileSync(path.join(__dirname,'../web',page),'utf8');assert.match(html,/id="waveformPanel"/);assert.match(html,/js\/waveform\.js/);assert.ok(html.indexOf('js/wave_protocol.js')<html.indexOf(page==='index.html'?'js/serial.js':'js/bridge_serial.js'));assert.match(html,/js\/input.js/);assert.match(html,/js\/display.js/);}
});

test('demo keeps its status transport dependency available',()=>{
 const html=fs.readFileSync(path.join(__dirname,'../web/demo.html'),'utf8');assert.ok(html.indexOf('js/wave_protocol.js')>=0);assert.ok(html.indexOf('js/wave_protocol.js')<html.indexOf('js/serial.js'));
});
