// ═══════════════════════════════════════════════════════
    // CONFIGURATEUR 3D (three.js) — finitions mates
    // ═══════════════════════════════════════════════════════
    // Palette unique partagée entre le châssis et le motif.
    // Matériaux volontairement mats (rugosité élevée, metalness quasi nul) :
    // les reflets brillants écrasaient le relief des motifs.
    // Le chassis et le motif n'ont PAS la meme palette : ce sont deux stocks de
    // filament differents. Une seule liste partagee (jusqu'au 19/09/2026)
    // proposait des teintes qu'Adel n'a pas en bobine pour l'une ou pour
    // l'autre. Toute modification ici doit etre reportee dans
    // commande_backend/api/checkout.js, qui refuse ce qu'il ne connait pas.
    const FINISHES = {
      'beige':        { label: 'Beige',            hex: '#D4B996', color: 0xD4B996, roughness: 0.85, metalness: 0.0 },
      'noir':         { label: 'Noir',             hex: '#2A2A2A', color: 0x2A2A2A, roughness: 0.85, metalness: 0.0 },
      'blanc':        { label: 'Blanc',            hex: '#F2F0EB', color: 0xF2F0EB, roughness: 0.85, metalness: 0.0 },
      'marbre':       { label: 'Marbre',           hex: '#E4E2DC', color: 0xE4E2DC, roughness: 0.80, metalness: 0.0 },
      'marron':       { label: 'Marron',           hex: '#927968', color: 0x927968, roughness: 0.85, metalness: 0.0 },
      'creme':        { label: 'Crème',            hex: '#F9DFB9', color: 0xF9DFB9, roughness: 0.85, metalness: 0.0 },
      'gris':         { label: 'Gris',             hex: '#97999B', color: 0x97999B, roughness: 0.85, metalness: 0.0 },
      'cacahuete':    { label: 'Marron cacahuète', hex: '#A9754F', color: 0xA9754F, roughness: 0.85, metalness: 0.0 },
      'vert-foret':   { label: 'Vert forêt',       hex: '#43523B', color: 0x43523B, roughness: 0.85, metalness: 0.0 },
      'gris-texture': { label: 'Gris texturé',     hex: '#75787B', color: 0x75787B, roughness: 0.95, metalness: 0.0 }
    };
    const MANDALA_COLORS = {
      'noir':       { label: 'Noir',       hex: '#2A2A2A', color: 0x2A2A2A, roughness: 0.85, metalness: 0.0 },
      'blanc':      { label: 'Blanc',      hex: '#F2F0EB', color: 0xF2F0EB, roughness: 0.85, metalness: 0.0 },
      'rouge':      { label: 'Rouge',      hex: '#B23A3A', color: 0xB23A3A, roughness: 0.85, metalness: 0.0 },
      'rose':       { label: 'Rose',       hex: '#E8308C', color: 0xE8308C, roughness: 0.85, metalness: 0.0 },
      'bleu':       { label: 'Bleu',       hex: '#4A7FC9', color: 0x4A7FC9, roughness: 0.85, metalness: 0.0 },
      'vert-foret': { label: 'Vert forêt', hex: '#43523B', color: 0x43523B, roughness: 0.85, metalness: 0.0 },
      'or':         { label: 'Or',         hex: '#C9A227', color: 0xC9A227, roughness: 0.70, metalness: 0.15 },
      'marron':     { label: 'Marron',     hex: '#927968', color: 0x927968, roughness: 0.85, metalness: 0.0 }
    };

    // Motif photographie sur toutes les photos de coloris : c'est le choix par
    // defaut, pour que la photo affichee soit exactement ce qui est commande.
    const MOTIF_PHOTO = 2;
    const state = { finish: 'noir', mandala: MOTIF_PHOTO, mandalaColor: 'or' };
    let scene, camera, renderer, controls, boxGroup, boxMesh = null, mandalaMesh = null, lidMesh = null;
    let boxSize = null, boxCenter = null;
    let threeStarted = false;
    let rendu3DActif = false;     // la boucle de rendu ne tourne qu'en mode 3D
    let boucleActive = false;
    let mandalaCharge = 0;        // motif deja dans la scene, pour ne pas le recharger

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
        if (!boucleActive) animate3D();
        loadLid();
        if (state.mandala) loadMandala(state.mandala);
        legende3D();
      }, undefined, (err) => console.error('Erreur de chargement du modèle 3D :', err));

      window.addEventListener('resize', () => {
        const w = container.clientWidth, h = container.clientHeight;
        if (!w || !h) return;    // conteneur masque (mode photo)
        camera.aspect = w / h;
        camera.updateProjectionMatrix();
        renderer.setSize(w, h);
      });
    }

    function animate3D() {
      if (!rendu3DActif) { boucleActive = false; return; }
      boucleActive = true;
      requestAnimationFrame(animate3D);
      controls.update();
      renderer.render(scene, camera);
    }

    // ── Mise en avant du motif ──
    // Au choix d'un motif ou de sa couleur : la caméra glisse face à la
    // façade (face -X monde) et la rotation est verrouillée 3 s, le temps
    // d'apprécier le rendu. Un nouveau choix pendant le verrou relance le
    // compte à rebours.
    let focusTimer = null;
    let focusAnim = null;
    function focusMotifFace() {
      if (!controls || !camera) return;

      controls.autoRotate = false;
      controls.enableRotate = false;
      controls.enableZoom = false;
      // Purge l'inertie d'un drag en cours : sans damping, update() applique
      // le reliquat d'un coup puis le remet à zéro — la caméra ne dérive plus.
      controls.enableDamping = false;
      controls.update();
      if (focusTimer) clearTimeout(focusTimer);
      focusTimer = setTimeout(() => {
        controls.enableRotate = true;
        controls.enableZoom = true;
        controls.enableDamping = true;
        focusTimer = null;
      }, 3000);

      // Même distance qu'actuellement (pas de saut de zoom), légère plongée
      const dist = camera.position.distanceTo(controls.target);
      const dir = new THREE.Vector3(-1, 0.28, 0).normalize();
      const from = camera.position.clone();
      const to = controls.target.clone().add(dir.multiplyScalar(dist));

      const start = performance.now();
      if (focusAnim) cancelAnimationFrame(focusAnim);
      const step = (now) => {
        const t = Math.min((now - start) / 800, 1);
        const e = 1 - Math.pow(1 - t, 3); // easeOutCubic
        camera.position.lerpVectors(from, to, e);
        camera.lookAt(controls.target);
        focusAnim = t < 1 ? requestAnimationFrame(step) : null;
      };
      focusAnim = requestAnimationFrame(step);
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
      if (mandalaMesh && mandalaCharge === index) { applyMandalaColor(); return; }
      if (mandalaMesh) {
        boxGroup.remove(mandalaMesh);
        mandalaMesh = null;
        mandalaCharge = 0;
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
        mandalaCharge = index;
        boxGroup.add(mandalaMesh);
        applyMandalaColor();
      }, undefined, (err) => console.error('Erreur de chargement du mandala :', err));
    }

    // ─── Aperçu : la photo réelle d'abord, la 3D à la demande ───
    // three.js et ses chargeurs (~500 Ko) ne sont demandés qu'au clic sur
    // « 3D », ou quand un motif ou une teinte est choisi (la photo ne montre
    // que sa propre configuration). Règle : ce qu'on voit est ce qu'on commande.
    const SCRIPTS_3D = [
      'https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js',
      'https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/controls/OrbitControls.js',
      'https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/loaders/GLTFLoader.js',
      'https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/loaders/DRACOLoader.js',
    ];
    let chargement3D = null;
    function charger3D() {
      if (chargement3D) return chargement3D;
      const un = (src) => new Promise((ok, ko) => {
        const el = document.createElement('script');
        el.src = src;
        el.onload = ok;
        el.onerror = () => ko(new Error('script 3D : ' + src));
        document.head.appendChild(el);
      });
      // three.min.js d'abord (les trois autres étendent THREE), puis les chargeurs ensemble.
      chargement3D = un(SCRIPTS_3D[0]).then(() => Promise.all(SCRIPTS_3D.slice(1).map(un)));
      chargement3D.catch(() => { chargement3D = null; });   // un échec réseau n'est pas définitif
      return chargement3D;
    }

    const apercuImg = document.getElementById('apercu-photo');
    const apercuLegende = document.getElementById('apercu-legende');
    const canvasBox = document.getElementById('canvas3d');
    const hint3D = document.getElementById('viewport-hint');
    const btnPhoto = document.getElementById('mode-photo');
    const btn3D = document.getElementById('mode-3d');
    let modeApercu = 'photo';

    function majModes() {
      [[btnPhoto, 'photo'], [btn3D, '3d']].forEach(([b, m]) => {
        b.classList.toggle('active', modeApercu === m);
        b.setAttribute('aria-pressed', modeApercu === m ? 'true' : 'false');
      });
    }
    function legende3D() {
      if (modeApercu !== '3d') return;
      apercuLegende.textContent = '3D · ' + FINISHES[state.finish].label +
        (state.mandala ? ' · motif ' + state.mandala + ' (' + MANDALA_COLORS[state.mandalaColor].label.toLowerCase() + ')' : ' · sans motif');
    }
    function montrerPhoto() {
      modeApercu = 'photo';
      rendu3DActif = false;
      canvasBox.hidden = true;
      hint3D.hidden = true;
      apercuImg.hidden = false;
      alignerSurPhoto(state.finish);
      majModes();
    }
    function montrer3D() {
      modeApercu = '3d';
      apercuImg.hidden = true;
      canvasBox.hidden = false;
      hint3D.hidden = false;
      majModes();
      if (!threeStarted) apercuLegende.textContent = 'Chargement de l\'aperçu 3D…';
      rendu3DActif = true;
      charger3D().then(() => {
        if (modeApercu !== '3d') return;
        init3D();
        if (boxMesh) {
          applyFinish();
          loadMandala(state.mandala);
          if (!boucleActive) animate3D();
          legende3D();
        }
      }).catch(() => {
        apercuLegende.textContent = 'Aperçu 3D indisponible pour le moment.';
        setTimeout(() => { if (modeApercu === '3d') montrerPhoto(); }, 1500);
      });
    }
    btnPhoto.addEventListener('click', montrerPhoto);
    btn3D.addEventListener('click', montrer3D);

    // ─── Contrôles du configurateur ───
    function selectIn(group, target) {
      group.forEach((el) => el.classList.remove('active'));
      target.classList.add('active');
    }

    // Génère les pastilles de couleur à partir de la palette partagée
    function buildSwatches(containerId, activeKey, onPick, palette) {
      const container = document.getElementById(containerId);
      const buttons = [];
      Object.entries(palette).forEach(([key, c]) => {
        const btn = document.createElement('button');
        btn.className = 'swatch' + (key === activeKey ? ' active' : '');
        btn.style.background = c.hex;
        btn.title = c.label;
        btn.setAttribute('aria-label', c.label);
        btn.dataset.key = key;
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

    const finishBtns = buildSwatches('finish-swatches', state.finish, (key) => {
      state.finish = key;
      document.getElementById('finish-note').textContent = FINISHES[key].label + ' — finition mate.';
      applyFinish();
      montrerColoris(key);
      if (modeApercu === 'photo') { if (photoDe(key)) alignerSurPhoto(key); else montrer3D(); }
      else legende3D();
    }, FINISHES);

    const mcolorBtns = buildSwatches('mcolor-swatches', state.mandalaColor, (key) => {
      state.mandalaColor = key;
      applyMandalaColor();
      if (modeApercu !== '3d') { montrer3D(); return; }   // la photo ne montre que sa propre teinte
      legende3D();
      if (state.mandala !== 0) focusMotifFace();
    }, MANDALA_COLORS);

    const mandalaBtns = document.querySelectorAll('[data-mandala]');
    mandalaBtns.forEach((btn) => {
      btn.addEventListener('click', () => {
        state.mandala = parseInt(btn.dataset.mandala, 10);
        selectIn(mandalaBtns, btn);
        document.getElementById('mandala-color-group').style.display = state.mandala === 0 ? 'none' : 'block';
        updateQuoteLink();
        if (modeApercu !== '3d') { montrer3D(); return; }   // le motif se voit en 3D, chargé dès qu'elle est prête
        loadMandala(state.mandala);
        legende3D();
        if (state.mandala !== 0) focusMotifFace();
      });
    });

    // La photo d'un châssis montre le motif photographié dans sa teinte : en
    // mode photo, choisir un châssis aligne la commande sur ce que l'on voit.
    function photoDe(finish) {
      const fig = colorisVues.find((f) => f.dataset.finish === finish);
      if (!fig) return null;
      const img = fig.querySelector('img');
      const m = (img.getAttribute('src') || '').match(/--([a-z-]+)\.jpg$/);
      return { src: img.getAttribute('src'), couleur: m ? m[1] : null, alt: img.alt };
    }
    function alignerSurPhoto(finish) {
      const ph = photoDe(finish);
      if (!ph) return;
      state.mandala = MOTIF_PHOTO;
      if (ph.couleur && MANDALA_COLORS[ph.couleur]) state.mandalaColor = ph.couleur;
      mandalaBtns.forEach((b) => b.classList.toggle('active', parseInt(b.dataset.mandala, 10) === state.mandala));
      mcolorBtns.forEach((b) => b.classList.toggle('active', b.dataset.key === state.mandalaColor));
      document.getElementById('mandala-color-group').style.display = 'block';
      if (apercuImg.getAttribute('src') !== ph.src) apercuImg.src = ph.src;
      apercuImg.alt = ph.alt + ' — photo réelle';
      apercuLegende.textContent = FINISHES[finish].label + ' · motif ' +
        MANDALA_COLORS[state.mandalaColor].label.toLowerCase() + ' — photo réelle';
      updateQuoteLink();
    }

    // ─── Coloris en photo ───
    // La bande de photos au-dessus du configurateur (liste ecrite par
    // outils_production/maj_coloris.py) suit la pastille du chassis : la photo
    // du coloris choisi est entouree et ramenee dans la bande. Les couleurs du
    // site sans photo sont nommees dessous plutot que passees sous silence ;
    // elles se deduisent de FINISHES, il n'y a rien a tenir a jour ici.
    const coloris = document.querySelector('[data-coloris]');
    const colorisPiste = coloris ? coloris.querySelector('.coloris-piste') : null;
    const colorisVues = colorisPiste ? Array.from(colorisPiste.querySelectorAll('figure[data-finish]')) : [];
    const colorisDoux = !(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);

    function montrerColoris(key) {
      if (!colorisPiste) return;
      coloris.querySelectorAll('[data-finish]').forEach((el) => el.classList.toggle('choisi', el.dataset.finish === key));
      const vue = colorisVues.find((f) => f.dataset.finish === key);
      if (!vue) return;
      // Deja entierement a l'ecran : on ne fait rien bouger.
      const g = vue.offsetLeft, d = g + vue.offsetWidth;
      if (g >= colorisPiste.scrollLeft && d <= colorisPiste.scrollLeft + colorisPiste.clientWidth) return;
      colorisPiste.scrollTo({ left: g - (colorisPiste.clientWidth - vue.offsetWidth) / 2, behavior: colorisDoux ? 'smooth' : 'auto' });
    }

    if (colorisPiste) {
      const prec = coloris.querySelector('.coloris-prec');
      const suiv = coloris.querySelector('.coloris-suiv');
      const pas = (sens) => colorisPiste.scrollBy({ left: sens * colorisPiste.clientWidth * 0.75, behavior: colorisDoux ? 'smooth' : 'auto' });
      prec.addEventListener('click', () => pas(-1));
      suiv.addEventListener('click', () => pas(1));
      let attente = 0;
      const peindre = () => {
        attente = 0;
        const max = colorisPiste.scrollWidth - colorisPiste.clientWidth;
        prec.hidden = suiv.hidden = max <= 2;   // tout tient a l'ecran : pas de fleches
        prec.disabled = colorisPiste.scrollLeft <= 2;
        suiv.disabled = colorisPiste.scrollLeft >= max - 2;
      };
      const plusTard = () => { if (!attente) attente = requestAnimationFrame(peindre); };
      colorisPiste.addEventListener('scroll', plusTard, { passive: true });
      window.addEventListener('resize', plusTard);
      peindre();

      colorisVues.forEach((fig) => {
        fig.style.cursor = 'pointer';
        fig.addEventListener('click', () => {
          const btn = finishBtns.find((b) => b.dataset.key === fig.dataset.finish);
          if (btn) btn.click();
        });
      });

      const photographies = new Set(colorisVues.map((f) => f.dataset.finish));
      const sansPhoto = Object.keys(FINISHES).filter((k) => !photographies.has(k));
      const ligne = document.getElementById('coloris-sans-photo');
      if (ligne && sansPhoto.length) {
        ligne.append(' Aussi en ');
        sansPhoto.forEach((k, i) => {
          if (i) ligne.append(i === sansPhoto.length - 1 ? ' et ' : ', ');
          const nom = document.createElement('span');
          nom.dataset.finish = k;
          const pastille = document.createElement('span');
          pastille.className = 'pastille';
          pastille.setAttribute('aria-hidden', 'true');
          pastille.style.background = FINISHES[k].hex;
          nom.append(pastille, FINISHES[k].label);
          ligne.append(nom);
        });
        ligne.append(' — pas encore en photo, l’aperçu 3D ci-dessous vous en montre la teinte.');
      }
    }

    // ─── Commande : le bouton crée la commande via le backend
    //     (config transmise UNE fois, visible dans Stripe + email de
    //     confirmation personnalisé). Si le backend est indisponible,
    //     secours automatique : Payment Link direct (client_reference_id).
    const CHECKOUT_BACKEND = 'https://adhanbox-commande.vercel.app';
    const STRIPE_PAYMENT_LINK = 'https://buy.stripe.com/00w00kg6P7sb5Woe7LfjG01';
    const PRICE_EUR = 95;
    const DOMICILE_EUR = 5;

    // ─── Livraison : point relais (offert) ou domicile (+5 €) ───
    // Le point relais lui-meme se choisit APRES le paiement (merci.html +
    // api/relais.js) : le bouton de commande n'est plus jamais grise. Ici on
    // ne garde que le choix du mode, et une sonde du backend (/api/map-token)
    // qui cache l'option relais si Boxtal est indisponible.
    const deliv = { mode: 'relais', enabled: null };
    const $ = (id) => document.getElementById(id);
    const delivBtns = document.querySelectorAll('[data-livraison]');

    function setDeliveryMode(mode) {
      deliv.mode = mode;
      delivBtns.forEach((b) => b.classList.toggle('active', b.dataset.livraison === mode));
      $('relais-note').hidden = mode !== 'relais';
      $('domicile-note').hidden = mode !== 'domicile';
      updateQuoteLink();
    }
    delivBtns.forEach((b) => b.addEventListener('click', () => setDeliveryMode(b.dataset.livraison)));

    function disableRelais(reason) {
      deliv.enabled = false;
      $('deliv-relais').hidden = true;
      setDeliveryMode('domicile');
      if (reason) console.warn('Point relais désactivé :', reason);
    }
    fetch(CHECKOUT_BACKEND + '/api/map-token')
      .then((r) => r.json())
      .then((d) => { if (!d || !d.enabled) throw new Error((d && d.error) || 'relais indisponible'); deliv.enabled = true; })
      .catch((err) => disableRelais(err && err.message));
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
      const total = PRICE_EUR + (deliv.mode === 'domicile' ? DOMICILE_EUR : 0);
      cta.textContent = 'Commander cette configuration — ' + total + ' €';
      const note = document.getElementById('cta-note');
      if (note) note.textContent = 'Paiement sécurisé par Stripe · 3× sans frais possible · ' +
        (deliv.mode === 'domicile' ? 'livraison à domicile 5 €.' : 'point relais offert.');
    }
    updateQuoteLink();

    // Barre d'achat fixe (mobile) : masquee des que le vrai bouton de
    // commande est a l'ecran, pour ne pas le doubler.
    const barreAchat = document.getElementById('barre-achat');
    if (barreAchat && 'IntersectionObserver' in window) {
      new IntersectionObserver((entries) => {
        barreAchat.classList.toggle('cachee', entries[0].isIntersecting);
      }, { threshold: 0.3 }).observe(document.getElementById('config-cta'));
    }

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
          mandalaColor: state.mandalaColor,
          livraison: deliv.enabled === false ? 'domicile' : deliv.mode,
          relais: null   // choisi apres le paiement (merci.html)
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
