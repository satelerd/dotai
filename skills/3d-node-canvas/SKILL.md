---
name: 3d-node-canvas
description: Build interactive 3D node-based visualizations (org charts, network graphs, dependency trees) as single-file HTML using Three.js CSS3DRenderer. Use when the user wants nodes with connections in 3D space that you can orbit, drag, and edit.
argument-hint: "[type: org-chart|network|dependency] [description]"
user-invocable: true
---

# 3D Node Canvas

Build interactive 3D visualizations where HTML cards float in 3D space connected by lines. Single-file HTML, no build step.

## When to use

- Org charts, reporting structures
- Network/service topology
- Dependency graphs
- Any node + edge visualization that benefits from 3D depth

## Architecture

```
┌─────────────────────────────────────────┐
│  Browser                                │
│  ┌───────────────────────────────────┐  │
│  │  CSS3DRenderer                    │  │
│  │  (positions HTML divs in 3D via   │  │
│  │   matrix3d CSS transforms)        │  │
│  │                                   │  │
│  │  ┌─────┐  ┌─────┐  ┌─────┐      │  │
│  │  │Node │  │Node │  │Node │ ...   │  │
│  │  │(div)│  │(div)│  │(div)│       │  │
│  │  └─────┘  └─────┘  └─────┘      │  │
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │  SVG overlay (pointer-events:none)│  │
│  │  Connections drawn by projecting  │  │
│  │  3D positions → 2D screen coords │  │
│  │  Updated every animation frame    │  │
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │  OrbitControls                    │  │
│  │  Camera rotation, zoom, pan       │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

Key insight: We use **CSS3DRenderer** (not WebGLRenderer) because nodes are real HTML elements — they support text, CSS styling, hover states, click events, and are always crisp. The 3D is for spatial arrangement, not for rendering geometry.

## Dependencies (CDN, no install needed)

```html
<script type="importmap">
{ "imports": {
    "three": "https://unpkg.com/three@0.160.0/build/three.module.js",
    "three/addons/": "https://unpkg.com/three@0.160.0/examples/jsm/"
}}
</script>
<script type="module">
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { CSS3DRenderer, CSS3DObject } from 'three/addons/renderers/CSS3DRenderer.js';
</script>
```

## Data model

Nodes need `x, y, z` coordinates in 3D space. Connections reference node IDs.

```js
const DATA = {
  groups: [
    { id: "eng", name: "Engineering", color: "#34d399" }
  ],
  nodes: [
    {
      id: "node1",
      name: "Alice",
      label: "Team Lead",       // subtitle
      groupId: "eng",
      connectsTo: ["node2"],    // array of IDs (first = primary, rest = secondary)
      x: 0, y: 200, z: 0,      // 3D position
      // ... any custom fields for display
    }
  ]
};
```

## Core implementation patterns

### 1. Scene setup

```js
const container = document.getElementById('scene-container');
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(50, w/h, 1, 10000);
camera.position.set(0, 400, 1000);

const renderer = new CSS3DRenderer();
renderer.setSize(w, h);
container.appendChild(renderer.domElement);

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.08;
controls.target.set(0, 0, 0); // orbit center
```

### 2. Creating nodes (HTML in 3D)

```js
function createNode(data, groupColor) {
  const div = document.createElement('div');
  div.className = 'node-card';
  div.innerHTML = `<h3>${data.name}</h3><p>${data.label}</p>`;

  // Tint card background with group color
  div.style.setProperty('--tint', `${groupColor}18`);
  div.style.setProperty('--border-tint', `${groupColor}30`);

  const obj = new CSS3DObject(div);
  obj.position.set(data.x, data.y, data.z);
  scene.add(obj);
  return { obj, div, data };
}
```

### 3. Billboard mode (nodes always face camera)

```js
function animate() {
  requestAnimationFrame(animate);
  controls.update();

  // Every node faces the camera
  nodeObjects.forEach(n => {
    n.obj.quaternion.copy(camera.quaternion);
  });

  renderer.render(scene, camera);
  updateConnections(); // redraw SVG
}
```

### 4. SVG connections (3D → 2D projection)

```js
const svgEl = document.getElementById('connections-svg');

function projectToScreen(pos3D) {
  const v = pos3D.clone().project(camera);
  return {
    x: (v.x * 0.5 + 0.5) * container.clientWidth,
    y: (-v.y * 0.5 + 0.5) * container.clientHeight
  };
}

function updateConnections() {
  let paths = '';
  nodes.forEach(node => {
    node.data.connectsTo.forEach((targetId, idx) => {
      const target = nodeMap.get(targetId);
      if (!target) return;

      const p1 = projectToScreen(node.obj.position);
      const p2 = projectToScreen(target.obj.position);

      // Bezier curve
      const midY = p1.y + (p2.y - p1.y) * 0.4;
      const d = `M ${p1.x} ${p1.y} C ${p1.x} ${midY}, ${p2.x} ${midY}, ${p2.x} ${p2.y}`;

      const isPrimary = idx === 0;
      const stroke = isPrimary ? 'rgba(150,120,230,0.4)' : 'rgba(250,190,40,0.25)';
      const dash = isPrimary ? '' : 'stroke-dasharray="5 3"';

      paths += `<path d="${d}" stroke="${stroke}" stroke-width="${isPrimary ? 2 : 1.2}" ${dash} />`;
    });
  });
  svgEl.innerHTML = paths;
}
```

### 5. Drag nodes in 3D (with double-click protection)

The trick: create an invisible plane perpendicular to the camera, passing through the node. Raycast mouse onto that plane to get new 3D position.

```js
let pendingDrag = null, dragState = null;
const DRAG_THRESHOLD = 5;

// On mousedown: prepare but don't start drag yet
function onNodeMouseDown(e, nodeData, obj) {
  pendingDrag = { data: nodeData, obj, startX: e.clientX, startY: e.clientY };
}

// On mousemove: only start drag if mouse moved past threshold
window.addEventListener('mousemove', e => {
  if (pendingDrag && !dragState) {
    const dx = e.clientX - pendingDrag.startX;
    const dy = e.clientY - pendingDrag.startY;
    if (Math.sqrt(dx*dx + dy*dy) > DRAG_THRESHOLD) {
      // NOW start the real drag
      controls.enabled = false;
      const planeNormal = new THREE.Vector3(0, 0, 1).applyQuaternion(camera.quaternion);
      const dragPlane = new THREE.Plane().setFromNormalAndCoplanarPoint(planeNormal, pendingDrag.obj.position.clone());

      const raycaster = new THREE.Raycaster();
      const ndc = screenToNDC(pendingDrag.startX, pendingDrag.startY);
      raycaster.setFromCamera(ndc, camera);
      const hit = new THREE.Vector3();
      raycaster.ray.intersectPlane(dragPlane, hit);
      const offset = hit.sub(pendingDrag.obj.position.clone());

      dragState = { ...pendingDrag, plane: dragPlane, offset };
      pendingDrag = null;
    }
    return;
  }

  if (!dragState) return;
  const ndc = screenToNDC(e.clientX, e.clientY);
  const raycaster = new THREE.Raycaster();
  raycaster.setFromCamera(ndc, camera);
  const hit = new THREE.Vector3();
  raycaster.ray.intersectPlane(dragState.plane, hit);
  if (hit) {
    hit.sub(dragState.offset);
    dragState.obj.position.copy(hit);
    dragState.data.x = hit.x;
    dragState.data.y = hit.y;
    dragState.data.z = hit.z;
  }
});

// On mouseup: detect click vs drag
window.addEventListener('mouseup', e => {
  const wasPending = pendingDrag;
  pendingDrag = null;
  if (dragState) { dragState = null; }
  controls.enabled = true;

  // If pending never became drag → it was a click
  if (wasPending) handleNodeClick(wasPending.data);
});

function screenToNDC(clientX, clientY) {
  const rect = container.getBoundingClientRect();
  return new THREE.Vector2(
    ((clientX - rect.left) / rect.width) * 2 - 1,
    -((clientY - rect.top) / rect.height) * 2 + 1
  );
}
```

### 6. Node styling (CSS)

```css
.node-card {
  width: 200px;
  padding: 14px 16px;
  background: var(--tint, rgba(30,20,60,0.95));
  border: 1px solid var(--border-tint, rgba(60,40,100,0.5));
  border-radius: 12px;
  font-family: 'DM Sans', sans-serif;
  color: #F5F0E8;
  cursor: grab;
  user-select: none;
  pointer-events: auto; /* CRITICAL for CSS3DRenderer */
  backdrop-filter: blur(8px);
}
```

> `pointer-events: auto` is essential. CSS3DRenderer's container has pointer-events disabled by default.

### 7. HTML structure

```html
<div id="scene-container">
  <!-- CSS3DRenderer injects its DOM here -->
  <svg id="connections-svg"
       style="position:absolute; inset:0; pointer-events:none; z-index:1;">
  </svg>
</div>
```

## Layout tips

- Spread nodes across all 3 axes. Flat layouts (same Z) look boring in 3D.
- Group related nodes by region: e.g., team A in the -X/-Z quadrant, team B in +X/-Z.
- Vary Y slightly within groups so they don't overlap when viewed from the side.
- Use 150-250 unit spacing between adjacent nodes for readability.
- Camera start position ~1000-1200 units away for 10-20 nodes.

## Gotchas

1. **dblclick doesn't work with CSS3DRenderer** — the renderer's DOM structure breaks native dblclick events. Implement double-click manually via timestamp comparison on mouseup.
2. **SVG connections must update every frame** — they're 2D projections that depend on camera position.
3. **OrbitControls must be disabled during drag** — otherwise dragging a node rotates the camera.
4. **Drag threshold is essential** — without it, mousedown immediately starts drag, preventing clicks.
5. **Billboard quaternion copy** — `obj.quaternion.copy(camera.quaternion)` must run every frame, not just on camera change.
6. **Import maps work in modern browsers** — Chrome 89+, Safari 16.4+, Firefox 108+. For older browsers, use a bundler or script tags.

## Customization checklist

When adapting for a new project:
- [ ] Define your data model (what fields per node?)
- [ ] Choose group/cluster colors
- [ ] Design node card HTML/CSS
- [ ] Decide connection semantics (what does primary vs secondary mean?)
- [ ] Set initial 3D positions (or implement auto-layout)
- [ ] Add any edit panel / interaction UI
- [ ] Choose dark or light theme
