# Examples

## Org Chart (SmartUp-style)

Data with hierarchical reporting, team clusters, and metadata:

```js
const ORG = {
  groups: [
    { id: "leadership", name: "Leadership", color: "#a855f7" },
    { id: "engineering", name: "Engineering", color: "#34d399" },
    { id: "product", name: "Product", color: "#60a5fa" }
  ],
  nodes: [
    { id: "ceo", name: "Max", label: "CEO", groupId: "leadership",
      connectsTo: [], x: 0, y: 400, z: 0 },
    { id: "cto", name: "Sat", label: "CTO", groupId: "leadership",
      connectsTo: ["ceo"], x: -300, y: 200, z: 80 },
    { id: "lead", name: "Marcelo", label: "Eng Lead", groupId: "engineering",
      connectsTo: ["cto"], x: -400, y: -20, z: -200,
      meta: { repo: "platform" } },
    { id: "dev1", name: "Alex", label: "Developer", groupId: "engineering",
      connectsTo: ["lead", "coo"],  // primary + secondary report
      x: -500, y: -220, z: -380,
      meta: { repo: "tools", clients: ["Client A"] } }
  ]
};
```

Node card with metadata chips:
```html
<div class="node-card">
  <div class="group-label" style="color: ${color}">${group.name}</div>
  <div class="name">${node.name}</div>
  <div class="role">${node.label}</div>
  <div class="chips">
    ${node.meta?.repo ? `<span class="chip repo">${node.meta.repo}</span>` : ''}
    ${(node.meta?.clients || []).map(c => `<span class="chip client">${c}</span>`).join('')}
  </div>
</div>
```

## Service Topology

Microservices and their dependencies:

```js
const SERVICES = {
  groups: [
    { id: "frontend", name: "Frontend", color: "#f472b6" },
    { id: "backend", name: "Backend", color: "#38bdf8" },
    { id: "data", name: "Data", color: "#a78bfa" },
    { id: "infra", name: "Infrastructure", color: "#fb923c" }
  ],
  nodes: [
    { id: "web", name: "Web App", label: "Next.js", groupId: "frontend",
      connectsTo: ["api"], x: 0, y: 300, z: 200 },
    { id: "api", name: "API Gateway", label: "Flask", groupId: "backend",
      connectsTo: ["auth", "orders"], x: 0, y: 100, z: 0,
      meta: { health: "green", latency: "45ms" } },
    { id: "auth", name: "Auth Service", label: "JWT", groupId: "backend",
      connectsTo: ["db"], x: -250, y: -100, z: -150 },
    { id: "orders", name: "Orders", label: "Flask", groupId: "backend",
      connectsTo: ["db", "cache"], x: 250, y: -100, z: -150 },
    { id: "db", name: "PostgreSQL", label: "Primary", groupId: "data",
      connectsTo: [], x: 0, y: -300, z: -300 },
    { id: "cache", name: "Redis", label: "Cache", groupId: "infra",
      connectsTo: [], x: 350, y: -300, z: -200 }
  ]
};
```

## Dependency Graph (npm packages)

```js
const DEPS = {
  groups: [
    { id: "core", name: "Core", color: "#fbbf24" },
    { id: "ui", name: "UI", color: "#34d399" },
    { id: "util", name: "Utilities", color: "#94a3b8" }
  ],
  nodes: [
    { id: "app", name: "my-app", label: "v2.1.0", groupId: "core",
      connectsTo: ["react", "utils", "ui-lib"], x: 0, y: 300, z: 0 },
    { id: "react", name: "react", label: "18.2.0", groupId: "ui",
      connectsTo: ["react-dom"], x: -200, y: 100, z: 100 },
    { id: "react-dom", name: "react-dom", label: "18.2.0", groupId: "ui",
      connectsTo: [], x: -300, y: -100, z: 200 },
    { id: "ui-lib", name: "@company/ui", label: "3.0.0", groupId: "ui",
      connectsTo: ["react"], x: 200, y: 100, z: -100 },
    { id: "utils", name: "lodash", label: "4.17.21", groupId: "util",
      connectsTo: [], x: 0, y: -100, z: -200 }
  ]
};
```

## Dark theme palette (recommended)

```css
:root {
  --void: #0a0618;        /* deepest background */
  --surface: #1e1445;     /* card background base */
  --border: #362663;      /* default borders */
  --cream: #F5F0E8;       /* primary text */
  --cream-dim: #B8B0A0;   /* secondary text */
  --purple: #7C3AED;      /* accent / highlights */
}
```

## Light theme palette (alternative)

```css
:root {
  --void: #f8f7f4;
  --surface: #ffffff;
  --border: #e5e2db;
  --cream: #1a1a2e;
  --cream-dim: #6b7194;
  --purple: #7C3AED;
}
```
