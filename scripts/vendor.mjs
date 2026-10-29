import * as esbuild from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
const dest='Resources/Preview';
await esbuild.build({entryPoints:['scripts/preview-entry.js'],bundle:true,minify:true,format:'iife',target:['safari16'],outfile:dest+'/vendor.js',legalComments:'eof'});
fs.copyFileSync('scripts/node_modules/@mermaid-js/tiny/dist/mermaid.tiny.js',dest+'/mermaid.js');
fs.copyFileSync('scripts/node_modules/katex/dist/katex.min.css',dest+'/katex.min.css');
fs.cpSync('scripts/node_modules/katex/dist/fonts',dest+'/fonts',{recursive:true});
let notices='# Bundled offline libraries\n\nDependencies pinned in scripts/package-lock.json. Runtime makes no CDN requests.\n\n';
for(const name of ['markdown-it','@mermaid-js/tiny','katex','dompurify','highlight.js','argparse','entities','linkify-it','mdurl','punycode.js','uc.micro']) {
 const base='scripts/node_modules/'+name, p=JSON.parse(fs.readFileSync(base+'/package.json','utf8'));
 notices+=`## ${name} ${p.version}\n\nOfficial package: https://www.npmjs.com/package/${name}\n\n`;
 for(const f of fs.readdirSync(base).filter(f=>/^(license|licence|copying)/i.test(f))) notices+=fs.readFileSync(path.join(base,f),'utf8')+'\n\n';
}
fs.writeFileSync('Resources/THIRD_PARTY_NOTICES.md',notices);
