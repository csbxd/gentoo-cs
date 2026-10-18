import {setTimeout as sleep} from 'node:timers/promises';
const [port,fragment,xText,yText]=process.argv.slice(2),x=Number(xText),y=Number(yText);
if(!Number.isFinite(x)||!Number.isFinite(y))throw Error('invalid coordinate');
const targets=await(await fetch(`http://127.0.0.1:${port}/json`)).json();
const target=targets.find(t=>t.url.includes(fragment)&&t.webSocketDebuggerUrl);
if(!target)throw Error('target not available: '+JSON.stringify(targets));
const ws=new WebSocket(target.webSocketDebuggerUrl);let id=0;const pending=new Map();
ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id&&pending.has(m.id)){const p=pending.get(m.id);pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(m.error):p.resolve(m.result);}});
await new Promise((resolve,reject)=>{ws.addEventListener('open',resolve,{once:true});ws.addEventListener('error',reject,{once:true});});
function send(method,params={}){return new Promise((resolve,reject)=>{const n=++id;const timer=setTimeout(()=>reject(Error('timeout '+method)),2000);pending.set(n,{resolve,reject,timer});ws.send(JSON.stringify({id:n,method,params}));});}
console.log('target',target.title,target.url);
console.log('element',JSON.stringify(await send('Runtime.evaluate',{expression:`document.elementFromPoint(${x},${y}).outerHTML.slice(0,1800)`,returnByValue:true})));
await send('Input.dispatchMouseEvent',{type:'mouseMoved',x,y});
await send('Input.dispatchMouseEvent',{type:'mousePressed',x,y,button:'left',clickCount:1});
await sleep(100);
await send('Input.dispatchMouseEvent',{type:'mouseReleased',x,y,button:'left',clickCount:1});
await sleep(500);ws.close();console.log('clicked',x,y);
