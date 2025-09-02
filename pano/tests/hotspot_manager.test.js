import HotspotManager from '../core/hotspot_manager.js';

// Простые стабы для зависимостей
function createViewerStub() {
  return {
    created: [],
    updated: [],
    removed: [],
    createVisualMarker(h) { this.created.push(h); },
    updateVisualMarker(h) { this.updated.push(h); },
    removeVisualMarker(id) { this.removed.push(id); }
  };
}

function createSceneManagerStub() {
  const scenes = new Map();
  return {
    addScene(scene) { scenes.set(scene.id, scene); },
    getSceneById(id) { return scenes.get(id); }
  };
}

describe('HotspotManager', () => {
  test('add/update/remove hotspot', () => {
    const hm = new HotspotManager();
    const viewer = createViewerStub();
    const sm = createSceneManagerStub();
    const scene = { id: 'scene_1', hotspots: [] };

    hm.setViewerManager(viewer);
    hm.setSceneManager(sm);
    sm.addScene(scene);

    const data = { title: 'Test', type: 'hotspot', position: { x: 0, y: 0, z: -5 } };
    hm.addHotspot(scene, data);

    expect(hm.hotspots.length).toBe(1);
    expect(scene.hotspots.length).toBe(1);
    expect(viewer.created.length).toBe(1);

    const id = hm.hotspots[0].id;
    hm.updateHotspot(id, { title: 'Updated' });
    expect(hm.hotspots[0].title).toBe('Updated');
    expect(viewer.updated.length).toBe(1);

    hm.removeHotspotById(id);
    expect(hm.hotspots.length).toBe(0);
    expect(scene.hotspots.length).toBe(0);
    expect(viewer.removed).toContain(id);
  });

  test('updateHotspotPosition normalizes input', () => {
    const hm = new HotspotManager();
    const viewer = createViewerStub();
    const sm = createSceneManagerStub();
    const scene = { id: 'scene_1', hotspots: [] };

    hm.setViewerManager(viewer);
    hm.setSceneManager(sm);
    sm.addScene(scene);

    const data = { title: 'Test', type: 'hotspot', position: { x: 0, y: 0, z: -5 } };
    hm.addHotspot(scene, data);
    const id = hm.hotspots[0].id;

    hm.updateHotspotPosition(id, '1 2 3');
    expect(hm.hotspots[0].position).toEqual({ x: 1, y: 2, z: 3 });

    hm.updateHotspotPosition(id, { x: 4, y: 5, z: 6 });
    expect(hm.hotspots[0].position).toEqual({ x: 4, y: 5, z: 6 });
  });
});
