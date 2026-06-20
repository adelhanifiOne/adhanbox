// ═══════════════════════════════════════════════════════
    // CONFIGURATEUR 3D (three.js) — finitions mates
    // ═══════════════════════════════════════════════════════
    // Palette unique partagée entre le châssis et le motif.
    // Matériaux volontairement mats (rugosité élevée, metalness quasi nul) :
    // les reflets brillants écrasaient le relief des motifs.
    const PALETTE = {
      'bois':   { label: 'Bois',    hex: '#8B5A2B', color: 0x8B5A2B, roughness: 0.85, metalness: 0.0 },
      'marbre': { label: 'Marbre',  hex: '#E4E2DC', color: 0xE4E2DC, roughness: 0.8,  metalness: 0.0 },
      'blanc':  { label: 'Blanc',   hex: '#F2F0EB', color: 0xF2F0EB, roughness: 0.85, metalness: 0.0 },
      'gris':   { label: 'Gris',    hex: '#8A8A8A', color: 0x8A8A8A, roughness: 0.85, metalness: 0.0 },
      'noir':   { label: 'Noir',    hex: '#2A2A2A', color: 0x2A2A2A, roughness: 0.85, metalness: 0.0 },
      'dore':   { label: 'Doré',    hex: '#C9A227', color: 0xC9A227, roughness: 0.7,  metalness: 0.15 },
      'rouge':  { label: 'Rouge',   hex: '#B23A3A', color: 0xB23A3A, roughness: 0.85, metalness: 0.0 },
      'orange': { label: 'Orange',  hex: '#C97A35', color: 0xC97A35, roughness: 0.85, metalness: 0.0 },
      'jaune':  { label: 'Jaune',   hex: '#D6B23A', color: 0xD6B23A, roughness: 0.85, metalness: 0.0 },
      'vert':   { label: 'Vert',    hex: '#4A7A52', color: 0x4A7A52, roughness: 0.85, metalness: 0.0 },
      'bleu':   { label: 'Bleu',    hex: '#3D5A8C', color: 0x3D5A8C, roughness: 0.85, metalness: 0.0 },
      'violet': { label: 'Violet',  hex: '#6B4E8C', color: 0x6B4E8C, roughness: 0.85, metalness: 0.0 },
      'rose':   { label: 'Rose',    hex: '#CE8BA3', color: 0xCE8BA3, roughness: 0.85, metalness: 0.0 }
    };
    const FINISHES = PALETTE;
    const MANDALA_COLORS = PALETTE;

    const state = { finish: 'bois', mandala: 0, mandalaColor: 'dore' };
    let scene, camera, renderer, controls, boxGroup, boxMesh = null, mandalaMesh = null, lidMesh = null;
    let boxSize = null, boxCenter = null;
    let threeStarted = false;

    function makeLoader() {
      const loader = new THREE.GLTFLoader();
      const draco = new THREE.DRACOLoader();
      draco.setDecoderPath('https://www.gstatic.com/draco/versioned/decoders/1.5.6/');
      loader.setDRACOLoader(draco);
      return loader;
    }

    function init3D() {
      if (threeStarted || typeof THREE === 'undefined') return;
      threeStarted = true;

      const container = document.getElementById('canvas3d');
      const width = container.clientWidth || 320;
      const height = container.clientHeight || 320;

      scene = new THREE.Scene();
      camera = new THREE.PerspectiveCamera(38, width / height, 0.01, 10);
      camera.position.set(0.14, 0.11, -0.20);

      renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
      renderer.setSize(width, height);
      renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
      renderer.toneMapping = THREE.ACESFilmicToneMapping;
      container.appendChild(renderer.domElement);

      controls = new THREE.OrbitControls(camera, renderer.domElement);
      controls.enableDamping = true;
      controls.dampingFactor = 0.05;
      controls.enablePan = false;
      controls.minDistance = 0.10;
      controls.maxDistance = 0.40;
      controls.autoRotate = true;
      controls.autoRotateSpeed = 1.5;
      controls.addEventListener('start', () => { controls.autoRotate = false; });

      // Éclairage doux et enveloppant : les matériaux mats ont besoin de
      // lumière diffuse pour révéler le relief, pas de reflets spéculaires.
      scene.add(new THREE.AmbientLight(0xffffff, 0.55));
      scene.add(new THREE.HemisphereLight(0xfff8ec, 0x8a7a5c, 0.55));
      const key = new THREE.DirectionalLight(0xffffff, 0.95);
      key.position.set(2, 4, 3);
      scene.add(key);
      const fill = new THREE.DirectionalLight(0xfff2dd, 0.45);
      fill.position.set(-2, 2, -3);
      scene.add(fill);

      boxGroup = new THREE.Group();
      scene.add(boxGroup);

      makeLoader().load('adhanbox.glb', (gltf) => {
        boxMesh = gltf.scene;
        boxMesh.traverse((child) => {
          if (child.isMesh) child.material = new THREE.MeshStandardMaterial();
        });
        const bounds = new THREE.Box3().setFromObject(boxMesh);
        boxSize = new THREE.Vector3();
        bounds.getSize(boxSize);
        boxCenter = new THREE.Vector3();
        bounds.getCenter(boxCenter);
        boxMesh.position.sub(boxCenter);
        boxGroup.add(boxMesh);
        boxGroup.rotation.x = -Math.PI / 2;
        applyFinish();
        animate3D();
        loadLid();
      }, undefined, (err) => console.error('Erreur de chargement du modèle 3D :', err));

      window.addEventListener('resize', () => {
        const w = container.clientWidth, h = container.clientHeight;
        camera.aspect = w / h;
        camera.updateProjectionMatrix();
        renderer.setSize(w, h);
      });
    }

    function animate3D() {
      requestAnimationFrame(animate3D);
      controls.update();
      renderer.render(scene, camera);
    }

    function loadLid() {
      makeLoader().load('lid.glb', (gltf) => {
        lidMesh = gltf.scene;
        // OBJ from Fusion 360 exports in mm; adhanbox.glb is in m → scale down 1000×
        lidMesh.scale.setScalar(0.001);
        // Apply rotation BEFORE computing bounds so centering accounts for it
        lidMesh.rotation.x = Math.PI;
        lidMesh.updateMatrixWorld(true);
        const lidBounds = new THREE.Box3().setFromObject(lidMesh);
        const lidCenter = new THREE.Vector3();
        const lidSize = new THREE.Vector3();
        lidBounds.getCenter(lidCenter);
        lidBounds.getSize(lidSize);
        lidMesh.position.sub(lidCenter);
        if (boxSize) {
          lidMesh.position.z += boxSize.z / 2 + lidSize.z / 2 - 0.036;
        }
        // Build material with current finish color directly — avoids two-step apply issue
        const f = FINISHES[state.finish];
        lidMesh.traverse((child) => {
          if (child.isMesh) {
            // The lid OBJ has no normals → compute them so lighting works
            if (child.geometry && !child.geometry.attributes.normal) {
              child.geometry.computeVertexNormals();
            }
            child.material = new THREE.MeshStandardMaterial({
              color: f.color,
              roughness: f.roughness,
              metalness: f.metalness,
              side: THREE.DoubleSide
            });
          }
        });
        boxGroup.add(lidMesh);
      }, undefined, (err) => console.error('Erreur de chargement du couvercle :', err));
    }

    function applyFinish() {
      const f = FINISHES[state.finish];
      [boxMesh, lidMesh].forEach((mesh) => {
        if (!mesh) return;
        mesh.traverse((child) => {
          if (child.isMesh) {
            child.material.color.setHex(f.color);
            child.material.roughness = f.roughness;
            child.material.metalness = f.metalness;
            child.material.needsUpdate = true;
          }
        });
      });
    }

    function applyMandalaColor() {
      if (!mandalaMesh) return;
      const c = MANDALA_COLORS[state.mandalaColor];
      mandalaMesh.traverse((child) => {
        if (child.isMesh) {
          child.material.color.setHex(c.color);
          child.material.roughness = c.roughness;
          child.material.metalness = c.metalness;
          child.material.needsUpdate = true;
        }
      });
    }

    function loadMandala(index) {
      if (mandalaMesh) {
        boxGroup.remove(mandalaMesh);
        mandalaMesh = null;
      }
      if (index === 0 || !boxSize) return;

      makeLoader().load('mandala' + index + '.glb', (gltf) => {
        // L'utilisateur a pu changer de motif pendant le chargement
        if (state.mandala !== index) return;

        const model = gltf.scene;
        model.traverse((child) => {
          if (child.isMesh) child.material = new THREE.MeshStandardMaterial({ side: THREE.DoubleSide });
        });
        const bounds = new THREE.Box3().setFromObject(model);
        const size = new THREE.Vector3();
        bounds.getSize(size);
        const center = new THREE.Vector3();
        bounds.getCenter(center);
        model.position.sub(center);

        const wrapper = new THREE.Group();
        wrapper.add(model);
        const scale = (boxSize.x * 0.7) / Math.max(size.x, size.y, size.z);
        wrapper.scale.setScalar(scale);
        // Façade : face -X locale du boîtier
        wrapper.position.set(-boxSize.x / 2 - 0.0015, 0, 0);
        wrapper.rotation.set(0, -Math.PI / 2, 0);

        if (mandalaMesh) boxGroup.remove(mandalaMesh);
        mandalaMesh = wrapper;
        boxGroup.add(mandalaMesh);
        applyMandalaColor();
      }, undefined, (err) => console.error('Erreur de chargement du mandala :', err));
    }

    // Initialisation différée : la 3D ne démarre que lorsque la section est visible
    const configSection = document.getElementById('configurateur');
    new IntersectionObserver((entries, obs) => {
      if (entries[0].isIntersecting) {
        const tryInit = () => (typeof THREE !== 'undefined' && THREE.OrbitControls) ? init3D() : setTimeout(tryInit, 150);
        tryInit();
        obs.disconnect();
      }
    }, { rootMargin: '200px' }).observe(configSection);

    // ─── Contrôles du configurateur ───
    function selectIn(group, target) {
      group.forEach((el) => el.classList.remove('active'));
      target.classList.add('active');
    }

    // Génère les pastilles de couleur à partir de la palette partagée
    function buildSwatches(containerId, activeKey, onPick) {
      const container = document.getElementById(containerId);
      const buttons = [];
      Object.entries(PALETTE).forEach(([key, c]) => {
        const btn = document.createElement('button');
        btn.className = 'swatch' + (key === activeKey ? ' active' : '');
        btn.style.background = c.hex;
        btn.title = c.label;
        btn.setAttribute('aria-label', c.label);
        btn.addEventListener('click', () => {
          selectIn(buttons, btn);
          onPick(key);
          updateQuoteLink();
        });
        container.appendChild(btn);
        buttons.push(btn);
      });
      return buttons;
    }

    buildSwatches('finish-swatches', state.finish, (key) => {
      state.finish = key;
      document.getElementById('finish-note').textContent = PALETTE[key].label + ' — finition mate.';
      applyFinish();
    });

    buildSwatches('mcolor-swatches', state.mandalaColor, (key) => {
      state.mandalaColor = key;
      applyMandalaColor();
    });

    const mandalaBtns = document.querySelectorAll('[data-mandala]');
    mandalaBtns.forEach((btn) => {
      btn.addEventListener('click', () => {
        state.mandala = parseInt(btn.dataset.mandala, 10);
        selectIn(mandalaBtns, btn);
        document.getElementById('mandala-color-group').style.display = state.mandala === 0 ? 'none' : 'block';
        loadMandala(state.mandala);
        updateQuoteLink();
      });
    });

    // ─── Devis : le mail reprend la configuration choisie ───
    function updateQuoteLink() {
      const finish = FINISHES[state.finish].label;
      const motif = state.mandala === 0
        ? 'Sans motif'
        : 'Motif ' + state.mandala + ' (' + MANDALA_COLORS[state.mandalaColor].label + ')';
      const subject = encodeURIComponent('Demande de devis AdhanBox — ' + finish + ' · ' + motif);
      const body = encodeURIComponent(
        'Assalamou alaykoum,\n\n' +
        'Je souhaite recevoir un devis pour une AdhanBox avec la configuration suivante :\n\n' +
        '• Finition du châssis : ' + finish + '\n' +
        '• Façade : ' + motif + '\n\n' +
        'Merci !'
      );
      document.getElementById('config-cta').href =
        'mailto:adel.hanifi@yahoo.fr?subject=' + subject + '&body=' + body;
    }
    updateQuoteLink();
