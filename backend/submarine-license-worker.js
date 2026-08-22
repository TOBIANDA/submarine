// backend/submarine-license-worker.js
// Cloudflare Worker: License Key Engine & Web Admin Dashboard for Submarine

const ADMIN_PIN = "8899"; // Ganti PIN admin ini sesuai keinginanmu

// Default in-memory seed keys jika belum ada KV
let defaultKeys = [
  { code: "SUB-VIP-MASTER", name: "Tobi Admin", active: true, createdAt: "2026-08-22" },
  { code: "SUB-DEMO-0001", name: "Andi Kampus", active: true, createdAt: "2026-08-22" },
  { code: "SUB-DEMO-0002", name: "Budi Rekan", active: false, createdAt: "2026-08-22" },
];

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin") || "*";

    // Handle CORS
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

    // Helper: get keys from KV or memory
    async function getKeys() {
      if (env && env.SUBMARINE_KV) {
        const val = await env.SUBMARINE_KV.get("license_keys");
        if (val) {
          try { return JSON.parse(val); } catch(_) {}
        }
      }
      return defaultKeys;
    }

    // Helper: save keys to KV
    async function saveKeys(keys) {
      defaultKeys = keys;
      if (env && env.SUBMARINE_KV) {
        await env.SUBMARINE_KV.put("license_keys", JSON.stringify(keys));
      }
    }

    // ── 1. API: Verify License Key (Dipanggil dari Aplikasi Submarine) ──
    if (url.pathname === "/api/verify") {
      const code = (url.searchParams.get("code") || "").trim().toUpperCase();
      if (!code) {
        return new Response(JSON.stringify({ valid: false, error: "Kode kunci tidak boleh kosong" }), {
          status: 400,
          headers: corsHeaders,
        });
      }

      const keys = await getKeys();
      const match = keys.find(k => k.code.toUpperCase() === code);

      if (!match) {
        return new Response(JSON.stringify({ valid: false, error: "Kunci akses tidak terdaftar di sistem" }), {
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

    // ── 2. API: Admin Endpoints (Dilindungi PIN) ──
    if (url.pathname.startsWith("/api/admin")) {
      const authHeader = request.headers.get("Authorization") || "";
      const pin = authHeader.replace("Bearer ", "").trim();
      const currentAdminPin = (env && env.ADMIN_PIN) ? env.ADMIN_PIN : ADMIN_PIN;

      if (pin !== currentAdminPin) {
        return new Response(JSON.stringify({ error: "PIN Admin tidak valid" }), {
          status: 401,
          headers: corsHeaders,
        });
      }

      // GET /api/admin/keys
      if (url.pathname === "/api/admin/keys" && request.method === "GET") {
        const keys = await getKeys();
        return new Response(JSON.stringify({ keys }), { headers: corsHeaders });
      }

      // POST /api/admin/keys (Create Key)
      if (url.pathname === "/api/admin/keys" && request.method === "POST") {
        const body = await request.json();
        const name = (body.name || "Pengguna").trim();
        let code = (body.code || "").trim().toUpperCase();
        
        if (!code) {
          const rand = Math.random().toString(36).substring(2, 6).toUpperCase();
          code = `SUB-${name.substring(0, 4).toUpperCase()}-${rand}`;
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

      // POST /api/admin/toggle (Toggle Active / Revoke)
      if (url.pathname === "/api/admin/toggle" && request.method === "POST") {
        const body = await request.json();
        const code = (body.code || "").trim().toUpperCase();

        const keys = await getKeys();
        const key = keys.find(k => k.code === code);
        if (!key) {
          return new Response(JSON.stringify({ error: "Kunci tidak ditemukan" }), {
            status: 404,
            headers: corsHeaders,
          });
        }

        key.active = !key.active;
        await saveKeys(keys);
        return new Response(JSON.stringify({ success: true, key }), { headers: corsHeaders });
      }

      // DELETE /api/admin/keys (Delete Key)
      if (url.pathname === "/api/admin/keys" && request.method === "DELETE") {
        const body = await request.json();
        const code = (body.code || "").trim().toUpperCase();

        let keys = await getKeys();
        keys = keys.filter(k => k.code !== code);
        await saveKeys(keys);
        return new Response(JSON.stringify({ success: true }), { headers: corsHeaders });
      }
    }

    // ── 3. Web Admin Dashboard (HTML/CSS/JS) ──
    return new Response(renderAdminDashboardHtml(), {
      headers: { "Content-Type": "text/html; charset=utf-8" },
    });
  },
};

function renderAdminDashboardHtml() {
  return `<!DOCTYPE html>
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
      --bg-gradient: radial-gradient(circle at 10% 20%, rgba(18, 22, 34, 1) 0%, rgba(8, 10, 16, 1) 90%);
      --card-bg: rgba(22, 28, 45, 0.75);
      --card-border: rgba(255, 255, 255, 0.08);
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
    .container { width: 100%; max-width: 1000px; }
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
    
    /* Login Box */
    #loginSection { max-width: 420px; margin: 60px auto; text-align: center; }
    .input-group { margin-bottom: 18px; text-align: left; }
    .input-group label { display: block; font-size: 13px; color: var(--text-dim); margin-bottom: 6px; font-weight: 500; }
    input[type="text"], input[type="password"] {
      width: 100%;
      padding: 13px 16px;
      background: rgba(15, 19, 32, 0.8);
      border: 1px solid rgba(255,255,255,0.12);
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
      padding: 12px 22px;
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
    .btn-danger { background: rgba(239, 68, 68, 0.15); color: #f87171; border: 1px solid rgba(239, 68, 68, 0.3); }
    .btn-danger:hover { background: rgba(239, 68, 68, 0.3); }
    
    /* Stats & Controls */
    .controls { display: flex; gap: 14px; flex-wrap: wrap; margin-bottom: 20px; }
    .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 24px; }
    .stat-card {
      background: rgba(15, 20, 35, 0.6);
      border: 1px solid var(--card-border);
      border-radius: 14px;
      padding: 16px 20px;
    }
    .stat-card h3 { font-size: 12px; color: var(--text-dim); text-transform: uppercase; margin-bottom: 4px; }
    .stat-card .val { font-size: 26px; font-weight: 700; }
    
    /* Table */
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
      padding: 4px 10px;
      border-radius: 6px;
      font-size: 13px;
      font-weight: 600;
    }
    
    .badge-status {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 4px 10px;
      border-radius: 20px;
      font-size: 12px;
      font-weight: 600;
    }
    .badge-active { background: rgba(16, 185, 129, 0.15); color: #34d399; border: 1px solid rgba(16, 185, 129, 0.3); }
    .badge-revoked { background: rgba(239, 68, 68, 0.15); color: #f87171; border: 1px solid rgba(239, 68, 68, 0.3); }
    .dot { width: 7px; height: 7px; border-radius: 50%; }
    .badge-active .dot { background: #34d399; box-shadow: 0 0 8px #34d399; }
    .badge-revoked .dot { background: #f87171; }
    
    .action-group { display: flex; gap: 8px; align-items: center; }
    
    /* Modal */
    .modal {
      position: fixed; inset: 0; background: rgba(0,0,0,0.7);
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
          <p>Sistem Pengendalian Lisensi & Izin Akses Pengguna</p>
        </div>
      </div>
      <div id="adminHeaderActions" style="display:none;">
        <button class="btn btn-outline btn-sm" onclick="logout()">🔒 Kunci Dashboard</button>
      </div>
    </header>

    <!-- 1. LOGIN PIN SCREEN -->
    <div id="loginSection" class="card">
      <h2 style="margin-bottom:8px; font-size:22px;">Masukkan PIN Admin</h2>
      <p style="color:var(--text-dim); font-size:14px; margin-bottom:24px;">Masukkan PIN otorisasi untuk mengelola izin akses Submarine.</p>
      <div class="input-group">
        <label>PIN Admin</label>
        <input type="password" id="pinInput" placeholder="Masukkan 4-6 digit PIN..." onkeydown="if(event.key==='Enter') login()">
      </div>
      <button class="btn btn-primary" style="width:100%;" onclick="login()">Buka Dashboard 🚀</button>
      <p id="loginError" style="color:var(--danger); font-size:13px; margin-top:12px; display:none;"></p>
    </div>

    <!-- 2. MAIN DASHBOARD SCREEN -->
    <div id="dashboardSection" style="display:none;">
      <!-- Stats -->
      <div class="stats-grid">
        <div class="stat-card">
          <h3>Total Kunci Terdaftar</h3>
          <div class="val" id="totalKeysCount">0</div>
        </div>
        <div class="stat-card">
          <h3>Akses Aktif</h3>
          <div class="val" id="activeKeysCount" style="color:#34d399;">0</div>
        </div>
        <div class="stat-card">
          <h3>Akses Dicabut</h3>
          <div class="val" id="revokedKeysCount" style="color:#f87171;">0</div>
        </div>
      </div>

      <!-- Controls & Table -->
      <div class="card">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px; flex-wrap:wrap; gap:12px;">
          <div>
            <h2 style="font-size:18px; font-weight:700;">Daftar Kunci & Izin Akses Teman</h2>
            <p style="color:var(--text-dim); font-size:13px;">Kelola siapa saja yang boleh membuka aplikasi Submarine secara real-time.</p>
          </div>
          <button class="btn btn-primary" onclick="openCreateModal()">+ Buat Kunci Baru</button>
        </div>

        <div class="table-container">
          <table>
            <thead>
              <tr>
                <th>Nama Panggilan</th>
                <th>Kode Akses</th>
                <th>Status Izin</th>
                <th>Tanggal Buat</th>
                <th>Aksi Saklar</th>
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

  <!-- MODAL: BUAT KUNCI BARU -->
  <div class="modal" id="createModal">
    <div class="modal-content">
      <div class="modal-header">
        <h3 style="font-size:18px;">+ Tambah Kunci Akses Baru</h3>
        <button style="background:none; border:none; color:#fff; font-size:20px; cursor:pointer;" onclick="closeCreateModal()">&times;</button>
      </div>
      <div class="input-group">
        <label>Nama Panggilan Teman</label>
        <input type="text" id="newKeyName" placeholder="Contoh: Budi, Ghazi, Andi...">
      </div>
      <div class="input-group">
        <label>Kode Kunci Kustom (Opsional)</label>
        <input type="text" id="newKeyCode" placeholder="Biarkan kosong untuk auto-generate (SUB-XXXX-YYYY)">
      </div>
      <div style="display:flex; justify-content:flex-end; gap:10px; margin-top:24px;">
        <button class="btn btn-outline" onclick="closeCreateModal()">Batal</button>
        <button class="btn btn-primary" onclick="submitCreateKey()">Buat Kunci 🔑</button>
      </div>
    </div>
  </div>

  <script>
    let adminPin = localStorage.getItem("sub_admin_pin") || "";
    let keysList = [];

    window.onload = () => {
      if (adminPin) {
        fetchKeys();
      }
    };

    function login() {
      const pin = document.getElementById("pinInput").value.trim();
      if (!pin) return;
      adminPin = pin;
      fetchKeys(true);
    }

    function logout() {
      adminPin = "";
      localStorage.removeItem("sub_admin_pin");
      document.getElementById("dashboardSection").style.display = "none";
      document.getElementById("adminHeaderActions").style.display = "none";
      document.getElementById("loginSection").style.display = "block";
      document.getElementById("pinInput").value = "";
    }

    async function fetchKeys(isFromLogin = false) {
      try {
        const res = await fetch("/api/admin/keys", {
          headers: { "Authorization": "Bearer " + adminPin }
        });
        if (res.status === 401) {
          if (isFromLogin) {
            document.getElementById("loginError").innerText = "PIN Salah! Silakan coba lagi.";
            document.getElementById("loginError").style.display = "block";
          } else {
            logout();
          }
          return;
        }

        const data = await res.json();
        keysList = data.keys || [];
        localStorage.setItem("sub_admin_pin", adminPin);

        document.getElementById("loginSection").style.display = "none";
        document.getElementById("dashboardSection").style.display = "block";
        document.getElementById("adminHeaderActions").style.display = "block";
        renderTable();
      } catch (err) {
        alert("Gagal terhubung ke server: " + err.message);
      }
    }

    function renderTable() {
      const tbody = document.getElementById("keysTableBody");
      tbody.innerHTML = "";

      let activeCount = 0;
      let revokedCount = 0;

      if (keysList.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align:center; padding:30px; color:var(--text-dim);">Belum ada kunci dibuat. Klik tombol "+ Buat Kunci Baru" di atas.</td></tr>';
      } else {
        keysList.forEach(k => {
          if (k.active) activeCount++; else revokedCount++;
          const tr = document.createElement("tr");

          const statusBadge = k.active 
            ? '<span class="badge-status badge-active"><span class="dot"></span> AKTIF (BISA AKSES)</span>'
            : '<span class="badge-status badge-revoked"><span class="dot"></span> DICABUT (TERKUNCI)</span>';

          const toggleBtn = k.active
            ? \`<button class="btn btn-danger btn-sm" onclick="toggleKey('\${k.code}')">🛑 Cabut Izin</button>\`
            : \`<button class="btn btn-primary btn-sm" style="background:#10b981;" onclick="toggleKey('\${k.code}')">✅ Hidupkan Izin</button>\`;

          tr.innerHTML = \`
            <td><strong>\${escapeHtml(k.name)}</strong></td>
            <td>
              <span class="code-badge">\${escapeHtml(k.code)}</span>
              <button style="background:none; border:none; color:var(--accent); cursor:pointer; margin-left:6px;" title="Copy Kunci" onclick="copyText('\${k.code}')">📋</button>
            </td>
            <td>\${statusBadge}</td>
            <td style="color:var(--text-dim); font-size:13px;">\${k.createdAt || '-'}</td>
            <td>
              <div class="action-group">
                \${toggleBtn}
                <button class="btn btn-outline btn-sm" style="color:#f87171;" title="Hapus Permanen" onclick="deleteKey('\${k.code}')">🗑️</button>
              </div>
            </td>
          \`;
          tbody.appendChild(tr);
        });
      }

      document.getElementById("totalKeysCount").innerText = keysList.length;
      document.getElementById("activeKeysCount").innerText = activeCount;
      document.getElementById("revokedKeysCount").innerText = revokedCount;
    }

    async function toggleKey(code) {
      try {
        const res = await fetch("/api/admin/toggle", {
          method: "POST",
          headers: {
            "Authorization": "Bearer " + adminPin,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ code })
        });
        if (res.ok) fetchKeys();
      } catch(e) { alert("Gagal toggle status: " + e.message); }
    }

    async function deleteKey(code) {
      if (!confirm("Hapus kunci " + code + " secara permanen?")) return;
      try {
        const res = await fetch("/api/admin/keys", {
          method: "DELETE",
          headers: {
            "Authorization": "Bearer " + adminPin,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ code })
        });
        if (res.ok) fetchKeys();
      } catch(e) { alert("Gagal menghapus: " + e.message); }
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
      const name = document.getElementById("newKeyName").value.trim();
      const code = document.getElementById("newKeyCode").value.trim();
      if (!name) { alert("Masukkan nama teman!"); return; }

      try {
        const res = await fetch("/api/admin/keys", {
          method: "POST",
          headers: {
            "Authorization": "Bearer " + adminPin,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ name, code })
        });
        const data = await res.json();
        if (res.ok) {
          closeCreateModal();
          fetchKeys();
        } else {
          alert(data.error || "Gagal membuat kunci");
        }
      } catch(e) { alert("Error: " + e.message); }
    }

    function copyText(text) {
      navigator.clipboard.writeText(text);
      alert("Kode kunci " + text + " berhasil disalin ke clipboard!");
    }

    function escapeHtml(str) {
      return (str || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    }
  </script>
</body>
</html>`;
}
