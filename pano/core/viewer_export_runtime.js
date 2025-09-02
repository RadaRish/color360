// Viewer runtime extracted from export_manager for cleaner exported package
// This file will be copied as viewer.js into the exported bundle.

(function(){
    // Регистрируем компоненты если ещё не определены
    if (typeof AFRAME !== 'undefined') {
        if (!AFRAME.components['billboard']) {
            AFRAME.registerComponent('billboard', {
                tick: function () {
                    const camera = document.querySelector('[camera]');
                    if (camera) this.el.object3D.lookAt(camera.object3D.position);
                }
            });
        }
    }
})();
