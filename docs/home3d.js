/* Aperçu 3D de l'AdhanBox sur la page d'accueil (auto-rotation, finition bois). */
(function () {
  var WOOD = { color: 0x8B5A2B, roughness: 0.85, metalness: 0.0 };

  function makeLoader() {
    var l = new THREE.GLTFLoader();
    var d = new THREE.DRACOLoader();
    d.setDecoderPath('https://www.gstatic.com/draco/versioned/decoders/1.5.6/');
    l.setDRACOLoader(d);
    return l;
  }

  function init() {
    var container = document.getElementById('home-3d');
    if (!container) return;
    if (typeof THREE === 'undefined' || !THREE.OrbitControls) {
      return setTimeout(init, 150);
    }

    var w = container.clientWidth || 360, h = container.clientHeight || 360;
    var scene = new THREE.Scene();
    var camera = new THREE.PerspectiveCamera(38, w / h, 0.01, 10);
    camera.position.set(0.14, 0.11, -0.20);

    var renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    container.appendChild(renderer.domElement);

    var controls = new THREE.OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.05;
    controls.enablePan = false;
    controls.enableZoom = false;
    controls.autoRotate = true;
    controls.autoRotateSpeed = 1.3;

    scene.add(new THREE.AmbientLight(0xffffff, 0.55));
    scene.add(new THREE.HemisphereLight(0xfff8ec, 0x8a7a5c, 0.55));
    var key = new THREE.DirectionalLight(0xffffff, 0.95); key.position.set(2, 4, 3); scene.add(key);
    var fill = new THREE.DirectionalLight(0xfff2dd, 0.45); fill.position.set(-2, 2, -3); scene.add(fill);

    var group = new THREE.Group();
    scene.add(group);
    var boxSize = null;

    makeLoader().load('adhanbox.glb', function (gltf) {
      var box = gltf.scene;
      box.traverse(function (c) { if (c.isMesh) c.material = new THREE.MeshStandardMaterial(WOOD); });
      var b = new THREE.Box3().setFromObject(box);
      boxSize = new THREE.Vector3(); b.getSize(boxSize);
      var center = new THREE.Vector3(); b.getCenter(center);
      box.position.sub(center);
      group.add(box);
      group.rotation.x = -Math.PI / 2;
      animate();

      makeLoader().load('lid.glb', function (g2) {
        var lid = g2.scene;
        lid.scale.setScalar(0.001);
        lid.rotation.x = Math.PI;
        lid.updateMatrixWorld(true);
        var lb = new THREE.Box3().setFromObject(lid);
        var lc = new THREE.Vector3(), ls = new THREE.Vector3();
        lb.getCenter(lc); lb.getSize(ls);
        lid.position.sub(lc);
        lid.position.z += boxSize.z / 2 + ls.z / 2 - 0.036;
        lid.traverse(function (c) {
          if (c.isMesh) {
            if (c.geometry && !c.geometry.attributes.normal) c.geometry.computeVertexNormals();
            c.material = new THREE.MeshStandardMaterial({
              color: WOOD.color, roughness: WOOD.roughness, metalness: WOOD.metalness, side: THREE.DoubleSide
            });
          }
        });
        group.add(lid);
      });
    }, undefined, function (err) { console.error('Erreur de chargement 3D :', err); });

    function animate() {
      requestAnimationFrame(animate);
      controls.update();
      renderer.render(scene, camera);
    }

    window.addEventListener('resize', function () {
      var W = container.clientWidth, H = container.clientHeight;
      camera.aspect = W / H; camera.updateProjectionMatrix(); renderer.setSize(W, H);
    });
  }

  init();
})();
