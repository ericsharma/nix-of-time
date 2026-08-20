// Copies the repo's plain markdown into the Starlight content collection.
//
// The files under ../docs are ordinary GitHub-readable markdown: no
// frontmatter, an `# H1` as the first line, and relative `.md` links. Starlight
// needs frontmatter with a title and it serves pages at extensionless URLs, so
// this script adapts them at build time instead of rewriting the sources.
// Editing ../docs/*.md stays exactly as it was; the site follows.
//
// src/content/docs is fully generated and gitignored. Hand-authored pages that
// belong to the site rather than the repo live in src/site-pages and are laid
// down first, so a synced file can never silently replace one.

import { readdir, readFile, writeFile, mkdir, rm, cp, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join, relative, resolve, posix } from "node:path";
import { fileURLToPath } from "node:url";

const siteRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(siteRoot, "..");
const outRoot = join(siteRoot, "src/content/docs");
const sitePages = join(siteRoot, "src/site-pages");

// Repo path -> site path (relative to src/content/docs, no extension).
// Anything under docs/ that is not listed keeps its own path.
const EXPLICIT = {
  "README.md": "reference/repo-readme",
  "CLAUDE.md": "reference/repo-conventions",
};

// Pages that need a fixed sidebar position. Everything else sorts by title.
const ORDER = {
  "architecture": 1,
  "secrets": 2,
  "adding-a-service": 3,
  "adding-a-machine": 4,
};

async function walk(dir) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await walk(full)));
    else if (entry.name.endsWith(".md")) out.push(full);
  }
  return out;
}

/** Repo-relative source path -> site path without extension. */
function sitePathFor(repoPath) {
  if (EXPLICIT[repoPath]) return EXPLICIT[repoPath];
  if (!repoPath.startsWith("docs/")) return null;
  // A README.md inside docs/ is the landing page for its directory, so it
  // becomes <dir>/index and is served at /<dir>/.
  return repoPath
    .slice("docs/".length)
    .replace(/(^|\/)README\.md$/, "$1index")
    .replace(/\.md$/, "");
}

/** Site path without extension -> the URL Starlight will serve it at. */
function urlFor(sitePath) {
  const clean = sitePath.replace(/\/index$/, "").replace(/^index$/, "");
  return clean ? `/${clean}/` : "/";
}

function titleCase(slug) {
  return slug
    .replace(/[-_]/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

/** Pull `# Title` off the top of the body; Starlight renders it from frontmatter. */
function extractTitle(body, fallbackSlug) {
  const lines = body.split("\n");
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim() === "") continue;
    const m = /^#\s+(.+?)\s*$/.exec(lines[i]);
    if (m) return { title: m[1], body: lines.slice(i + 1).join("\n").replace(/^\n+/, "") };
    break; // first non-empty line is not an H1 — leave the body alone
  }
  return { title: titleCase(fallbackSlug), body };
}

/** First real paragraph, flattened, for the page description and search blurb. */
function extractDescription(body) {
  for (const block of body.split(/\n\s*\n/)) {
    const t = block.trim();
    if (!t || t.startsWith("#") || t.startsWith("|") || t.startsWith("```")) continue;
    if (t.startsWith(">") || t.startsWith("- ") || t.startsWith("![")) continue;
    const flat = t.replace(/\s+/g, " ").replace(/[*_`\[\]]/g, "").replace(/\(([^)]*)\)/g, "");
    return flat.length > 160 ? `${flat.slice(0, 157).trimEnd()}...` : flat;
  }
  return undefined;
}

function yamlString(s) {
  return `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

/**
 * Rewrite relative markdown links so they resolve on the site.
 * `[x](../../README.md)` -> `[x](/reference/repo-readme/)`.
 * Links to non-markdown repo files (a .nix module) are left untouched: they
 * read as paths in prose, and the source is not published next to the site.
 */
function rewriteLinks(body, repoPath, knownSitePaths) {
  return body.replace(/\]\(([^)\s]+?\.md)(#[^)\s]*)?\)/g, (whole, target, anchor = "") => {
    if (/^(https?:|\/\/)/.test(target)) return whole;
    const abs = posix.normalize(posix.join(posix.dirname(repoPath), target));
    const mapped = sitePathFor(abs);
    if (!mapped || !knownSitePaths.has(mapped)) return whole;
    return `](${urlFor(mapped)}${anchor})`;
  });
}

const sources = [];
for (const p of [...(await walk(join(repoRoot, "docs"))), join(repoRoot, "README.md"), join(repoRoot, "CLAUDE.md")]) {
  const repoPath = relative(repoRoot, p).split("\\").join("/");
  const sitePath = sitePathFor(repoPath);
  if (sitePath) sources.push({ repoPath, sitePath, file: p });
}

// website-outline.md is a design brief for this very site, not documentation.
const skip = new Set(["website-outline"]);
const kept = sources.filter((s) => !skip.has(s.sitePath));
const knownSitePaths = new Set(kept.map((s) => s.sitePath));

await rm(outRoot, { recursive: true, force: true });
await mkdir(outRoot, { recursive: true });
if (existsSync(sitePages)) await cp(sitePages, outRoot, { recursive: true });

let written = 0;
for (const { repoPath, sitePath, file } of kept) {
  const raw = await readFile(file, "utf8");
  if (raw.startsWith("---\n")) {
    // Already has frontmatter — the author is driving. Copy it through.
    const dest = join(outRoot, `${sitePath}.md`);
    await mkdir(dirname(dest), { recursive: true });
    await writeFile(dest, raw);
    written++;
    continue;
  }

  const slug = sitePath.split("/").pop();
  const { title, body } = extractTitle(raw, slug === "index" ? sitePath.split("/")[0] : slug);
  const description = extractDescription(body);
  const linked = rewriteLinks(body, repoPath, knownSitePaths);

  const fm = ["---", `title: ${yamlString(title)}`];
  if (description) fm.push(`description: ${yamlString(description)}`);
  if (ORDER[sitePath] !== undefined) fm.push("sidebar:", `  order: ${ORDER[sitePath]}`);
  fm.push(`editUrl: false`, "---", "");

  const dest = join(outRoot, `${sitePath}.md`);
  await mkdir(dirname(dest), { recursive: true });
  await writeFile(dest, `${fm.join("\n")}\n${linked.trimEnd()}\n`);
  written++;
}

console.log(`sync-docs: ${written} page(s) from ../docs into src/content/docs`);
