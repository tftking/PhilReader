import SwiftUI

/// Library ▸ Web Server: shows the address to open on a computer and the files received.
struct WebServerView: View {
    @StateObject private var server = WebServer()
    @State private var copied = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    Image(systemName: "wifi")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 84, height: 84)
                        .background(Color.accentColor.opacity(0.12), in: Circle())
                    Text("Upload from Your Computer")
                        .font(.title3.bold())
                    status
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .multilineTextAlignment(.center)
            } footer: {
                Text("Your computer must be on the same Wi-Fi network. Keep PhilReader open on this screen while files upload.")
            }

            if !server.uploads.isEmpty {
                Section("Received") {
                    ForEach(server.uploads) { upload in
                        UploadRow(upload: upload)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Web Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if server.state == .running || server.state == .starting {
                    Button("Stop") { server.stop() }
                } else {
                    Button("Start") { server.start() }
                }
            }
        }
        .onAppear {
            server.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            server.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    @ViewBuilder
    private var status: some View {
        switch server.state {
        case .running:
            if let address = server.address {
                Text("In a browser on your computer, go to")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    UIPasteboard.general.string = address
                    withAnimation { copied = true }
                } label: {
                    HStack(spacing: 8) {
                        Text(address)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityHint("Copies the address")
            } else {
                Text("Connect to Wi-Fi to upload from a computer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .starting:
            ProgressView()
        case .stopped:
            Text("The server is off.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
        }
    }
}

private struct UploadRow: View {
    let upload: WebServer.Upload

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 19))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(upload.name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch upload.status {
            case .receiving, .importing:
                ProgressView()
            case .imported:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
        }
    }

    private var detail: String {
        switch upload.status {
        case .receiving: return "Receiving…"
        case .importing: return "Importing…"
        case .imported: return "Added to your library"
        case .failed(let message): return message
        }
    }
}

/// The page a computer's browser sees: drop files or choose them, then watch them upload.
enum WebServerPage {
    static let html = #"""
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>PhilReader</title>
    <style>
      :root { color-scheme: light dark; --accent: #007aff; --bg: #f2f2f7; --card: #fff; --text: #1c1c1e; --muted: #6e6e73; --line: #d1d1d6; }
      @media (prefers-color-scheme: dark) { :root { --accent: #0a84ff; --bg: #000; --card: #1c1c1e; --text: #f2f2f7; --muted: #98989f; --line: #38383a; } }
      * { box-sizing: border-box; }
      body { margin: 0; font: 17px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; background: var(--bg); color: var(--text); }
      main { max-width: 640px; margin: 0 auto; padding: 48px 20px; }
      header { display: flex; align-items: center; gap: 14px; margin-bottom: 28px; }
      .glyph { width: 52px; height: 52px; border-radius: 13px; background: linear-gradient(145deg, #3d8bff, #0051d5); display: grid; place-items: center; color: #fff; font-weight: 800; font-size: 24px; box-shadow: 0 6px 18px rgba(0,90,255,.3); }
      h1 { font-size: 28px; margin: 0; letter-spacing: -.02em; }
      header p { margin: 2px 0 0; color: var(--muted); font-size: 15px; }
      #drop { display: block; border: 2px dashed var(--line); border-radius: 20px; background: var(--card); padding: 44px 24px; text-align: center; cursor: pointer; transition: border-color .15s, background .15s; }
      #drop.over { border-color: var(--accent); background: color-mix(in srgb, var(--accent) 8%, var(--card)); }
      #drop strong { display: block; font-size: 20px; margin-bottom: 6px; }
      #drop span { color: var(--muted); font-size: 15px; }
      #drop .button { display: inline-block; margin-top: 18px; background: var(--accent); color: #fff; border-radius: 999px; padding: 10px 22px; font-weight: 600; }
      input[type=file] { display: none; }
      ul { list-style: none; margin: 24px 0 0; padding: 0; background: var(--card); border-radius: 14px; overflow: hidden; }
      ul:empty { display: none; }
      li { padding: 14px 16px; border-top: 1px solid var(--line); }
      li:first-child { border-top: 0; }
      .row { display: flex; justify-content: space-between; gap: 12px; }
      .name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 500; }
      .state { color: var(--muted); font-size: 15px; white-space: nowrap; }
      .state.ok { color: #34c759; } .state.bad { color: #ff9f0a; }
      .bar { height: 4px; border-radius: 2px; background: var(--line); margin-top: 10px; overflow: hidden; }
      .bar div { height: 100%; width: 0; background: var(--accent); transition: width .1s; }
      footer { margin-top: 28px; color: var(--muted); font-size: 13px; text-align: center; }
    </style>
    </head>
    <body>
    <main>
      <header>
        <div class="glyph">P</div>
        <div><h1>PhilReader</h1><p>Send comics to your iPhone or iPad</p></div>
      </header>
      <label id="drop">
        <strong>Drop comics here</strong>
        <span>CBZ, CBR, CB7, PDF and EPUB</span><br>
        <span class="button">Choose Files…</span>
        <input id="picker" type="file" multiple accept=".cbz,.cbr,.cb7,.zip,.rar,.7z,.pdf,.epub">
      </label>
      <ul id="list"></ul>
      <footer>Keep PhilReader open on the Web Server screen until uploads finish.</footer>
    </main>
    <script>
      const drop = document.getElementById('drop');
      const picker = document.getElementById('picker');
      const list = document.getElementById('list');
      const queue = [];
      let busy = false;

      function add(files) {
        for (const file of files) {
          const li = document.createElement('li');
          li.innerHTML = '<div class="row"><span class="name"></span><span class="state">Waiting</span></div><div class="bar"><div></div></div>';
          li.querySelector('.name').textContent = file.name;
          list.appendChild(li);
          queue.push({ file, li });
        }
        next();
      }

      function next() {
        if (busy || queue.length === 0) return;
        busy = true;
        const { file, li } = queue.shift();
        const state = li.querySelector('.state');
        const bar = li.querySelector('.bar div');
        const xhr = new XMLHttpRequest();
        xhr.open('POST', '/upload');
        xhr.setRequestHeader('X-File-Name', encodeURIComponent(file.name));
        xhr.upload.onprogress = (e) => {
          if (!e.lengthComputable) return;
          const percent = Math.round(e.loaded / e.total * 100);
          bar.style.width = percent + '%';
          state.textContent = percent < 100 ? percent + '%' : 'Importing…';
        };
        xhr.onload = () => {
          let message = 'Failed';
          try { message = JSON.parse(xhr.responseText).message || message; } catch (_) {}
          const ok = xhr.status === 200;
          state.textContent = ok ? 'Added' : message;
          state.className = 'state ' + (ok ? 'ok' : 'bad');
          bar.parentElement.remove();
          busy = false; next();
        };
        xhr.onerror = () => {
          state.textContent = 'Connection lost';
          state.className = 'state bad';
          busy = false; next();
        };
        xhr.send(file);
      }

      picker.addEventListener('change', () => { add(picker.files); picker.value = ''; });
      ['dragenter', 'dragover'].forEach(t => drop.addEventListener(t, e => { e.preventDefault(); drop.classList.add('over'); }));
      ['dragleave', 'drop'].forEach(t => drop.addEventListener(t, e => { e.preventDefault(); drop.classList.remove('over'); }));
      drop.addEventListener('drop', e => add(e.dataTransfer.files));
    </script>
    </body>
    </html>
    """#
}
