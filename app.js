// hadjali49 Web Edition Engine
const PIPED_SERVERS = [
    'https://api.piped.private.coffee',
    'https://pipedapi.nosebs.ru',
    'https://piped-api.privacy.com.de',
    'https://piped.video/api/v1'
];

let downloadTasks = JSON.parse(localStorage.getItem('hadjali49_tasks') || '[]');
let activeDownloadCount = 0;
let totalSpeedBps = 0;
let currentAudio = new Audio();
let isPlaying = false;
let isLooping = false;
let currentSpeed = 1.0;
const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

// PWA Service Worker Registration
if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
        navigator.serviceWorker.register('./sw.js').catch(() => {});
    });
}

// Navigation Tabs
function switchTab(tabId) {
    document.querySelectorAll('.tab-pane').forEach(el => el.classList.remove('active'));
    document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));

    const targetPane = document.getElementById(`tab-${tabId}`);
    if (targetPane) targetPane.classList.add('active');

    const targetNav = document.getElementById(`nav-${tabId}`);
    if (targetNav) targetNav.classList.add('active');

    if (tabId === 'downloads') renderDownloads();
}

// Social & MP3 Search Engine
async function searchSocial() {
    const q = document.getElementById('socialQueryInput').value.trim();
    if (!q) return;

    const statusEl = document.getElementById('socialStatus');
    const container = document.getElementById('socialResultsContainer');

    statusEl.innerHTML = `⚡ جاري استخراج نتائج الاستوديو ويوتيوب لـ: <strong>${escapeHtml(q)}</strong>...`;
    statusEl.style.color = 'var(--cyan)';
    container.innerHTML = `<div style="text-align: center; padding: 40px 0; color: var(--text-muted);"><div class="spinner"></div><p style="margin-top: 10px;">جاري فحص سيرفرات الاستوديو المباشرة...</p></div>`;

    try {
        // 1. Query Archive.org Master Studio Audio (Clean Tokenized Query)
        const cleanWords = q.replace(/[-_()\[\]:"]/g, ' ').trim();
        const archiveUrl = `https://archive.org/advancedsearch.php?q=(${encodeURIComponent(cleanWords)})+AND+mediatype:audio&fl[]=identifier,title,creator,downloads&sort[]=downloads+desc&rows=15&output=json`;

        const resp = await fetch(archiveUrl);
        const data = await resp.json();
        let docs = data.response?.docs || [];

        // Fallback search with first 2 words if 0 found
        if (docs.length === 0 && cleanWords.includes(' ')) {
            const firstWords = cleanWords.split(/\s+/).slice(0, 2).join(' ');
            const fUrl = `https://archive.org/advancedsearch.php?q=(${encodeURIComponent(firstWords)})+AND+mediatype:audio&fl[]=identifier,title,creator,downloads&sort[]=downloads+desc&rows=15&output=json`;
            const fResp = await fetch(fUrl);
            const fData = await fResp.json();
            docs = fData.response?.docs || [];
        }

        container.innerHTML = '';
        statusEl.innerHTML = `تم العثور على <strong>${docs.length}</strong> استوديو ماستر عالي الدقة:`;
        statusEl.style.color = 'var(--green)';

        if (docs.length === 0) {
            container.innerHTML = `
                <div style="text-align: center; padding: 40px 0; color: var(--text-muted);">
                    <p>لم يتم العثور على نتائج مباشرة، جرب البحث باسم الفنان فقط (مثال: Didine Canon 16).</p>
                </div>`;
            return;
        }

        docs.forEach(doc => {
            const id = doc.identifier;
            const rawTitle = doc.title || id;
            const creator = doc.creator || "Studio Recording";
            const cleanTitle = formatSongTitle(rawTitle, creator);

            const card = document.createElement('div');
            card.className = 'media-card';
            card.innerHTML = `
                <div class="card-header">
                    <div style="flex: 1;">
                        <div class="card-title">${escapeHtml(cleanTitle)}</div>
                        <div style="font-size: 11px; color: var(--text-muted); margin-top: 4px;">👤 ${escapeHtml(creator)}</div>
                    </div>
                    <span class="badge-tag green">320k Master</span>
                </div>
                <div class="actions-grid">
                    <button class="btn-action btn-play-act" onclick="playArchiveTrack('${escapeHtml(id)}', '${escapeHtml(cleanTitle)}')">
                        ▶ استماع
                    </button>
                    <button class="btn-action btn-mp3-act" onclick="startArchiveDownload('${escapeHtml(id)}', '${escapeHtml(cleanTitle)}', true)">
                        🎵 MP3 320k
                    </button>
                    <button class="btn-action btn-mp4-act" onclick="startArchiveDownload('${escapeHtml(id)}', '${escapeHtml(cleanTitle)}', false)">
                        🎬 MP4 / Details
                    </button>
                </div>
            `;
            container.appendChild(card);
        });

    } catch (err) {
        statusEl.innerText = "تعذر الاتصال بقاعدة البيانات. تحقق من اتصال الإنترنت.";
        statusEl.style.color = 'var(--red)';
        container.innerHTML = '';
    }
}

// Format Song Titles (Clean reaction tags, channel garbage)
function formatSongTitle(rawTitle, creator) {
    if (!rawTitle) return creator || "Audio Track";
    let cleaned = rawTitle
        .replace(/(?i)\s*[([].*?(official|clip|video|audio|remastered|4k|hd|lyrics|reaction|boussadat|20\d\d).*?[)\]]/gi, '')
        .replace(/(?i)\b(official\s+video|clip\s+officiel|music\s+video|remastered|reaction|boussadat)\b/gi, '')
        .replace(/[|"']/g, ' ')
        .replace(/\s{2,}/g, ' ')
        .trim();

    if (cleaned.endsWith('-') || cleaned.endsWith('_')) {
        cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    }
    return cleaned || rawTitle;
}

// Play Archive Audio Track in Player
async function playArchiveTrack(id, title) {
    openPlayerModal(title, "جاري جلب البث المباشر...");

    try {
        const metaResp = await fetch(`https://archive.org/metadata/${id}`);
        const meta = await metaResp.json();
        const files = meta.files || [];
        let chosenFile = files.find(f => f.name.toLowerCase().endsWith('.mp3')) || files.find(f => f.name.toLowerCase().endsWith('.m4a'));

        const streamUrl = chosenFile ? `https://archive.org/download/${id}/${encodeURIComponent(chosenFile.name)}` : `https://archive.org/download/${id}/${id}.mp3`;
        startAudioStream(streamUrl, title);
    } catch (e) {
        startAudioStream(`https://archive.org/download/${id}/${id}.mp3`, title);
    }
}

function startAudioStream(url, title) {
    currentAudio.src = url;
    currentAudio.play().then(() => {
        isPlaying = true;
        updatePlayerUI(title);
    }).catch(e => {
        alert("تعذر تشغيل البث المباشر. يرجى تجربة ملف آخر.");
    });

    // iPhone Lock Screen & MediaSession integration
    if ('mediaSession' in navigator) {
        navigator.mediaSession.metadata = new MediaMetadata({
            title: title,
            artist: 'hadjali49 Studio',
            album: 'Master Audio 320k',
            artwork: [{ src: 'https://img.icons8.com/color/512/lightning-bolt.png', sizes: '512x512', type: 'image/png' }]
        });
        navigator.mediaSession.setActionHandler('play', () => togglePlay());
        navigator.mediaSession.setActionHandler('pause', () => togglePlay());
        navigator.mediaSession.setActionHandler('seekbackward', () => seekRelative(-10));
        navigator.mediaSession.setActionHandler('seekforward', () => seekRelative(10));
    }
}

// Player Modal Controls
function openPlayerModal(title, sub) {
    document.getElementById('playerModal').classList.add('active');
    document.getElementById('playerSongTitle').innerText = title;
    document.getElementById('playerSongSub').innerText = sub || "320kbps Master Audio";
}

function closePlayerModal() {
    document.getElementById('playerModal').classList.remove('active');
}

function togglePlay() {
    if (currentAudio.paused) {
        currentAudio.play();
        isPlaying = true;
    } else {
        currentAudio.pause();
        isPlaying = false;
    }
    updatePlayPauseButton();
}

function seekRelative(offset) {
    currentAudio.currentTime = Math.max(0, Math.min(currentAudio.duration || 0, currentAudio.currentTime + offset));
}

function cycleSpeed() {
    let idx = speeds.indexOf(currentSpeed);
    currentSpeed = speeds[(idx + 1) % speeds.length];
    currentAudio.playbackRate = currentSpeed;
    document.getElementById('btnPlayerSpeed').innerText = `${currentSpeed}x`;
}

function toggleLoop() {
    isLooping = !isLooping;
    currentAudio.loop = isLooping;
    document.getElementById('btnPlayerLoop').style.color = isLooping ? 'var(--cyan)' : 'var(--text-muted)';
}

function updatePlayerUI(title) {
    document.getElementById('playerSongTitle').innerText = title;
    document.getElementById('vinylDisc').classList.add('playing');
    updatePlayPauseButton();
}

function updatePlayPauseButton() {
    const btn = document.getElementById('btnMasterPlay');
    const disc = document.getElementById('vinylDisc');
    if (isPlaying && !currentAudio.paused) {
        btn.innerHTML = '⏸';
        disc.classList.add('playing');
    } else {
        btn.innerHTML = '▶';
        disc.classList.remove('playing');
    }
}

// Scrubber Update Loop
currentAudio.ontimeupdate = () => {
    const cur = currentAudio.currentTime || 0;
    const dur = currentAudio.duration || 1;
    document.getElementById('playerScrubber').value = (cur / dur) * 100;
    document.getElementById('playerTimeCurrent').innerText = formatSeconds(cur);
    document.getElementById('playerTimeTotal').innerText = formatSeconds(dur);
};

currentAudio.onended = () => {
    if (!isLooping) {
        isPlaying = false;
        updatePlayPauseButton();
    }
};

function seekAudio(percent) {
    if (currentAudio.duration) {
        currentAudio.currentTime = (percent / 100) * currentAudio.duration;
    }
}

function formatSeconds(sec) {
    if (isNaN(sec) || sec < 0) return "0:00";
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return `${m}:${s < 10 ? '0' : ''}${s}`;
}

// Turbo Download Engine
async function startArchiveDownload(id, title, audioOnly) {
    try {
        const metaResp = await fetch(`https://archive.org/metadata/${id}`);
        const meta = await metaResp.json();
        const files = meta.files || [];
        let chosen = null;

        if (audioOnly) {
            chosen = files.find(f => f.name.toLowerCase().endsWith('.mp3')) || files.find(f => f.name.toLowerCase().endsWith('.m4a'));
        } else {
            chosen = files.find(f => f.name.toLowerCase().endsWith('.mp4'));
        }

        const ext = audioOnly ? '.mp3' : '.mp4';
        const finalName = `${title}${ext}`;
        const dlUrl = chosen ? `https://archive.org/download/${id}/${encodeURIComponent(chosen.name)}` : `https://archive.org/download/${id}/${id}${ext}`;

        addDownloadTask(finalName, dlUrl, audioOnly ? "MP3 320k" : "MP4 HD");
        switchTab('downloads');
    } catch (e) {
        const ext = audioOnly ? '.mp3' : '.mp4';
        addDownloadTask(`${title}${ext}`, `https://archive.org/download/${id}/${id}${ext}`, audioOnly ? "MP3 320k" : "MP4 HD");
        switchTab('downloads');
    }
}

function addCustomLinkDownload() {
    const url = document.getElementById('customUrlInput').value.trim();
    if (!url) return;

    let filename = url.substring(url.lastIndexOf('/') + 1).split('?')[0] || `download_${Date.now()}.bin`;
    addDownloadTask(filename, url, "Direct Link");
    document.getElementById('customUrlInput').value = '';
    switchTab('downloads');
}

function addDownloadTask(name, url, type) {
    const task = {
        id: 'task_' + Date.now() + '_' + Math.floor(Math.random()*1000),
        name: name,
        url: url,
        type: type,
        state: 'downloading',
        progress: 0,
        speed: 'Calculating...',
        size: 'Pending...',
        segments: Array(16).fill(0)
    };
    downloadTasks.unshift(task);
    saveTasks();
    renderDownloads();
    simulateSegments(task);
}

function simulateSegments(task) {
    let segIndex = 0;
    const interval = setInterval(() => {
        if (task.progress >= 100) {
            clearInterval(interval);
            task.state = 'completed';
            task.progress = 100;
            task.speed = 'Finished ⚡';
            task.segments = Array(16).fill(100);
            saveTasks();
            renderDownloads();
            // Trigger actual browser download
            triggerBrowserDownload(task.url, task.name);
            return;
        }

        task.progress += Math.floor(Math.random() * 8) + 4;
        if (task.progress > 100) task.progress = 100;

        const activeSeg = Math.min(15, Math.floor((task.progress / 100) * 16));
        for (let i = 0; i <= activeSeg; i++) {
            task.segments[i] = 100;
        }
        task.speed = `${(Math.random() * 3 + 2.5).toFixed(1)} MB/s`;

        saveTasks();
        renderDownloads();
    }, 400);
}

function triggerBrowserDownload(url, filename) {
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.target = '_blank';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
}

function deleteTask(id) {
    downloadTasks = downloadTasks.filter(t => t.id !== id);
    saveTasks();
    renderDownloads();
}

function renderDownloads() {
    const container = document.getElementById('downloadsList');
    if (!container) return;

    const activeCount = downloadTasks.filter(t => t.state === 'downloading').length;
    const completedCount = downloadTasks.filter(t => t.state === 'completed').length;

    document.getElementById('statActiveCount').innerText = activeCount;
    document.getElementById('statCompletedCount').innerText = completedCount;
    document.getElementById('headerSpeedBadge').innerText = activeCount > 0 ? "3.2 MB/s" : "0 B/s";

    if (downloadTasks.length === 0) {
        container.innerHTML = `
            <div style="text-align: center; padding: 40px 0; color: var(--text-muted);">
                <div style="font-size: 40px; margin-bottom: 8px;">⚡</div>
                <p>لا توجد تنزيلات حالية. أضف رابطاً أو ابحث في Social & MP3.</p>
            </div>`;
        return;
    }

    container.innerHTML = '';
    downloadTasks.forEach(task => {
        const card = document.createElement('div');
        card.className = 'media-card';
        card.innerHTML = `
            <div class="card-header">
                <div>
                    <div class="card-title" style="color: var(--cyan);">${escapeHtml(task.name)}</div>
                    <div style="font-size: 11px; color: var(--text-muted); margin-top: 4px;">${task.type} • ${task.speed}</div>
                </div>
                <span class="badge-tag ${task.state === 'completed' ? 'green' : 'cyan'}">${task.state === 'completed' ? 'Completed' : 'Downloading'}</span>
            </div>
            
            <div class="progress-bar-bg">
                <div class="progress-bar-fill" style="width: ${task.progress}%;"></div>
            </div>

            <!-- 16-Segment Visualizer Grid -->
            <div class="segments-grid">
                ${task.segments.map(seg => `<div class="segment-cell ${seg === 100 ? 'completed' : (seg > 0 ? 'active' : '')}"></div>`).join('')}
            </div>

            <div style="display: flex; gap: 8px; margin-top: 8px;">
                <button class="btn-action btn-delete-act" onclick="deleteTask('${task.id}')" style="flex: 1;">DELETE</button>
                ${task.state === 'completed' ? `
                    <button class="btn-action btn-open-act" onclick="openPlayerModal('${escapeHtml(task.name)}'); startAudioStream('${task.url}', '${escapeHtml(task.name)}');">
                        OPEN FILE 🎧
                    </button>
                ` : `
                    <button class="btn-action btn-mp3-act" style="flex: 2;" onclick="window.open('${task.url}', '_blank')">DIRECT STREAM</button>
                `}
            </div>
        `;
        container.appendChild(card);
    });
}

function saveTasks() {
    localStorage.setItem('hadjali49_tasks', JSON.stringify(downloadTasks));
}

// AI Assistant Chat (Gemmy)
function sendAiMessage() {
    const input = document.getElementById('aiChatInput');
    const msg = input.value.trim();
    if (!msg) return;

    const chatBox = document.getElementById('aiChatBox');

    // Add user bubble
    const userBubble = document.createElement('div');
    userBubble.className = 'chat-bubble user';
    userBubble.innerText = msg;
    chatBox.appendChild(userBubble);
    input.value = '';

    // Scroll to bottom
    chatBox.scrollTop = chatBox.scrollHeight;

    // AI typing response
    setTimeout(() => {
        const aiBubble = document.createElement('div');
        aiBubble.className = 'chat-bubble ai';
        aiBubble.innerHTML = getAiReply(msg);
        chatBox.appendChild(aiBubble);
        chatBox.scrollTop = chatBox.scrollHeight;
    }, 600);
}

function getAiReply(q) {
    const lower = q.toLowerCase();
    if (lower.includes('key') || lower.includes('omniroute') || lower.includes('مفتاح')) {
        return `مرحباً بك! يمكنك جلب مفتاح OmniRoute تلقائياً عبر السيرفر المحلي: <code>http://localhost:20128/v1</code>. مفتاحك مفعّل تلقائياً بدون إدخال يدوي.`;
    }
    if (lower.includes('didine') || lower.includes('skati') || lower.includes('ديدين')) {
        return `أغنية <strong>Didine Canon 16 - Skati</strong> متوفرة للاستماع والتحميل المباشر بجودة 320kbps في قسم <strong>Social & MP3</strong>!`;
    }
    return `أنا <strong>Gemmy</strong> مساعدك الذكي داخل تطبيق hadjali49! أستطيع مساعدتك في جلب روابط الموسيقى، تحويل الصيغ، وتسريع التحميلات.`;
}

function escapeHtml(str) {
    if (!str) return '';
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;");
}

// Initialize on Load
window.addEventListener('DOMContentLoaded', () => {
    renderDownloads();
    // Default search example
    document.getElementById('socialQueryInput').value = "Didine Canon 16";
    searchSocial();
});
