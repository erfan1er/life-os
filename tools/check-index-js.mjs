import { readFileSync } from 'node:fs';
import { Script } from 'node:vm';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const blocks = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)].map(match => match[1]);
if (blocks.length !== 1) throw new Error(`Expected one inline application script, found ${blocks.length}.`);
new Script(blocks[0], { filename: 'index.html:inline-script' });
console.log('index.html inline JavaScript syntax: OK');
