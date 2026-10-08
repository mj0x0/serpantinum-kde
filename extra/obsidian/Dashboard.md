---
cssclasses:
  - dashboard-layout
  - max
---

```dataviewjs
// Dashboard-Komorebi
// more dashboards → https://github.com/InlitX/Obsidian-Dashboard-Gallery

const wrap = dv.container.createDiv({ cls: 'komo-header-block' });
const hdr  = wrap.createDiv({ cls: 'komo-header' });

// ── BRAND (left) ─────────────────────────────
const brand = hdr.createDiv({ cls: 'komo-brand' });

const vaultName   = (app.vault.getName() || 'VAULT').toUpperCase();
const savedTitle  = localStorage.getItem('komo-title')  || vaultName;
const savedMantra = localStorage.getItem('komo-mantra') || 'notes, thoughts & things that matter';

const titleEl = brand.createEl('div', {
    cls: 'komo-title',
    attr: { contenteditable: 'true', spellcheck: 'false', 'data-placeholder': vaultName }
});
titleEl.textContent = savedTitle;
titleEl.addEventListener('blur', () => {
    const v = titleEl.textContent.trim();
    if (v) localStorage.setItem('komo-title', v);
});

const mantraEl = brand.createEl('div', {
    cls: 'komo-mantra',
    attr: { contenteditable: 'true', spellcheck: 'false' }
});
mantraEl.textContent = savedMantra;
mantraEl.addEventListener('blur', () => {
    const v = mantraEl.textContent.trim();
    if (v) localStorage.setItem('komo-mantra', v);
});

// ── CLOCK (center) ────────────────────────────
const clk    = hdr.createDiv({ cls: 'komo-clock-block' });
const timeEl = clk.createDiv({ cls: 'komo-time' });
const dateEl = clk.createDiv({ cls: 'komo-date' });

function tick() {
    const now = new Date();
    const pad = n => String(n).padStart(2, '0');
    timeEl.textContent = `${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
    const jpDate = now.toLocaleDateString('ja-JP', {
        year: 'numeric', month: 'long', day: 'numeric', weekday: 'long'
    });
    const enDate = now.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
    dateEl.innerHTML = `<span>${jpDate}</span><span class="komo-sep"> · </span><span class="komo-date-en">${enDate}</span>`;
}
tick();
setInterval(tick, 1000);

// ── RIGHT — GREETING + STATS ──────────────────
const rightHdr = hdr.createDiv({ cls: 'komo-header-right' });

const GREETS = [
    { h: [0,5],  jp: 'late',    en: 'Still going?' },
    { h: [5,9],  jp: 'dawn',    en: 'New day, new flow.' },
    { h: [9,13], jp: 'morning', en: 'Peak focus. Engage.' },
    { h: [13,18],jp: 'noon',    en: 'Stay in the flow.' },
    { h: [18,21],jp: 'dusk',    en: 'Review your progress.' },
    { h: [21,24],jp: 'night',   en: 'Wind down. Reflect.' }
];
const gEl = rightHdr.createDiv({ cls: 'komo-greeting' });
const gJp = gEl.createEl('span', { cls: 'komo-greet-jp' });
const gEn = gEl.createEl('span', { cls: 'komo-greet-en' });
function paintGreet() {
    const h = new Date().getHours();
    const G = GREETS.find(g => h >= g.h[0] && h < g.h[1]) || GREETS[5];
    if (gJp.textContent !== G.jp) { gJp.textContent = G.jp; gEn.textContent = G.en; }
}
paintGreet();
setInterval(paintGreet, 60000);

// Vault stats
const statsRow = rightHdr.createDiv({ cls: 'komo-stats-row' });
const pages  = dv.pages();
const tasks  = pages.file.tasks;
const doneN  = tasks.where(t => t.completed).length;
const openN  = tasks.where(t => !t.completed).length;

[
    { n: pages.length, l: 'notes', q: null },
    { n: openN,        l: 'open',  q: 'task-todo:""' },
    { n: doneN,        l: 'done',  q: 'task-done:""' },
].forEach(({ n, l, q }) => {
    const p = statsRow.createDiv({ cls: 'komo-pill' });
    p.createDiv({ cls: 'komo-pill-num', text: n.toString() });
    p.createDiv({ cls: 'komo-pill-lbl', text: l });
    if (q) {
        p.style.cursor = 'pointer';
        p.addEventListener('click', () => {
            const gs = app.internalPlugins.getPluginById('global-search');
            if (gs) gs.instance.openGlobalSearch(q);
            else new Notice('Global search unavailable');
        });
    }
});

// Thin sakura divider
wrap.createDiv({ cls: 'komo-divider' });
```

```dataviewjs
// Dashboard-Komorebi
// more dashboards → https://github.com/InlitX/Obsidian-Dashboard-Gallery

const wrap  = dv.container.createDiv({ cls: 'komo-grid-block' });
const grid  = wrap.createDiv({ cls: 'komo-grid' });

// ══════════════════════════════════════════════
//  LEFT COLUMN
// ══════════════════════════════════════════════
const colL = grid.createDiv({ cls: 'komo-col-left' });

// ── FOCUS CARD (file-backed so today's goal syncs across devices) ──
const focusCard = colL.createDiv({ cls: 'komo-card' });
focusCard.createDiv({ cls: 'komo-label', text: "today's goal" });

const FOCUS_PATH = '.obsidian/focus.json';
async function loadFocus() {
    try {
        if (await app.vault.adapter.exists(FOCUS_PATH)) {
            const o = JSON.parse(await app.vault.adapter.read(FOCUS_PATH));
            if (o && typeof o.text === 'string') return o.text;
        }
    } catch (e) {}
    // first run — migrate any old per-device value
    return localStorage.getItem('komo-focus') || 'do the work. trust the process.';
}
async function saveFocus(text) {
    try { await app.vault.adapter.write(FOCUS_PATH, JSON.stringify({ text }, null, 2)); }
    catch (e) { new Notice('Could not save goal'); }
}

const focusEl = focusCard.createEl('div', {
    cls: 'komo-focus',
    attr: { contenteditable: 'true', spellcheck: 'false', placeholder: 'define your focus...' }
});
const focusText = await loadFocus();
focusEl.textContent = focusText;
// Persist immediately so the file exists and carries the value to other devices,
// even if the goal is never re-edited here (mirrors habits/collection seeding).
if (!(await app.vault.adapter.exists(FOCUS_PATH))) await saveFocus(focusText);
focusEl.addEventListener('blur', () => { saveFocus(focusEl.textContent.trim()); });

// ── SYSTEM CARD ──────────────────────────────
const sysCard = colL.createDiv({ cls: 'komo-card komo-sys-card' });
sysCard.createDiv({ cls: 'komo-label', text: 'system' });

const ACTIONS = [
    { icon: 'calendar',    lbl: 'daily',   em: '📅' },
    { icon: 'search',      lbl: 'search',  cmd: 'global-search:open',        em: '🔍' },
    { icon: 'share-2',     lbl: 'graph',   cmd: 'graph:open',                em: '🕸' },
    { icon: 'file-plus',   lbl: 'new',     cmd: 'file-explorer:new-file',    em: '＋' },
    { icon: 'zap',         lbl: 'quick',   cmd: 'quickadd:runQuickAdd',      em: '⚡' },
    { icon: 'terminal',    lbl: 'cmds',    cmd: 'command-palette:open',      em: '⌘' },
];

const actGrid = sysCard.createDiv({ cls: 'komo-act-grid' });
ACTIONS.forEach(a => {
    const btn = actGrid.createDiv({ cls: 'komo-act-btn' });
    const ico = btn.createDiv({ cls: 'komo-act-icon' });
    try { setIcon(ico, a.icon); } catch(e) { ico.textContent = a.em; }
    btn.createDiv({ cls: 'komo-act-lbl', text: a.lbl });
    btn.addEventListener('click', () => {
        if (a.lbl === 'daily') {
            // Daily note at Daily/<year>/<month>/<dd-mm-yy>.md — open if it exists, else create the tree
            const d = new Date();
            const p = n => String(n).padStart(2, '0');
            const yyyy = d.getFullYear(), mm = p(d.getMonth() + 1), dd = p(d.getDate());
            const folder = `Daily/${yyyy}/${mm}`;
            const path = `${folder}/${dd}-${mm}-${String(yyyy).slice(-2)}.md`;
            if (app.vault.getAbstractFileByPath(path)) {
                app.workspace.openLinkText(path, '', false);
            } else {
                (async () => {
                    for (const f of ['Daily', `Daily/${yyyy}`, folder])
                        if (!app.vault.getAbstractFileByPath(f)) { try { await app.vault.createFolder(f); } catch (e) {} }
                    // Seed from Templates/Daily.md (resolving {{date:…}}/{{time}}/{{title}}),
                    // fall back to a bare title if the template is missing.
                    let content = `# ${d.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}\n\n`;
                    try {
                        const TPL = 'Templates/Daily.md';
                        if (await app.vault.adapter.exists(TPL)) {
                            const m = window.moment ? window.moment(d) : null;
                            const base = path.split('/').pop().replace(/\.md$/, '');
                            content = (await app.vault.adapter.read(TPL))
                                .replace(/{{\s*date\s*:\s*([^}]+?)\s*}}/g, (_, fmt) => m ? m.format(fmt) : '')
                                .replace(/{{\s*date\s*}}/g, m ? m.format('YYYY-MM-DD') : '')
                                .replace(/{{\s*time\s*(?::\s*([^}]+?))?\s*}}/g, (_, fmt) => m ? m.format(fmt || 'HH:mm') : '')
                                .replace(/{{\s*title\s*}}/g, base);
                        }
                    } catch (e) {}
                    await app.vault.create(path, content);
                    app.workspace.openLinkText(path, '', false);
                    new Notice('📅 ' + path);
                })();
            }
            return;
        }
        try {
            if (!app.commands.commands[a.cmd]) {
                if (a.lbl === 'quick') new Notice('⚡ QuickAdd plugin not installed');
                else new Notice(`Command "${a.lbl}" not available`);
                return;
            }
            app.commands.executeCommandById(a.cmd);
        } catch(e) {
            new Notice(`Failed to run: ${a.lbl}`);
        }
    });
});

// ── WEATHER WIDGET (BIG) ─────────────────────
const weatherCard = colL.createDiv({ cls: 'komo-card komo-weather-card komo-big-widget' });

async function renderWeather() {
    const savedApiKey = localStorage.getItem('komo-weather-api-key') || '';
    const savedCity = localStorage.getItem('komo-weather-city') || 'barcelona';
    const savedUnits = localStorage.getItem('komo-weather-units') || 'metric';
    const savedLang = localStorage.getItem('komo-weather-lang') || 'en';

    weatherCard.innerHTML = '';
    weatherCard.createDiv({ cls: 'komo-label', text: 'weather' });

    // Settings button
    const settingsBtn = weatherCard.createDiv({ cls: 'komo-weather-settings' });
    try { setIcon(settingsBtn, 'settings'); } catch(e) { settingsBtn.textContent = '⚙'; }
    settingsBtn.addEventListener('click', showWeatherSettings);

    const weatherContent = weatherCard.createDiv({ cls: 'komo-weather-content' });

    if (!savedApiKey) {
        const setupMsg = weatherContent.createDiv({ cls: 'komo-weather-setup' });
        setupMsg.innerHTML = '<div class="komo-weather-big-icon">☁</div><div>configure weather</div>';
        setupMsg.addEventListener('click', showWeatherSettings);
        return;
    }

    try {
        const url = `https://api.openweathermap.org/data/2.5/weather?q=${savedCity}&units=${savedUnits}&lang=${savedLang}&appid=${savedApiKey}`;
        const response = await fetch(url);
        if (!response.ok) throw new Error('Weather error');
        const data = await response.json();

        const temp = Math.round(data.main.temp);
        const iconCode = data.weather[0].icon;
        const description = data.weather[0].description;
        const city = data.name;

        const mainRow = weatherContent.createDiv({ cls: 'komo-weather-main-big' });
        const iconEl = mainRow.createDiv({ cls: 'komo-weather-big-icon' });
        iconEl.innerHTML = getWeatherIcon(iconCode);

        const tempWrap = mainRow.createDiv({ cls: 'komo-weather-temp-wrap' });
        tempWrap.createDiv({ cls: 'komo-weather-temp-big', text: `${temp}°` });
        tempWrap.createDiv({ cls: 'komo-weather-city-big', text: city });

        weatherContent.createDiv({ cls: 'komo-weather-desc-big', text: description });

    } catch (e) {
        weatherContent.createDiv({ cls: 'komo-weather-error', text: '⚠ weather unavailable' });
    }
}

function getWeatherIcon(code) {
    const icons = {
        '01d': '☀', '01n': '☽',
        '02d': '⛅', '02n': '☁',
        '03d': '☁', '03n': '☁',
        '04d': '☁', '04n': '☁',
        '09d': '🌧', '09n': '🌧',
        '10d': '🌦', '10n': '🌧',
        '11d': '⚡', '11n': '⚡',
        '13d': '❄', '13n': '❄',
        '50d': '🌫', '50n': '🌫'
    };
    return icons[code] || '◌';
}

function showWeatherSettings() {
    const overlay = document.body.createDiv({ cls: 'komo-modal-overlay' });
    const modal = overlay.createDiv({ cls: 'komo-modal' });

    modal.createDiv({ cls: 'komo-modal-title', text: 'weather settings' });

    const form = modal.createDiv({ cls: 'komo-card-form' });

    const apiRow = form.createDiv({ cls: 'komo-form-row' });
    apiRow.createEl('label', { text: 'openweathermap api key' });
    const apiInput = apiRow.createEl('input', {
        cls: 'komo-modal-search',
        type: 'password',
        attr: { placeholder: 'your api key...', value: localStorage.getItem('komo-weather-api-key') || '' }
    });

    const cityRow = form.createDiv({ cls: 'komo-form-row' });
    cityRow.createEl('label', { text: 'city' });
    const cityInput = cityRow.createEl('input', {
        cls: 'komo-modal-search',
        attr: { placeholder: 'city name...', value: localStorage.getItem('komo-weather-city') || 'barcelona' }
    });

    const unitRow = form.createDiv({ cls: 'komo-form-row' });
    unitRow.createEl('label', { text: 'units' });
    const unitSelect = unitRow.createEl('select', { cls: 'komo-modal-search' });
    ['metric', 'imperial', 'kelvin'].forEach(u => {
        const opt = unitSelect.createEl('option', { text: u, value: u });
        if (u === (localStorage.getItem('komo-weather-units') || 'metric')) opt.selected = true;
    });

    const btns = modal.createDiv({ cls: 'komo-modal-btns' });
    const cancelBtn = btns.createEl('button', { cls: 'komo-modal-btn komo-btn-cancel', text: 'cancel' });
    const saveBtn = btns.createEl('button', { cls: 'komo-modal-btn komo-btn-save', text: 'save' });

    cancelBtn.addEventListener('click', () => overlay.remove());
    saveBtn.addEventListener('click', () => {
        localStorage.setItem('komo-weather-api-key', apiInput.value.trim());
        localStorage.setItem('komo-weather-city', cityInput.value.trim() || 'barcelona');
        localStorage.setItem('komo-weather-units', unitSelect.value);
        renderWeather();
        overlay.remove();
    });

    overlay.addEventListener('click', e => { if (e.target === overlay) overlay.remove(); });
}

renderWeather();

// ══════════════════════════════════════════════
//  CENTER — RELATED CARDS (BIG)
// ══════════════════════════════════════════════
const colC    = grid.createDiv({ cls: 'komo-col-center' });
const cardsCard = colC.createDiv({ cls: 'komo-card komo-cards-card' });

// Header with add button
const cardsHdr = cardsCard.createDiv({ cls: 'komo-cards-hdr' });
cardsHdr.createDiv({ cls: 'komo-label', text: 'collection' });

// Size control (persisted per-device) — resize all collection boxes live
const SIZE_KEY = 'komo-card-size';
let cardMin = parseInt(localStorage.getItem(SIZE_KEY) || '180', 10);
const applyCardSize = () => {
    cardMin = Math.max(120, Math.min(360, cardMin));
    cardsCard.style.setProperty('--komo-card-min', cardMin + 'px');
    localStorage.setItem(SIZE_KEY, String(cardMin));
};
const sizeCtl   = cardsHdr.createDiv({ cls: 'komo-size-ctl' });
const sizeMinus = sizeCtl.createDiv({ cls: 'komo-size-btn', text: '−' });
sizeCtl.createDiv({ cls: 'komo-size-lbl', text: 'size' });
const sizePlus  = sizeCtl.createDiv({ cls: 'komo-size-btn', text: '+' });
sizeMinus.addEventListener('click', () => { cardMin -= 20; applyCardSize(); });
sizePlus.addEventListener('click',  () => { cardMin += 20; applyCardSize(); });
applyCardSize();

const addCardBtn = cardsHdr.createDiv({ cls: 'komo-add-card-btn', text: '+ add' });
addCardBtn.addEventListener('click', showAddCardModal);

// Cards container
const cardsContainer = cardsCard.createDiv({ cls: 'komo-cards-container komo-cards-big' });

// ── Collection state: file-backed so it syncs (same method as Habits).
//    Seeded once with Films / TV Shows as normal, editable cards. ──
const CARDS_PATH = '.obsidian/collection.json';

async function loadCards() {
    let arr = null;
    try {
        if (await app.vault.adapter.exists(CARDS_PATH))
            arr = JSON.parse(await app.vault.adapter.read(CARDS_PATH));
    } catch (e) { arr = null; }
    if (Array.isArray(arr)) return arr;
    // First run — seed the two media shortcuts, then migrate any old localStorage cards
    let old = [];
    try { const o = JSON.parse(localStorage.getItem('komo-cards') || '[]'); if (Array.isArray(o)) old = o; } catch (e) {}
    return [
        { id: 1, title: 'Films',    subtitle: 'Movie posters', emoji: '🎬', image: '', link: 'Media/Films.md',    color: 'var(--color-pink)'   },
        { id: 2, title: 'TV Shows', subtitle: 'Show posters',  emoji: '📺', image: '', link: 'Media/TV Shows.md', color: 'var(--color-yellow)' },
        ...old
    ];
}

async function saveCards() {
    try { await app.vault.adapter.write(CARDS_PATH, JSON.stringify(cards, null, 2)); }
    catch (e) { new Notice('Could not save collection'); }
}

let cards = await loadCards();
await saveCards();  // persist the seed / migration on first run

// Get all available files for dropdown
function getAllFiles() {
    return app.vault.getMarkdownFiles()
        .map(f => ({ name: f.name, path: f.path }))
        .sort((a, b) => a.name.localeCompare(b.name));
}

// Build a single card DOM element
function buildCardEl(card, idx) {
    const cardEl = document.createElement('div');
    cardEl.className = 'komo-related-card komo-card-big';
    cardEl.style.borderColor = card.color || 'var(--komo-border)';
    cardEl.dataset.cardIdx = idx;

    const imgWrap = document.createElement('div');
    imgWrap.className = 'komo-card-img-wrap-big';
    if (card.image) {
        const img = document.createElement('img');
        img.className = 'komo-card-img-big';
        if (card.image.startsWith('http://') || card.image.startsWith('https://')) {
            img.src = card.image;
        } else {
            try { img.src = app.vault.adapter.getResourcePath(card.image); }
            catch(e) { img.src = card.image; }
        }
        img.onerror = () => { imgWrap.innerHTML = ''; imgWrap.textContent = card.emoji || '◻'; };
        imgWrap.appendChild(img);
    } else {
        imgWrap.textContent = card.emoji || '◻';
    }
    cardEl.appendChild(imgWrap);

    const content = document.createElement('div');
    content.className = 'komo-card-content-big';
    const titleEl2 = document.createElement('div');
    titleEl2.className = 'komo-card-title-big';
    titleEl2.textContent = card.title;
    content.appendChild(titleEl2);
    if (card.subtitle) {
        const subEl = document.createElement('div');
        subEl.className = 'komo-card-subtitle-big';
        subEl.textContent = card.subtitle;
        content.appendChild(subEl);
    }
    cardEl.appendChild(content);

    const actions = document.createElement('div');
    actions.className = 'komo-card-actions';
    const editBtn = document.createElement('div');
    editBtn.className = 'komo-card-action';
    editBtn.textContent = '✎';
    const delBtn2 = document.createElement('div');
    delBtn2.className = 'komo-card-action komo-card-del';
    delBtn2.textContent = '✕';
    actions.appendChild(editBtn);
    actions.appendChild(delBtn2);
    cardEl.appendChild(actions);

    editBtn.addEventListener('click', (e) => { e.stopPropagation(); editCard(idx); });
    delBtn2.addEventListener('click', (e) => { e.stopPropagation(); deleteCard(idx); });

    if (card.link) {
        cardEl.addEventListener('click', () => app.workspace.openLinkText(card.link, '', false));
        cardEl.style.cursor = 'pointer';
    }
    return cardEl;
}

// Full render — only called on first load
function renderCards() {
    cardsContainer.innerHTML = '';
    cards.forEach((card, idx) => cardsContainer.appendChild(buildCardEl(card, idx)));
}

// Surgical update — replaces only ONE card node, never touches others
function patchCard(idx) {
    if (!cardsContainer.isConnected) { renderCards(); return; }

    const existing = cardsContainer.querySelector(`[data-card-idx="${idx}"]`);
    if (existing) {
        const newEl = buildCardEl(cards[idx], idx);
        cardsContainer.replaceChild(newEl, existing);
    } else {
        // Card is new — append it and remove empty placeholder if present
        const empty = cardsContainer.querySelector('.komo-cards-empty');
        if (empty) empty.remove();
        cardsContainer.appendChild(buildCardEl(cards[idx], idx));
    }
    // Re-index all cards so their idx stays correct after any reorder
    Array.from(cardsContainer.querySelectorAll('.komo-related-card:not(.komo-pinned-card)')).forEach((el, i) => { el.dataset.cardIdx = i; });
}

function showAddCardModal() {
    const overlay = document.body.createDiv({ cls: 'komo-modal-overlay' });
    const modal = overlay.createDiv({ cls: 'komo-modal komo-card-modal' });

    modal.createDiv({ cls: 'komo-modal-title', text: 'create card' });

    const form = modal.createDiv({ cls: 'komo-card-form' });

    const titleRow = form.createDiv({ cls: 'komo-form-row' });
    titleRow.createEl('label', { text: 'title' });
    const titleInput = titleRow.createEl('input', {
        cls: 'komo-modal-search',
        attr: { placeholder: 'card name...', type: 'text' }
    });

    const subRow = form.createDiv({ cls: 'komo-form-row' });
    subRow.createEl('label', { text: 'subtitle (optional)' });
    const subInput = subRow.createEl('input', {
        cls: 'komo-modal-search',
        attr: { placeholder: 'description...', type: 'text' }
    });

    const emojiRow = form.createDiv({ cls: 'komo-form-row' });
    emojiRow.createEl('label', { text: 'emoji' });
    const emojiInput = emojiRow.createEl('input', {
        cls: 'komo-modal-search',
        attr: { placeholder: '🌸', type: 'text', maxlength: '2' }
    });

    const imgRow = form.createDiv({ cls: 'komo-form-row' });
    imgRow.createEl('label', { text: 'image path (optional)' });
    const imgInput = imgRow.createEl('input', {
        cls: 'komo-modal-search',
        attr: { placeholder: 'path/to/image.png or https://...', type: 'text' }
    });

    const linkRow = form.createDiv({ cls: 'komo-form-row' });
    linkRow.createEl('label', { text: 'link to note' });
    const linkSelect = linkRow.createEl('select', { cls: 'komo-modal-search' });
    linkSelect.createEl('option', { text: '-- no link --', value: '' });
    getAllFiles().forEach(f => linkSelect.createEl('option', { text: f.name, value: f.path }));

    const colorRow = form.createDiv({ cls: 'komo-form-row' });
    colorRow.createEl('label', { text: 'accent color' });
    const colorGrid = colorRow.createDiv({ cls: 'komo-color-grid' });
    const colors = ['#f5c2e7', '#cba6f7', '#89dceb', '#f9e2af', '#f38ba8', '#a6e3a1', '#fab387'];
    let selectedColor = colors[0];
    colors.forEach(c => {
        const colorDot = colorGrid.createDiv({ cls: 'komo-color-dot' });
        colorDot.style.background = c;
        if (c === selectedColor) colorDot.classList.add('active');
        colorDot.addEventListener('click', () => {
            colorGrid.querySelectorAll('.komo-color-dot').forEach(d => d.classList.remove('active'));
            colorDot.classList.add('active');
            selectedColor = c;
        });
    });

    const btns = modal.createDiv({ cls: 'komo-modal-btns' });
    const cancelBtn = btns.createEl('button', { cls: 'komo-modal-btn komo-btn-cancel', text: 'cancel' });
    const saveBtn = btns.createEl('button', { cls: 'komo-modal-btn komo-btn-save', text: 'create' });

    cancelBtn.addEventListener('click', () => overlay.remove());
    saveBtn.addEventListener('click', () => {
        const newCard = {
            id: Date.now(),
            title: titleInput.value.trim() || 'untitled',
            subtitle: subInput.value.trim(),
            emoji: emojiInput.value.trim(),
            image: imgInput.value.trim(),
            link: linkSelect.value,
            color: selectedColor
        };
        cards.push(newCard);
        saveCards();
        overlay.remove();
        patchCard(cards.length - 1);
    });

    titleInput.focus();
    overlay.addEventListener('click', e => { if (e.target === overlay) overlay.remove(); });
}

function editCard(idx) {
    const card = cards[idx];
    const overlay = document.body.createDiv({ cls: 'komo-modal-overlay' });
    const modal = overlay.createDiv({ cls: 'komo-modal komo-card-modal' });

    modal.createDiv({ cls: 'komo-modal-title', text: 'edit card' });

    const form = modal.createDiv({ cls: 'komo-card-form' });

    const titleRow = form.createDiv({ cls: 'komo-form-row' });
    titleRow.createEl('label', { text: 'title' });
    const titleInput = titleRow.createEl('input', {
        cls: 'komo-modal-search',
        attr: { placeholder: 'card name...', type: 'text', value: card.title }
    });

    const subRow = form.createDiv({ cls: 'komo-form-row' });
    subRow.createEl('label', { text: 'subtitle (optional)' });
    const subInput = subRow.createEl('input', {
        cls: 'komo-modal-search',
        attr: { placeholder: 'description...', type: 'text', value: card.subtitle || '' }
    });

    const emojiRow = form.createDiv({ cls: 'komo-form-row' });
    emojiRow.createEl('label', { text: 'emoji' });
    const emojiInput = emojiRow.createEl('input', {
        cls: 'komo-modal-search',
        attr: { placeholder: '🌸', type: 'text', maxlength: '2', value: card.emoji || '' }
    });

    const imgRow = form.createDiv({ cls: 'komo-form-row' });
    imgRow.createEl('label', { text: 'image path (optional)' });
    const imgInput = imgRow.createEl('input', {
        cls: 'komo-modal-search',
        attr: { placeholder: 'path/to/image.png or https://...', type: 'text', value: card.image || '' }
    });

    // File selector dropdown
    const linkRow = form.createDiv({ cls: 'komo-form-row' });
    linkRow.createEl('label', { text: 'link to note' });

    const linkSelect = linkRow.createEl('select', { cls: 'komo-modal-search' });
    linkSelect.createEl('option', { text: '-- no link --', value: '' });

    const allFiles = getAllFiles();
    allFiles.forEach(f => {
        const opt = linkSelect.createEl('option', { text: f.name, value: f.path });
        if (f.path === card.link) opt.selected = true;
    });

    const colorRow = form.createDiv({ cls: 'komo-form-row' });
    colorRow.createEl('label', { text: 'accent color' });
    const colorGrid = colorRow.createDiv({ cls: 'komo-color-grid' });
    const colors = ['#f5c2e7', '#cba6f7', '#89dceb', '#f9e2af', '#f38ba8', '#a6e3a1', '#fab387'];
    let selectedColor = card.color || colors[0];

    colors.forEach(c => {
        const colorDot = colorGrid.createDiv({ cls: 'komo-color-dot' });
        colorDot.style.background = c;
        if (c === selectedColor) colorDot.classList.add('active');
        colorDot.addEventListener('click', () => {
            colorGrid.querySelectorAll('.komo-color-dot').forEach(d => d.classList.remove('active'));
            colorDot.classList.add('active');
            selectedColor = c;
        });
    });

    const btns = modal.createDiv({ cls: 'komo-modal-btns' });
    const cancelBtn = btns.createEl('button', { cls: 'komo-modal-btn komo-btn-cancel', text: 'cancel' });
    const saveBtn = btns.createEl('button', { cls: 'komo-modal-btn komo-btn-save', text: 'save' });
    const delBtn = btns.createEl('button', { cls: 'komo-modal-btn komo-btn-delete', text: 'delete' });

    cancelBtn.addEventListener('click', () => overlay.remove());
    saveBtn.addEventListener('click', () => {
        cards[idx] = {
            ...card,
            title: titleInput.value.trim() || 'untitled',
            subtitle: subInput.value.trim(),
            emoji: emojiInput.value.trim(),
            image: imgInput.value.trim(),
            link: linkSelect.value,
            color: selectedColor
        };
        saveCards();
        overlay.remove();
        patchCard(idx);
    });
    delBtn.addEventListener('click', () => {
        // Remove the DOM node directly — no full re-render needed
        const el = cardsContainer.querySelector(`[data-card-idx="${idx}"]`);
        if (el) el.remove();
        cards.splice(idx, 1);
        saveCards();
        overlay.remove();
        // Re-index remaining cards
        Array.from(cardsContainer.querySelectorAll('.komo-related-card:not(.komo-pinned-card)')).forEach((e, i) => { e.dataset.cardIdx = i; });
        if (cards.length === 0) {
            const empty = cardsContainer.createDiv({ cls: 'komo-cards-empty' });
            empty.createEl('span', { cls: 'komo-empty-icon', text: '◻' });
            empty.createEl('span', { text: 'no cards yet — click +add to create one' });
        }
    });

    overlay.addEventListener('click', e => { if (e.target === overlay) overlay.remove(); });
}

function showConfirmModal(message, onConfirm, onCancel) {
    const overlay = document.body.createDiv({ cls: 'komo-modal-overlay' });
    const modal = overlay.createDiv({ cls: 'komo-modal komo-confirm-modal' });

    const content = modal.createDiv({ cls: 'komo-confirm-content' });
    content.createDiv({ cls: 'komo-confirm-icon', text: '⚠' });
    content.createDiv({ cls: 'komo-confirm-title', text: 'confirm deletion' });
    content.createDiv({ cls: 'komo-confirm-message', text: message });

    const btns = modal.createDiv({ cls: 'komo-modal-btns' });
    const cancelBtn = btns.createEl('button', { cls: 'komo-modal-btn komo-btn-cancel', text: 'cancel' });
    const confirmBtn = btns.createEl('button', { cls: 'komo-modal-btn komo-btn-delete', text: 'delete' });

    cancelBtn.addEventListener('click', () => {
        overlay.remove();
        if (onCancel) onCancel();
    });

    confirmBtn.addEventListener('click', () => {
        overlay.remove();
        if (onConfirm) onConfirm();
    });

    overlay.addEventListener('click', e => {
        if (e.target === overlay) {
            overlay.remove();
            if (onCancel) onCancel();
        }
    });
}

function deleteCard(idx) {
    const card = cards[idx];
    showConfirmModal(`delete "${card.title}"?`, () => {
        const el = cardsContainer.querySelector(`[data-card-idx="${idx}"]`);
        if (el) el.remove();
        cards.splice(idx, 1);
        saveCards();
        Array.from(cardsContainer.querySelectorAll('.komo-related-card:not(.komo-pinned-card)')).forEach((e, i) => { e.dataset.cardIdx = i; });
        if (cards.length === 0) {
            const empty = cardsContainer.createDiv({ cls: 'komo-cards-empty' });
            empty.createEl('span', { cls: 'komo-empty-icon', text: '◻' });
            empty.createEl('span', { text: 'no cards yet — click +add to create one' });
        }
    });
}

renderCards();

// ══════════════════════════════════════════════
//  RIGHT COLUMN — CALENDAR ONLY
// ══════════════════════════════════════════════
const colR = grid.createDiv({ cls: 'komo-col-right' });

// ── MINI CALENDAR (daily notes only) ─────
const calCard = colR.createDiv({ cls: 'komo-card komo-cal-card' });
calCard.createDiv({ cls: 'komo-label', text: 'calendar' });

let calY = new Date().getFullYear();
let calM = new Date().getMonth();
const calContainer = calCard.createDiv({ cls: 'komo-cal-container' });

// ── Note-activity index: a day gets a dot if any note was written that day. ──
// "Written" = the date in the note's title if it's a dated/daily note,
// otherwise the note's creation day (stat.ctime). Built once per render.
const ymd = dt => `${dt.getFullYear()}-${String(dt.getMonth()+1).padStart(2,'0')}-${String(dt.getDate()).padStart(2,'0')}`;

function dateFromName(bn) {
    let m = bn.match(/^(\d{4})-(\d{2})-(\d{2})$/);   // YYYY-MM-DD
    if (m) return `${m[1]}-${m[2]}-${m[3]}`;
    m = bn.match(/^(\d{2})-(\d{2})-(\d{2})$/);        // DD-MM-YY (daily-note format)
    if (m) return `20${m[3]}-${m[2]}-${m[1]}`;
    m = bn.match(/^(\d{2})-(\d{2})-(\d{4})$/);        // DD-MM-YYYY
    if (m) return `${m[3]}-${m[2]}-${m[1]}`;
    return null;
}

const noteIndex = {};   // 'YYYY-MM-DD' -> [{name, path, daily}]
const CAL_SKIP = ['Media/', 'Templates/', '.obsidian/'];  // ignore the Jellyfin dump etc.
for (const f of app.vault.getMarkdownFiles()) {
    if (f.path === 'Dashboard.md') continue;
    if (CAL_SKIP.some(s => f.path.startsWith(s))) continue;
    const named = dateFromName(f.basename);
    const key = named || ymd(new Date(f.stat.ctime));
    if (!noteIndex[key]) noteIndex[key] = [];
    noteIndex[key].push({ name: f.basename, path: f.path, daily: !!named });
}

// Get notes written on a given date
function getDailyNotesForDate(year, month, day) {
    const key = `${year}-${String(month+1).padStart(2,'0')}-${String(day).padStart(2,'0')}`;
    return noteIndex[key] || [];
}

function renderCal() {
    calContainer.innerHTML = '';

    // Navigation
    const nav  = calContainer.createDiv({ cls: 'komo-cal-nav' });
    const prev = nav.createDiv({ cls: 'komo-cal-nav-btn', text: '‹' });
    nav.createDiv({
        cls: 'komo-cal-month-label',
        text: new Date(calY, calM).toLocaleDateString('en-US', { year: 'numeric', month: 'long' })
    });
    const next = nav.createDiv({ cls: 'komo-cal-nav-btn', text: '›' });

    prev.addEventListener('click', () => { if(calM===0){calM=11;calY--;}else calM--; renderCal(); });
    next.addEventListener('click', () => { if(calM===11){calM=0;calY++;}else calM++; renderCal(); });

    // Day headers (English, Sun–Sat)
    const hdrG = calContainer.createDiv({ cls: 'komo-cal-grid' });
    ['Su','Mo','Tu','We','Th','Fr','Sa'].forEach(d => hdrG.createDiv({ cls: 'komo-cal-dh', text: d }));

    // Day cells
    const dayG     = calContainer.createDiv({ cls: 'komo-cal-grid' });
    const firstDay = new Date(calY, calM, 1).getDay();   // 0=Sun
    const dim      = new Date(calY, calM + 1, 0).getDate();
    const now      = new Date();

    for (let i = 0; i < firstDay; i++) {
        dayG.createDiv({ cls: 'komo-cal-cell empty' });
    }
    for (let d = 1; d <= dim; d++) {
        const isToday = d === now.getDate() && calM === now.getMonth() && calY === now.getFullYear();
        const cell    = dayG.createDiv({ cls: `komo-cal-cell ${isToday ? 'today' : ''}` });

        // Day number
        const dayNum = cell.createDiv({ cls: 'komo-cal-day-num', text: String(d) });

        // Check for daily notes on this day
        const notes = getDailyNotesForDate(calY, calM, d);

        // Add pink dot if there are daily notes
        if (notes.length > 0) {
            const dotContainer = cell.createDiv({ cls: 'komo-cal-dots' });
            const dotsToShow = Math.min(notes.length, 3);
            for (let i = 0; i < dotsToShow; i++) {
                dotContainer.createDiv({ cls: 'komo-cal-dot' });
            }
        }

        // Click handler - show notes popup
        cell.addEventListener('click', (e) => {
            if (notes.length > 0) {
                showNotesPopup(e, notes, d, calY, calM);
            } else {
                // Try to open daily note
                const ds = `${calY}-${String(calM+1).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
                const file = app.vault.getMarkdownFiles().find(f => f.basename === ds);
                if (file) {
                    app.workspace.openLinkText(file.path, '', false);
                } else if (isToday) {
                    try { app.commands.executeCommandById('daily-notes:goto-today'); }
                    catch(e) { new Notice(`No note for ${ds}`); }
                } else {
                    new Notice(`No daily note for ${ds}`);
                }
            }
        });
    }
}

function showNotesPopup(e, notes, day, year, month) {
    document.querySelector('.komo-cal-popup')?.remove();

    const popup = document.body.createDiv({ cls: 'komo-cal-popup' });
    popup.style.left = `${e.clientX}px`;
    popup.style.top = `${e.clientY + 20}px`;

    const header = popup.createDiv({ cls: 'komo-cal-popup-header' });
    const dateStr = `${year}-${String(month+1).padStart(2,'0')}-${String(day).padStart(2,'0')}`;
    header.textContent = dateStr;

    const list = popup.createDiv({ cls: 'komo-cal-popup-list' });
    if (notes.length > 3) {
        list.style.maxHeight = '120px';
        list.style.overflowY = 'auto';
    }

    notes.forEach(note => {
        const item = list.createDiv({ cls: 'komo-cal-popup-item' });
        item.createDiv({ cls: 'komo-cal-popup-dot' });
        item.createDiv({ cls: 'komo-cal-popup-name', text: note.name });
        item.addEventListener('click', () => {
            app.workspace.openLinkText(note.path, '', false);
            popup.remove();
        });
    });

    // Keep the popup inside the viewport — flip left/up instead of running off
    // the right edge on the Thu–Sat columns (or the bottom on the last rows).
    const M = 8;
    const rect = popup.getBoundingClientRect();
    let left = e.clientX;
    let top  = e.clientY + 20;
    if (left + rect.width + M > window.innerWidth)  left = Math.max(M, e.clientX - rect.width);
    if (top + rect.height + M > window.innerHeight) top  = Math.max(M, e.clientY - rect.height - 10);
    popup.style.left = `${left}px`;
    popup.style.top  = `${top}px`;

    setTimeout(() => {
        document.addEventListener('click', function closePopup(e) {
            if (!popup.contains(e.target)) {
                popup.remove();
                document.removeEventListener('click', closePopup);
            }
        });
    }, 10);
}

renderCal();

// ── POMODORO TIMER ──────────────────────────
const pomodoroCard = colR.createDiv({ cls: 'komo-card komo-pomodoro-card' });
pomodoroCard.createDiv({ cls: 'komo-label', text: 'pomodoro' });

const pomodoroContainer = pomodoroCard.createDiv({ cls: 'komo-pomodoro' });

// Load settings
let pomoTime = parseInt(localStorage.getItem('komo-pomo-time') || '25');
let pomoBreak = parseInt(localStorage.getItem('komo-pomo-break') || '5');
let pomoCount = parseInt(localStorage.getItem('komo-pomo-count') || '0');
let pomoState = localStorage.getItem('komo-pomo-state') || 'idle'; // idle, running, paused, break
let pomoRemaining = parseInt(localStorage.getItem('komo-pomo-remaining') || (pomoTime * 60));
let pomoInterval = null;

function formatTime(seconds) {
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

function renderPomodoro() {
    pomodoroContainer.innerHTML = '';

    // Timer display
    const timerDisplay = pomodoroContainer.createDiv({ cls: 'komo-pomo-timer' });
    timerDisplay.textContent = formatTime(pomoRemaining);

    // Progress bar
    const totalTime = pomoState === 'break' ? (pomoBreak * 60) : (pomoTime * 60);
    const progress = ((totalTime - pomoRemaining) / totalTime) * 100;
    const progressBar = pomodoroContainer.createDiv({ cls: 'komo-pomo-progress' });
    const progressFill = progressBar.createDiv({ cls: 'komo-pomo-progress-fill' });
    progressFill.style.width = `${progress}%`;
    progressFill.style.background = pomoState === 'break' ? 'var(--komo-green)' : 'var(--komo-sakura)';

    // Status
    const statusText = pomodoroContainer.createDiv({ cls: 'komo-pomo-status' });
    if (pomoState === 'idle') statusText.textContent = 'ready to focus';
    else if (pomoState === 'running') statusText.textContent = 'focusing...';
    else if (pomoState === 'paused') statusText.textContent = 'paused';
    else if (pomoState === 'break') statusText.textContent = 'break time';

    // Controls
    const controls = pomodoroContainer.createDiv({ cls: 'komo-pomo-controls' });

    const startBtn = controls.createDiv({ cls: 'komo-pomo-btn komo-pomo-btn-primary', text: pomoState === 'running' ? '⏸' : '▶' });
    const resetBtn = controls.createDiv({ cls: 'komo-pomo-btn', text: '↺' });
    const settingsBtn = controls.createDiv({ cls: 'komo-pomo-btn', text: '⚙' });

    // Today's count
    const countDisplay = pomodoroContainer.createDiv({ cls: 'komo-pomo-count' });
    countDisplay.textContent = `today: ${pomoCount} pomodoros`;

    startBtn.addEventListener('click', () => {
        if (pomoState === 'running') {
            pausePomodoro();
        } else {
            startPomodoro();
        }
        renderPomodoro();
    });

    resetBtn.addEventListener('click', () => {
        resetPomodoro();
        renderPomodoro();
    });

    settingsBtn.addEventListener('click', showPomodoroSettings);
}

function startPomodoro() {
    pomoState = pomoState === 'break' ? 'break' : 'running';
    localStorage.setItem('komo-pomo-state', pomoState);

    pomoInterval = setInterval(() => {
        pomoRemaining--;
        localStorage.setItem('komo-pomo-remaining', pomoRemaining);

        if (pomoRemaining <= 0) {
            completePomodoro();
        }
        renderPomodoro();
    }, 1000);
}

function pausePomodoro() {
    pomoState = 'paused';
    localStorage.setItem('komo-pomo-state', pomoState);
    if (pomoInterval) {
        clearInterval(pomoInterval);
        pomoInterval = null;
    }
}

function resetPomodoro() {
    if (pomoInterval) {
        clearInterval(pomoInterval);
        pomoInterval = null;
    }
    pomoState = 'idle';
    pomoRemaining = pomoTime * 60;
    localStorage.setItem('komo-pomo-state', pomoState);
    localStorage.setItem('komo-pomo-remaining', pomoRemaining);
}

function completePomodoro() {
    if (pomoInterval) {
        clearInterval(pomoInterval);
        pomoInterval = null;
    }

    if (pomoState === 'break') {
        // Break finished, back to work
        pomoState = 'idle';
        pomoRemaining = pomoTime * 60;
        new Notice('Break finished! Ready to focus?');
    } else {
        // Work finished, start break
        pomoCount++;
        localStorage.setItem('komo-pomo-count', pomoCount);
        pomoState = 'break';
        pomoRemaining = pomoBreak * 60;
        new Notice('Pomodoro complete! Take a break 🌸');
    }

    localStorage.setItem('komo-pomo-state', pomoState);
    localStorage.setItem('komo-pomo-remaining', pomoRemaining);
}

function showPomodoroSettings() {
    const overlay = document.body.createDiv({ cls: 'komo-modal-overlay' });
    const modal = overlay.createDiv({ cls: 'komo-modal' });

    modal.createDiv({ cls: 'komo-modal-title', text: 'pomodoro settings' });

    const form = modal.createDiv({ cls: 'komo-card-form' });

    const workRow = form.createDiv({ cls: 'komo-form-row' });
    workRow.createEl('label', { text: 'work time (minutes)' });
    const workInput = workRow.createEl('input', {
        cls: 'komo-modal-search',
        type: 'number',
        attr: { value: pomoTime, min: '1', max: '60' }
    });

    const breakRow = form.createDiv({ cls: 'komo-form-row' });
    breakRow.createEl('label', { text: 'break time (minutes)' });
    const breakInput = breakRow.createEl('input', {
        cls: 'komo-modal-search',
        type: 'number',
        attr: { value: pomoBreak, min: '1', max: '30' }
    });

    const btns = modal.createDiv({ cls: 'komo-modal-btns' });
    const cancelBtn = btns.createEl('button', { cls: 'komo-modal-btn komo-btn-cancel', text: 'cancel' });
    const saveBtn = btns.createEl('button', { cls: 'komo-modal-btn komo-btn-save', text: 'save' });

    cancelBtn.addEventListener('click', () => overlay.remove());
    saveBtn.addEventListener('click', () => {
        pomoTime = parseInt(workInput.value) || 25;
        pomoBreak = parseInt(breakInput.value) || 5;
        localStorage.setItem('komo-pomo-time', pomoTime);
        localStorage.setItem('komo-pomo-break', pomoBreak);

        // Reset if idle
        if (pomoState === 'idle' || pomoState === 'paused') {
            pomoRemaining = pomoTime * 60;
            localStorage.setItem('komo-pomo-remaining', pomoRemaining);
        }

        renderPomodoro();
        overlay.remove();
    });

    overlay.addEventListener('click', e => { if (e.target === overlay) overlay.remove(); });
}

// Resume if was running
if (pomoState === 'running') {
    startPomodoro();
}

renderPomodoro();
```

```dataviewjs
// Dashboard-Komorebi
// more dashboards → https://github.com/InlitX/Obsidian-Dashboard-Gallery

const wrap = dv.container.createDiv({ cls: 'komo-bottom-block' });

// Create bottom row with 2 columns
const bottomRow = wrap.createDiv({ cls: 'komo-bottom-row' });

// ══════════════════════════════════════════════
//  LEFT: HABIT TRACKER
// ══════════════════════════════════════════════
const habitCard = bottomRow.createDiv({ cls: 'komo-card komo-habit-card' });

// Header
const habitHdr = habitCard.createDiv({ cls: 'komo-habit-hdr' });
habitHdr.createDiv({ cls: 'komo-label', text: 'habits' });
const addBtn = habitHdr.createDiv({ cls: 'komo-add-habit-btn', text: '+ add' });

// ── File-backed state: syncs via the vault, Sunday-first, auto-clears weekly ──
const HABITS_PATH = '.obsidian/habits.json';
const DAYS = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
const blank = () => [false,false,false,false,false,false,false];

// week key = date (YYYY-MM-DD) of the Sunday that starts the current week
function weekKey(dt = new Date()) {
    const s = new Date(dt); s.setHours(0,0,0,0);
    s.setDate(s.getDate() - s.getDay());   // rewind to Sunday (getDay 0 = Sun)
    return `${s.getFullYear()}-${String(s.getMonth()+1).padStart(2,'0')}-${String(s.getDate()).padStart(2,'0')}`;
}

async function loadState() {
    let st = null;
    try {
        if (await app.vault.adapter.exists(HABITS_PATH))
            st = JSON.parse(await app.vault.adapter.read(HABITS_PATH));
    } catch (e) { st = null; }
    if (!st || typeof st !== 'object') st = { week: weekKey(), habits: [], checks: {} };
    if (!Array.isArray(st.habits)) st.habits = [];
    if (!st.checks || typeof st.checks !== 'object') st.checks = {};
    // one-time migration of habit names from the old localStorage tracker
    if (st.habits.length === 0) {
        try {
            const old = JSON.parse(localStorage.getItem('komo-habits') || '[]');
            if (Array.isArray(old) && old.length) st.habits = old.slice();
        } catch (e) {}
    }
    // weekly reset — wipe checks when a new week has started
    const wk = weekKey();
    if (st.week !== wk) { st.week = wk; st.checks = {}; }
    for (const h of st.habits)
        if (!Array.isArray(st.checks[h]) || st.checks[h].length !== 7) st.checks[h] = blank();
    return st;
}

async function saveState() {
    try { await app.vault.adapter.write(HABITS_PATH, JSON.stringify(state, null, 2)); }
    catch (e) { new Notice('Could not save habits'); }
}

let state = await loadState();
await saveState();  // persist any migration / weekly reset right away

const habitGrid = habitCard.createDiv({ cls: 'komo-habit-grid' });

// Bio bar
const bioRow     = habitCard.createDiv({ cls: 'komo-bio-row' });
const bioLbl     = bioRow.createDiv({ cls: 'komo-bio-lbl', text: '○ starting' });
const bioBarWrap = bioRow.createDiv({ cls: 'komo-bio-bar-wrap' });
const bioBar     = bioBarWrap.createDiv({ cls: 'komo-bio-bar' });
const bioPct     = bioRow.createDiv({ cls: 'komo-bio-pct', text: '0%' });

const pctOf = arr => Math.round(arr.filter(Boolean).length / 7 * 100);

function updateBioBar() {
    // Effort curve: average of √(each habit's weekly ratio). Showing up counts
    // for a lot, perfection has diminishing returns — fairer to a rotating routine
    // than flat grid-completion (which pooled everything to ~45%).
    const n = state.habits.length;
    let acc = 0;
    for (const h of state.habits) {
        const frac = state.checks[h].filter(Boolean).length / 7;   // 0..1 for this habit
        acc += Math.sqrt(frac);
    }
    const p = n ? Math.round(acc / n * 100) : 0;
    bioBar.style.width = `${p}%`;
    bioPct.textContent = `${p}%`;
    bioLbl.textContent = p >= 80 ? '🌸 consistent' : p >= 50 ? '⚡ building' : '○ starting';
}

// One habit column (original Komorebi logic): fixed compact grid; two of these
// sit side-by-side when there are >4 habits, which is what fills the width.
function buildHabitColumn(container, subset, offset, compact) {
    const rowCols = compact ? '120px repeat(7, 24px) 38px' : '130px repeat(7, 28px) 40px';
    const gap     = compact ? '3px'    : '4px';
    const dotSize = compact ? '15px'   : '20px';
    const nameFz  = compact ? '0.66rem': '0.73rem';
    const pctFz   = compact ? '0.58rem': '0.63rem';
    const dayFz   = compact ? '0.55rem': '0.58rem';
    const today   = new Date().getDay();  // 0 = Sun

    const hdr = container.createDiv({ cls: 'komo-week-hdr' });
    hdr.style.cssText = `display:grid;grid-template-columns:${rowCols};align-items:center;gap:${gap};padding:0 4px 6px;border-bottom:1px solid var(--komo-border);margin-bottom:4px;`;
    hdr.createDiv({ cls: 'komo-week-hdr-name' });
    DAYS.forEach(d => { const dh = hdr.createDiv({ cls: 'komo-week-hdr-day', text: d }); dh.style.fontSize = dayFz; dh.style.whiteSpace = 'nowrap'; });
    hdr.createDiv({ cls: 'komo-week-hdr-pct', text: '%' });

    subset.forEach((habit, localIdx) => {
        const idx = offset + localIdx;
        const row = container.createDiv({ cls: 'komo-habit-row' });
        row.style.cssText = `display:grid;grid-template-columns:${rowCols};align-items:center;gap:${gap};padding:3px 4px;border-radius:3px;`;

        const nameEl = row.createDiv({ cls: 'komo-habit-name', text: habit });
        nameEl.style.fontSize = nameFz;
        nameEl.style.overflow = 'hidden';
        nameEl.style.whiteSpace = 'nowrap';
        nameEl.style.textOverflow = 'ellipsis';
        nameEl.title = 'right-click to rename / delete';
        nameEl.addEventListener('contextmenu', e => { e.preventDefault(); showCtxMenu(e, idx); });

        for (let d = 0; d < 7; d++) {
            const dot = row.createDiv({ cls: `komo-dot ${state.checks[habit][d] ? 'on' : ''}` });
            if (compact) { dot.style.width = dotSize; dot.style.height = dotSize; }
            if (d === today) dot.style.boxShadow = '0 0 0 1px var(--komo-border-hover)';
            dot.addEventListener('click', async () => {
                state.checks[habit][d] = !state.checks[habit][d];
                dot.classList.toggle('on');
                const rp = row.querySelector('.komo-habit-pct');
                if (rp) rp.textContent = `${pctOf(state.checks[habit])}%`;
                updateBioBar();
                await saveState();
            });
        }
        const pctEl = row.createDiv({ cls: 'komo-habit-pct', text: `${pctOf(state.checks[habit])}%` });
        pctEl.style.fontSize = pctFz;
    });
}

function renderHabits() {
    habitGrid.innerHTML = '';
    const twoCol = state.habits.length > 4;
    if (twoCol) {
        habitGrid.style.cssText = 'display:grid;grid-template-columns:1fr 1fr;gap:0 18px;align-items:start;';
        const mid  = Math.ceil(state.habits.length / 2);
        const colA = habitGrid.createDiv();
        const colB = habitGrid.createDiv();
        colA.style.cssText = 'display:flex;flex-direction:column;gap:2px;min-width:0;overflow:hidden;';
        colB.style.cssText = 'display:flex;flex-direction:column;gap:2px;min-width:0;overflow:hidden;';
        buildHabitColumn(colA, state.habits.slice(0, mid), 0, true);
        buildHabitColumn(colB, state.habits.slice(mid), mid, true);
    } else {
        habitGrid.style.cssText = 'display:flex;flex-direction:column;gap:2px;';
        buildHabitColumn(habitGrid, state.habits, 0, false);
    }
    updateBioBar();
}

function showHabitModal({ title, defaultValue = '', confirmText, onConfirm }) {
    const overlay = document.body.createDiv({ cls: 'komo-modal-overlay' });
    const modal = overlay.createDiv({ cls: 'komo-modal' });
    modal.createDiv({ cls: 'komo-modal-title', text: title });
    const form = modal.createDiv({ cls: 'komo-card-form' });
    const row = form.createDiv({ cls: 'komo-form-row' });
    row.createEl('label', { text: 'name' });
    const input = row.createEl('input', { cls: 'komo-modal-search', attr: { placeholder: 'habit name...', type: 'text', value: defaultValue } });
    const btns = modal.createDiv({ cls: 'komo-modal-btns' });
    const cancelBtn = btns.createEl('button', { cls: 'komo-modal-btn komo-btn-cancel', text: 'cancel' });
    const saveBtn = btns.createEl('button', { cls: 'komo-modal-btn komo-btn-save', text: confirmText });
    const doSave = () => { const v = input.value.trim(); if (v) onConfirm(v); overlay.remove(); };
    cancelBtn.addEventListener('click', () => overlay.remove());
    saveBtn.addEventListener('click', doSave);
    input.addEventListener('keydown', e => { if (e.key === 'Enter') doSave(); });
    overlay.addEventListener('click', e => { if (e.target === overlay) overlay.remove(); });
    setTimeout(() => input.focus(), 30);
}

function showCtxMenu(e, idx) {
    document.querySelector('.komo-ctx-menu')?.remove();
    const menu = document.body.createDiv({ cls: 'komo-ctx-menu' });
    menu.style.cssText = `left:${e.clientX}px;top:${e.clientY}px;`;
    const rename = menu.createDiv({ cls: 'komo-ctx-item', text: '✎  rename' });
    rename.addEventListener('click', () => {
        menu.remove();
        showHabitModal({ title: 'rename habit', defaultValue: state.habits[idx], confirmText: 'rename',
            onConfirm: async (newName) => {
                const old = state.habits[idx];
                if (newName === old) return;
                state.checks[newName] = state.checks[old] || blank();
                delete state.checks[old];
                state.habits[idx] = newName;
                await saveState(); renderHabits();
            }});
    });
    const del = menu.createDiv({ cls: 'komo-ctx-item komo-ctx-del', text: '✕  remove' });
    del.addEventListener('click', async () => {
        delete state.checks[state.habits[idx]];
        state.habits.splice(idx, 1);
        await saveState(); renderHabits(); menu.remove();
    });
    document.addEventListener('click', () => menu.remove(), { once: true });
}

addBtn.addEventListener('click', () => {
    showHabitModal({ title: 'add habit', confirmText: 'add',
        onConfirm: async (name) => {
            if (!state.habits.includes(name)) { state.habits.push(name); state.checks[name] = blank(); }
            await saveState(); renderHabits();
        }});
});

renderHabits();

// ==============================================
//  RIGHT: RECENTLY EDITED
// ==============================================
const recentCard = bottomRow.createDiv({ cls: 'komo-card komo-recent-card' });
recentCard.createDiv({ cls: 'komo-label', text: 'recently edited' });
const recentList = recentCard.createDiv({ cls: 'komo-recent-list' });

function relTime(ms) {
    const s = Math.floor((Date.now() - ms) / 1000);
    if (s < 60) return 'now';
    const m = Math.floor(s / 60); if (m < 60) return m + 'm';
    const h = Math.floor(m / 60); if (h < 24) return h + 'h';
    const d = Math.floor(h / 24); if (d < 7) return d + 'd';
    return Math.floor(d / 7) + 'w';
}

function renderRecent() {
    recentList.innerHTML = '';
    const skip = ['Media/', 'Templates/', 'Journal/', '.obsidian/'];
    const files = app.vault.getMarkdownFiles()
        .filter(fl => fl.path !== 'Dashboard.md' && !skip.some(s => fl.path.startsWith(s)))
        .sort((a, b) => b.stat.mtime - a.stat.mtime)
        .slice(0, 9);
    if (files.length === 0) { recentList.createDiv({ cls: 'komo-recent-empty', text: 'nothing yet' }); return; }
    for (const fl of files) {
        const item = recentList.createDiv({ cls: 'komo-recent-item' });
        item.createDiv({ cls: 'komo-recent-name', text: fl.basename });
        item.createDiv({ cls: 'komo-recent-time', text: relTime(fl.stat.mtime) });
        item.addEventListener('click', () => app.workspace.openLinkText(fl.path, '', false));
    }
}

renderRecent();

```
