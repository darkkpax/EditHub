import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
const root=path.resolve('.qa');
let page;
for(let i=0;i<80;i++){try{const pages=await (await fetch('http://127.0.0.1:9223/json/list')).json();page=pages.find(p=>p.url.startsWith('http://tauri.localhost'));if(page)break}catch{}await new Promise(r=>setTimeout(r,100));}
if(!page)throw Error('launch the debug app with isolated .qa config and CDP port 9223 first');
const socket=new WebSocket(page.webSocketDebuggerUrl);await new Promise((resolve,reject)=>{socket.onopen=resolve;socket.onerror=reject});
let seq=0;const waiting=new Map();
socket.onmessage=({data})=>{const m=JSON.parse(data);if(m.id){const h=waiting.get(m.id);waiting.delete(m.id);m.error?h.reject(m.error):h.resolve(m.result)}};
function cdp(method,params={}){return new Promise((resolve,reject)=>{const id=++seq;waiting.set(id,{resolve,reject});socket.send(JSON.stringify({id,method,params}))})}
async function evaluate(expression){const result=await cdp('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(result.exceptionDetails)throw Error(result.exceptionDetails.text+JSON.stringify(result.exceptionDetails.exception));return result.result.value}
async function clickUI(selector){const p=await evaluate(`(()=>{const el=document.querySelector(${JSON.stringify(selector)});if(!el)throw Error('missing click target');const r=el.getBoundingClientRect();const x=r.x+r.width/2,y=r.y+r.height/2;const hit=document.elementFromPoint(x,y);return {x,y,reachable:el===hit||el.contains(hit)}})()`);assert.equal(p.reachable,true,`pointer cannot reach ${selector}`);await cdp('Input.dispatchMouseEvent',{type:'mouseMoved',x:p.x,y:p.y});await cdp('Input.dispatchMouseEvent',{type:'mousePressed',x:p.x,y:p.y,button:'left',clickCount:1});await cdp('Input.dispatchMouseEvent',{type:'mouseReleased',x:p.x,y:p.y,button:'left',clickCount:1});}
async function invoke(name,args={}){return evaluate(`window.__TAURI_INTERNALS__.invoke(${JSON.stringify(name)},${JSON.stringify(args)})`)}
try{
 for(let i=0;i<100;i++){if(await evaluate(`!!window.__TAURI_INTERNALS__?.invoke`))break;await new Promise(r=>setTimeout(r,50));}
 const settings=await invoke('get_settings');assert.equal(path.resolve(settings.projectsFolder),path.join(root,'projects'),'refusing to mutate real user projects');
 let projects=await invoke('list_projects');let project=projects.find(p=>p.name==='Autumn');
 if(!project)project=await invoke('create_project',{name:'Autumn',editor:'davinci',urls:[]});
 assert.equal(project.editor,'davinci');const folderStart=performance.now();await invoke('project_entries',{id:project.id,relative:'FOOTAGE',folderPath:project.folderPath});const folderLookupMs=Math.round(performance.now()-folderStart);console.log(JSON.stringify({folderLookupMs}));const folders=await invoke('project_entries',{id:project.id,relative:''});assert.ok(folders.some(f=>f.name==='FOOTAGE'));assert.ok(folders.some(f=>f.name==='VOICE'));
 const fixture=path.join(project.folderPath,'FOOTAGE','00-preview.mp4');
 try{await fs.access(fixture)}catch{const encoded=spawnSync('ffmpeg',['-nostdin','-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=640x360:rate=24','-t','2','-c:v','mpeg4','-y',fixture],{windowsHide:true});assert.equal(encoded.status,0,String(encoded.stderr));}
 const cover=await invoke('project_preview',{id:project.id,folderPath:project.folderPath});assert.ok(cover?.startsWith('data:image/jpeg;base64,'));const coverBytes=Buffer.from(cover.split(',')[1],'base64');assert.equal(coverBytes[0],255);assert.equal(coverBytes[1],216);assert.equal(await invoke('project_preview',{id:project.id,folderPath:project.folderPath}),cover);
 const payload=Buffer.from('edithub native download smoke test');
 const fileName=`native-smoke-${Date.now()}.mov`;
 const server=http.createServer((req,res)=>{res.setHeader('content-type','application/octet-stream');res.setHeader('content-disposition',`attachment; filename="${fileName}"`);res.setHeader('content-length',payload.length);res.end(payload)});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 try{
  const download=await evaluate(`(async()=>{const events=[];const off=await window.__TAURI_INTERNALS__.invoke('plugin:event|listen',{event:'download-progress',target:{kind:'Any'},handler:window.__TAURI_INTERNALS__.transformCallback(e=>events.push(e.payload))});window.__smokeEvents=events;return true})()`);
  assert.equal(download,true);await invoke('start_downloads',{id:project.id,urls:[`http://127.0.0.1:${server.address().port}/file.mov`]});
  let done;for(let i=0;i<100;i++){done=await evaluate(`window.__smokeEvents.find(e=>['complete','error'].includes(e.state))`);if(done)break;await new Promise(resolve=>setTimeout(resolve,100))}
  assert.equal(done?.state,'complete',JSON.stringify(done));assert.deepEqual(await fs.readFile(path.join(project.folderPath,'FOOTAGE',fileName)),payload);
 }finally{server.close()}
 await cdp('Page.reload');await new Promise(resolve=>setTimeout(resolve,1300));
 await fs.mkdir(path.join(root,'screenshots'),{recursive:true});const shot=await cdp('Page.captureScreenshot',{format:'png'});await fs.writeFile(path.join(root,'screenshots/workspace.png'),Buffer.from(shot.data,'base64'));
 const ui=await evaluate(`({text:document.body.innerText,overflows:document.documentElement.scrollWidth>innerWidth,buttons:document.querySelectorAll('button').length})`);assert.ok(ui.text.includes('Autumn'));assert.equal(ui.overflows,false);
 async function waitUI(expression){for(let i=0;i<40;i++){if(await evaluate(expression))return;await new Promise(r=>setTimeout(r,50))}throw Error(`UI condition failed: ${expression}`)}
 assert.equal(await evaluate(`!!document.querySelector('.app-topbar,.brand,.workspace-heading')`),false);
 await waitUI(`!!document.querySelector('.project-hero .project-mark img')`);
 const heroTop=await evaluate(`document.querySelector('.project-hero').getBoundingClientRect().top`);
 await evaluate(`(()=>{const e=document.querySelector('.project-scroll .scroll-viewport');e.style.height='350px';e.scrollTop=120;e.dispatchEvent(new Event('scroll',{bubbles:true}));return true})()`);
 await new Promise(r=>setTimeout(r,150));assert.ok(Math.abs(heroTop-await evaluate(`document.querySelector('.project-hero').getBoundingClientRect().top`))<1);
 assert.ok((await evaluate(`getComputedStyle(document.querySelector('.project-hero'),'::before').backdropFilter`)).includes('26px'));assert.ok((await evaluate(`getComputedStyle(document.querySelector('.sidebar-bottom'),'::before').backdropFilter`)).includes('26px'));
 assert.equal(await evaluate(`getComputedStyle(document.querySelector('.project-sidebar'),'::after').content`),'none');assert.equal(await evaluate(`!!document.querySelector('.project-badge')`),false);
 await evaluate(`(()=>{const e=document.querySelector('.project-scroll .scroll-viewport');e.style.height='';e.scrollTop=0;e.dispatchEvent(new Event('scroll',{bubbles:true}));return true})()`);
 await evaluate(`document.querySelector('.new-project').click()`);await waitUI(`!!document.querySelector('[role="dialog"]')`);
 assert.ok((await evaluate(`document.querySelector('[role="dialog"]').innerText`)).includes('New project'));assert.equal(await evaluate(`!!document.querySelector('.inspector,.theme-toggle,button[aria-label="Sound library"]')`),false);
 await new Promise(r=>setTimeout(r,300));
 const modalShot=await cdp('Page.captureScreenshot',{format:'png'});await fs.writeFile(path.join(root,'screenshots/create-project.png'),Buffer.from(modalShot.data,'base64'));
 await evaluate(`document.querySelector('[role="dialog"] button[aria-label="Close"]').click()`);await waitUI(`!document.querySelector('[role="dialog"]')`);
 await evaluate(`document.querySelector('button[aria-label="Settings"]').click()`);await waitUI(`!!document.querySelector('.path-field input')`);
 assert.equal(await evaluate(`document.querySelector('.path-field input').value`),settings.projectsFolder);
 assert.equal(await evaluate(`!!document.querySelector('[role="alert"]')`),false);
 const settingsShot=await cdp('Page.captureScreenshot',{format:'png'});await fs.writeFile(path.join(root,'screenshots/settings.png'),Buffer.from(settingsShot.data,'base64'));
 await clickUI('.filter:first-child');await waitUI(`!!document.querySelector('.project-hero')`);
 await evaluate(`document.querySelector('button[aria-label="Settings"]').click()`);await waitUI(`!!document.querySelector('.settings-screen')`);await clickUI('button[aria-label="Back to projects"]');await waitUI(`!!document.querySelector('.project-hero')`);
 assert.equal(await evaluate(`window.__TAURI_INTERNALS__.invoke('list_library').then(()=>false,()=>true)`),true);
 async function enterFootage(){await evaluate(`Array.from(document.querySelectorAll('.folder-card')).find(e=>e.querySelector('strong').textContent==='FOOTAGE').click()`);await waitUI(`document.querySelector('.files-toolbar .breadcrumb')?.textContent==='FOOTAGE'&&!document.querySelector('.detail-primary .loading')`);}
 async function parentFolder(){await evaluate(`document.querySelector('button[aria-label="Parent folder"]').click()`);await waitUI(`!!document.querySelector('.folder-card')`);}
 await enterFootage();await parentFolder();
 const refreshFile=`refresh-check-${Date.now()}.mov`;await fs.writeFile(path.join(project.folderPath,'FOOTAGE',refreshFile),'refresh check');
 await enterFootage();assert.equal(await evaluate(`Array.from(document.querySelectorAll('.folder-card strong')).some(e=>e.textContent===${JSON.stringify(refreshFile)})`),false,'reopened folder should keep cached entries until refresh');
 await evaluate(`document.querySelector('button[aria-label="Refresh files"]').click()`);await waitUI(`Array.from(document.querySelectorAll('.folder-card strong')).some(e=>e.textContent===${JSON.stringify(refreshFile)})`);await parentFolder();
 const oldCover=await evaluate(`document.querySelector('.project-hero .project-mark img').src`);
 const updatedFixture=spawnSync('ffmpeg',['-nostdin','-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=640x360:rate=24','-t','2','-vf',`hue=h=${Date.now()%360}`,'-c:v','mpeg4','-y',fixture],{windowsHide:true});assert.equal(updatedFixture.status,0,String(updatedFixture.stderr));
 await evaluate(`document.querySelector('button[aria-label="Refresh files"]').click()`);await waitUI(`document.querySelector('.project-hero .project-mark img')?.src!==${JSON.stringify(oldCover)}`);
 const originalTheme=await evaluate(`localStorage.getItem('edithub:theme')`);
 async function chooseTheme(theme){if(await evaluate(`document.documentElement.dataset.theme!==${JSON.stringify(theme)}`)){await evaluate(`document.querySelector('button[aria-label="Settings"]').click()`);await waitUI(`!!document.querySelector('.theme-option')`);await evaluate(`document.querySelector('.theme-option.${theme}').click()`);await evaluate(`document.querySelector('button[aria-label="Projects"]').click()`);await waitUI(`!!document.querySelector('.project-hero')`);}await waitUI(`document.documentElement.dataset.theme===${JSON.stringify(theme)}`);await evaluate(`document.fonts.ready.then(()=>true)`);await new Promise(r=>setTimeout(r,350));}
 async function screenshot(name){const image=await cdp('Page.captureScreenshot',{format:'png'});await fs.writeFile(path.join(root,'screenshots',name),Buffer.from(image.data,'base64'));}
 try{
  await chooseTheme('dark');assert.equal(await evaluate(`document.fonts.check('700 96px UnifrakturCook')`),true);await screenshot('workspace-dark.png');
  await chooseTheme('light');assert.equal(await evaluate(`localStorage.getItem('edithub:theme')`),'light');assert.equal(await invoke('plugin:window|theme',{label:'main'}),'light');
  await cdp('Page.reload');await waitUI(`!!document.querySelector('.project-hero')`);await waitUI(`document.documentElement.dataset.theme==='light'`);await evaluate(`document.fonts.ready.then(()=>true)`);await new Promise(r=>setTimeout(r,350));await screenshot('workspace-light.png');
  await evaluate(`document.querySelector('.new-project').click()`);await waitUI(`!!document.querySelector('[role="dialog"]')`);await new Promise(r=>setTimeout(r,350));
  assert.equal(await evaluate(`getComputedStyle(document.querySelector('.dialog-overlay')).backdropFilter`),'none');assert.ok((await evaluate(`getComputedStyle(document.querySelector('.dialog-content')).backdropFilter`)).includes('24px'));await screenshot('create-project-light.png');
  await evaluate(`document.querySelector('[role="dialog"] button[aria-label="Close"]').click()`);await waitUI(`!document.querySelector('[role="dialog"]')`);
  await chooseTheme('dark');assert.equal(await invoke('plugin:window|theme',{label:'main'}),'dark');
  await evaluate(`document.querySelector('.new-project').click()`);await waitUI(`!!document.querySelector('[role="dialog"]')`);await new Promise(r=>setTimeout(r,350));await screenshot('create-project-dark.png');
  await evaluate(`document.querySelector('[role="dialog"] button[aria-label="Close"]').click()`);await waitUI(`!document.querySelector('[role="dialog"]')`);
  await cdp('Emulation.setDeviceMetricsOverride',{width:824,height:700,deviceScaleFactor:1,mobile:false});await new Promise(r=>setTimeout(r,250));
  const menuVisible=await evaluate(`(()=>{const r=document.querySelector('.project-menu>summary').getBoundingClientRect();return r.width>0&&r.height>0})()`);assert.equal(menuVisible,true);
  await evaluate(`document.querySelector('.project-menu>summary').click()`);await evaluate(`document.querySelector('.project-menu-content button').click()`);await waitUI(`!!document.querySelector('[role="dialog"]')`);
  assert.ok((await evaluate(`document.querySelector('[role="dialog"]').innerText`)).includes('Move to iCloud'));await evaluate(`document.querySelector('[role="dialog"] button[aria-label="Close"]').click()`);await waitUI(`!document.querySelector('[role="dialog"]')`);
  assert.equal(await evaluate(`document.documentElement.scrollWidth>innerWidth`),false);await screenshot('workspace-narrow.png');
 }finally{await cdp('Emulation.clearDeviceMetricsOverride');await chooseTheme(originalTheme==='light'?'light':'dark');if(originalTheme===null)await evaluate(`localStorage.removeItem('edithub:theme')`);}
 console.log(JSON.stringify({ok:true,checks:['native IPC','pointer returns from settings through filters and back button','real video frame preview','preview disk cache','manual refresh updates video cover','top bar and branding removed','full project header backdrop blur','pinned Settings footer blur','sidebar divider removed','sound library IPC removed','folder revisit uses cache','manual folder refresh','isolated settings','create project','folder layout','HTTP download to FOOTAGE','progress completion event','React native rendering','no horizontal overflow','Radix dialog open/close','settings UI renders real config','dark and light themes','theme survives reload','native title bar follows theme','self-hosted gothic font loaded','dialog backdrop blur','archive actions remain accessible at narrow viewport'],screenshot:path.join(root,'screenshots/workspace.png'),buttons:ui.buttons},null,2));
}finally{socket.close()}
