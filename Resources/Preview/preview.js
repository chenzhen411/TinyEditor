'use strict';
const {MarkdownIt,mermaid,katex,DOMPurify,hljs}=TinyLib;
let source='', lineStarts=[], scrollFraction=0, revision=0, selectedAll=false, formulaQueue=[];
function formulaHTML(tex,block,raw){const id='formula-'+formulaQueue.length;formulaQueue.push({id,tex,block,raw});return `<span class="math" data-formula="${id}">${escape(raw)}</span>`}
const root=document.getElementById('document');
const md=new MarkdownIt({html:true,linkify:true,typographer:false,highlight:(code,lang)=>{try{return lang&&hljs.getLanguage(lang)?hljs.highlight(code,{language:lang,ignoreIllegals:true}).value:''}catch{return ''}}});
const escape=md.utils.escapeHtml;
DOMPurify.addHook('uponSanitizeAttribute',(node,data)=>{if(node.nodeName==='IMG'&&data.attrName==='src'){node.setAttribute('data-original-src',data.attrValue);data.keepAttr=false}});
function setLines(text) { lineStarts=[0]; for(let i=0;i<text.length;i++){if(text[i]==='\r'){if(text[i+1]==='\n')i++;lineStarts.push(i+1)}else if(text[i]==='\n')lineStarts.push(i+1)} }
function sourceRange(map){return [lineStarts[map[0]]??source.length,lineStarts[map[1]]??source.length]}
function attrs(map){if(!map)return '';const [s,e]=sourceRange(map);return ` data-source-start="${s}" data-source-end="${e}"`}
const original=md.renderer.renderToken.bind(md.renderer);
md.renderer.renderToken=(tokens,i,options)=>{const t=tokens[i];if(t.map&&t.nesting!==-1){const[s,e]=sourceRange(t.map);t.attrSet('data-source-start',String(s));t.attrSet('data-source-end',String(e));}return original(tokens,i,options)};
md.inline.ruler.before('escape','tiny_math',(state,silent)=>{const start=state.pos;if(state.src[start]!=='$')return false;const block=state.src[start+1]==='$';const mark=block?'$$':'$';let end=state.src.indexOf(mark,start+mark.length);if(end<0||(!block&&state.src.slice(start+1,end).includes('\n')))return false;if(!silent){let t=state.push('tiny_math','span',0);t.content=state.src.slice(start+mark.length,end);t.meta={block,raw:state.src.slice(start,end+mark.length)};}state.pos=end+mark.length;return true});
md.renderer.rules.tiny_math=(tokens,i)=>{const t=tokens[i];return formulaHTML(t.content,t.meta.block,t.meta.raw)};
const fence=md.renderer.rules.fence;
md.renderer.rules.fence=(tokens,i,options,env,self)=>{const t=tokens[i];let content;if(t.info.trim()==='mermaid'){content=`<div class="mermaid" data-code="${escape(t.content)}">${escape(t.content)}</div>`}else content=fence(tokens,i,options,env,self);return `<section class="code-unit"${attrs(t.map)}><button class="copy-source" type="button" aria-label="复制 Markdown">复制 Markdown</button>${content}</section>`};
const htmlBlock=md.renderer.rules.html_block;
md.renderer.rules.html_block=(tokens,i,options,env,self)=>`<section${attrs(tokens[i].map)}>${htmlBlock(tokens,i,options,env,self)}</section>`;
// Block math is processed as a source-mapped fenced unit, preserving the original offsets.
md.block.ruler.before('fence','tiny_math_block',(state,start,end,silent)=>{
 const pos=state.bMarks[start]+state.tShift[start];if(!state.src.slice(pos,state.eMarks[start]).trim().startsWith('$$'))return false;
 let last=start, body=state.src.slice(pos,state.eMarks[start]).trim();
 if(body.length>4&&body.endsWith('$$')) body=body.slice(2,-2);
 else {let chunks=[body.slice(2)];let found=false;for(last=start+1;last<end;last++){const line=state.src.slice(state.bMarks[last],state.eMarks[last]);if(line.trim().endsWith('$$')){chunks.push(line.slice(0,line.lastIndexOf('$$')));found=true;break}chunks.push(line)}if(!found)return false;body=chunks.join('\n')}
 if(silent)return true;const token=state.push('tiny_math_block','section',0);token.block=true;token.map=[start,last+1];token.content=body;state.line=last+1;return true;
});
md.renderer.rules.tiny_math_block=(tokens,i)=>{const t=tokens[i];return `<section class="math-unit"${attrs(t.map)}><button class="copy-source">复制 Markdown</button>${formulaHTML(t.content,true,source.slice(...sourceRange(t.map)))}</section>`};
function nearest(node){return (node?.nodeType===1?node:node?.parentElement)?.closest('[data-source-start]')}
function rangeForSelection(){const sel=getSelection();if(!sel||sel.rangeCount===0||sel.isCollapsed)return null;const range=sel.getRangeAt(0);if(selectedAll || (range.startContainer===root&&range.startOffset===0&&range.endContainer===root&&range.endOffset===root.childNodes.length))return [0,source.length];
 const a=nearest(range.startContainer),b=nearest(range.endContainer);if(!a||!b)return null;
 let start=+a.dataset.sourceStart,end=+b.dataset.sourceEnd;
 // Exact substring copy is safe only for a single unchanged literal text node.
 if(range.startContainer===range.endContainer&&range.startContainer.nodeType===3){const node=range.startContainer;const raw=source.slice(+a.dataset.sourceStart,+a.dataset.sourceEnd);if(node.parentElement===a&&raw.replace(/\r?\n$/,'')===node.textContent){return [+a.dataset.sourceStart+range.startOffset,+a.dataset.sourceStart+range.endOffset]}}
 return [Math.min(start,+b.dataset.sourceStart),Math.max(end,+a.dataset.sourceEnd)];
}
function postCopy(range){if(range)window.webkit.messageHandlers.tiny.postMessage({kind:'copy',start:range[0],end:range[1],revision})}
window.copySelection=()=>postCopy(rangeForSelection());
window.selectSourceAll=()=>{selectedAll=true;const r=document.createRange();r.selectNodeContents(root);const s=getSelection();s.removeAllRanges();s.addRange(r)};
document.addEventListener('copy',e=>{e.preventDefault();postCopy(rangeForSelection())});
document.addEventListener('keydown',e=>{if(e.metaKey&&e.key.toLowerCase()==='a'){e.preventDefault();window.selectSourceAll()}if(e.metaKey&&e.key.toLowerCase()==='c'){e.preventDefault();if(e.shiftKey)postCopy([0,source.length]);else window.copySelection()}});
document.addEventListener('pointerdown',()=>{selectedAll=false});
root.addEventListener('contextmenu',e=>{e.preventDefault();const unit=nearest(e.target);const range=rangeForSelection()||(unit?[+unit.dataset.sourceStart,+unit.dataset.sourceEnd]:null);window.webkit.messageHandlers.tiny.postMessage({kind:'contextMenu',start:range?.[0]??-1,end:range?.[1]??-1,revision})});
root.addEventListener('click',e=>{const button=e.target.closest('.copy-source');if(button){const unit=nearest(button);postCopy([+unit.dataset.sourceStart,+unit.dataset.sourceEnd]);return}const a=e.target.closest('a');if(a){e.preventDefault();const href=a.getAttribute('href');if(href?.startsWith('#')){document.getElementById(decodeURIComponent(href.slice(1)))?.scrollIntoView()}else window.webkit.messageHandlers.tiny.postMessage({kind:'link',href})}});
window.getPreviewScroll=()=>scrollY;
window.applyTheme=(dark,size)=>{document.documentElement.dataset.theme=dark?'dark':'light';document.documentElement.style.fontSize=`${size/14*15}px`;document.documentElement.style.setProperty('--preview-scale',size/14)};
window.renderDocument=async(text,rev,dark,size,scroll=0)=>{
 source=text;revision=rev;selectedAll=false;setLines(source);window.applyTheme(dark,size);
 try{
  formulaQueue=[];let html=md.render(source);
  html=DOMPurify.sanitize(html,{ADD_ATTR:['data-source-start','data-source-end','data-code','aria-label'],FORBID_TAGS:['script','iframe','object','embed','form','input','style','link','meta','base','video','audio','source'],FORBID_ATTR:['style','srcset'],ALLOW_DATA_ATTR:true});
  root.innerHTML=html;
  // Raw HTML has already been sanitized. Insert only our trust:false KaTeX output afterwards,
  // preserving its own positioning styles without permitting user-authored CSS.
  for(const formula of formulaQueue){const node=root.querySelector(`[data-formula="${formula.id}"]`);if(!node)continue;try{node.innerHTML=katex.renderToString(formula.tex,{displayMode:formula.block,throwOnError:true,trust:false,maxExpand:500,maxSize:20})}catch(e){node.className='render-error';node.textContent='公式渲染失败：'+e.message+'\n'+formula.raw}}

  root.querySelectorAll('img').forEach(img=>{const raw=img.getAttribute('data-original-src')||'';img.removeAttribute('src');window.webkit.messageHandlers.tiny.postMessage({kind:'image',href:raw,id:(img.id='image-'+crypto.randomUUID()),revision:rev})});
  // A checkbox is presentation only; the original list marker remains in the mapped source range.
  root.querySelectorAll('li').forEach(li=>{const first=li.querySelector('p')||li;const node=first.firstChild;if(node?.nodeType===3&&/^\[[ xX]\] /.test(node.textContent)){const checked=node.textContent[1].toLowerCase()==='x';node.textContent=node.textContent.slice(4);const mark=document.createElement('span');mark.className='task-mark';mark.textContent=checked?'☑ ':'☐ ';first.prepend(mark)}});
  mermaid.initialize({startOnLoad:false,securityLevel:'strict',htmlLabels:false,theme:dark?'dark':'default',maxTextSize:100000,maxEdges:500,suppressErrorRendering:true,flowchart:{htmlLabels:false},secure:['securityLevel','startOnLoad','maxTextSize','maxEdges','htmlLabels','themeCSS','flowchart']});
  for(const [i,node]of [...root.querySelectorAll('.mermaid')].entries()){const code=node.dataset.code||node.textContent;try{const{svg}=await mermaid.render('mermaid-'+rev+'-'+i,code);if(rev!==revision)return;node.innerHTML=DOMPurify.sanitize(svg,{USE_PROFILES:{svg:true,svgFilters:true},ADD_TAGS:['style'],FORBID_TAGS:['foreignObject','image','a']})}catch(e){node.className='render-error';node.textContent='图表渲染失败：'+e.message+'\n'+code}}
  if(rev!==revision)return;window.scrollTo(0,scroll);window.webkit.messageHandlers.tiny.postMessage({kind:'ready',revision:rev,blocks:root.querySelectorAll('[data-source-start]').length});
 }catch(e){root.textContent='预览失败：'+e.message+'\n\n'+source;root.dataset.sourceStart='0';root.dataset.sourceEnd=String(source.length);window.webkit.messageHandlers.tiny.postMessage({kind:'error',message:e.message})}
};
window.setLocalImage=(id,url,rev)=>{if(rev!==revision)return;const node=document.getElementById(id);if(node){if(url){node.src=url;node.title=''}else{node.alt=(node.alt?node.alt+' — ':'')+'图片未加载：远程图片默认关闭，或路径超出文档目录';node.title=node.alt}}};
