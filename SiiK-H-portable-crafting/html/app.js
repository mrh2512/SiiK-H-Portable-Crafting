const app = document.getElementById('app');
const benchName = document.getElementById('benchName');
const levelVal = document.getElementById('levelVal');
const xpVal = document.getElementById('xpVal');
const xpFill = document.getElementById('xpFill');
const xpNext = document.getElementById('xpNext');

const categoryList = document.getElementById('categoryList');
const recipeGrid = document.getElementById('recipeGrid');

const search = document.getElementById('search');
const amount = document.getElementById('amount');
const amtMinus = document.getElementById('amtMinus');
const amtPlus = document.getElementById('amtPlus');

const details = document.getElementById('details');
const detailName = document.getElementById('detailName');
const detailMeta = document.getElementById('detailMeta');
const detailIngs = document.getElementById('detailIngs');
const detailOut = document.getElementById('detailOut');
const craftBtn = document.getElementById('craftBtn');
const lockBanner = document.getElementById('lockBanner');
const detailIcon = document.getElementById('detailIcon');
const detailOutIcon = document.getElementById('detailOutIcon');

const craftTime = document.getElementById('craftTime');
const craftFill = document.getElementById('craftFill');

const weaponMeta = document.getElementById('weaponMeta');
const weaponMetaBody = document.getElementById('weaponMetaBody');

const drawOverlay = document.getElementById('drawOverlay');
const closeBtn = document.getElementById('closeBtn');

let state = {
  open: false,
  dbId: null,
  tableType: null,
  tableLabel: '',
  level: 1,
  xp: 0,
  xpNext: 0,
  categories: [],
  recipesByCat: {},
  selectedCat: null,
  selectedRecipe: null,
  counts: {}, // { item: {have, need} }
  crafting: false,
  previewToken: null,
  previewSerials: [],
};

function post(name, data = {}) {
  return fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  }).then(r => r.json()).catch(() => ({}));
}

function itemImg(itemName){
  return `nui://qb-inventory/html/images/${itemName}.png`;
}

function setIcon(el, itemName){
  el.innerHTML = '';
  const img = document.createElement('img');
  img.src = itemImg(itemName);
  img.onerror = () => { img.remove(); };
  el.appendChild(img);
}

function setOpen(v){
  state.open = v;
  app.classList.toggle('hidden', !v);
  if(!v){
    state.dbId = null;
    state.tableType = null;
    state.selectedCat = null;
    state.selectedRecipe = null;
    state.counts = {};
    state.crafting = false;
    state.previewToken = null;
    state.previewSerials = [];
    recipeGrid.innerHTML = '';
    categoryList.innerHTML = '';
    details.classList.add('hidden');
    search.value = '';
    amount.value = 1;
    craftFill.style.width = '0%';
  }
}

function renderStats(){
  levelVal.textContent = state.level;
  xpVal.textContent = state.xp;
  const next = Math.max(1, state.xpNext);
  const pct = Math.max(0, Math.min(100, (state.xp / next) * 100));
  xpFill.style.width = `${pct}%`;
  xpNext.textContent = `${state.xp} / ${next}`;
  benchName.textContent = state.tableLabel || 'Blueprint Workbench';
}

function renderCategories(){
  categoryList.innerHTML = '';
  state.categories.forEach(cat => {
    const btn = document.createElement('div');
    btn.className = 'cat' + (state.selectedCat === cat ? ' active' : '');
    const count = (state.recipesByCat[cat] || []).length;
    btn.innerHTML = `<div class="cat-name">${cat}</div><div class="cat-count">${count}</div>`;
    btn.addEventListener('click', () => {
      state.selectedCat = cat;
      state.selectedRecipe = null;
      state.counts = {};
      renderCategories();
      renderRecipes();
      hideDetails();
    });
    categoryList.appendChild(btn);
  });
}

function renderRecipes(){
  const q = (search.value || '').toLowerCase().trim();
  recipeGrid.innerHTML = '';

  const list = state.selectedCat ? (state.recipesByCat[state.selectedCat] || []) : [];
  list
    .filter(r => !q || (r.label || r.key || '').toLowerCase().includes(q))
    .forEach(r => {
      const locked = state.level < (r.levelRequired || 1);

      const el = document.createElement('div');
      el.className = 'recipe' + (locked ? ' locked' : '');
      el.innerHTML = `
        <div class="r-top">
          <div class="item-icon" data-icon="${r.key}"></div>
          <div>
            <div class="r-name">${r.label || r.key}</div>
            <div class="r-sub">Req Lvl: ${r.levelRequired || 1}<br/>XP: ${r.xp || 0} / craft</div>
          </div>
        </div>
        <div class="badge">${locked ? 'LOCKED BLUEPRINT' : 'READY'}</div>
      `;

      const iconBox = el.querySelector('[data-icon]');
      setIcon(iconBox, r.key);

      el.addEventListener('click', () => {
        state.selectedRecipe = r;
        showDetails(r);
      });

      recipeGrid.appendChild(el);
    });
}

function clampAmount(){
  let v = parseInt(amount.value || '1', 10);
  if(isNaN(v) || v < 1) v = 1;
  if(v > 50) v = 50;
  amount.value = v;
  return v;
}

function enforceWeaponAmount(){
  if(!state.selectedRecipe) return;
  const isWeapon = (state.selectedRecipe.key || '').startsWith('weapon_');
  if(isWeapon){
    amount.value = 1;
    amount.setAttribute('disabled', 'disabled');
    amtMinus.setAttribute('disabled', 'disabled');
    amtPlus.setAttribute('disabled', 'disabled');
  } else {
    amount.removeAttribute('disabled');
    amtMinus.removeAttribute('disabled');
    amtPlus.removeAttribute('disabled');
  }
}

function hideDetails(){
  details.classList.add('hidden');
  drawOverlay.classList.add('hidden');
  state.crafting = false;
  state.previewToken = null;
  state.previewSerials = [];
  weaponMeta.classList.add('hidden');
  weaponMetaBody.innerHTML = '';
}

async function refreshCounts(){
  if(!state.selectedRecipe) return;

  const amt = clampAmount();
  const ingredients = state.selectedRecipe.ingredients || {};
  const res = await post('getCounts', { ingredients, amount: amt });
  state.counts = (res && res.counts) ? res.counts : {};

  renderDetailsIngredients();
  updateCraftButtonState();
}

function renderDetailsIngredients(){
  detailIngs.innerHTML = '';
  const ing = state.selectedRecipe ? (state.selectedRecipe.ingredients || {}) : {};
  const keys = Object.keys(ing);

  if(keys.length === 0){
    const row = document.createElement('div');
    row.className = 'ingRow good';
    row.innerHTML = `<div class="ingName">No ingredients</div><div class="ingCount">OK</div>`;
    detailIngs.appendChild(row);
    return;
  }

  keys.forEach(item => {
    const perCraft = ing[item] || 0;
    const entry = state.counts[item] || { have: 0, need: perCraft * clampAmount() };
    const have = entry.have ?? 0;
    const need = entry.need ?? (perCraft * clampAmount());
    const good = have >= need;

    const row = document.createElement('div');
    row.className = 'ingRow ' + (good ? 'good' : 'bad');
    row.innerHTML = `
      <div class="ingLeft">
        <div class="item-icon" data-ingicon="${item}"></div>
        <div class="ingName">${item}</div>
      </div>
      <div class="ingCount">${have}/${need}</div>
    `;
    const iconBox = row.querySelector('[data-ingicon]');
    setIcon(iconBox, item);

    detailIngs.appendChild(row);
  });
}

function updateCraftButtonState(){
  if(!state.selectedRecipe){
    craftBtn.disabled = true;
    return;
  }

  const locked = state.level < (state.selectedRecipe.levelRequired || 1);
  lockBanner.classList.toggle('hidden', !locked);

  let missing = false;
  const ing = state.selectedRecipe.ingredients || {};
  for(const item of Object.keys(ing)){
    const c = state.counts[item];
    const need = c ? c.need : (ing[item] * clampAmount());
    const have = c ? c.have : 0;
    if(have < need) { missing = true; break; }
  }

  craftBtn.disabled = locked || missing || state.crafting;

  if(locked){
    craftBtn.textContent = 'LOCKED';
  } else if(missing){
    craftBtn.textContent = 'MISSING ITEMS';
  } else if(state.crafting){
    craftBtn.textContent = 'CRAFTING…';
  } else {
    craftBtn.textContent = 'CRAFT';
  }
}

function startDrawAnimation(){
  drawOverlay.classList.remove('hidden');
  const lines = drawOverlay.querySelectorAll('.draw-line');
  lines.forEach(l => {
    l.style.animation = 'none';
    void l.offsetHeight;
    l.style.animation = '';
  });
}

function stopDrawAnimation(){
  drawOverlay.classList.add('hidden');
}

function animateRuler(ms){
  craftFill.style.width = '0%';
  const start = performance.now();
  const dur = Math.max(250, ms);

  function tick(now){
    const t = Math.min(1, (now - start) / dur);
    craftFill.style.width = `${(t * 100).toFixed(2)}%`;
    if(state.crafting && t < 1){
      requestAnimationFrame(tick);
    }
  }
  requestAnimationFrame(tick);
}

async function requestWeaponPreview(){
  if(!state.selectedRecipe) return;
  const key = state.selectedRecipe.key || '';
  if(!key.startsWith('weapon_')) return;

  const res = await post('weaponPreview', { recipeKey: key, amount: 1 });
  const prev = res && res.preview;

  state.previewToken = prev ? prev.token : null;
  state.previewSerials = prev ? (prev.serials || []) : [];

  weaponMetaBody.innerHTML = '';
  if(!prev || !state.previewSerials.length){
    weaponMetaBody.innerHTML = `<div class="meta-line">No preview available.</div>`;
    return;
  }

  const s = state.previewSerials[0];
  const row = document.createElement('div');
  row.className = 'meta-line';
  row.innerHTML = `<strong>SERIAL:</strong> ${s}`;
  weaponMetaBody.appendChild(row);
}

function showDetails(r){
  details.classList.remove('hidden');
  stopDrawAnimation();

  state.previewToken = null;
  state.previewSerials = [];
  craftFill.style.width = '0%';

  enforceWeaponAmount();

  detailName.textContent = (r.label || r.key || 'Recipe').toUpperCase();
  detailMeta.textContent = `Req Level: ${r.levelRequired || 1} • XP: ${r.xp || 0}`;

  setIcon(detailIcon, r.key);
  setIcon(detailOutIcon, r.key);

  const baseTime = (r.timeMs || 1500);
  const totalTime = baseTime * clampAmount();

  craftTime.textContent = `TIME: ${(totalTime/1000).toFixed(1)}s`;

  const outAmt = (r.amountOut || 1) * clampAmount();
  detailOut.textContent = `${outAmt}x ${r.key}`;

  const isWeapon = (r.key || '').startsWith('weapon_');
  weaponMeta.classList.toggle('hidden', !isWeapon);
  weaponMetaBody.innerHTML = isWeapon ? `<div class="meta-line">Generating preview…</div>` : '';

  state.crafting = false;
  updateCraftButtonState();

  refreshCounts();
  if(isWeapon){
    requestWeaponPreview();
  }
}

closeBtn.addEventListener('click', () => { post('close'); });

document.addEventListener('keydown', (e) => {
  if(!state.open) return;
  if(e.key === 'Escape'){
    post('close');
  }
});

search.addEventListener('input', () => renderRecipes());

amount.addEventListener('change', () => {
  if(state.selectedRecipe && (state.selectedRecipe.key || '').startsWith('weapon_')) {
    amount.value = 1;
    return;
  }
  clampAmount();
  if(state.selectedRecipe){
    const outAmt = (state.selectedRecipe.amountOut || 1) * clampAmount();
    detailOut.textContent = `${outAmt}x ${state.selectedRecipe.key}`;

    const baseTime = (state.selectedRecipe.timeMs || 1500);
    const totalTime = baseTime * clampAmount();
    craftTime.textContent = `TIME: ${(totalTime/1000).toFixed(1)}s`;
    craftFill.style.width = '0%';

    refreshCounts();
  }
});

amtMinus.addEventListener('click', () => {
  if(state.selectedRecipe && (state.selectedRecipe.key || '').startsWith('weapon_')) return;
  amount.value = clampAmount() - 1;
  clampAmount();
  if(state.selectedRecipe){
    const outAmt = (state.selectedRecipe.amountOut || 1) * clampAmount();
    detailOut.textContent = `${outAmt}x ${state.selectedRecipe.key}`;

    const baseTime = (state.selectedRecipe.timeMs || 1500);
    const totalTime = baseTime * clampAmount();
    craftTime.textContent = `TIME: ${(totalTime/1000).toFixed(1)}s`;
    craftFill.style.width = '0%';

    refreshCounts();
  }
});

amtPlus.addEventListener('click', () => {
  if(state.selectedRecipe && (state.selectedRecipe.key || '').startsWith('weapon_')) return;
  amount.value = clampAmount() + 1;
  clampAmount();
  if(state.selectedRecipe){
    const outAmt = (state.selectedRecipe.amountOut || 1) * clampAmount();
    detailOut.textContent = `${outAmt}x ${state.selectedRecipe.key}`;

    const baseTime = (state.selectedRecipe.timeMs || 1500);
    const totalTime = baseTime * clampAmount();
    craftTime.textContent = `TIME: ${(totalTime/1000).toFixed(1)}s`;
    craftFill.style.width = '0%';

    refreshCounts();
  }
});

craftBtn.addEventListener('click', async () => {
  if(!state.selectedRecipe) return;

  updateCraftButtonState();
  if(craftBtn.disabled) return;

  const amt = clampAmount();

  // weapons always 1
  if((state.selectedRecipe.key || '').startsWith('weapon_')){
    amount.value = 1;
  }

  const baseTime = (state.selectedRecipe.timeMs || 1500);
  const totalTime = baseTime * clampAmount();

  state.crafting = true;
  updateCraftButtonState();

  animateRuler(totalTime);
  startDrawAnimation();

  await post('craft', {
    dbId: state.dbId,
    recipeKey: state.selectedRecipe.key,
    amount: clampAmount(),
    previewToken: state.previewToken
  });

  // Server will send updateStats or craftCanceled to end animation.
  // Safety timeout:
  setTimeout(() => {
    if(state.crafting){
      state.crafting = false;
      stopDrawAnimation();
      craftFill.style.width = '0%';
      updateCraftButtonState();
    }
  }, Math.max(2500, totalTime + 1500));
});

window.addEventListener('message', (event) => {
  const data = event.data || {};

  if(data.action === 'open'){
    state.dbId = data.dbId;
    state.tableType = data.tableType;
    state.tableLabel = data.tableLabel || 'Blueprint Workbench';

    state.level = data.level || 1;
    state.xp = data.xp || 0;
    state.xpNext = data.xpNext || 1;

    state.categories = data.categories || [];
    state.recipesByCat = data.recipesByCat || {};

    state.selectedCat = state.categories[0] || null;
    state.selectedRecipe = null;
    state.counts = {};
    state.crafting = false;
    state.previewToken = null;
    state.previewSerials = [];

    setOpen(true);
    renderStats();
    renderCategories();
    renderRecipes();
    hideDetails();
  }

  if(data.action === 'updateStats'){
    state.level = data.level || state.level;
    state.xp = (data.xp ?? state.xp);
    state.xpNext = data.xpNext || state.xpNext;
    renderStats();

    if(state.crafting){
      state.crafting = false;
      stopDrawAnimation();
    }

    if(state.selectedRecipe){
      // Re-check lock + refresh counts
      const outAmt = (state.selectedRecipe.amountOut || 1) * clampAmount();
      detailOut.textContent = `${outAmt}x ${state.selectedRecipe.key}`;
      refreshCounts();
      enforceWeaponAmount();
      if((state.selectedRecipe.key || '').startsWith('weapon_')){
        requestWeaponPreview();
      }
    }

    renderRecipes();
    renderCategories();
  }

  if(data.action === 'craftCanceled'){
    state.crafting = false;
    stopDrawAnimation();
    craftFill.style.width = '0%';
    craftBtn.textContent = 'CANCELED';
    craftBtn.disabled = true;

    setTimeout(() => {
      updateCraftButtonState();
    }, 900);
  }

  if(data.action === 'close'){
    setOpen(false);
  }
});
