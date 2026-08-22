// backend/submarine-license-worker.js
// Cloudflare Worker: Full Custom Key Generator & Licensing Backend

const ADMIN_PIN = "8899";
const SALT = "SubMarine_Secure_2026_Salt";

let defaultKeys = [
  { code: "SUB-VIP", name: "TOBI VIP", active: true, createdAt: "2026-08-22" },
  { code: "SUB-TOBI-D705EE", name: "TOBI", active: true, createdAt: "2026-08-22" },
  { code: "SUB-ANDI-958D09", name: "ANDI", active: true, createdAt: "2026-08-22" },
  { code: "SUB-GHAZI-A5AF49", name: "GHAZI", active: true, createdAt: "2026-08-22" },
  { code: "SUB-BUDI-5AD569", name: "BUDI", active: true, createdAt: "2026-08-22" },
];

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin") || "*";

    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": origin,
          "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
      });
    }

    const corsHeaders = {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Content-Type": "application/json",
    };

    async function getKeys() {
      if (env && env.SUBMARINE_KV) {
        const val = await env.SUBMARINE_KV.get("license_keys");
        if (val) {
          try { return JSON.parse(val); } catch(_) {}
        }
      }
      return defaultKeys;
    }

    async function saveKeys(keys) {
      defaultKeys = keys;
      if (env && env.SUBMARINE_KV) {
        await env.SUBMARINE_KV.put("license_keys", JSON.stringify(keys));
      }
    }

    // ── 1. API: Verify License Key (Dipanggil oleh HP) ──
    if (url.pathname === "/api/verify") {
      const code = (url.searchParams.get("code") || "").trim().toUpperCase().replace(/\s+/g, '');
      if (!code) {
        return new Response(JSON.stringify({ valid: false, error: "Kode kunci tidak boleh kosong" }), {
          status: 400,
          headers: corsHeaders,
        });
      }

      const keys = await getKeys();
      const match = keys.find(k => k.code.toUpperCase() === code);

      if (!match) {
        return new Response(JSON.stringify({ valid: false, error: "Kode kunci tidak terdaftar di sistem" }), {
          status: 404,
          headers: corsHeaders,
        });
      }

      if (!match.active) {
        return new Response(JSON.stringify({ valid: true, active: false, name: match.name, error: "Izin akses telah dicabut oleh admin" }), {
          status: 403,
          headers: corsHeaders,
        });
      }

      return new Response(JSON.stringify({ valid: true, active: true, name: match.name, code: match.code }), {
        status: 200,
        headers: corsHeaders,
      });
    }

    // ── 2. API: Admin Endpoints ──
    if (url.pathname === "/api/keys") {
      if (request.method === "GET") {
        const keys = await getKeys();
        return new Response(JSON.stringify({ keys }), { headers: corsHeaders });
      }

      if (request.method === "POST") {
        const body = await request.json();
        const name = (body.name || "Pengguna").trim().toUpperCase();
        let code = (body.code || "").trim().toUpperCase().replace(/\s+/g, '');

        if (!code) {
          const rand = Math.random().toString(36).substring(2, 6).toUpperCase();
          code = `SUB-${name.substring(0, 4)}-${rand}`;
        }

        const keys = await getKeys();
        if (keys.some(k => k.code === code)) {
          return new Response(JSON.stringify({ error: "Kode kunci sudah ada sebelumnya" }), {
            status: 400,
            headers: corsHeaders,
          });
        }

        const newKey = {
          code,
          name,
          active: true,
          createdAt: new Date().toISOString().split("T")[0],
        };

        keys.unshift(newKey);
        await saveKeys(keys);
        return new Response(JSON.stringify({ success: true, key: newKey }), { headers: corsHeaders });
      }

      if (request.method === "DELETE") {
        const body = await request.json();
        const code = (body.code || "").trim().toUpperCase();
        let keys = await getKeys();
        keys = keys.filter(k => k.code !== code);
        await saveKeys(keys);
        return new Response(JSON.stringify({ success: true }), { headers: corsHeaders });
      }
    }

    // ── 3. Serve Web Admin Dashboard ──
    return new Response(dashboardHtml, {
      headers: { "Content-Type": "text/html; charset=utf-8" },
    });
  },
};

const dashboardHtml = `<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Submarine - Admin Licensing Dashboard</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700;800&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg-gradient: radial-gradient(circle at 10% 20%, #121622 0%, #080a10 90%);
      --card-bg: rgba(22, 28, 45, 0.85);
      --card-border: rgba(255, 255, 255, 0.1);
      --primary: #6366f1;
      --primary-glow: rgba(99, 102, 241, 0.35);
      --accent: #06b6d4;
      --success: #10b981;
      --danger: #ef4444;
      --text: #f3f4f6;
      --text-dim: #9ca3af;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Outfit', sans-serif;
      background: var(--bg-gradient);
      color: var(--text);
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 30px 20px;
    }
    .container { width: 100%; max-width: 1050px; }
    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 30px;
      padding-bottom: 20px;
      border-bottom: 1px solid var(--card-border);
    }
    .brand { display: flex; align-items: center; gap: 14px; }
    .brand-icon {
      font-size: 32px;
      background: linear-gradient(135deg, var(--primary), var(--accent));
      padding: 10px 14px;
      border-radius: 16px;
      box-shadow: 0 8px 25px var(--primary-glow);
    }
    .brand h1 { font-size: 26px; font-weight: 700; }
    .brand p { font-size: 13px; color: var(--text-dim); }
    
    .card {
      background: var(--card-bg);
      backdrop-filter: blur(16px);
      border: 1px solid var(--card-border);
      border-radius: 20px;
      padding: 26px;
      margin-bottom: 24px;
      box-shadow: 0 20px 40px rgba(0,0,0,0.4);
    }
    
    #loginSection { max-width: 420px; margin: 60px auto; text-align: center; }
    .input-group { margin-bottom: 18px; text-align: left; }
    .input-group label { display: block; font-size: 13px; color: var(--text-dim); margin-bottom: 6px; font-weight: 500; }
    input[type="text"], input[type="password"] {
      width: 100%;
      padding: 13px 16px;
      background: rgba(15, 19, 32, 0.8);
      border: 1px solid rgba(255,255,255,0.15);
      border-radius: 12px;
      color: #fff;
      font-size: 15px;
      outline: none;
      transition: 0.2s;
    }
    input:focus { border-color: var(--primary); box-shadow: 0 0 0 3px var(--primary-glow); }
    
    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      padding: 12px 20px;
      border-radius: 12px;
      font-weight: 600;
      font-size: 14px;
      border: none;
      cursor: pointer;
      transition: all 0.2s ease;
    }
    .btn-primary {
      background: linear-gradient(135deg, var(--primary), #4f46e5);
      color: #fff;
      box-shadow: 0 4px 15px var(--primary-glow);
    }
    .btn-primary:hover { transform: translateY(-2px); box-shadow: 0 6px 20px rgba(99,102,241,0.5); }
    .btn-sm { padding: 7px 14px; font-size: 12px; border-radius: 8px; }
    .btn-outline { background: transparent; border: 1px solid rgba(255,255,255,0.15); color: var(--text); }
    .btn-outline:hover { background: rgba(255,255,255,0.05); }
    
    .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 24px; }
    .stat-card {
      background: rgba(15, 20, 35, 0.6);
      border: 1px solid var(--card-border);
      border-radius: 14px;
      padding: 16px 20px;
    }
    .stat-card h3 { font-size: 12px; color: var(--text-dim); text-transform: uppercase; margin-bottom: 4px; }
    .stat-card .val { font-size: 26px; font-weight: 700; }
    
    .table-container { overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; text-align: left; }
    th { padding: 14px 16px; font-size: 12px; color: var(--text-dim); text-transform: uppercase; border-bottom: 1px solid var(--card-border); }
    td { padding: 16px; border-bottom: 1px solid rgba(255,255,255,0.04); font-size: 14px; vertical-align: middle; }
    tr:hover td { background: rgba(255,255,255,0.02); }
    
    .code-badge {
      font-family: 'JetBrains Mono', monospace;
      background: rgba(99, 102, 241, 0.15);
      border: 1px solid rgba(99, 102, 241, 0.3);
      color: #a5b4fc;
      padding: 5px 12px;
      border-radius: 8px;
      font-size: 14px;
      font-weight: 700;
      letter-spacing: 0.5px;
    }
    
    .badge-status {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 4px 10px;
      border-radius: 20px;
      font-size: 12px;
      font-weight: 600;
      background: rgba(16, 185, 129, 0.15);
      color: #34d399;
      border: 1px solid rgba(16, 185, 129, 0.3);
    }
    .dot { width: 7px; height: 7px; border-radius: 50%; background: #34d399; box-shadow: 0 0 8px #34d399; }
    
    .action-group { display: flex; gap: 6px; align-items: center; }
    
    .modal {
      position: fixed; inset: 0; background: rgba(0,0,0,0.75);
      backdrop-filter: blur(8px); display: none; align-items: center; justify-content: center; z-index: 999;
    }
    .modal-content {
      background: #151a2e; border: 1px solid var(--card-border);
      border-radius: 20px; width: 100%; max-width: 440px; padding: 26px;
    }
    .modal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="brand">
        <div class="brand-icon">🚢</div>
        <div>
          <h1>Submarine Control</h1>
          <p>Sistem Pengendalian Lisensi & Custom Key Generator</p>
        </div>
      </div>
      <div id="adminHeaderActions" style="display:none;">
        <button class="btn btn-outline btn-sm" onclick="logout()">🔒 Kunci Dashboard</button>
      </div>
    </header>

    <!-- LOGIN SECTION -->
    <div id="loginSection" class="card">
      <h2 style="margin-bottom:8px; font-size:22px;">Masukkan PIN Admin</h2>
      <p style="color:var(--text-dim); font-size:14px; margin-bottom:24px;">Masukkan PIN otorisasi (Default: <code>8899</code>) untuk mengelola kunci akses.</p>
      <div class="input-group">
        <label>PIN Admin</label>
        <input type="password" id="pinInput" placeholder="Ketik 8899..." autofocus onkeydown="if(event.key==='Enter') login()">
      </div>
      <button class="btn btn-primary" style="width:100%;" onclick="login()">Buka Dashboard 🚀</button>
      <p id="loginError" style="color:var(--danger); font-size:13px; margin-top:14px; display:none;"></p>
    </div>

    <!-- MAIN DASHBOARD -->
    <div id="dashboardSection" style="display:none;">
      <div class="stats-grid">
        <div class="stat-card">
          <h3>Total Kunci Terdaftar</h3>
          <div class="val" id="totalKeysCount">0</div>
        </div>
        <div class="stat-card">
          <h3>Kunci Aktif (Siap Pakai)</h3>
          <div class="val" id="activeKeysCount" style="color:#34d399;">0</div>
        </div>
        <div class="stat-card">
          <h3>Tipe Kunci</h3>
          <div class="val" style="color:#22d3ee; font-size:20px;">Custom & Crypto</div>
        </div>
      </div>

      <div class="card">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px; flex-wrap:wrap; gap:12px;">
          <div>
            <h2 style="font-size:18px; font-weight:700;">Daftar Kunci Akses Teman</h2>
            <p style="color:var(--text-dim); font-size:13px;">Kamu bisa membuat kode bebas sesukamu (Contoh: <code>SUB-VIP</code>, <code>SUB-ANDI-KEREN</code>, dll).</p>
          </div>
          <button class="btn btn-primary" onclick="openCreateModal()">+ Buat Kunci Baru</button>
        </div>

        <div class="table-container">
          <table>
            <thead>
              <tr>
                <th>Nama Panggilan</th>
                <th>Kode Akses</th>
                <th>Status Kunci</th>
                <th>Tanggal Dibuat</th>
                <th>Aksi</th>
              </tr>
            </thead>
            <tbody id="keysTableBody">
              <tr><td colspan="5" style="text-align:center; color:var(--text-dim);">Memuat data kunci...</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>

  <!-- MODAL CREATE KEY -->
  <div class="modal" id="createModal">
    <div class="modal-content">
      <div class="modal-header">
        <h3 style="font-size:18px;">+ Buat Kunci Akses Baru</h3>
        <button style="background:none; border:none; color:#fff; font-size:24px; cursor:pointer;" onclick="closeCreateModal()">&times;</button>
      </div>
      <div class="input-group">
        <label>Nama Panggilan Teman</label>
        <input type="text" id="newKeyName" placeholder="Contoh: ANDI, GHAZI, BUDI...">
      </div>
      <div class="input-group">
        <label>Kode Kunci Kustom (Bebas / Sesukamu)</label>
        <input type="text" id="newKeyCode" placeholder="Contoh: SUB-VIP, SUB-ANDI-123 (Kosongkan jika ingin auto)">
      </div>
      <div style="background:rgba(99,102,241,0.1); border:1px solid rgba(99,102,241,0.25); border-radius:10px; padding:12px; font-size:12px; color:#a5b4fc; line-height:1.4;">
        💡 Kamu bebas menentukan format kode kunci apa saja sesuai keinginanmu!
      </div>
      <div style="display:flex; justify-content:flex-end; gap:10px; margin-top:24px;">
        <button class="btn btn-outline" onclick="closeCreateModal()">Batal</button>
        <button class="btn btn-primary" onclick="submitCreateKey()">Simpan Kunci 🔑</button>
      </div>
    </div>
  </div>

  <script>
    var DEFAULT_PIN = "8899";

    function safeGet(k) {
      try { return localStorage.getItem(k); } catch(e) { return null; }
    }
    function safeSet(k, v) {
      try { localStorage.setItem(k, v); } catch(e) {}
    }

    var defaultKeysList = [
      { code: "SUB-VIP", name: "TOBI VIP", active: true, createdAt: "2026-08-22" },
      { code: "SUB-TOBI-D705EE", name: "TOBI", active: true, createdAt: "2026-08-22" },
      { code: "SUB-ANDI-958D09", name: "ANDI", active: true, createdAt: "2026-08-22" },
      { code: "SUB-GHAZI-A5AF49", name: "GHAZI", active: true, createdAt: "2026-08-22" },
      { code: "SUB-BUDI-5AD569", name: "BUDI", active: true, createdAt: "2026-08-22" }
    ];

    var stored = safeGet("sub_crypto_keys");
    var keysList = stored ? JSON.parse(stored) : defaultKeysList;

    window.onload = function() {
      var savedPin = safeGet("sub_admin_pin");
      if (savedPin === DEFAULT_PIN) {
        showDashboard();
      }
    };

    function login() {
      var pinEl = document.getElementById("pinInput");
      var errEl = document.getElementById("loginError");
      var val = (pinEl ? pinEl.value : "").trim();

      if (val === DEFAULT_PIN) {
        if (errEl) errEl.style.display = "none";
        safeSet("sub_admin_pin", val);
        showDashboard();
      } else {
        if (errEl) {
          errEl.innerHTML = "<strong>PIN Salah!</strong> Masukkan 4 digit PIN: <code>8899</code>";
          errEl.style.display = "block";
        }
      }
    }

    function showDashboard() {
      document.getElementById("loginSection").style.display = "none";
      document.getElementById("dashboardSection").style.display = "block";
      document.getElementById("adminHeaderActions").style.display = "block";
      renderTable();
    }

    function logout() {
      safeSet("sub_admin_pin", "");
      document.getElementById("dashboardSection").style.display = "none";
      document.getElementById("adminHeaderActions").style.display = "none";
      document.getElementById("loginSection").style.display = "block";
      var pinEl = document.getElementById("pinInput");
      if (pinEl) pinEl.value = "";
    }

    function saveLocal() {
      safeSet("sub_crypto_keys", JSON.stringify(keysList));
      renderTable();
    }

    function renderTable() {
      var tbody = document.getElementById("keysTableBody");
      if (!tbody) return;
      tbody.innerHTML = "";

      var activeCount = 0;

      if (keysList.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align:center; padding:30px; color:var(--text-dim);">Belum ada kunci dibuat. Klik tombol "+ Buat Kunci Baru" di atas.</td></tr>';
      } else {
        keysList.forEach(function(k) {
          if (k.active) activeCount++;

          var tr = document.createElement("tr");

          var tdName = document.createElement("td");
          tdName.innerHTML = "<strong>" + escapeHtml(k.name) + "</strong>";

          var tdCode = document.createElement("td");
          tdCode.innerHTML = '<span class="code-badge">' + escapeHtml(k.code) + '</span>';
          var copyIconBtn = document.createElement("button");
          copyIconBtn.style.cssText = "background:none; border:none; color:var(--accent); cursor:pointer; margin-left:8px; font-size:16px;";
          copyIconBtn.title = "Copy Kunci";
          copyIconBtn.innerText = "📋";
          copyIconBtn.onclick = function() { copyText(k.code); };
          tdCode.appendChild(copyIconBtn);

          var tdStatus = document.createElement("td");
          tdStatus.innerHTML = '<span class="badge-status"><span class="dot"></span> VALID & SIAP PAKAI</span>';

          var tdDate = document.createElement("td");
          tdDate.style.cssText = "color:var(--text-dim); font-size:13px;";
          tdDate.innerText = k.createdAt || "-";

          var tdAction = document.createElement("td");
          var actionGroup = document.createElement("div");
          actionGroup.className = "action-group";

          var copyBtn = document.createElement("button");
          copyBtn.className = "btn btn-primary btn-sm";
          copyBtn.innerText = "Salin Kunci 📋";
          copyBtn.onclick = function() { copyText(k.code); };

          var delBtn = document.createElement("button");
          delBtn.className = "btn btn-outline btn-sm";
          delBtn.style.color = "#f87171";
          delBtn.innerText = "🗑️";
          delBtn.onclick = function() { deleteKey(k.code); };

          actionGroup.appendChild(copyBtn);
          actionGroup.appendChild(delBtn);
          tdAction.appendChild(actionGroup);

          tr.appendChild(tdName);
          tr.appendChild(tdCode);
          tr.appendChild(tdStatus);
          tr.appendChild(tdDate);
          tr.appendChild(tdAction);

          tbody.appendChild(tr);
        });
      }

      var totalEl = document.getElementById("totalKeysCount");
      if (totalEl) totalEl.innerText = keysList.length;
      var activeEl = document.getElementById("activeKeysCount");
      if (activeEl) activeEl.innerText = activeCount;
    }

    function deleteKey(code) {
      if (!confirm("Hapus kunci " + code + "?")) return;
      keysList = keysList.filter(function(k) { return k.code !== code; });
      saveLocal();
    }

    function openCreateModal() {
      document.getElementById("newKeyName").value = "";
      document.getElementById("newKeyCode").value = "";
      document.getElementById("createModal").style.display = "flex";
    }

    function closeCreateModal() {
      document.getElementById("createModal").style.display = "none";
    }

    async function submitCreateKey() {
      var rawName = document.getElementById("newKeyName").value.trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
      var customCode = document.getElementById("newKeyCode").value.trim().toUpperCase().replace(/\\s+/g, "");

      if (!rawName) { alert("Masukkan nama teman!"); return; }

      var code = customCode;
      if (!code) {
        var rand = Math.random().toString(36).substring(2, 6).toUpperCase();
        code = "SUB-" + rawName + "-" + rand;
      }

      if (keysList.some(function(k) { return k.code === code; })) {
        alert("Kunci untuk nama ini sudah ada: " + code);
        return;
      }

      keysList.unshift({
        code: code,
        name: rawName,
        active: true,
        createdAt: new Date().toISOString().split("T")[0]
      });

      saveLocal();
      closeCreateModal();
      copyText(code);
    }

    function copyText(text) {
      navigator.clipboard.writeText(text);
      alert("✅ Kunci Akses: " + text + "\\nBerhasil disalin ke clipboard! Silakan kirimkan ke temanmu.");
    }

    function escapeHtml(str) {
      return (str || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    }
  </script>
</body>
</html>`;
