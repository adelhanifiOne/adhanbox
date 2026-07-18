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
      'vert':   { label: 'Vert',    hex: '#4A7A52', color: 0x4A7A52, roughness: 0.85, metalness: 0.0 },
      'bleu':   { label: 'Bleu',    hex: '#3D5A8C', color: 0x3D5A8C, roughness: 0.85, metalness: 0.0 },
      'violet': { label: 'Violet',  hex: '#6B4E8C', color: 0x6B4E8C, roughness: 0.85, metalness: 0.0 }
      // Palette alignée sur les 10 options du paiement Stripe (max 10 par menu déroulant).
    };
    const FINISHES = PALETTE;
    const MANDALA_COLORS = PALETTE;

    const state = { finish: 'noir', mandala: 0, mandalaColor: 'dore' };
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
        addGlowAndPort();
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

    // Coque lumineuse uniforme + port USB-C rond — identiques au hero d'accueil.
    // Ces objets ne sont pas affectés par applyFinish (qui ne touche que boxMesh/lidMesh),
    // donc la lueur reste chaude et le port reste noir quelle que soit la couleur choisie.
    function addGlowAndPort() {
      if (!boxSize) return;
      // ── coque lumineuse UNIFORME : même lueur derrière toutes les fenêtres ──
      const glow = new THREE.Mesh(
        new THREE.BoxGeometry(boxSize.x * 0.95, boxSize.y * 0.95, boxSize.z * 1.0),
        new THREE.MeshBasicMaterial({ color: 0xFFEAD0 })
      );
      boxGroup.add(glow);

      // ── port USB-C panneau ROND (press-fit) sur la face opposée au motif (+X) ──
      const usb = new THREE.Group();
      const usbBack = new THREE.Mesh(
        new THREE.CylinderGeometry(0.0100, 0.0100, 0.0020, 36),
        new THREE.MeshStandardMaterial({ color: 0x0c0c0c, roughness: 0.7, metalness: 0.1 })
      );
      usbBack.rotation.z = Math.PI / 2;
      usbBack.position.x = -0.0016;
      usb.add(usbBack);
      const usbBezel = new THREE.Mesh(
        new THREE.CylinderGeometry(0.0083, 0.0083, 0.0040, 36),
        new THREE.MeshStandardMaterial({ color: 0x141414, roughness: 0.5, metalness: 0.2 })
      );
      usbBezel.rotation.z = Math.PI / 2;
      usb.add(usbBezel);
      const usbSlot = new THREE.Mesh(
        new THREE.BoxGeometry(0.0026, 0.0082, 0.0038),
        new THREE.MeshStandardMaterial({ color: 0x050505, roughness: 0.6, metalness: 0.2 })
      );
      usbSlot.position.x = 0.0014;
      usb.add(usbSlot);
      const usbTongue = new THREE.Mesh(
        new THREE.BoxGeometry(0.0018, 0.0060, 0.0014),
        new THREE.MeshStandardMaterial({ color: 0x8c8c8c, roughness: 0.4, metalness: 0.6 })
      );
      usbTongue.position.x = 0.0018;
      usb.add(usbTongue);
      usb.position.set(boxSize.x / 2 - 0.0002, 0, -0.016);
      boxGroup.add(usb);
    }

    function loadLid() {
      makeLoader().load('lid.glb', (gltf) => {
        lidMesh = gltf.scene;
        // lid.glb (STL Fusion) est en mm, Z-up jupe vers le bas ; adhanbox.glb est en m → scale 1000×
        lidMesh.scale.setScalar(0.001);
        lidMesh.updateMatrixWorld(true);
        const lidBounds = new THREE.Box3().setFromObject(lidMesh);
        const lidCenter = new THREE.Vector3();
        const lidSize = new THREE.Vector3();
        lidBounds.getCenter(lidCenter);
        lidBounds.getSize(lidSize);
        lidMesh.position.sub(lidCenter);
        if (boxSize) {
          // la jupe de 5 mm s'insère dans l'ouverture de la box
          lidMesh.position.z += boxSize.z / 2 + lidSize.z / 2 - 0.001;
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
        // 55 % de la largeur et décalé vers le bas : les fenêtres en arches
        // occupent le haut de la façade (z ≥ 69 mm), le motif doit rester dessous
        const scale = (boxSize.x * 0.55) / Math.max(size.x, size.y, size.z);
        wrapper.scale.setScalar(scale);
        // Façade : face -X locale du boîtier
        wrapper.position.set(-boxSize.x / 2 - 0.0015, 0, -0.008);
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

    // ─── Précommande : le bouton crée la commande via le backend
    //     (config transmise UNE fois, visible dans Stripe + email de
    //     confirmation personnalisé). Si le backend est indisponible,
    //     secours automatique : Payment Link direct (client_reference_id).
    const CHECKOUT_BACKEND = 'https://adhanbox-commande.vercel.app';
    const STRIPE_PAYMENT_LINK = 'https://buy.stripe.com/00w00kg6P7sb5Woe7LfjG01';
    function slug(s) {
      return (s || '').toLowerCase()
        .normalize('NFD').replace(/[̀-ͯ]/g, '')
        .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40);
    }
    function updateQuoteLink() {
      const finish = FINISHES[state.finish].label;
      const motif = state.mandala === 0
        ? 'Sans motif'
        : 'Motif ' + state.mandala + ' (' + MANDALA_COLORS[state.mandalaColor].label + ')';
      // référence lisible pour Stripe : chassis + motif (+ teinte)
      let ref = 'chassis-' + slug(finish);
      if (state.mandala === 0) {
        ref += '_sans-motif';
      } else {
        ref += '_motif-' + state.mandala + '-' + slug(MANDALA_COLORS[state.mandalaColor].label);
      }
      const cta = document.getElementById('config-cta');
      cta.href = STRIPE_PAYMENT_LINK + '?client_reference_id=' + encodeURIComponent(ref);
      cta.textContent = 'Précommander cette configuration — 95 €';
    }
    updateQuoteLink();

    // Paiement via le backend : on intercepte le clic, on crée la session
    // Checkout (config incluse) puis on redirige. En cas d'échec (backend
    // down, réseau), on laisse suivre le lien Stripe de secours (cta.href).
    document.getElementById('config-cta').addEventListener('click', function (e) {
      const cta = e.currentTarget;
      if (!CHECKOUT_BACKEND || cta.dataset.busy) return; // secours : lien direct
      e.preventDefault();
      cta.dataset.busy = '1';
      const prevText = cta.textContent;
      cta.textContent = 'Ouverture du paiement sécurisé…';
      fetch(CHECKOUT_BACKEND + '/api/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          finish: state.finish,
          mandala: state.mandala,
          mandalaColor: state.mandalaColor
        })
      })
        .then(function (r) { return r.json(); })
        .then(function (d) {
          if (d && d.url) { window.location.href = d.url; }
          else { throw new Error((d && d.error) || 'réponse invalide'); }
        })
        .catch(function () {
          // Secours : Payment Link direct (la config passe en client_reference_id)
          delete cta.dataset.busy;
          cta.textContent = prevText;
          window.location.href = cta.href;
        });
    });
