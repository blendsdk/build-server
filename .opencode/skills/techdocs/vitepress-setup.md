# techdocs — VitePress Setup (Phase 3)

> **CodeOps Artifact Schema**: 1

Scaffold VitePress for the `docs/` set: install it, generate the config, add npm scripts, and
ignore build output. Read this when first scaffolding the docs site, and whenever new pages are
added (the sidebar must stay in sync).

## 1. Install VitePress

Install VitePress as a dev dependency using the project's package manager:

```bash
# npm
npm install -D vitepress vitepress-plugin-mermaid mermaid

# yarn
yarn add -D vitepress vitepress-plugin-mermaid mermaid

# pnpm
pnpm add -D vitepress vitepress-plugin-mermaid mermaid
```

> `vitepress-plugin-mermaid` is required for the architecture diagrams — vanilla VitePress does
> NOT render ```` ```mermaid ```` blocks. The config below must wrap `defineConfig` with
> `withMermaid` accordingly:
>
> ```typescript
> import { withMermaid } from 'vitepress-plugin-mermaid'
> export default withMermaid(defineConfig({ /* … */ }))
> ```

## 2. Generate `.vitepress/config.ts`

Generate `docs/.vitepress/config.ts` based on the **actual** documentation structure.

```typescript
import { defineConfig } from 'vitepress'

export default defineConfig({
  title: '[Project Name] — Technical Documentation',
  description: 'Architecture documentation for [Project Name]',

  themeConfig: {
    nav: [
      { text: 'Architecture', link: '/architecture/system-overview' },
      { text: 'Decisions', link: '/decisions/' },
      { text: 'Guides', link: '/guides/getting-started' },
      { text: 'Reference', link: '/reference/configuration' },
    ],

    sidebar: [
      {
        text: 'Overview',
        items: [
          { text: 'Introduction', link: '/' },
        ],
      },
      {
        text: 'Architecture',
        items: [
          { text: 'System Overview', link: '/architecture/system-overview' },
          { text: 'Data Model', link: '/architecture/data-model' },
          { text: 'API Design', link: '/architecture/api-design' },
          { text: 'Infrastructure', link: '/architecture/infrastructure' },
          { text: 'Security', link: '/architecture/security' },
        ],
      },
      {
        text: 'Decisions',
        items: [
          { text: 'Decision Log', link: '/decisions/' },
          // Individual ADRs are listed here as they are created
        ],
      },
      {
        text: 'Developer Guides',
        items: [
          { text: 'Getting Started', link: '/guides/getting-started' },
          { text: 'Development Workflow', link: '/guides/development' },
          { text: 'Deployment', link: '/guides/deployment' },
        ],
      },
      {
        text: 'Reference',
        items: [
          { text: 'Configuration', link: '/reference/configuration' },
          { text: 'Integrations', link: '/reference/integrations' },
        ],
      },
    ],

    socialLinks: [
      // { icon: 'github', link: 'https://github.com/...' },
    ],
  },
})
```

> **Rule:** The sidebar MUST only include sections that actually exist. Remove entries for any
> section skipped per the project-type adaptation table in SKILL.md.

## 3. Add npm scripts

Add documentation scripts to the project's `package.json`:

```json
{
  "scripts": {
    "docs:dev": "vitepress dev docs",
    "docs:build": "vitepress build docs",
    "docs:preview": "vitepress preview docs"
  }
}
```

## 4. Update `.gitignore`

Add the VitePress build output to `.gitignore`:

```
docs/.vitepress/dist
docs/.vitepress/cache
```

## Sidebar auto-update when pages are added

When new documentation pages are added (new ADRs, new architecture sections), update
`.vitepress/config.ts` so the new pages appear in the sidebar.

When a new ADR is created, add it under the Decisions section:

```typescript
{
  text: 'Decisions',
  items: [
    { text: 'Decision Log', link: '/decisions/' },
    { text: 'ADR-001: [Title]', link: '/decisions/ADR-001-short-name' },
    { text: 'ADR-002: [Title]', link: '/decisions/ADR-002-short-name' },
    // New ADR added here
  ],
}
```
